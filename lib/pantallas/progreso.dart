/// Pestaña de progreso: resumen por rutina y calendario de entrenamientos.
///
/// A diferencia de la versión Flet, la pestaña elegida y el mes visible son
/// estado del widget: no hay que meterlos en los parámetros de la ruta ni
/// reconstruir la pila para conservarlos.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/formato.dart' as formato;
import '../estado/providers.dart';
import '../tema/tokens.dart';
import '../tema/tokens.dart' as t;
import '../tema/ui.dart' as ui;
import 'resultado_rutina.dart';

class PantallaProgreso extends ConsumerStatefulWidget {
  const PantallaProgreso({super.key});

  @override
  ConsumerState<PantallaProgreso> createState() => _PantallaProgresoState();
}

class _PantallaProgresoState extends ConsumerState<PantallaProgreso> {
  int _pestana = 0;
  late DateTime _mes = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    backgroundColor: context.fondo,
    child: CustomScrollView(
      slivers: [
        CupertinoSliverNavigationBar(
          largeTitle: const Text('Progreso'),
          backgroundColor: context.barra,
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: t.l, vertical: t.s),
            child: SizedBox(
              width: double.infinity,
              child: CupertinoSlidingSegmentedControl<int>(
                groupValue: _pestana,
                onValueChanged: (valor) =>
                    setState(() => _pestana = valor ?? 0),
                children: const {
                  0: Padding(
                    padding: EdgeInsets.symmetric(vertical: t.xs),
                    child: Text('Resumen'),
                  ),
                  1: Padding(
                    padding: EdgeInsets.symmetric(vertical: t.xs),
                    child: Text('Calendario'),
                  ),
                },
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _pestana == 0
              ? const _Resumen()
              : _Calendario(
                  mes: _mes,
                  onMes: (nuevo) => setState(() => _mes = nuevo),
                ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: t.xxl)),
      ],
    ),
  );
}

// ── Resumen ──────────────────────────────────────────────────────────────────

class _Resumen extends ConsumerWidget {
  const _Resumen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resumen = ref.watch(resumenRutinasProvider);

    return resumen.when(
      loading: () =>
          const Padding(padding: EdgeInsets.all(t.xxl), child: ui.Cargando()),
      error: (e, _) => ui.EstadoVacio(
        icono: CupertinoIcons.exclamationmark_triangle,
        titulo: 'No se pudo cargar el progreso',
        subtitulo: '$e',
      ),
      data: (rutinas) {
        final conDatos = [
          for (final r in rutinas)
            if (r.ultimaFecha != null) r,
        ];
        if (conDatos.isEmpty) {
          return const Padding(
            padding: EdgeInsets.only(top: t.xxl),
            child: ui.EstadoVacio(
              icono: CupertinoIcons.chart_bar,
              titulo: 'Todavía no hay datos',
              subtitulo:
                  'Registra tu primer entrenamiento desde una rutina y '
                  'aquí verás cómo progresas en cada ejercicio.',
            ),
          );
        }

        return ui.Grupo(
          cabecera: 'Rutinas entrenadas',
          pie:
              'Entra en una rutina para ver la evolución del peso en cada '
              'ejercicio.',
          filas: [
            for (final r in conDatos)
              CupertinoListTile(
                backgroundColor: context.tarjeta,
                leading: ui.PuntoColor(
                  colorDesdeHex(r.color, context.acento),
                  tamano: 12,
                ),
                title: Text(r.nombre, style: ui.estilo(context)),
                subtitle: Text(
                  formato.hace(r.ultimaFecha),
                  style: ui.estilo(
                    context,
                    size: t.footnote,
                    color: context.textoSec,
                  ),
                ),
                trailing: const CupertinoListTileChevron(),
                onTap: () => abrirResultadoRutina(context, r.id),
              ),
          ],
        );
      },
    );
  }
}

// ── Calendario ───────────────────────────────────────────────────────────────

class _Calendario extends ConsumerWidget {
  const _Calendario({required this.mes, required this.onMes});

  final DateTime mes;
  final ValueChanged<DateTime> onMes;

  List<DateTime> get _dias {
    final siguiente = DateTime(mes.year, mes.month + 1);
    final total = siguiente.difference(DateTime(mes.year, mes.month)).inDays;
    return [
      for (var i = 0; i < total; i++) DateTime(mes.year, mes.month, i + 1),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entrenamientos =
        ref.watch(entrenamientosPorDiaProvider(mes)).value ?? const {};
    final colores = ref.watch(coloresRutinasProvider).value ?? const {};
    final ahora = DateTime.now();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);

    final dias = _dias;
    // Lunes = 1 en Dart, así que weekday - 1 da los huecos iniciales.
    final huecos = dias.first.weekday - 1;
    final rutinasDelMes = {
      for (final sesiones in entrenamientos.values)
        for (final s in sesiones) s.idRutina,
    };

    /// Colores de las rutinas distintas entrenadas ese día, sin repetir.
    List<Color> coloresDe(DateTime dia) => [
      for (final id in {
        for (final s in entrenamientos[dia] ?? const []) s.idRutina,
      })
        colorDesdeHex(colores[id]?.$2, context.acento),
    ];

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: t.l, vertical: t.s),
          decoration: BoxDecoration(
            color: context.tarjeta,
            borderRadius: BorderRadius.circular(t.radioL),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: t.l,
                  vertical: t.s,
                ),
                child: Row(
                  children: [
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      onPressed: () => onMes(DateTime(mes.year, mes.month - 1)),
                      child: const Icon(CupertinoIcons.chevron_left, size: 18),
                    ),
                    Expanded(
                      child: Text(
                        '${formato.mes(mes.month)} ${mes.year}',
                        textAlign: TextAlign.center,
                        style: ui.estilo(
                          context,
                          size: t.headline,
                          weight: t.semibold,
                        ),
                      ),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      onPressed: () => onMes(DateTime(mes.year, mes.month + 1)),
                      child: const Icon(CupertinoIcons.chevron_right, size: 18),
                    ),
                  ],
                ),
              ),
              Container(height: 0.5, color: context.separador),
              Padding(
                padding: const EdgeInsets.all(t.m),
                child: GridView.count(
                  crossAxisCount: 7,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: t.xs,
                  crossAxisSpacing: t.xs,
                  children: [
                    for (final etiqueta in formato.diasSemana)
                      Center(
                        child: Text(
                          etiqueta,
                          style: ui.estilo(
                            context,
                            size: t.caption,
                            color: context.textoSec,
                          ),
                        ),
                      ),
                    for (var i = 0; i < huecos; i++) const SizedBox.shrink(),
                    for (final dia in dias)
                      _Celda(
                        dia: dia,
                        esHoy: dia == hoy,
                        colores: coloresDe(dia),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (rutinasDelMes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: t.l),
            child: Text(
              'Ningún entrenamiento este mes',
              style: ui.estilo(
                context,
                size: t.footnote,
                color: context.textoSec,
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: t.l, vertical: t.l),
            child: Wrap(
              spacing: t.l,
              runSpacing: t.s,
              children: [
                for (final id in rutinasDelMes.toList()..sort())
                  if (colores[id] case final datos?)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ui.PuntoColor(colorDesdeHex(datos.$2, context.acento)),
                        const SizedBox(width: t.xs),
                        Text(
                          datos.$1,
                          style: ui.estilo(
                            context,
                            size: t.footnote,
                            color: context.textoSec,
                          ),
                        ),
                      ],
                    ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Celda extends StatelessWidget {
  const _Celda({required this.dia, required this.esHoy, required this.colores});

  final DateTime dia;
  final bool esHoy;

  /// Un color por rutina distinta entrenada ese día; vacío si no se entrenó.
  final List<Color> colores;

  @override
  Widget build(BuildContext context) {
    final entrenado = colores.isNotEmpty;
    return DecoratedBox(
      decoration: BoxDecoration(
        // Con una sola rutina basta el relleno de siempre; con varias hay que
        // pintar los sectores, y entonces el fondo lo pone el pintor.
        color: colores.length == 1 ? colores.single : null,
        shape: BoxShape.circle,
        border: esHoy && !entrenado
            ? Border.all(color: context.acento, width: 1.5)
            : null,
      ),
      child: CustomPaint(
        painter: colores.length > 1 ? _Sectores(colores) : null,
        child: Center(
          child: Text(
            '${dia.day}',
            style: ui.estilo(
              context,
              size: t.subhead,
              weight: entrenado || esHoy ? t.semibold : null,
              color: entrenado
                  ? CupertinoColors.white
                  : (esHoy ? context.acento : context.texto),
            ),
          ),
        ),
      ),
    );
  }
}

/// Reparte la celda en sectores, uno por rutina distinta entrenada ese día.
///
/// A partir de cuatro rutinas se pintan tres sectores y un punto de «hay más»,
/// porque más porciones en un círculo de 30 px no se distinguen.
class _Sectores extends CustomPainter {
  const _Sectores(this.colores);

  static const _maxSectores = 3;

  final List<Color> colores;

  List<Color> get _visibles => colores.length > _maxSectores
      ? colores.take(_maxSectores).toList()
      : colores;

  @override
  void paint(Canvas lienzo, Size tamano) {
    final caja = Rect.fromLTWH(0, 0, tamano.width, tamano.height);
    final visibles = _visibles;
    final porcion = 2 * 3.1415926535897932 / visibles.length;

    for (final (indice, color) in visibles.indexed) {
      lienzo.drawArc(
        caja,
        // Desde arriba, para que el corte quede vertical con dos rutinas.
        -3.1415926535897932 / 2 + porcion * indice,
        porcion,
        true,
        Paint()..color = color,
      );
    }

    if (colores.length <= _maxSectores) return;
    lienzo.drawCircle(
      Offset(tamano.width / 2, tamano.height - 2),
      2,
      Paint()..color = CupertinoColors.white,
    );
  }

  @override
  bool shouldRepaint(_Sectores anterior) => anterior.colores != colores;
}
