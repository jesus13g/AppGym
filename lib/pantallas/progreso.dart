/// Pestaña de progreso: resumen por rutina y calendario de entrenamientos.
///
/// A diferencia de la versión Flet, la pestaña elegida y el mes visible son
/// estado del widget: no hay que meterlos en los parámetros de la ruta ni
/// reconstruir la pila para conservarlos.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/bd.dart';
import '../datos/formato.dart' as formato;
import '../datos/metricas.dart' as metricas;
import '../datos/reloj.dart' as reloj;
import '../estado/providers.dart';
import '../tema/tokens.dart';
import '../tema/tokens.dart' as t;
import '../tema/ui.dart' as ui;
import 'medidas.dart';
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
                // Tres opciones caben; con una cuarta el texto empezaría a
                // apretarse en un móvil estrecho.
                children: const {
                  0: Padding(
                    padding: EdgeInsets.symmetric(vertical: t.xs),
                    child: Text('Resumen'),
                  ),
                  1: Padding(
                    padding: EdgeInsets.symmetric(vertical: t.xs),
                    child: Text('Calendario'),
                  ),
                  2: Padding(
                    padding: EdgeInsets.symmetric(vertical: t.xs),
                    child: Text('Cuerpo'),
                  ),
                },
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: switch (_pestana) {
            0 => const _Resumen(),
            1 => _Calendario(
              mes: _mes,
              onMes: (nuevo) => setState(() => _mes = nuevo),
            ),
            _ => const _Cuerpo(),
          },
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

        return Column(
          children: [
            const _Semana(),
            ui.Grupo(
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
            ),
          ],
        );
      },
    );
  }
}

// ── C17: la semana y la racha ────────────────────────────────────────────────

/// Cuántos días sin entrenar hacen falta para decirlo.
const _diasAviso = 7;

/// La tarjeta que responde a «¿voy bien esta semana?».
///
/// Sesiones frente al objetivo de Ajustes, volumen, comparativa con la semana
/// anterior, racha y los últimos siete días. Todo sale de **una** consulta
/// (`sesionesRecientesProvider`) más los colores de las rutinas, que ya están
/// cargados para la leyenda del calendario.
///
/// No aparece si no hay ninguna sesión registrada: ahí manda el `EstadoVacio`
/// de la pestaña, que ya explica por dónde empezar.
class _Semana extends ConsumerWidget {
  const _Semana();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesiones = ref.watch(sesionesRecientesProvider).value ?? const [];
    if (sesiones.isEmpty) return const SizedBox.shrink();

    final ajustes = ref.watch(ajustesProvider).value ?? const Ajustes();
    final colores = ref.watch(coloresRutinasProvider).value ?? const {};
    final objetivo = ajustes.sesionesPorSemana;

    // El «hoy» sale del reloj de la app y no de `DateTime.now()`, que es lo que
    // permite a los tests fijar la semana en vez de depender de cuándo corran.
    final hoy = reloj.ahora();
    final lunes = metricas.lunesDe(hoy);
    final estaSemana = metricas.resumenSemana(sesiones, lunes);
    final anterior = metricas.resumenSemana(
      sesiones,
      lunes.subtract(const Duration(days: 7)),
    );
    final racha = metricas.rachaSemanas(sesiones, objetivo, hoy: hoy);

    // La lista viene de la más reciente a la más antigua, así que la primera es
    // la última sesión.
    final ultima = sesiones.first.fecha;
    final diasSinEntrenar = DateTime(
      hoy.year,
      hoy.month,
      hoy.day,
    ).difference(DateTime(ultima.year, ultima.month, ultima.day)).inDays;

    return ui.Grupo(
      cabecera: 'Esta semana',
      filas: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: t.m, vertical: t.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${estaSemana.sesiones} de $objetivo',
                      style: ui.estilo(context, size: t.title2, weight: t.bold),
                    ),
                  ),
                  Flexible(
                    child: Text(
                      formato.peso(estaSemana.volumen, ajustes),
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ui.estilo(
                        context,
                        size: t.subhead,
                        color: context.textoSec,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: t.s),
              ui.BarraProgreso(
                objetivo == 0 ? 0 : estaSemana.sesiones / objetivo,
              ),
              if (!anterior.vacia) ...[
                const SizedBox(height: t.m),
                _Comparativa(estaSemana: estaSemana, anterior: anterior),
              ],
              if (racha > 0) ...[
                const SizedBox(height: t.m),
                Row(
                  children: [
                    Icon(
                      CupertinoIcons.flame_fill,
                      size: 16,
                      color: context.acento,
                    ),
                    const SizedBox(width: t.xs),
                    Flexible(
                      child: Text(
                        '${formato.plural(racha, 'semana', 'semanas')} '
                        'seguidas cumpliendo el objetivo',
                        style: ui.estilo(context, size: t.footnote),
                      ),
                    ),
                  ],
                ),
              ],
              if (diasSinEntrenar > _diasAviso) ...[
                const SizedBox(height: t.m),
                Text(
                  'Hace ${formato.plural(diasSinEntrenar, 'día', 'días')} de '
                  'tu último entrenamiento',
                  style: ui.estilo(
                    context,
                    size: t.footnote,
                    color: context.textoSec,
                  ),
                ),
              ],
            ],
          ),
        ),
        _UltimosDias(sesiones: sesiones, colores: colores, hoy: hoy),
      ],
    );
  }
}

/// La variación frente a la semana anterior, con signo y color.
///
/// Sin datos de la semana previa no se pinta —de eso se encarga quien la
/// monta—: un `+0 %` contra la nada no dice nada.
class _Comparativa extends StatelessWidget {
  const _Comparativa({required this.estaSemana, required this.anterior});

  final metricas.ResumenSemana estaSemana;
  final metricas.ResumenSemana anterior;

  @override
  Widget build(BuildContext context) {
    final sesiones = estaSemana.sesiones - anterior.sesiones;
    final volumen = metricas.variacion(estaSemana.volumen, anterior.volumen);

    String conSigno(num valor) => valor > 0 ? '+$valor' : '$valor';

    return Row(
      children: [
        Expanded(
          child: _Variacion(
            texto:
                '${conSigno(sesiones)} '
                '${sesiones.abs() == 1 ? 'sesión' : 'sesiones'}',
            signo: sesiones,
          ),
        ),
        if (volumen != null)
          Expanded(
            child: _Variacion(
              texto: '${conSigno((volumen * 100).round())} % de volumen',
              signo: volumen,
            ),
          ),
      ],
    );
  }
}

class _Variacion extends StatelessWidget {
  const _Variacion({required this.texto, required this.signo});

  final String texto;

  /// Positivo, negativo o cero; solo se mira el signo.
  final num signo;

  @override
  Widget build(BuildContext context) => Text(
    texto,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: ui.estilo(
      context,
      size: t.footnote,
      color: switch (signo) {
        > 0 => context.exito,
        < 0 => context.destructivo,
        _ => context.textoSec,
      },
    ),
  );
}

/// Siete puntos, uno por día de la semana en curso, con el color de la rutina.
///
/// De lunes a domingo, coherente con `formato.diasSemana` y con la semana que
/// mide la racha.
class _UltimosDias extends StatelessWidget {
  const _UltimosDias({
    required this.sesiones,
    required this.colores,
    required this.hoy,
  });

  final List<SesionConVolumen> sesiones;
  final Map<int, (String, String)> colores;
  final DateTime hoy;

  @override
  Widget build(BuildContext context) {
    final lunes = metricas.lunesDe(hoy);
    final dia = DateTime(hoy.year, hoy.month, hoy.day);

    /// La rutina entrenada ese día, si hubo alguna.
    int? rutinaDe(DateTime cuando) {
      for (final s in sesiones) {
        if (s.fecha.year == cuando.year &&
            s.fecha.month == cuando.month &&
            s.fecha.day == cuando.day) {
          return s.idRutina;
        }
      }
      return null;
    }

    return Padding(
      padding: const EdgeInsets.only(
        left: t.m,
        right: t.m,
        top: t.s,
        bottom: t.m,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final (indice, etiqueta) in formato.diasSemana.indexed)
            Builder(
              builder: (_) {
                final cuando = lunes.add(Duration(days: indice));
                final idRutina = rutinaDe(cuando);
                // Los días que aún no han llegado se apagan: no son días sin
                // entrenar, son días que no han pasado.
                final futuro = cuando.isAfter(dia);

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      etiqueta,
                      style: ui.estilo(
                        context,
                        size: t.caption,
                        color: futuro ? context.textoTer : context.textoSec,
                      ),
                    ),
                    const SizedBox(height: t.xs),
                    ui.PuntoColor(
                      idRutina == null
                          ? (futuro ? context.relleno : context.separador)
                          : colorDesdeHex(
                              colores[idRutina]?.$2,
                              context.acento,
                            ),
                      tamano: 10,
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

// ── Cuerpo ───────────────────────────────────────────────────────────────────

/// Las medidas del cuerpo, con el peso corporal delante.
///
/// Si hace más de una semana que no se registra el peso, lo ofrece de un toque:
/// una serie de peso corporal con huecos de un mes no dice gran cosa.
class _Cuerpo extends ConsumerWidget {
  const _Cuerpo();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ajustes = ref.watch(ajustesProvider).value ?? const Ajustes();
    final ultimoPeso = ref.watch(ultimaMedidaProvider('peso')).value;
    final dias = ultimoPeso == null
        ? null
        : DateTime.now().difference(ultimoPeso.fecha).inDays;

    return Column(
      children: [
        if (dias == null || dias >= diasAvisoPeso)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: t.l, vertical: t.s),
            child: ui.BotonPrincipal(
              ultimoPeso == null
                  ? 'Registrar tu peso'
                  : 'Actualizar tu peso (${formato.hace(ultimoPeso.fecha).toLowerCase()})',
              icono: CupertinoIcons.plus_circle,
              onPressed: () => registrarMedida(context, ref, 'peso'),
            ),
          ),
        ui.Grupo(
          cabecera: 'Medidas',
          pie:
              'El peso corporal es el contexto de las cargas: subir en press '
              'perdiendo peso no es lo mismo que subir ganándolo.',
          filas: [
            for (final (clave, nombre, _) in tiposMedida)
              _FilaMedida(clave: clave, nombre: nombre, ajustes: ajustes),
          ],
        ),
      ],
    );
  }
}

class _FilaMedida extends ConsumerWidget {
  const _FilaMedida({
    required this.clave,
    required this.nombre,
    required this.ajustes,
  });

  final String clave;
  final String nombre;
  final Ajustes ajustes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ultima = ref.watch(ultimaMedidaProvider(clave)).value;

    return CupertinoListTile(
      backgroundColor: context.tarjeta,
      title: Text(nombre, style: ui.estilo(context)),
      subtitle: Text(
        ultima == null ? 'Sin registros' : formato.hace(ultima.fecha),
        style: ui.estilo(context, size: t.footnote, color: context.textoSec),
      ),
      additionalInfo: ultima == null
          ? null
          : Text(
              valorMedida(ultima.valor, clave, ajustes),
              style: ui.estilo(context, weight: t.semibold),
            ),
      trailing: const CupertinoListTileChevron(),
      onTap: () => abrirMedidas(context, tipo: clave),
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
