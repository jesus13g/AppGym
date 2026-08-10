/// Grupo «Datos» de Ajustes: copia de seguridad, media y borrado.
///
/// Vive aparte de `ajustes.dart` porque es lo único de esa pantalla que hace
/// trabajo de verdad —escribe ficheros, abre el selector del sistema, restaura
/// la base entera— y mezclarlo con las filas de preferencias dejaba un fichero
/// que no se podía leer de un tirón.
library;

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../datos/bd.dart';
import '../datos/copia.dart' as copia;
import '../datos/media.dart' as media;
import '../datos/semilla.dart';
import '../estado/providers.dart';
import '../l10n/textos.dart';
import '../tema/tokens.dart';
import '../tema/tokens.dart' as t;
import '../tema/ui.dart' as ui;

/// Escribe una copia JSON en el almacenamiento de la app y devuelve el fichero.
///
/// Es la red de seguridad de K7: la salida «la cuenta manda» del primer enlace
/// llama a esto **sin preguntar** antes de sustituir el histórico local, que es
/// la única acción de la app capaz de destruir dos años de datos.
///
/// Va al directorio de documentos y **no al temporal**, al revés que
/// `_compartir`: aquel escribe un fichero de paso, porque el que importa es el
/// que el usuario guarda desde la hoja de compartir. Aquí no hay hoja —K7 dice
/// «sin preguntar»— y una red de seguridad en un directorio que el sistema puede
/// vaciar no es una red.
Future<File> escribirCopiaLocal(AppBD bd, {DateTime? cuando}) async {
  final datos = await copia.exportar(bd);
  final nombre = copia.nombreFichero(cuando ?? DateTime.now());
  final directorio = await getApplicationDocumentsDirectory();
  final fichero = File('${directorio.path}/$nombre');
  await fichero.writeAsString(
    const JsonEncoder.withIndent('  ').convert(datos),
  );
  return fichero;
}

class GrupoDatos extends ConsumerStatefulWidget {
  const GrupoDatos({super.key});

  @override
  ConsumerState<GrupoDatos> createState() => _GrupoDatosState();
}

class _GrupoDatosState extends ConsumerState<GrupoDatos> {
  /// Qué acción está en marcha, para no lanzar dos a la vez.
  String? _ocupado;

  /// Lo último que pasó, que se cuenta al pie del grupo.
  String? _estado;

  bool get _libre => _ocupado == null;

  void _informar(String mensaje) {
    if (mounted) setState(() => _estado = mensaje);
  }

  Future<void> _hacer(String nombre, Future<void> Function() trabajo) async {
    if (!_libre) return;
    setState(() {
      _ocupado = nombre;
      _estado = null;
    });
    try {
      await trabajo();
    } finally {
      if (mounted) setState(() => _ocupado = null);
    }
  }

  // ── Exportar ───────────────────────────────────────────────────────────────

  /// Escribe el fichero en el directorio temporal y lo pasa a «compartir».
  ///
  /// El temporal es a propósito: el fichero que importa es el que el usuario
  /// guarde en Drive o se mande por correo, no una copia escondida dentro de la
  /// app —que se iría con la app al desinstalarla, que es justo de lo que esto
  /// protege—.
  Future<void> _compartir(
    String contenido,
    String nombre, {
    bool conBom = false,
  }) async {
    // Se lee antes del primer `await`: después, el `BuildContext` puede haber
    // dejado de ser válido y el analizador lo avisa.
    final t = context.t;
    final directorio = await getTemporaryDirectory();
    final fichero = File('${directorio.path}/$nombre');
    // El BOM es **solo** para el CSV: sin él, Excel abre los acentos como
    // basura. En el JSON estorbaría, porque `jsonDecode` no lo admite y la
    // copia dejaría de poder reimportarse.
    await fichero.writeAsString(conBom ? '\u{FEFF}$contenido' : contenido);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(fichero.path)],
        fileNameOverrides: [nombre],
        subject: t.copiaAsunto,
      ),
    );
  }

  Future<void> _exportarJson() => _hacer('json', () async {
    final t = context.t;
    final datos = await copia.exportar(ref.read(bdProvider));
    final nombre = copia.nombreFichero(DateTime.now());
    await _compartir(const JsonEncoder.withIndent('  ').convert(datos), nombre);
    _informar(t.copiaGenerada(nombre));
  });

  Future<void> _exportarCsv() => _hacer('csv', () async {
    final t = context.t;
    final texto = await copia.exportarCsv(ref.read(bdProvider));
    final nombre = copia.nombreFichero(DateTime.now(), extension: 'csv');
    await _compartir(texto, nombre, conBom: true);
    _informar(t.copiaCsvGenerado(nombre));
  });

  // ── Importar ───────────────────────────────────────────────────────────────

  Future<void> _importar() => _hacer('importar', () async {
    final t = context.t;
    // Sin `type: FileType.custom`: en Android muchos gestores no etiquetan los
    // .json y filtrar por extensión deja el selector vacío. Se valida el
    // contenido, que es lo que de verdad protege.
    final elegido = await FilePicker.pickFiles(
      withData: true,
      dialogTitle: t.copiaElegirFichero,
    );
    final fichero = elegido?.files.singleOrNull;
    if (fichero == null || !mounted) return;

    final bytes =
        fichero.bytes ??
        (fichero.path == null ? null : await File(fichero.path!).readAsBytes());
    if (bytes == null) {
      _informar(t.copiaNoSeLee);
      return;
    }

    final datos = copia.leer(utf8.decode(bytes, allowMalformed: true));
    if (datos == null) {
      _informar(t.copiaNoEsJson);
      return;
    }

    final errores = copia.validar(t, datos);
    if (errores.isNotEmpty) {
      _informar(errores.first);
      return;
    }
    if (!mounted) return;

    final modo = await _elegirModo();
    if (modo == null || !mounted) return;

    if (modo == copia.ModoImportacion.reemplazar) {
      final confirmado = await ui.dialogoConfirmar(
        context,
        titulo: t.copiaReemplazarTitulo,
        mensaje: t.copiaReemplazarMensaje,
        etiquetaAceptar: t.copiaReemplazar,
        etiquetaCancelar: t.comunCancelar,
      );
      if (!confirmado || !mounted) return;
    }

    try {
      final informe = await copia.importar(
        ref.read(bdProvider),
        t,
        datos,
        modo: modo,
      );
      if (!mounted) return;
      invalidarTodo(ref);
      _informar(
        [t.copiaImportado(informe.resumen(t)), ...informe.avisos].join('\n'),
      );
    } on Exception catch (e) {
      _informar(t.copiaErrorImportar('$e'));
    }
  });

  Future<copia.ModoImportacion?> _elegirModo() async {
    final elegido = await ui.elegirEnHoja<copia.ModoImportacion>(
      context,
      titulo: context.t.copiaImportar,
      mensaje: context.t.copiaModoMensaje,
      opciones: [
        (copia.ModoImportacion.fusionar, context.t.copiaFusionar),
        (copia.ModoImportacion.reemplazar, context.t.copiaReemplazarTodo),
      ],
      etiquetaCancelar: context.t.comunCancelar,
    );
    return elegido?.$1;
  }

  // ── Media y borrado ────────────────────────────────────────────────────────

  Future<void> _descargarMedia() => _hacer('media', () async {
    final t = context.t;
    final catalogo = await ref.read(arranqueProvider.future);
    final pendientes = media.rutasPendientes(catalogo).length;
    if (pendientes == 0) {
      _informar(t.copiaMediaYaEstaba);
      return;
    }

    _informar(t.copiaMediaProgreso(0, pendientes));
    final resultado = await media.descargarTodo(
      catalogo,
      alProgresar: (hechos, total, _) =>
          _informar(t.copiaMediaProgreso(hechos, total)),
    );
    _informar(
      resultado.fallos == 0
          ? t.copiaMediaHecha
          : t.copiaMediaFallos(resultado.fallos),
    );
  });

  /// Borra los datos del usuario. Pide confirmación **dos veces**.
  ///
  /// El catálogo no se borra: son 1.324 filas regenerables desde el asset, y
  /// tirarlas solo alargaría el siguiente arranque. Se resiembra por si acaso.
  Future<void> _borrarTodo() async {
    final t = context.t;
    final primera = await ui.dialogoConfirmar(
      context,
      titulo: t.copiaBorrarTitulo,
      mensaje: t.copiaBorrarMensaje,
      etiquetaAceptar: t.copiaBorrar,
      etiquetaCancelar: t.comunCancelar,
    );
    if (!primera || !mounted) return;

    final segunda = await ui.dialogoConfirmar(
      context,
      titulo: t.copiaBorrarTitulo2,
      mensaje: t.copiaBorrarMensaje2,
      etiquetaAceptar: t.copiaBorrarConfirmar,
      etiquetaCancelar: t.comunCancelar,
    );
    if (!segunda || !mounted) return;

    await _hacer('borrar', () async {
      final bd = ref.read(bdProvider);
      await bd.borrarTodosLosDatos();
      await sembrarCatalogo(bd);
      if (!mounted) return;
      invalidarTodo(ref);
      _informar(t.copiaBorrado);
    });
  }

  // ── Interfaz ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) => ui.Grupo(
    cabecera: context.t.copiaDatos,
    pie: _estado ?? context.t.copiaDatosPie,
    filas: [
      _accion(
        context,
        icono: CupertinoIcons.square_arrow_up,
        titulo: context.t.copiaExportar,
        subtitulo: context.t.copiaExportarDetalle,
        cargando: _ocupado == 'json',
        onTap: _exportarJson,
      ),
      _accion(
        context,
        icono: CupertinoIcons.square_arrow_down,
        titulo: context.t.copiaImportar,
        subtitulo: context.t.copiaImportarDetalle,
        cargando: _ocupado == 'importar',
        onTap: _importar,
      ),
      _accion(
        context,
        icono: CupertinoIcons.table,
        titulo: context.t.copiaExportarCsv,
        subtitulo: context.t.copiaExportarCsvDetalle,
        cargando: _ocupado == 'csv',
        onTap: _exportarCsv,
      ),
      _accion(
        context,
        icono: CupertinoIcons.cloud_download,
        titulo: context.t.copiaDescargarMedia,
        subtitulo: media.descargaCompleta
            ? context.t.copiaMediaCompleta
            : context.t.copiaMediaDetalle,
        cargando: _ocupado == 'media',
        onTap: _descargarMedia,
      ),
      _accion(
        context,
        icono: CupertinoIcons.trash,
        titulo: context.t.copiaBorrarTodo,
        subtitulo: context.t.copiaBorrarTodoDetalle,
        destructivo: true,
        cargando: _ocupado == 'borrar',
        onTap: _borrarTodo,
      ),
    ],
  );

  Widget _accion(
    BuildContext context, {
    required IconData icono,
    required String titulo,
    required String subtitulo,
    required bool cargando,
    required VoidCallback onTap,
    bool destructivo = false,
  }) {
    final color = destructivo ? context.destructivo : context.acento;
    return CupertinoListTile(
      backgroundColor: context.tarjeta,
      leading: Icon(icono, color: color, size: 24),
      title: Text(titulo, style: ui.estilo(context, color: color)),
      subtitle: Text(
        subtitulo,
        style: ui.estilo(context, size: t.footnote, color: context.textoSec),
      ),
      trailing: cargando
          ? const CupertinoActivityIndicator()
          : const CupertinoListTileChevron(),
      // Deshabilitado mientras haya otra acción en marcha: importar a la vez
      // que se borra todo no lleva a ningún sitio bueno.
      onTap: _libre ? onTap : null,
    );
  }
}
