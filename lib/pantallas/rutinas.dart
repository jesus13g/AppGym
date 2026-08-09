/// Pestaña de rutinas: la lista de rutinas del usuario.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/bd.dart';
import '../datos/formato.dart';
import '../datos/plantillas.dart';
import '../estado/providers.dart';
import '../l10n/textos.dart';
import '../tema/tokens.dart';
import '../tema/tokens.dart' as t;
import '../tema/ui.dart' as ui;
import 'ajustes.dart';
import 'rutina.dart';

class PantallaRutinas extends ConsumerWidget {
  const PantallaRutinas({super.key});

  /// Punto de entrada del «+»: en blanco o desde una plantilla.
  ///
  /// Construir una rutina de ocho ejercicios a mano son ocho búsquedas en el
  /// catálogo, así que la lista de plantillas se ofrece antes que el diálogo
  /// del nombre y no escondida detrás de él.
  Future<void> _nueva(BuildContext context, WidgetRef ref) async {
    final plantillas = await cargarPlantillas();
    if (!context.mounted) return;

    final elegida = await showCupertinoModalPopup<int>(
      context: context,
      builder: (hoja) => CupertinoActionSheet(
        title: Text(context.t.rutinasNueva),
        message: Text(context.t.rutinasPlantillasMensaje),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(hoja, -1),
            child: Text(hoja.t.rutinasEnBlanco),
          ),
          for (final (indice, p) in plantillas.indexed)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(hoja, indice),
              child: Column(
                children: [
                  Text(p.nombre),
                  const SizedBox(height: 2),
                  Text(
                    hoja.t.comunRutinaConEjercicios(
                      p.resumen,
                      hoja.t.comunEjercicios(p.nEjercicios),
                    ),
                    textAlign: TextAlign.center,
                    style: ui.estilo(
                      hoja,
                      size: t.footnote,
                      color: hoja.textoSec,
                    ),
                  ),
                ],
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(hoja),
          child: Text(hoja.t.comunCancelar),
        ),
      ),
    );
    if (elegida == null || !context.mounted) return;

    if (elegida < 0) {
      await _crear(context, ref);
    } else {
      await _desdePlantilla(context, ref, plantillas[elegida]);
    }
  }

  /// Enseña lo que va a crear y, si se acepta, lo crea.
  Future<void> _desdePlantilla(
    BuildContext context,
    WidgetRef ref,
    Plantilla plantilla,
  ) async {
    final confirmado = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogo) => CupertinoAlertDialog(
        title: Text(plantilla.nombre),
        content: Padding(
          padding: const EdgeInsets.only(top: t.s),
          child: Column(
            children: [
              Text(plantilla.descripcion, textAlign: TextAlign.center),
              const SizedBox(height: t.m),
              for (final r in plantilla.rutinas)
                Text(
                  dialogo.t.comunRutinaConEjercicios(
                    r.nombre,
                    dialogo.t.comunEjercicios(r.ejercicios.length),
                  ),
                  textAlign: TextAlign.center,
                  style: ui.estilo(dialogo, size: t.footnote),
                ),
            ],
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialogo, false),
            child: Text(dialogo.t.comunCancelar),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(dialogo, true),
            child: Text(dialogo.t.comunCrear),
          ),
        ],
      ),
    );
    if (confirmado != true || !context.mounted) return;

    final creadas = await crearRutinasDesdePlantilla(
      ref.read(bdProvider),
      plantilla,
    );
    if (!context.mounted) return;

    invalidarRutinas(ref);
    if (creadas.isEmpty) {
      ui.aviso(context, context.t.rutinasPlantillaTodasExisten);
      return;
    }
    if (creadas.length < plantilla.rutinas.length) {
      ui.aviso(context, context.t.rutinasPlantillaAlgunasExisten);
    }
    await abrirRutina(context, creadas.first);
  }

  Future<void> _crear(BuildContext context, WidgetRef ref) async {
    final nombre = await ui.dialogoTexto(
      context,
      titulo: context.t.rutinasNueva,
      marcador: context.t.rutinasNombreMarcador,
      mensaje: context.t.rutinasNombreMensaje,
      etiquetaAceptar: context.t.comunCrear,
      etiquetaCancelar: context.t.comunCancelar,
    );
    if (nombre == null || !context.mounted) return;

    final id = await ref.read(bdProvider).insertarRutina(nombre);
    if (!context.mounted) return;

    if (id == null) {
      ui.aviso(context, context.t.rutinasNombreRepetido(nombre));
      return;
    }
    invalidarRutinas(ref);
    await abrirRutina(context, id);
  }

  Future<void> _borrar(WidgetRef ref, int idRutina) async {
    await ref.read(bdProvider).borrarRutina(idRutina);
    invalidarRutinas(ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resumen = ref.watch(resumenRutinasProvider);

    return CupertinoPageScaffold(
      backgroundColor: context.fondo,
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: Text(context.t.raizRutinas),
            backgroundColor: context.barra,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  onPressed: () => abrirAjustes(context),
                  child: const Icon(CupertinoIcons.settings, size: 20),
                ),
                const SizedBox(width: t.m),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  onPressed: () => _nueva(context, ref),
                  child: const Icon(CupertinoIcons.add, size: 22),
                ),
              ],
            ),
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: resumen.when(
              loading: () => const ui.Cargando(),
              error: (e, _) => ui.EstadoVacio(
                icono: CupertinoIcons.exclamationmark_triangle,
                titulo: context.t.rutinasError,
                subtitulo: '$e',
              ),
              data: (rutinas) => rutinas.isEmpty
                  ? ui.EstadoVacio(
                      icono: CupertinoIcons.square_stack_3d_up,
                      titulo: context.t.rutinasVacio,
                      subtitulo: context.t.rutinasVacioDetalle,
                      accion: ui.BotonPrincipal(
                        context.t.rutinasCrearRutina,
                        icono: CupertinoIcons.add,
                        onPressed: () => _nueva(context, ref),
                      ),
                    )
                  : _Lista(
                      rutinas: rutinas,
                      formato: formatoDe(context, ref),
                      onBorrar: (id) => _borrar(ref, id),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Lista extends StatelessWidget {
  const _Lista({
    required this.rutinas,
    required this.formato,
    required this.onBorrar,
  });

  final List<ResumenRutina> rutinas;
  final Formato formato;
  final void Function(int idRutina) onBorrar;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ui.Grupo(
        pie: context.t.rutinasPie,
        filas: [
          for (final r in rutinas)
            ui.DeslizarParaBorrar(
              llave: ValueKey(r.id),
              onBorrar: () => onBorrar(r.id),
              titulo: context.t.rutinasEliminarTitulo(r.nombre),
              mensaje: context.t.rutinasEliminarMensaje,
              etiquetaEliminar: context.t.comunEliminar,
              etiquetaCancelar: context.t.comunCancelar,
              child: CupertinoListTile(
                backgroundColor: context.tarjeta,
                leading: ui.PuntoColor(
                  colorDesdeHex(r.color, context.acento),
                  tamano: 12,
                ),
                title: Text(r.nombre, style: ui.estilo(context)),
                subtitle: Text(
                  [
                    context.t.comunEjercicios(r.nEjercicios),
                    formato.hace(r.ultimaFecha),
                  ].join(' · '),
                  style: ui.estilo(
                    context,
                    size: t.footnote,
                    color: context.textoSec,
                  ),
                ),
                trailing: const CupertinoListTileChevron(),
                onTap: () => abrirRutina(context, r.id),
              ),
            ),
        ],
      ),
      const SizedBox(height: t.xxl),
    ],
  );
}
