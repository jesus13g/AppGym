/// Qué hacer hoy con un ejercicio: doble progresión, estancamiento y descarga.
///
/// Tercer módulo puro de la app, con la misma forma que `metricas.dart` y
/// `musculos.dart`: **no importa Flutter, no toca la base de datos**, recibe
/// listas y devuelve valores. Las dos entradas que necesita —el historial por
/// sesión y las series de la última— son las que las pantallas ya piden, así que
/// esto no añade ni una consulta.
///
/// El modelo es la **doble progresión**: con el peso actual se sube de
/// repeticiones dentro de un rango sesión a sesión y, cuando todas las series
/// efectivas llegan al tope, se sube el peso un escalón y se vuelve al suelo.
///
/// Devolver `null` es la mitad del diseño. Sin dos sesiones previas, en cardio o
/// con la progresión desactivada no hay sugerencia y la interfaz no enseña nada:
/// una sugerencia inventada el primer día vale menos que ninguna.
library;

import 'bd.dart';

// ── Vocabulario ──────────────────────────────────────────────────────────────

/// Qué hacer hoy con un ejercicio.
enum TipoSugerencia {
  subirPeso,
  subirRepeticiones,
  mantener,
  bajarPeso,
  descarga,
}

/// El porqué, **como dato y no como texto**.
///
/// La frase se compone en la pantalla, que es la que sabe el idioma: cuando
/// entre el bloque I esto no habrá que tocarlo.
enum MotivoSugerencia {
  /// Todas las series llegaron al tope del rango.
  rangoCompletado,

  /// Falta llegar al tope en alguna serie.
  rangoIncompleto,

  /// RPE medio ≥ 9,5: no se sube aunque tocara.
  esfuerzoAlto,

  /// RPE medio ≤ 7 con el rango completo.
  esfuerzoBajo,

  /// Repeticiones por debajo del suelo del rango.
  repeticionesCaidas,

  /// Dos sesiones sin mejorar.
  estancado,

  /// Tres sesiones estancado.
  descargaSugerida,
}

/// Cómo progresa un ejercicio.
///
/// El orden **es** el valor que se guarda en `ejercicios.estrategia`, así que no
/// se reordena: añadir una estrategia nueva se hace al final.
enum Estrategia {
  /// Sin sugerencias para este ejercicio.
  desactivada,

  /// Repeticiones dentro del rango y, al completarlo, un escalón de peso.
  dobleProgresion,

  /// Solo repeticiones, sin tocar el peso. Es lo que toca en peso corporal.
  soloRepeticiones,
}

/// Rangos de repeticiones que se ofrecen, del más pesado al más ligero.
///
/// Son los que se enseñan en la hoja del ejercicio y contra los que se
/// aproxima [rangoObservado]: proponer «7–13» porque es la media exacta del
/// historial sería precisión falsa.
const rangosRepeticiones = <(int, int)>[
  (3, 5),
  (5, 8),
  (6, 10),
  (8, 12),
  (10, 15),
  (12, 20),
  (15, 25),
];

/// Rango por defecto de un ejercicio de peso corporal.
///
/// Sin escalón que subir, la progresión es solo por repeticiones y el rango se
/// amplía: en dominadas, ir de 8 a 12 y no poder subir peso deja la sugerencia
/// sin salida a la tercera sesión.
const rangoPesoCorporal = (5, 15);

/// A partir de aquí no se sube peso aunque el rango esté completo.
const rpeAlto = 9.5;

/// Por debajo de aquí, con el rango completo, se puede subir doble.
const rpeBajo = 7.0;

/// Sesiones consecutivas sin mejorar que declaran el estancamiento.
const sesionesParaEstancarse = 3;

/// Cuánto baja la descarga cuando el historial no dice a qué peso volver.
const fraccionDescarga = 0.10;

// ── Configuración ────────────────────────────────────────────────────────────

/// Los tres niveles de configuración de J2, ya resueltos en uno.
///
/// Global (la tabla `ajustes`) ← por ejercicio (las cuatro columnas anulables de
/// `ejercicios`, donde `null` significa «como el global») ← lo que imponen el
/// propio ejercicio y su historial (cardio y peso corporal).
class ConfiguracionProgresion {
  const ConfiguracionProgresion({
    this.repMin = 8,
    this.repMax = 12,
    this.incrementoKg = 2.5,
    this.estrategia = Estrategia.dobleProgresion,
    this.perfil = Perfil.estandar,
    this.esfuerzoActivo = false,
  });

  /// Resuelve los tres niveles para un ejercicio concreto.
  ///
  /// [pesoCorporal] no es una preferencia sino un hecho del historial: lo decide
  /// [esDePesoCorporal] mirando las series, no el equipamiento del catálogo,
  /// porque un usuario puede hacer dominadas lastradas y entonces sí hay peso.
  factory ConfiguracionProgresion.resolver(
    EjercicioConFicha ejercicio,
    Ajustes ajustes, {
    bool pesoCorporal = false,
  }) {
    final fila = ejercicio.ejercicio;

    // El escalón global está en la unidad activa (`ajustes.pasoPeso` alimenta el
    // selector de peso); la columna, en kilogramos. Se traduce aquí, y una sola
    // vez, para que el resto del módulo trabaje siempre en kilos.
    final incremento = fila.incrementoKg ?? ajustes.aKilos(ajustes.pasoPeso);

    final estrategia = switch (fila.estrategia) {
      // Cardio nunca, sea cual sea lo configurado: series y repeticiones no
      // describen una carrera, y una sugerencia mala en un sitio resta
      // credibilidad a las buenas de todos los demás.
      _ when esCardio(ejercicio.ficha) => Estrategia.desactivada,
      _ when !ajustes.progresionActiva && fila.estrategia == null =>
        Estrategia.desactivada,
      final int guardado
          when guardado >= 0 && guardado < Estrategia.values.length =>
        Estrategia.values[guardado],
      // Sin peso no hay escalón que subir, así que la doble progresión global se
      // degrada a solo repeticiones.
      _ when pesoCorporal => Estrategia.soloRepeticiones,
      _ => Estrategia.dobleProgresion,
    };

    final (minPorDefecto, maxPorDefecto) = pesoCorporal
        ? rangoPesoCorporal
        : (ajustes.repMinGlobal, ajustes.repMaxGlobal);

    final min = fila.repMin ?? minPorDefecto;
    final max = fila.repMax ?? maxPorDefecto;

    return ConfiguracionProgresion(
      repMin: min,
      // Un rango invertido no se rechaza: se endereza. Viene de una copia de
      // seguridad editada a mano o de un ajuste a medio hacer, y no puede
      // impedir que el ejercicio tenga sugerencia.
      repMax: max < min ? min : max,
      incrementoKg: incremento > 0 ? incremento : 2.5,
      estrategia: estrategia,
      perfil: ajustes.perfilProgresion,
      esfuerzoActivo: ajustes.esfuerzoActivo,
    );
  }

  /// Suelo del rango de repeticiones.
  final int repMin;

  /// Tope del rango de repeticiones.
  final int repMax;

  /// Escalón de peso, **en kilogramos**.
  final double incrementoKg;

  final Estrategia estrategia;
  final Perfil perfil;

  /// Si el usuario registra el esfuerzo. Cuando no, el modelo va solo con
  /// repeticiones — que es el caso por defecto y no puede ser el degradado.
  final bool esfuerzoActivo;
}

/// Si un ejercicio del catálogo es cardio y por tanto no recibe sugerencia.
///
/// Se mira `bodyPart` **y** `target`: el filtro del catálogo usa el primero y el
/// mapa muscular el segundo, y hay ejercicios que solo encajan por uno de los
/// dos. Un ejercicio personalizado (sin ficha) no es cardio: no hay dato que lo
/// diga y suponerlo dejaría sin sugerencia a todo lo que el usuario cree.
bool esCardio(FichaCatalogo? ficha) =>
    ficha != null &&
    (ficha.bodyPart == 'cardio' || ficha.target == 'cardiovascular system');

/// Si el ejercicio se hace sin peso: dominadas, fondos, plancha.
///
/// Se decide por el historial y no por el equipamiento del catálogo, porque unas
/// dominadas lastradas sí tienen peso que subir. Basta con que **una** serie
/// efectiva haya llevado peso para dejar de considerarlo peso corporal.
bool esDePesoCorporal(
  List<ResumenSesionEjercicio> historial,
  List<ValoresSerie> ultimasSeries,
) {
  if (historial.isEmpty && ultimasSeries.isEmpty) return false;
  final conPeso =
      historial.any((s) => s.pesoMaximo > 0) ||
      ultimasSeries.any((s) => !s.calentamiento && s.peso > 0);
  return !conPeso;
}

// ── La sugerencia ────────────────────────────────────────────────────────────

/// Lo que se propone hacer hoy con un ejercicio.
class Sugerencia {
  const Sugerencia({
    required this.tipo,
    required this.motivo,
    required this.series,
    this.deltaPeso = 0,
    this.fiable = true,
  });

  final TipoSugerencia tipo;
  final MotivoSugerencia motivo;

  /// Las series propuestas, listas para precargar el registro.
  final List<ValoresSerie> series;

  /// Diferencia con la última sesión, en kilogramos. Puede ser negativa o cero.
  final double deltaPeso;

  /// `false` cuando el historial es corto o el esfuerzo no está registrado.
  ///
  /// Se enseña igual, pero marcada, como el 1RM de más de doce repeticiones.
  final bool fiable;

  /// El peso que proponen las series, o cero si no hay ninguna.
  double get peso => series.isEmpty ? 0 : series.first.peso;
}

/// Qué hacer hoy con un ejercicio, o `null` si no hay nada que decir.
///
/// [historial] es lo que devuelve `AppBD.resumenSesionesEjercicio`, de la sesión
/// más antigua a la más reciente, y [ultimasSeries] lo que devuelve
/// `AppBD.ultimasSeriesEjercicio`. Las series de calentamiento no cuentan, igual
/// que en `metricas.volumen`.
///
/// [descargaYaSugerida] evita que la descarga se repita: se propone una vez y,
/// si se ignora, la sesión siguiente vuelve a la regla normal. Insistir es lo
/// que convierte un consejo en una regañina.
Sugerencia? sugerir(
  List<ResumenSesionEjercicio> historial,
  List<ValoresSerie> ultimasSeries,
  ConfiguracionProgresion config, {
  bool descargaYaSugerida = false,
}) {
  if (config.estrategia == Estrategia.desactivada) return null;

  // Menos de dos sesiones registradas: no hay tendencia que leer.
  if (historial.length < 2) return null;

  final efectivas = [
    for (final s in ultimasSeries)
      if (!s.calentamiento) s,
  ];
  if (efectivas.isEmpty) return null;

  final pesoBase = efectivas.map((s) => s.peso).reduce((a, b) => a > b ? a : b);
  final soloRepeticiones = config.estrategia == Estrategia.soloRepeticiones;

  // El esfuerzo entra **solo** si el usuario lo registra: es opcional y está
  // desactivado de fábrica, así que el modelo tiene que funcionar sin él.
  final conEsfuerzo =
      config.esfuerzoActivo && efectivas.every((s) => s.rpe != null);
  final rpeMedio = conEsfuerzo
      ? efectivas.map((s) => s.rpe!).reduce((a, b) => a + b) / efectivas.length
      : null;

  // Historial corto o sin esfuerzo: se enseña igual, pero marcada.
  final fiable = historial.length >= 3 && conEsfuerzo;

  // ── Estancamiento y descarga ──
  if (!descargaYaSugerida &&
      sesionesSinMejorar(historial) >= sesionesParaEstancarse) {
    final destino = _pesoDeDescarga(historial, config, pesoBase);
    return Sugerencia(
      tipo: TipoSugerencia.descarga,
      motivo: MotivoSugerencia.descargaSugerida,
      series: [
        for (final s in efectivas)
          s.copiar(repeticiones: config.repMin, peso: destino, sinRpe: true),
      ],
      deltaPeso: destino - pesoBase,
      fiable: fiable,
    );
  }

  // ── Doble progresión ──
  final alTope = efectivas.every((s) => s.repeticiones >= config.repMax);
  final caidas =
      efectivas.where((s) => s.repeticiones < config.repMin).length >
      efectivas.length / 2;

  if (alTope) {
    if (soloRepeticiones) {
      // Sin peso que subir, completar el rango no tiene premio: se mantiene y se
      // deja que el rango propio del ejercicio (o el observado) haga su trabajo.
      return Sugerencia(
        tipo: TipoSugerencia.mantener,
        motivo: MotivoSugerencia.rangoCompletado,
        series: [for (final s in efectivas) s.copiar(sinRpe: true)],
        fiable: fiable,
      );
    }

    if (rpeMedio != null && rpeMedio >= rpeAlto) {
      return Sugerencia(
        tipo: TipoSugerencia.mantener,
        motivo: MotivoSugerencia.esfuerzoAlto,
        series: [for (final s in efectivas) s.copiar(sinRpe: true)],
        fiable: fiable,
      );
    }

    // El conservador quiere ver el rango completo dos sesiones seguidas antes de
    // cargar la barra.
    if (config.perfil == Perfil.conservador &&
        !_completoElRango(historial[historial.length - 2], config)) {
      return Sugerencia(
        tipo: TipoSugerencia.mantener,
        motivo: MotivoSugerencia.rangoCompletado,
        series: [for (final s in efectivas) s.copiar(sinRpe: true)],
        fiable: fiable,
      );
    }

    final escalones =
        (rpeMedio != null &&
            rpeMedio <= rpeBajo &&
            config.perfil == Perfil.agresivo)
        ? 2
        : 1;
    final destino = redondearAEscalon(
      pesoBase + config.incrementoKg * escalones,
      config.incrementoKg,
    );

    return Sugerencia(
      tipo: TipoSugerencia.subirPeso,
      motivo: escalones == 2
          ? MotivoSugerencia.esfuerzoBajo
          : MotivoSugerencia.rangoCompletado,
      series: [
        for (final s in efectivas)
          s.copiar(repeticiones: config.repMin, peso: destino, sinRpe: true),
      ],
      deltaPeso: destino - pesoBase,
      fiable: fiable,
    );
  }

  if (caidas && !soloRepeticiones) {
    final destino = redondearAEscalon(
      pesoBase - config.incrementoKg,
      config.incrementoKg,
    );
    return Sugerencia(
      tipo: TipoSugerencia.bajarPeso,
      motivo: MotivoSugerencia.repeticionesCaidas,
      series: [
        for (final s in efectivas)
          s.copiar(repeticiones: config.repMin, peso: destino, sinRpe: true),
      ],
      deltaPeso: destino - pesoBase,
      fiable: fiable,
    );
  }

  // Mismo peso, una repetición más en la primera serie que no llegó al tope.
  final primera = efectivas.indexWhere((s) => s.repeticiones < config.repMax);
  return Sugerencia(
    tipo: TipoSugerencia.subirRepeticiones,
    motivo: MotivoSugerencia.rangoIncompleto,
    series: [
      for (final (indice, s) in efectivas.indexed)
        indice == primera
            ? s.copiar(repeticiones: s.repeticiones + 1, sinRpe: true)
            : s.copiar(sinRpe: true),
    ],
    fiable: fiable,
  );
}

/// Redondea un peso al múltiplo del escalón más cercano, en kilogramos.
///
/// Es lo que garantiza que la sugerencia caiga siempre en un valor que el
/// selector de peso puede enseñar. Con el usuario en libras el escalón en kilos
/// no es redondo (2,5 lb son 1,134 kg), pero los múltiplos de ese valor sí lo
/// son al convertirlos de vuelta, que es lo que ve el usuario.
double redondearAEscalon(double kilos, double incrementoKg) {
  if (incrementoKg <= 0) return kilos < 0 ? 0 : kilos;
  final pasos = (kilos / incrementoKg).round();
  return pasos <= 0 ? 0 : pasos * incrementoKg;
}

/// El peso al que baja una descarga.
///
/// Se vuelve al **último peso donde se completó el rango**, que son datos reales
/// del usuario y suele quedar más ajustado; si no hay ninguno en el historial,
/// se baja un 10 % redondeado al escalón hacia abajo.
double _pesoDeDescarga(
  List<ResumenSesionEjercicio> historial,
  ConfiguracionProgresion config,
  double pesoBase,
) {
  for (final sesion in historial.reversed) {
    if (_completoElRango(sesion, config) && sesion.pesoMaximo < pesoBase) {
      return sesion.pesoMaximo;
    }
  }

  final objetivo = pesoBase * (1 - fraccionDescarga);
  if (config.incrementoKg <= 0) return objetivo;
  final pasos = (objetivo / config.incrementoKg).floor();
  return pasos <= 0 ? 0 : pasos * config.incrementoKg;
}

/// Si una sesión llegó al tope del rango en todas sus series.
///
/// El historial viene agregado, así que esto se deduce de la suma: `repeticiones
/// >= nSeries * repMax` es exacto salvo que alguien pase del tope en unas series
/// y no llegue en otras, un caso que la sugerencia de esa sesión ya corrigió.
bool _completoElRango(
  ResumenSesionEjercicio sesion,
  ConfiguracionProgresion config,
) =>
    sesion.nSeries > 0 && sesion.repeticiones >= sesion.nSeries * config.repMax;

// ── Estancamiento ────────────────────────────────────────────────────────────

/// Cuántas sesiones seguidas lleva el ejercicio sin mejorar.
///
/// Mejorar es subir el peso máximo, las repeticiones totales **o** el volumen
/// efectivo. Los tres datos ya están en `ResumenSesionEjercicio`, así que esto es
/// un recorrido y no una consulta — y por lo mismo que los récords de C16, el
/// estancamiento **no se guarda**: almacenarlo lo dejaría desincronizado en
/// cuanto se editara o se borrara una sesión.
int sesionesSinMejorar(List<ResumenSesionEjercicio> historial) {
  if (historial.length < 2) return 0;

  var sin = 0;
  for (var i = historial.length - 1; i > 0; i--) {
    final actual = historial[i];
    final previa = historial[i - 1];
    final mejoro =
        actual.pesoMaximo > previa.pesoMaximo ||
        actual.repeticiones > previa.repeticiones ||
        actual.volumen > previa.volumen;
    if (mejoro) break;
    sin++;
  }
  return sin;
}

/// Un ejercicio que lleva sesiones sin mejorar, para la línea del resumen.
class EjercicioEstancado {
  const EjercicioEstancado({
    required this.idRutina,
    required this.idEjercicio,
    required this.nombre,
    required this.ultimaFecha,
    required this.sesionesSinMejorar,
  });

  final int idRutina;
  final int idEjercicio;
  final String nombre;
  final DateTime ultimaFecha;

  /// Sesiones consecutivas sin mejorar peso, repeticiones ni volumen.
  final int sesionesSinMejorar;
}

/// Los ejercicios estancados, del que más lleva al que menos.
///
/// Recibe lo que devuelve `AppBD.resumenSesionesTodos`: una sola consulta para
/// toda la app, y el reparto aquí.
List<EjercicioEstancado> estancados(List<SesionesDeEjercicio> porEjercicio) {
  final lista = <EjercicioEstancado>[];
  for (final grupo in porEjercicio) {
    if (grupo.sesiones.isEmpty) continue;
    final sin = sesionesSinMejorar(grupo.sesiones);
    if (sin < sesionesParaEstancarse) continue;
    lista.add(
      EjercicioEstancado(
        idRutina: grupo.idRutina,
        idEjercicio: grupo.idEjercicio,
        nombre: grupo.nombre,
        ultimaFecha: grupo.sesiones.last.fecha,
        sesionesSinMejorar: sin,
      ),
    );
  }

  lista.sort((a, b) {
    final porSesiones = b.sesionesSinMejorar.compareTo(a.sesionesSinMejorar);
    return porSesiones != 0
        ? porSesiones
        : b.ultimaFecha.compareTo(a.ultimaFecha);
  });
  return lista;
}

// ── El rango que el usuario hace de verdad ───────────────────────────────────

/// El rango de repeticiones que se deduce del historial, si difiere del que hay.
///
/// Quien hace 5×5 no debería ver sugerencias de 8–12 para siempre. Con al menos
/// tres sesiones se mira la media de repeticiones por serie y se devuelve el
/// rango estándar más cercano — **para proponerlo**, nunca para aplicarlo solo:
/// aparece preseleccionado en la hoja del ejercicio y el usuario decide.
///
/// Devuelve `null` cuando no hay historial suficiente o cuando el rango que ya
/// está configurado es el que mejor describe lo que se hace.
(int, int)? rangoObservado(
  List<ResumenSesionEjercicio> historial,
  ConfiguracionProgresion config,
) {
  final utiles = [
    for (final s in historial)
      if (s.nSeries > 0) s,
  ];
  if (utiles.length < sesionesParaEstancarse) return null;

  // Las tres últimas: el rango de hace un año no describe lo que se hace hoy.
  final recientes = utiles.sublist(utiles.length - sesionesParaEstancarse);
  final media =
      recientes.map((s) => s.repeticiones / s.nSeries).reduce((a, b) => a + b) /
      recientes.length;

  (int, int) mejor = rangosRepeticiones.first;
  var distancia = double.infinity;
  for (final rango in rangosRepeticiones) {
    final centro = (rango.$1 + rango.$2) / 2;
    final d = (centro - media).abs();
    if (d < distancia) {
      distancia = d;
      mejor = rango;
    }
  }

  if (mejor.$1 == config.repMin && mejor.$2 == config.repMax) return null;
  return mejor;
}
