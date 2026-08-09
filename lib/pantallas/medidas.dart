/// Peso corporal y perímetros: registro y evolución.
///
/// La app medía las cargas pero no al usuario, y el peso corporal es el
/// contexto que las explica: subir 5 kg en press perdiendo 3 kg de peso no es
/// el mismo resultado que subirlos ganando 4.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/bd.dart';
import '../datos/formato.dart';
import '../estado/providers.dart';
import '../l10n/textos.dart';
import '../tema/tokens.dart';
import '../tema/tokens.dart' as t;
import '../tema/ui.dart' as ui;

/// Ventana de la media móvil del peso corporal.
///
/// Los saltos diarios de ±1 kg son agua y comida, no grasa ni músculo: sin
/// suavizarlos, la tendencia —que es lo único que importa— no se ve.
const ventanaMedia = 7;

/// Cada cuánto conviene volver a pesarse antes de que la app lo recuerde.
const diasAvisoPeso = 7;

Future<void> abrirMedidas(BuildContext context, {String tipo = 'peso'}) =>
    Navigator.of(context).push(
      CupertinoPageRoute<void>(builder: (_) => PantallaMedidas(tipo: tipo)),
    );

class PantallaMedidas extends ConsumerStatefulWidget {
  const PantallaMedidas({super.key, this.tipo = 'peso'});

  final String tipo;

  @override
  ConsumerState<PantallaMedidas> createState() => _PantallaMedidasState();
}

class _PantallaMedidasState extends ConsumerState<PantallaMedidas> {
  late String _tipo = widget.tipo;

  @override
  Widget build(BuildContext context) {
    final serie = ref.watch(serieMedidaProvider(_tipo)).value ?? const [];
    final f = formatoDe(context, ref);
    final (etiqueta, _) = etiquetaMedida(context.t, _tipo);

    return CupertinoPageScaffold(
      backgroundColor: context.fondo,
      navigationBar: ui.barra(
        context,
        titulo: etiqueta,
        tituloAnterior: context.t.comunProgreso,
        derecha: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          onPressed: () => registrarMedida(context, ref, _tipo),
          child: const Icon(CupertinoIcons.add, size: 22),
        ),
      ),
      child: SafeArea(
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: t.l,
                vertical: t.s,
              ),
              child: SizedBox(
                height: 34,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: tiposMedida.length,
                  separatorBuilder: (_, _) => const SizedBox(width: t.s),
                  itemBuilder: (context, indice) {
                    final (clave, _) = tiposMedida[indice];
                    final (nombre, _) = etiquetaMedida(context.t, clave);
                    final activo = clave == _tipo;
                    return GestureDetector(
                      onTap: () => setState(() => _tipo = clave),
                      child: ui.Pildora(
                        nombre,
                        color: activo ? CupertinoColors.white : context.texto,
                        relleno: activo ? context.acento : context.relleno,
                      ),
                    );
                  },
                ),
              ),
            ),
            if (serie.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: t.xxl),
                child: ui.EstadoVacio(
                  icono: CupertinoIcons.chart_bar_alt_fill,
                  titulo: context.t.medidasSinRegistros(etiqueta),
                  subtitulo: context.t.medidasVacioDetalle,
                  accion: ui.BotonPrincipal(
                    context.t.medidasRegistrar,
                    icono: CupertinoIcons.add,
                    onPressed: () => registrarMedida(context, ref, _tipo),
                  ),
                ),
              )
            else ...[
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
                child: _Grafico(serie: serie, tipo: _tipo, formato: f),
              ),
              if (_tipo == 'peso')
                Padding(
                  padding: const EdgeInsets.only(
                    left: t.l,
                    right: t.l,
                    top: t.s,
                  ),
                  child: Text(
                    context.t.medidasNotaMedia(ventanaMedia),
                    textAlign: TextAlign.center,
                    style: ui.estilo(
                      context,
                      size: t.caption,
                      color: context.textoTer,
                    ),
                  ),
                ),
              ui.Grupo(
                cabecera: context.t.comunHistorico,
                pie: context.t.medidasPieHistorico,
                filas: [
                  for (final medida in serie.reversed)
                    ui.DeslizarParaBorrar(
                      llave: ValueKey(medida.id),
                      onBorrar: () => _borrar(medida),
                      child: CupertinoListTile(
                        backgroundColor: context.tarjeta,
                        title: Text(
                          f.fechaLarga(medida.fecha),
                          style: ui.estilo(context),
                        ),
                        additionalInfo: Text(
                          valorMedida(medida.valor, _tipo, f),
                          style: ui.estilo(context, weight: t.semibold),
                        ),
                        onTap: () => registrarMedida(
                          context,
                          ref,
                          _tipo,
                          fecha: medida.fecha,
                          valor: medida.valor,
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: t.xxl),
          ],
        ),
      ),
    );
  }

  Future<void> _borrar(Medida medida) async {
    await ref.read(bdProvider).borrarMedida(medida.fecha, medida.tipo);
    invalidarMedidas(ref);
  }
}

/// Un valor con su unidad, ya convertido si hace falta.
///
/// El peso corporal es lo único que va en kilos y, por tanto, lo único que se
/// convierte a libras. Los perímetros son centímetros y la grasa, por ciento:
/// esos no dependen de la unidad de las cargas.
String valorMedida(double valor, String tipo, Formato f) {
  if (tipo == 'peso') return f.peso(valor);
  final (_, unidad) = etiquetaMedida(f.textos, tipo);
  return '${f.numero((valor * 10).round() / 10)} $unidad';
}

/// Pide un valor y lo guarda. Repetir el mismo día sustituye al anterior.
Future<void> registrarMedida(
  BuildContext context,
  WidgetRef ref,
  String tipo, {
  DateTime? fecha,
  double? valor,
}) async {
  final f = leerFormato(context, ref);
  final ajustes = f.ajustes;
  final (etiqueta, unidad) = etiquetaMedida(f.textos, tipo);
  // Se pide en la unidad que el usuario ve; se guarda siempre en kilos.
  final enPantalla = valor == null
      ? null
      : (tipo == 'peso' ? ajustes.desdeKilos(valor) : valor);

  final texto = await ui.dialogoTexto(
    context,
    titulo: etiqueta,
    marcador: tipo == 'peso' ? ajustes.unidad.sufijo : unidad,
    valor: enPantalla == null ? '' : f.numero((enPantalla * 10).round() / 10),
    mensaje: context.t.medidasUnoPorDia,
    etiquetaAceptar: context.t.comunGuardar,
    etiquetaCancelar: context.t.comunCancelar,
  );
  if (texto == null || !context.mounted) return;

  // Coma decimal: el teclado español la escribe y `double.parse` solo entiende
  // el punto.
  final numero = double.tryParse(texto.replaceAll(',', '.'));
  if (numero == null || numero <= 0) {
    ui.aviso(context, context.t.medidasNumeroInvalido);
    return;
  }

  await ref
      .read(bdProvider)
      .registrarMedida(
        fecha ?? DateTime.now(),
        tipo,
        tipo == 'peso' ? ajustes.aKilos(numero) : numero,
      );
  if (!context.mounted) return;
  invalidarMedidas(ref);
}

/// Media móvil de [ventana] valores, alineada al final.
///
/// Los primeros puntos promedian lo que hay: empezar la línea el séptimo día
/// dejaría el gráfico medio vacío la primera semana, que es justo cuando más se
/// mira.
List<double> mediaMovil(List<double> valores, {int ventana = ventanaMedia}) => [
  for (final (indice, _) in valores.indexed)
    () {
      final desde = indice - ventana + 1;
      final trozo = valores.sublist(desde < 0 ? 0 : desde, indice + 1);
      return trozo.reduce((a, b) => a + b) / trozo.length;
    }(),
];

/// Evolución en el tiempo.
///
/// `LineChart` y no el `BarChart` del progreso por ejercicio: esto es una serie
/// temporal continua, y las barras sugerirían que cada día es una medición
/// independiente de las de al lado.
class _Grafico extends StatelessWidget {
  const _Grafico({
    required this.serie,
    required this.tipo,
    required this.formato,
  });

  final List<Medida> serie;
  final String tipo;
  final Formato formato;

  /// Los valores en la unidad que se está mostrando.
  List<double> get _valores => [
    for (final m in serie)
      tipo == 'peso' ? formato.ajustes.desdeKilos(m.valor) : m.valor,
  ];

  @override
  Widget build(BuildContext context) {
    final valores = _valores;
    final media = mediaMovil(valores);
    final minimo = valores.reduce((a, b) => a < b ? a : b);
    final maximo = valores.reduce((a, b) => a > b ? a : b);
    // Un margen del 10 % del recorrido, con un mínimo: sin él, una serie plana
    // dejaría la línea pegada al borde.
    final margen = ((maximo - minimo) * 0.1).clamp(0.5, 1000.0);

    return LineChart(
      LineChartData(
        minY: minimo - margen,
        maxY: maximo + margen,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: context.separador,
            strokeWidth: 0.5,
            dashArray: const [4, 4],
          ),
        ),
        lineTouchData: const LineTouchData(enabled: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 38,
              getTitlesWidget: (valor, meta) => Text(
                formato.numero((valor * 10).round() / 10),
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
              // Solo los extremos: con veinte pesadas, una etiqueta por punto
              // se convierte en una mancha ilegible.
              interval: (serie.length - 1).clamp(1, 1000).toDouble(),
              getTitlesWidget: (valor, meta) {
                final indice = valor.round();
                if (indice < 0 || indice >= serie.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: t.xs),
                  child: Text(
                    formato.fechaCorta(serie[indice].fecha),
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
        lineBarsData: [
          // Los puntos reales, sin línea: son el dato bruto.
          LineChartBarData(
            spots: [
              for (final (indice, v) in valores.indexed)
                FlSpot(indice.toDouble(), v),
            ],
            color: context.textoTer,
            barWidth: 0,
            dotData: FlDotData(
              getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                radius: 2.5,
                color: context.textoTer,
                strokeWidth: 0,
              ),
            ),
          ),
          // Y encima la tendencia, que es lo que se lee de un vistazo.
          if (tipo == 'peso')
            LineChartBarData(
              spots: [
                for (final (indice, v) in media.indexed)
                  FlSpot(indice.toDouble(), v),
              ],
              color: context.acento,
              barWidth: 2.5,
              isCurved: true,
              curveSmoothness: 0.2,
              dotData: const FlDotData(show: false),
            ),
        ],
      ),
    );
  }
}
