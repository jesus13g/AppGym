/// Sesiones registradas de una rutina, de la más reciente a la más antigua.
///
/// Es la puerta a corregir o eliminar un entrenamiento: hasta ahora una sesión
/// guardada por error se quedaba para siempre contaminando el calendario y las
/// estadísticas.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/bd.dart';
import '../datos/formato.dart';
import '../estado/providers.dart';
import '../l10n/textos.dart';
import '../tema/tokens.dart';
import '../tema/tokens.dart' as t;
import '../tema/ui.dart' as ui;
import 'sesion.dart';

Future<void> abrirHistorial(BuildContext context, int idRutina) =>
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => PantallaHistorial(idRutina: idRutina),
      ),
    );

class PantallaHistorial extends ConsumerWidget {
  const PantallaHistorial({super.key, required this.idRutina});

  final int idRutina;

  Future<void> _borrar(WidgetRef ref, int idEntrenamiento) async {
    await ref.read(bdProvider).borrarEntrenamiento(idEntrenamiento);
    invalidarEntrenamientos(ref, idRutina);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rutina = ref.watch(rutinaProvider(idRutina));
    final historial = ref.watch(historialRutinaProvider(idRutina));
    final f = formatoDe(context, ref);

    return CupertinoPageScaffold(
      backgroundColor: context.fondo,
      navigationBar: ui.barra(
        context,
        titulo: context.t.historialTitulo,
        tituloAnterior: rutina.value?.nombre,
      ),
      child: SafeArea(
        child: historial.when(
          loading: () => const ui.Cargando(),
          error: (e, _) => ui.EstadoVacio(
            icono: CupertinoIcons.exclamationmark_triangle,
            titulo: context.t.historialError,
            subtitulo: '$e',
          ),
          data: (sesiones) => sesiones.isEmpty
              ? ui.EstadoVacio(
                  icono: CupertinoIcons.calendar,
                  titulo: context.t.historialVacio,
                  subtitulo: context.t.historialVacioDetalle,
                )
              : ListView(
                  children: [
                    ui.Grupo(
                      cabecera: context.t.comunSesiones(sesiones.length),
                      pie: context.t.historialPie,
                      filas: [
                        for (final sesion in sesiones)
                          ui.DeslizarParaBorrar(
                            llave: ValueKey(sesion.id),
                            onBorrar: () => _borrar(ref, sesion.id),
                            titulo: context.t.comunEliminarSesionTitulo,
                            mensaje: context.t.comunEliminarSesionMensaje,
                            etiquetaEliminar: context.t.comunEliminar,
                            etiquetaCancelar: context.t.comunCancelar,
                            child: CupertinoListTile(
                              backgroundColor: context.tarjeta,
                              title: Text(
                                f.fechaLarga(sesion.fecha),
                                style: ui.estilo(context),
                              ),
                              subtitle: Text(
                                _resumen(context, f, sesion),
                                style: ui.estilo(
                                  context,
                                  size: t.footnote,
                                  color: context.textoSec,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (sesion.tieneNota)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        right: t.xs,
                                      ),
                                      child: Icon(
                                        CupertinoIcons.text_bubble,
                                        size: 16,
                                        color: context.textoTer,
                                      ),
                                    ),
                                  const CupertinoListTileChevron(),
                                ],
                              ),
                              onTap: () => abrirSesion(context, sesion.id),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: t.xxl),
                  ],
                ),
        ),
      ),
    );
  }

  String _resumen(BuildContext context, Formato f, ResumenSesion sesion) =>
      context.t.historialResumen(
        context.t.comunEjercicios(sesion.nEjercicios),
        context.t.comunSeries(sesion.nSeries),
        f.peso(sesion.volumen),
      );
}
