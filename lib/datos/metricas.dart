/// Métricas de progreso: 1RM estimado, volumen, récords, semana y racha.
///
/// Todo lo de aquí son **funciones puras**: no tocan la base de datos, así que
/// se prueban directamente y con fechas fijas, sin montar nada. Lo que sí
/// consulta —el histórico por sesión, las sesiones con su volumen— vive en
/// `bd.dart` y se pasa como parámetro.
///
/// Los récords **se calculan, no se almacenan**: guardarlos abriría la puerta a
/// que quedaran desincronizados al editar o borrar una sesión, y con volúmenes
/// personales recorrer el histórico en memoria es instantáneo.
library;

import 'bd.dart';

// ── 1RM estimado ─────────────────────────────────────────────────────────────

/// A partir de aquí la estimación deja de ser fiable.
///
/// Una serie de 20 repeticiones dice mucho de la resistencia y poco de la
/// fuerza máxima: se calcula igual, pero se marca y no cuenta para un récord.
const maxRepeticionesFiables = 12;

/// Tope de repeticiones que admite Brzycki.
///
/// Su denominador es `37 − repeticiones`: con 37 divide por cero y a partir de
/// ahí devuelve negativos. Se satura ahí, que además es terreno donde la
/// estimación hace mucho que no significa nada.
const _maxBrzycki = 36;

/// El máximo estimado para una repetición a partir de una serie.
///
/// Con **una** repetición devuelve el peso tal cual, sea cual sea la fórmula:
/// levantar 100 kg una vez es un máximo de 100 kg, no de 103,3 que es lo que
/// daría Epley cruda.
double unoRm(double peso, int repeticiones, {Formula formula = Formula.epley}) {
  if (repeticiones <= 1) return peso;
  return switch (formula) {
    Formula.epley => peso * (1 + repeticiones / 30.0),
    Formula.brzycki =>
      peso *
          36.0 /
          (37 -
              (repeticiones > _maxBrzycki ? _maxBrzycki : repeticiones)
                  .toDouble()),
  };
}

/// Si una serie de tantas repeticiones da una estimación de fiar.
bool esFiable(int repeticiones) => repeticiones <= maxRepeticionesFiables;

/// Suma de peso × repeticiones. El calentamiento no cuenta.
double volumen(List<ValoresSerie> series) => series
    .where((s) => !s.calentamiento)
    .fold(0, (suma, s) => suma + s.peso * s.repeticiones);

/// La serie con mejor 1RM estimado, o `null` si no hay ninguna efectiva.
///
/// No es siempre la más pesada: 5×75 kg estima más que 1×80 kg.
ValoresSerie? mejorSerie(
  List<ValoresSerie> series, {
  Formula formula = Formula.epley,
}) {
  ValoresSerie? mejor;
  var maximo = double.negativeInfinity;
  for (final s in series.where((s) => !s.calentamiento)) {
    final estimado = unoRm(s.peso, s.repeticiones, formula: formula);
    if (estimado > maximo) {
      maximo = estimado;
      mejor = s;
    }
  }
  return mejor;
}

// ── Récords de un ejercicio ──────────────────────────────────────────────────

/// Los tres récords personales de un ejercicio.
///
/// Los tres son nulos mientras el ejercicio no tenga ninguna serie efectiva
/// registrada. El de 1RM además puede faltar cuando todas las series son de
/// más de [maxRepeticionesFiables] repeticiones.
class RecordsEjercicio {
  const RecordsEjercicio({
    this.pesoMaximo,
    this.mejor1RM,
    this.volumenMaximo,
    this.volumenTotal = 0,
  });

  /// El peso más alto movido en una serie efectiva.
  final double? pesoMaximo;

  /// El mejor 1RM estimado, contando solo las series fiables.
  final double? mejor1RM;

  /// El volumen más alto de una sola sesión.
  final double? volumenMaximo;

  /// La suma del volumen de todas las sesiones.
  final double volumenTotal;
}

/// Los récords que salen de un histórico por sesión.
///
/// La lista es la que devuelve `AppBD.resumenSesionesEjercicio`, ya agregada
/// por sesión, así que esto es un recorrido y no una consulta. Borrar la sesión
/// que tenía el récord lo pasa solo a la siguiente mejor: no hay nada guardado
/// que actualizar.
RecordsEjercicio recordsEjercicio(List<ResumenSesionEjercicio> sesiones) {
  double? maximo(Iterable<double?> valores) {
    double? mejor;
    for (final v in valores) {
      if (v != null && (mejor == null || v > mejor)) mejor = v;
    }
    return mejor;
  }

  return RecordsEjercicio(
    pesoMaximo: maximo(sesiones.map((s) => s.pesoMaximo)),
    mejor1RM: maximo(sesiones.map((s) => s.mejor1RMFiable)),
    volumenMaximo: maximo(sesiones.map((s) => s.volumen)),
    volumenTotal: sesiones.fold(0, (suma, s) => suma + s.volumen),
  );
}

/// Ids de las sesiones que, **en su día**, batieron alguno de los tres récords.
///
/// Se recorre en orden de fecha con un máximo corriente, así que marca lo que
/// fue un récord al hacerlo y no lo que hoy sigue siéndolo: es lo que tiene
/// sentido en una lista de histórico, donde cada fila es un día concreto.
Set<int> sesionesConRecord(List<ResumenSesionEjercicio> sesiones) {
  final marcadas = <int>{};
  var mejorPeso = double.negativeInfinity;
  var mejor1RM = double.negativeInfinity;
  var mejorVolumen = double.negativeInfinity;

  // La consulta ya las devuelve de la más antigua a la más reciente, pero esto
  // no puede depender de eso: ordenar una lista de decenas de elementos no se
  // nota y evita un fallo silencioso si algún día cambia el ORDER BY.
  final ordenadas = [...sesiones]
    ..sort((a, b) {
      final porFecha = a.fecha.compareTo(b.fecha);
      return porFecha != 0
          ? porFecha
          : a.idEntrenamiento.compareTo(b.idEntrenamiento);
    });

  for (final s in ordenadas) {
    var record = false;
    if (s.pesoMaximo > mejorPeso) {
      mejorPeso = s.pesoMaximo;
      record = true;
    }
    if (s.mejor1RMFiable case final fiable? when fiable > mejor1RM) {
      mejor1RM = fiable;
      record = true;
    }
    if (s.volumen > mejorVolumen) {
      mejorVolumen = s.volumen;
      record = true;
    }
    if (record) marcadas.add(s.idEntrenamiento);
  }
  return marcadas;
}

// ── La semana ────────────────────────────────────────────────────────────────

/// El lunes de la semana de [fecha], a medianoche.
///
/// La semana va de lunes a domingo, coherente con `formato.diasSemana`. En Dart
/// `weekday` da 1 para el lunes, así que restar `weekday - 1` días cae siempre
/// en su lunes.
DateTime lunesDe(DateTime fecha) {
  final dia = DateTime(fecha.year, fecha.month, fecha.day);
  return dia.subtract(Duration(days: dia.weekday - 1));
}

/// Lo que una semana dio de sí.
class ResumenSemana {
  const ResumenSemana({
    required this.lunes,
    required this.sesiones,
    required this.volumen,
  });

  /// El lunes al que corresponde, a medianoche.
  final DateTime lunes;

  final int sesiones;
  final double volumen;

  bool get vacia => sesiones == 0;
}

/// Agrupa las sesiones por semana. La clave es el lunes de cada una.
///
/// Se agrupa **en Dart** y no con un `strftime` de SQLite a propósito: las
/// funciones de fecha de SQLite trabajan en UTC, de modo que en huso local
/// partirían mal las semanas —y peor todavía en el cambio de año—. Una consulta
/// trae las sesiones y el reparto se hace aquí, que además es lo que permite
/// probarlo con fechas fijas y sin base de datos.
Map<DateTime, ResumenSemana> porSemana(List<SesionConVolumen> sesiones) {
  final cuentas = <DateTime, int>{};
  final volumenes = <DateTime, double>{};

  for (final s in sesiones) {
    final lunes = lunesDe(s.fecha);
    cuentas[lunes] = (cuentas[lunes] ?? 0) + 1;
    volumenes[lunes] = (volumenes[lunes] ?? 0) + s.volumen;
  }

  return {
    for (final lunes in cuentas.keys)
      lunes: ResumenSemana(
        lunes: lunes,
        sesiones: cuentas[lunes]!,
        volumen: volumenes[lunes]!,
      ),
  };
}

/// El resumen de la semana que empieza en [lunes].
///
/// Una semana sin sesiones devuelve un resumen a cero, no `null`: «esta semana
/// llevas 0 de 4» es una respuesta, y la ausencia de datos se distingue con
/// [ResumenSemana.vacia].
ResumenSemana resumenSemana(List<SesionConVolumen> sesiones, DateTime lunes) =>
    porSemana(sesiones)[lunesDe(lunes)] ??
    ResumenSemana(lunes: lunesDe(lunes), sesiones: 0, volumen: 0);

/// Semanas consecutivas cumpliendo el objetivo, **sin contar la semana en
/// curso**.
///
/// La semana en curso no rompe la racha hasta que acaba: si contara, el lunes
/// por la mañana toda racha valdría cero. Se cuenta hacia atrás desde la semana
/// pasada y se para en la primera semana cerrada que no llegó al objetivo.
int rachaSemanas(
  List<SesionConVolumen> sesiones,
  int objetivo, {
  required DateTime hoy,
}) {
  if (objetivo <= 0) return 0;
  final semanas = porSemana(sesiones);
  if (semanas.isEmpty) return 0;

  // El tope no es una arbitrariedad prudente: es el suelo de los datos. Sin él,
  // una racha que llegara hasta la primera semana registrada seguiría contando
  // semanas vacías hacia atrás para siempre.
  final primera = semanas.keys.reduce((a, b) => a.isBefore(b) ? a : b);

  var racha = 0;
  var semana = lunesDe(hoy).subtract(const Duration(days: 7));
  while (!semana.isBefore(primera)) {
    if ((semanas[semana]?.sesiones ?? 0) < objetivo) break;
    racha++;
    semana = semana.subtract(const Duration(days: 7));
  }
  return racha;
}

/// Variación relativa entre dos valores, en tanto por uno.
///
/// Devuelve `null` cuando no hay con qué comparar: sin la semana anterior, la
/// comparativa se omite en vez de enseñar un `+0 %` que no significa nada.
double? variacion(num actual, num anterior) {
  if (anterior <= 0) return null;
  return (actual - anterior) / anterior;
}
