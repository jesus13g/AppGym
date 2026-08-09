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

import '../datos/copia.dart' as copia;
import '../datos/media.dart' as media;
import '../datos/semilla.dart';
import '../estado/providers.dart';
import '../l10n/textos.dart';
import '../tema/tokens.dart';
import '../tema/tokens.dart' as t;
import '../tema/ui.dart' as ui;

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
        subject: 'Copia de seguridad de AppGym',
      ),
    );
  }

  Future<void> _exportarJson() => _hacer('json', () async {
    final datos = await copia.exportar(ref.read(bdProvider));
    final nombre = copia.nombreFichero(DateTime.now());
    await _compartir(const JsonEncoder.withIndent('  ').convert(datos), nombre);
    _informar('Copia generada: $nombre');
  });

  Future<void> _exportarCsv() => _hacer('csv', () async {
    final texto = await copia.exportarCsv(ref.read(bdProvider));
    final nombre = copia.nombreFichero(DateTime.now(), extension: 'csv');
    await _compartir(texto, nombre, conBom: true);
    _informar('CSV generado: $nombre');
  });

  // ── Importar ───────────────────────────────────────────────────────────────

  Future<void> _importar() => _hacer('importar', () async {
    // Sin `type: FileType.custom`: en Android muchos gestores no etiquetan los
    // .json y filtrar por extensión deja el selector vacío. Se valida el
    // contenido, que es lo que de verdad protege.
    final elegido = await FilePicker.pickFiles(
      withData: true,
      dialogTitle: 'Elige la copia de seguridad',
    );
    final fichero = elegido?.files.singleOrNull;
    if (fichero == null || !mounted) return;

    final bytes =
        fichero.bytes ??
        (fichero.path == null ? null : await File(fichero.path!).readAsBytes());
    if (bytes == null) {
      _informar('No se pudo leer el archivo.');
      return;
    }

    final datos = copia.leer(utf8.decode(bytes, allowMalformed: true));
    if (datos == null) {
      _informar('El archivo no es un JSON válido.');
      return;
    }

    final errores = copia.validar(datos);
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
        titulo: '¿Reemplazar todos los datos?',
        mensaje:
            'Se borrarán tus rutinas, sesiones y medidas actuales y se '
            'restaurarán las de la copia. No se puede deshacer.',
        etiquetaAceptar: 'Reemplazar',
        etiquetaCancelar: context.t.comunCancelar,
      );
      if (!confirmado || !mounted) return;
    }

    try {
      final informe = await copia.importar(
        ref.read(bdProvider),
        datos,
        modo: modo,
      );
      if (!mounted) return;
      invalidarTodo(ref);
      _informar(
        ['Importado: ${informe.resumen}', ...informe.avisos].join('\n'),
      );
    } on Exception catch (e) {
      _informar('No se pudo importar: $e');
    }
  });

  Future<copia.ModoImportacion?> _elegirModo() async {
    final elegido = await ui.elegirEnHoja<copia.ModoImportacion>(
      context,
      titulo: 'Importar copia de seguridad',
      mensaje:
          'Fusionar añade las rutinas que no tengas; una que ya exista entra '
          'como «(importada)» en vez de mezclarse.',
      opciones: const [
        (copia.ModoImportacion.fusionar, 'Fusionar con lo que tengo'),
        (copia.ModoImportacion.reemplazar, 'Reemplazar todos mis datos'),
      ],
      etiquetaCancelar: context.t.comunCancelar,
    );
    return elegido?.$1;
  }

  // ── Media y borrado ────────────────────────────────────────────────────────

  Future<void> _descargarMedia() => _hacer('media', () async {
    final catalogo = await ref.read(arranqueProvider.future);
    final pendientes = media.rutasPendientes(catalogo).length;
    if (pendientes == 0) {
      _informar('Las imágenes ya están descargadas.');
      return;
    }

    _informar('Descargando 0 de $pendientes…');
    final resultado = await media.descargarTodo(
      catalogo,
      alProgresar: (hechos, total, _) =>
          _informar('Descargando $hechos de $total…'),
    );
    _informar(
      resultado.fallos == 0
          ? 'Imágenes descargadas.'
          : '${resultado.fallos} archivos fallaron; se cargarán desde '
                'internet cuando hagan falta.',
    );
  });

  /// Borra los datos del usuario. Pide confirmación **dos veces**.
  ///
  /// El catálogo no se borra: son 1.324 filas regenerables desde el asset, y
  /// tirarlas solo alargaría el siguiente arranque. Se resiembra por si acaso.
  Future<void> _borrarTodo() async {
    final primera = await ui.dialogoConfirmar(
      context,
      titulo: '¿Borrar todos los datos?',
      mensaje:
          'Rutinas, ejercicios, sesiones, medidas y preferencias. El catálogo '
          'de ejercicios se conserva.',
      etiquetaAceptar: 'Borrar',
      etiquetaCancelar: context.t.comunCancelar,
    );
    if (!primera || !mounted) return;

    final segunda = await ui.dialogoConfirmar(
      context,
      titulo: 'No se puede deshacer',
      mensaje:
          'Si no has exportado una copia de seguridad, esto es definitivo. '
          '¿Seguro?',
      etiquetaAceptar: 'Sí, borrar todo',
      etiquetaCancelar: context.t.comunCancelar,
    );
    if (!segunda || !mounted) return;

    await _hacer('borrar', () async {
      final bd = ref.read(bdProvider);
      await bd.borrarTodosLosDatos();
      await sembrarCatalogo(bd);
      if (!mounted) return;
      invalidarTodo(ref);
      _informar('Datos borrados.');
    });
  }

  // ── Interfaz ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) => ui.Grupo(
    cabecera: 'Datos',
    pie:
        _estado ??
        'La copia es un archivo con todo tu histórico. Guárdala fuera del '
            'móvil: desinstalar la app borra la base de datos.',
    filas: [
      _accion(
        context,
        icono: CupertinoIcons.square_arrow_up,
        titulo: 'Exportar copia de seguridad',
        subtitulo: 'Un archivo JSON con todos tus datos',
        cargando: _ocupado == 'json',
        onTap: _exportarJson,
      ),
      _accion(
        context,
        icono: CupertinoIcons.square_arrow_down,
        titulo: 'Importar copia de seguridad',
        subtitulo: 'Fusionar o reemplazar lo que tienes',
        cargando: _ocupado == 'importar',
        onTap: _importar,
      ),
      _accion(
        context,
        icono: CupertinoIcons.table,
        titulo: 'Exportar a CSV',
        subtitulo: 'Una fila por serie, para una hoja de cálculo',
        cargando: _ocupado == 'csv',
        onTap: _exportarCsv,
      ),
      _accion(
        context,
        icono: CupertinoIcons.cloud_download,
        titulo: 'Descargar imágenes',
        subtitulo: media.descargaCompleta
            ? 'Ya están todas en el móvil'
            : 'Para ver el catálogo sin conexión',
        cargando: _ocupado == 'media',
        onTap: _descargarMedia,
      ),
      _accion(
        context,
        icono: CupertinoIcons.trash,
        titulo: 'Borrar todos los datos',
        subtitulo: 'Rutinas, sesiones y medidas',
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
