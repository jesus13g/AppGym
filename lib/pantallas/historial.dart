/// Sesiones registradas de una rutina, de la más reciente a la más antigua.
///
/// Es la puerta a corregir o eliminar un entrenamiento: hasta ahora una sesión
/// guardada por error se quedaba para siempre contaminando el calendario y las
/// estadísticas.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/bd.dart';
import '../datos/formato.dart' as formato;
import '../estado/providers.dart';
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

    return CupertinoPageScaffold(
      backgroundColor: context.fondo,
      navigationBar: ui.barra(
        context,
        titulo: 'Sesiones',
        tituloAnterior: rutina.value?.nombre,
      ),
      child: SafeArea(
        child: historial.when(
          loading: () => const ui.Cargando(),
          error: (e, _) => ui.EstadoVacio(
            icono: CupertinoIcons.exclamationmark_triangle,
            titulo: 'No se pudo cargar el historial',
            subtitulo: '$e',
          ),
          data: (sesiones) => sesiones.isEmpty
              ? const ui.EstadoVacio(
                  icono: CupertinoIcons.calendar,
                  titulo: 'Todavía no hay sesiones',
                  subtitulo:
                      'Registra un entrenamiento de esta rutina y aquí '
                      'podrás repasarlo, corregirlo o eliminarlo.',
                )
              : ListView(
                  children: [
                    ui.Grupo(
                      cabecera: formato.plural(
                        sesiones.length,
                        'sesión',
                        'sesiones',
                      ),
                      pie: 'Desliza una sesión para eliminarla.',
                      filas: [
                        for (final sesion in sesiones)
                          ui.DeslizarParaBorrar(
                            llave: ValueKey(sesion.id),
                            onBorrar: () => _borrar(ref, sesion.id),
                            titulo: '¿Eliminar la sesión?',
                            mensaje:
                                'Se borrarán sus series y dejará de contar '
                                'en el calendario y en las estadísticas. '
                                'No se puede deshacer.',
                            child: CupertinoListTile(
                              backgroundColor: context.tarjeta,
                              title: Text(
                                formato.fechaLarga(sesion.fecha),
                                style: ui.estilo(context),
                              ),
                              subtitle: Text(
                                _resumen(sesion),
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

  String _resumen(ResumenSesion sesion) =>
      '${formato.plural(sesion.nEjercicios, 'ejercicio', 'ejercicios')} · '
      '${formato.plural(sesion.nSeries, 'serie', 'series')} · '
      '${formato.numero(sesion.volumen)} kg';
}
