/// Ejercicios de una rutina con acceso a su progreso individual.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/bd.dart';
import '../datos/formato.dart' as formato;
import '../estado/providers.dart';
import '../tema/tokens.dart';
import '../tema/tokens.dart' as t;
import '../tema/ui.dart' as ui;
import 'resultado_ejercicio.dart';

Future<void> abrirResultadoRutina(BuildContext context, int idRutina) =>
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        title: 'Progreso',
        builder: (_) => PantallaResultadoRutina(idRutina: idRutina),
      ),
    );

class PantallaResultadoRutina extends ConsumerWidget {
  const PantallaResultadoRutina({super.key, required this.idRutina});

  final int idRutina;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rutina = ref.watch(rutinaProvider(idRutina));
    final ejercicios = ref.watch(ejerciciosRutinaProvider(idRutina));
    final nombre = rutina.value?.nombre ?? 'Resultados';

    if (rutina.hasValue && rutina.value == null) {
      return CupertinoPageScaffold(
        backgroundColor: context.fondo,
        navigationBar: ui.barra(context, titulo: 'Resultados'),
        child: const ui.EstadoVacio(
          icono: CupertinoIcons.exclamationmark_triangle,
          titulo: 'Esta rutina ya no existe',
        ),
      );
    }

    return CupertinoPageScaffold(
      backgroundColor: context.fondo,
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: Text(nombre),
            previousPageTitle: 'Progreso',
            backgroundColor: context.barra,
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: ejercicios.when(
              loading: () => const ui.Cargando(),
              error: (e, _) => ui.EstadoVacio(
                icono: CupertinoIcons.exclamationmark_triangle,
                titulo: 'No se pudieron cargar los ejercicios',
                subtitulo: '$e',
              ),
              data: (lista) => lista.isEmpty
                  ? const ui.EstadoVacio(
                      icono: CupertinoIcons.chart_bar,
                      titulo: 'Esta rutina no tiene ejercicios',
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ui.Grupo(
                          cabecera: 'Ejercicios',
                          filas: [
                            for (final e in lista)
                              _Fila(idRutina: idRutina, ejercicio: e),
                          ],
                        ),
                        const SizedBox(height: t.xxl),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fila de un ejercicio con el resumen de sus registros.
///
/// Cada fila pide sus propias series, así que el trabajo se reparte en vez de
/// bloquear la pantalla entera hasta tenerlas todas.
class _Fila extends ConsumerWidget {
  const _Fila({required this.idRutina, required this.ejercicio});

  final int idRutina;
  final EjercicioConFicha ejercicio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registros = ref
        .watch(
          resumenSesionesEjercicioProvider((
            idRutina: idRutina,
            idEjercicio: ejercicio.id,
          )),
        )
        .value;
    final ajustes = ref.watch(ajustesProvider).value ?? const Ajustes();

    final String subtitulo;
    final VoidCallback? alTocar;

    if (registros == null) {
      subtitulo = '…';
      alTocar = null;
    } else if (registros.isEmpty) {
      subtitulo = 'Sin registros';
      alTocar = null;
    } else {
      final ultimo = registros.last;
      final maximo = registros
          .map((r) => r.pesoMaximo)
          .reduce((a, b) => a > b ? a : b);
      subtitulo =
          '${formato.plural(registros.length, 'sesión', 'sesiones')} · '
          'último ${formato.peso(ultimo.pesoMaximo, ajustes)} · '
          'máx ${formato.peso(maximo, ajustes)}';
      alTocar = () => abrirResultadoEjercicio(context, idRutina, ejercicio.id);
    }

    return CupertinoListTile(
      backgroundColor: context.tarjeta,
      leading: ui.Miniatura(formato.imagenEjercicio(ejercicio)),
      leadingSize: 48,
      title: Text(ejercicio.nombre, style: ui.estilo(context)),
      subtitle: Text(
        subtitulo,
        style: ui.estilo(context, size: t.footnote, color: context.textoSec),
      ),
      trailing: alTocar == null ? null : const CupertinoListTileChevron(),
      onTap: alTocar,
    );
  }
}
