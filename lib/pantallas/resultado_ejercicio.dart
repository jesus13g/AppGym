/// Evolución de un ejercicio: récords, gráfico e histórico de sesiones.
///
/// La métrica del gráfico y el rango de fechas son **estado del widget**: se
/// eligen aquí, se aplican sobre la lista que ya está cargada y no vuelven a
/// consultar la base de datos.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/bd.dart';
import '../datos/formato.dart';
import '../datos/metricas.dart' as metricas;
import '../datos/progresion.dart' as progresion;
import '../estado/providers.dart';
import '../l10n/textos.dart';
import '../tema/tokens.dart';
import '../tema/tokens.dart' as t;
import '../tema/ui.dart' as ui;
import 'sugerencia.dart';

/// Lo que se pinta en el eje Y del gráfico.
enum Metrica {
  peso('Peso'),
  unoRm('1RM'),
  volumen('Volumen');

  const Metrica(this.etiqueta);

  final String etiqueta;

  /// El valor de esta métrica en una sesión. Las tres son kilos: el volumen es
  /// kilos × repeticiones, así que también se convierte a la unidad activa.
  double de(ResumenSesionEjercicio sesion) => switch (this) {
    Metrica.peso => sesion.pesoMaximo,
    Metrica.unoRm => sesion.mejor1RM,
    Metrica.volumen => sesion.volumen,
  };
}

/// Cuánto histórico se pinta. Sustituye al tope fijo de doce barras.
enum Rango {
  mes('1M', 30),
  trimestre('3M', 91),
  ano('1A', 365),
  todo('Todo', null);

  const Rango(this.etiqueta, this.dias);

  final String etiqueta;

  /// `null` es «sin límite».
  final int? dias;
}

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
    // Una entrada por sesión, no por serie: con las series en crudo el gráfico
    // pintaría una barra por cada una.
    final registros = ref.watch(
      resumenSesionesEjercicioProvider((
        idRutina: idRutina,
        idEjercicio: idEjercicio,
      )),
    );
    final f = formatoDe(context, ref);
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
            : _Contenido(
                registros: lista,
                formato: f,
                // Aquí se analiza, no se entrena: la sugerencia se enseña con su
                // motivo y sin botón de aplicar.
                sugerencia: ref
                    .watch(
                      sugerenciaProvider((
                        idRutina: idRutina,
                        idEjercicio: idEjercicio,
                      )),
                    )
                    .value,
              ),
      ),
    );
  }
}

class _Contenido extends StatefulWidget {
  const _Contenido({
    required this.registros,
    required this.formato,
    this.sugerencia,
  });

  final List<ResumenSesionEjercicio> registros;

  /// De aquí salen el idioma, la unidad en la que se escriben los pesos y la
  /// fórmula con la que ya se estimó el 1RM.
  final Formato formato;

  final progresion.Sugerencia? sugerencia;

  @override
  State<_Contenido> createState() => _ContenidoState();
}

class _ContenidoState extends State<_Contenido> {
  Metrica _metrica = Metrica.peso;
  Rango _rango = Rango.todo;

  /// Las sesiones que caen dentro del rango elegido.
  ///
  /// Se filtra la lista que ya está en memoria: cambiar de rango o de métrica
  /// no vuelve a consultar.
  List<ResumenSesionEjercicio> get _enRango {
    final dias = _rango.dias;
    if (dias == null) return widget.registros;
    final desde = DateTime.now().subtract(Duration(days: dias));
    final recortada = [
      for (final r in widget.registros)
        if (r.fecha.isAfter(desde)) r,
    ];
    // Un rango sin ninguna sesión dejaría el gráfico en blanco y sin explicar
    // por qué; se enseña la última que hubo.
    return recortada.isEmpty
        ? widget.registros.sublist(widget.registros.length - 1)
        : recortada;
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.formato;
    final records = metricas.recordsEjercicio(widget.registros);
    final conRecord = metricas.sesionesConRecord(widget.registros);
    final enRango = _enRango;
    final maximo = enRango.map(_metrica.de).reduce((a, b) => a > b ? a : b);

    return SafeArea(
      child: ListView(
        children: [
          _Tarjeta(records: records, sesiones: widget.registros, formato: f),
          if (widget.sugerencia case final propuesta?)
            _TarjetaSugerencia(sugerencia: propuesta, formato: f),
          const SizedBox(height: t.s),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: t.l),
            child: SizedBox(
              width: double.infinity,
              child: CupertinoSlidingSegmentedControl<Metrica>(
                groupValue: _metrica,
                onValueChanged: (valor) =>
                    setState(() => _metrica = valor ?? Metrica.peso),
                children: {
                  for (final m in Metrica.values)
                    m: Padding(
                      padding: const EdgeInsets.symmetric(vertical: t.xs),
                      child: Text(m.etiqueta),
                    ),
                },
              ),
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
            child: _Grafico(
              registros: enRango,
              maximo: maximo,
              metrica: _metrica,
              formato: f,
            ),
          ),
          const SizedBox(height: t.s),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: t.l),
            child: SizedBox(
              width: double.infinity,
              child: CupertinoSlidingSegmentedControl<Rango>(
                groupValue: _rango,
                onValueChanged: (valor) =>
                    setState(() => _rango = valor ?? Rango.todo),
                children: {
                  for (final r in Rango.values)
                    r: Padding(
                      padding: const EdgeInsets.symmetric(vertical: t.xs),
                      child: Text(r.etiqueta),
                    ),
                },
              ),
            ),
          ),
          const SizedBox(height: t.l),
          ui.Grupo(
            cabecera: 'Histórico',
            pie: 'El trofeo marca las sesiones que batieron algún récord.',
            filas: [
              for (final r in widget.registros.reversed)
                CupertinoListTile(
                  backgroundColor: context.tarjeta,
                  title: Text(f.fechaLarga(r.fecha), style: ui.estilo(context)),
                  subtitle: Text(
                    '${context.t.comunSeries(r.nSeries)} · '
                    '${f.peso(r.volumen)} de volumen',
                    style: ui.estilo(
                      context,
                      size: t.footnote,
                      color: context.textoSec,
                    ),
                  ),
                  trailing: conRecord.contains(r.idEntrenamiento)
                      ? Icon(
                          CupertinoIcons.rosette,
                          size: 18,
                          color: context.acento,
                        )
                      : null,
                  additionalInfo: Text(
                    f.peso(r.pesoMaximo),
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

/// La sugerencia, como una tarjeta más junto a los récords.
///
/// Sin botón de aplicar: desde esta pantalla no se está entrenando. La descarga
/// además lleva su nota, que es donde J4 pedía decir lo que la app no sabe.
class _TarjetaSugerencia extends StatelessWidget {
  const _TarjetaSugerencia({required this.sugerencia, required this.formato});

  final progresion.Sugerencia sugerencia;
  final Formato formato;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: t.l, vertical: t.s),
    decoration: BoxDecoration(
      color: context.tarjeta,
      borderRadius: BorderRadius.circular(t.radioL),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LineaSugerencia(sugerencia: sugerencia, formato: formato),
        if (sugerencia.tipo == progresion.TipoSugerencia.descarga)
          Padding(
            padding: const EdgeInsets.fromLTRB(t.l, 0, t.l, t.m),
            child: Text(
              avisoDescarga(context.t),
              style: ui.estilo(
                context,
                size: t.caption,
                color: context.textoSec,
              ),
            ),
          ),
      ],
    ),
  );
}

/// Las cuatro cifras de cabecera, en dos filas de dos.
///
/// En una sola fila de cuatro los números se apretaban hasta partirse en un
/// móvil estrecho, que es donde hay que mirar.
class _Tarjeta extends StatelessWidget {
  const _Tarjeta({
    required this.records,
    required this.sesiones,
    required this.formato,
  });

  final metricas.RecordsEjercicio records;
  final List<ResumenSesionEjercicio> sesiones;
  final Formato formato;

  @override
  Widget build(BuildContext context) {
    // Sin ninguna serie fiable no hay récord de 1RM: se enseña la mejor
    // estimación que haya, en gris y con asterisco, para no dejar el hueco en
    // blanco sin decir por qué.
    final mejorDeTodas = sesiones
        .map((s) => s.mejor1RM)
        .reduce((a, b) => a > b ? a : b);
    final fiable = records.mejor1RM != null;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: t.l, vertical: t.s),
      padding: const EdgeInsets.symmetric(vertical: t.l),
      decoration: BoxDecoration(
        color: context.tarjeta,
        borderRadius: BorderRadius.circular(t.radioL),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _Dato(
                  '${formato.peso(records.mejor1RM ?? mejorDeTodas)}'
                      '${fiable ? '' : ' *'}',
                  '1RM estimado',
                  atenuado: !fiable,
                ),
              ),
              Expanded(
                child: _Dato(
                  formato.peso(records.pesoMaximo ?? 0),
                  'Peso máximo',
                ),
              ),
            ],
          ),
          const SizedBox(height: t.l),
          Row(
            children: [
              Expanded(
                child: _Dato(
                  formato.peso(records.volumenTotal),
                  'Volumen total',
                ),
              ),
              Expanded(child: _Dato('${sesiones.length}', 'Sesiones')),
            ],
          ),
          if (!fiable)
            Padding(
              padding: const EdgeInsets.only(top: t.s, left: t.l, right: t.l),
              child: Text(
                '* Estimado a partir de series de más de '
                '${metricas.maxRepeticionesFiables} repeticiones, así que es '
                'poco fiable y no cuenta como récord.',
                textAlign: TextAlign.center,
                style: ui.estilo(
                  context,
                  size: t.caption,
                  color: context.textoTer,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Grafico extends StatelessWidget {
  const _Grafico({
    required this.registros,
    required this.maximo,
    required this.metrica,
    required this.formato,
  });

  final List<ResumenSesionEjercicio> registros;

  /// El máximo en kilos; el eje se dibuja en la unidad activa.
  final double maximo;

  final Metrica metrica;
  final Formato formato;

  @override
  Widget build(BuildContext context) => BarChart(
    BarChartData(
      // El +15% evita que la barra más alta quede pegada al borde.
      maxY: formato.ajustes.desdeKilos(maximo) * 1.15 + 1,
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
            reservedSize: 40,
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
                toY: formato.ajustes.desdeKilos(metrica.de(r)),
                width: 16,
                // La estimación que sale de una serie larga se pinta apagada,
                // igual que el número de la tarjeta.
                color: metrica == Metrica.unoRm && !r.fiable
                    ? context.textoTer
                    : context.acento,
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
  const _Dato(this.valor, this.etiqueta, {this.atenuado = false});

  final String valor;
  final String etiqueta;

  /// Para la estimación de baja confianza.
  final bool atenuado;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        valor,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: ui.estilo(
          context,
          size: t.title3,
          weight: t.semibold,
          color: atenuado ? context.textoSec : null,
        ),
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
