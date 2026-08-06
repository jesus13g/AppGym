/// Evolución de un ejercicio: gráfico de peso e histórico de series.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/bd.dart';
import '../datos/formato.dart' as formato;
import '../estado/providers.dart';
import '../tema/tokens.dart';
import '../tema/tokens.dart' as t;
import '../tema/ui.dart' as ui;

/// Se muestran las últimas N sesiones para que el gráfico siga legible.
const _maxBarras = 12;

Future<void> abrirResultadoEjercicio(
  BuildContext context,
  int idRutina,
  int idEjercicio,
) => Navigator.of(context).push(
  CupertinoPageRoute<void>(
    builder: (_) => PantallaResultadoEjercicio(
      idRutina: idRutina,
      idEjercicio: idEjercicio,
    ),
  ),
);

class PantallaResultadoEjercicio extends ConsumerWidget {
  const PantallaResultadoEjercicio({
    super.key,
    required this.idRutina,
    required this.idEjercicio,
  });

  final int idRutina;
  final int idEjercicio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ejercicio = ref.watch(ejercicioProvider(idEjercicio));
    final registros = ref.watch(
      seriesConFechaProvider((idRutina: idRutina, idEjercicio: idEjercicio)),
    );
    final nombre = ejercicio.value?.nombre ?? 'Ejercicio';

    return CupertinoPageScaffold(
      backgroundColor: context.fondo,
      navigationBar: ui.barra(context, titulo: nombre),
      child: registros.when(
        loading: () => const ui.Cargando(),
        error: (e, _) => ui.EstadoVacio(
          icono: CupertinoIcons.exclamationmark_triangle,
          titulo: 'No se pudo cargar el progreso',
          subtitulo: '$e',
        ),
        // La guarda contra la lista vacía no es cosmética: en la versión Flet,
        // abrir un ejercicio sin registros reventaba al hacer max() de una lista
        // vacía.
        data: (lista) => lista.isEmpty
            ? const ui.EstadoVacio(
                icono: CupertinoIcons.chart_bar,
                titulo: 'Sin registros todavía',
                subtitulo:
                    'Registra un entrenamiento con este ejercicio para '
                    'ver aquí su evolución.',
              )
            : _Contenido(nombre: nombre, registros: lista),
      ),
    );
  }
}

class _Contenido extends StatelessWidget {
  const _Contenido({required this.nombre, required this.registros});

  final String nombre;
  final List<RegistroSerie> registros;

  @override
  Widget build(BuildContext context) {
    final recientes = registros.length > _maxBarras
        ? registros.sublist(registros.length - _maxBarras)
        : registros;
    final maximo = registros.map((r) => r.peso).reduce((a, b) => a > b ? a : b);
    final ultimo = registros.last;

    return SafeArea(
      child: ListView(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: t.l, vertical: t.s),
            padding: const EdgeInsets.symmetric(vertical: t.l),
            decoration: BoxDecoration(
              color: context.tarjeta,
              borderRadius: BorderRadius.circular(t.radioL),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _Dato('${formato.numero(ultimo.peso)} kg', 'Último'),
                _Dato('${formato.numero(maximo)} kg', 'Máximo'),
                _Dato('${registros.length}', 'Sesiones'),
              ],
            ),
          ),
          const SizedBox(height: t.s),
          Container(
            height: 240,
            margin: const EdgeInsets.symmetric(horizontal: t.l),
            padding: const EdgeInsets.only(
              left: t.s,
              right: t.l,
              top: t.xl,
              bottom: t.s,
            ),
            decoration: BoxDecoration(
              color: context.tarjeta,
              borderRadius: BorderRadius.circular(t.radioL),
            ),
            child: _Grafico(registros: recientes, maximo: maximo),
          ),
          const SizedBox(height: t.l),
          ui.Grupo(
            cabecera: 'Histórico',
            filas: [
              for (final r in registros.reversed)
                CupertinoListTile(
                  backgroundColor: context.tarjeta,
                  title: Text(
                    formato.fechaLarga(r.fecha),
                    style: ui.estilo(context),
                  ),
                  subtitle: Text(
                    '${r.series} series × ${r.repeticiones} repeticiones',
                    style: ui.estilo(
                      context,
                      size: t.footnote,
                      color: context.textoSec,
                    ),
                  ),
                  additionalInfo: Text(
                    '${formato.numero(r.peso)} kg',
                    style: ui.estilo(context, color: context.textoSec),
                  ),
                ),
            ],
          ),
          const SizedBox(height: t.xxl),
        ],
      ),
    );
  }
}

class _Grafico extends StatelessWidget {
  const _Grafico({required this.registros, required this.maximo});

  final List<RegistroSerie> registros;
  final double maximo;

  @override
  Widget build(BuildContext context) => BarChart(
    BarChartData(
      // El +15% evita que la barra más alta quede pegada al borde.
      maxY: maximo * 1.15 + 1,
      borderData: FlBorderData(show: false),
      gridData: FlGridData(
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) => FlLine(
          color: context.separador,
          strokeWidth: 0.5,
          dashArray: const [4, 4],
        ),
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 34,
            getTitlesWidget: (valor, meta) => Text(
              formato.numero(valor),
              style: ui.estilo(
                context,
                size: t.caption - 2,
                color: context.textoSec,
              ),
            ),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 26,
            getTitlesWidget: (valor, meta) {
              final indice = valor.round();
              if (indice < 0 || indice >= registros.length) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: t.xs),
                child: Text(
                  formato.fechaCorta(registros[indice].fecha),
                  style: ui.estilo(
                    context,
                    size: t.caption - 2,
                    color: context.textoSec,
                  ),
                ),
              );
            },
          ),
        ),
      ),
      barGroups: [
        for (final (indice, r) in registros.indexed)
          BarChartGroupData(
            x: indice,
            barRods: [
              BarChartRodData(
                toY: r.peso,
                width: 16,
                color: context.acento,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(6),
                ),
              ),
            ],
          ),
      ],
    ),
  );
}

class _Dato extends StatelessWidget {
  const _Dato(this.valor, this.etiqueta);

  final String valor;
  final String etiqueta;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        valor,
        textAlign: TextAlign.center,
        style: ui.estilo(context, size: t.title3, weight: t.semibold),
      ),
      const SizedBox(height: 2),
      Text(
        etiqueta,
        textAlign: TextAlign.center,
        style: ui.estilo(context, size: t.caption, color: context.textoSec),
      ),
    ],
  );
}
