/// El vocabulario muscular de la app y el reparto del trabajo entre músculos.
///
/// Tiene la misma forma que `metricas.dart`: **funciones puras**. No toca la
/// base ni pinta nada; recibe las filas que ya devolvió [AppBD.trabajoPorMusculo]
/// y devuelve números. Eso es lo que permite probar el reparto y las rachas con
/// fechas clavadas, sin montar ni base ni pantalla.
///
/// La idea de fondo: el dataset clasifica cada ejercicio por cuatro
/// vocabularios distintos y desiguales (`bodyPart` 10 valores, `target` 19,
/// `muscleGroup` 29, `secondaryMuscles` 40), que no coinciden entre sí ni
/// cubren lo mismo. Aquí se traducen todos a **21 regiones propias**, que son
/// las que se dibujan y las que se pueden tocar.
library;

import 'bd.dart';
import 'formato.dart' as formato;

// ── Las regiones ─────────────────────────────────────────────────────────────

/// La cara del modelo en la que se dibuja una región.
enum Vista {
  frente,
  espalda,

  /// Se dibuja en las dos: el trapecio y los gemelos se ven por delante y por
  /// detrás.
  ambas;

  /// Si algo de esta [Vista] se ve estando en la cara [cara].
  bool seVeEn(Vista cara) => this == ambas || this == cara;
}

/// Las 21 regiones musculares de la app.
///
/// Es un vocabulario **cerrado y propio**, no el del dataset: agrupa los
/// términos que significan lo mismo (`delts`, `deltoids`, `shoulders`) y parte
/// los que la app necesita distinguir.
enum Region {
  cuello,
  trapecio,
  deltoides,
  deltoidesPost,
  pectoral,
  biceps,
  triceps,
  antebrazo,
  dorsal,
  espaldaAlta,
  lumbar,
  abdomen,
  oblicuo,
  gluteo,
  cuadriceps,
  isquiotibial,
  aductor,
  abductor,
  flexorCadera,
  gemelo,
  tibial,
}

/// Dónde se dibuja una región y qué términos del catálogo casa.
///
/// **No lleva su nombre**: depende del idioma, que depende del `BuildContext`.
/// Lo pone `nombreRegion` (`pantallas/musculatura.dart`), desde un `switch`
/// exhaustivo que se rompe si se añade una región sin traducir. La clave del
/// `enum` sí es estable: está en `assets/musculatura.json`.
class DatosRegion {
  const DatosRegion({required this.vista, required this.terminos});

  /// La cara del modelo donde se dibuja.
  final Vista vista;

  /// Valores del catálogo que caen aquí, en inglés y en minúsculas, tal cual
  /// vienen del dataset. Salen de `target`, `muscleGroup` y `secondaryMuscles`.
  ///
  /// **`bodyPart` no se usa nunca**, ni aquí ni en [regionDe]. Sus diez valores
  /// se solapan con los de los otros tres vocabularios (`back` son 203
  /// ejercicios, `chest` 163) y atribuirían en bloque y mal: los dos únicos
  /// ejercicios de `bodyPart = neck` ya entran por su `target`.
  final Set<String> terminos;
}

const regiones = <Region, DatosRegion>{
  Region.cuello: DatosRegion(
    vista: Vista.ambas,
    terminos: {'sternocleidomastoid', 'levator scapulae', 'neck'},
  ),
  Region.trapecio: DatosRegion(
    vista: Vista.ambas,
    terminos: {'traps', 'trapezius'},
  ),
  Region.deltoides: DatosRegion(
    vista: Vista.ambas,
    terminos: {'delts', 'deltoids', 'shoulders', 'rotator cuff'},
  ),
  Region.deltoidesPost: DatosRegion(
    vista: Vista.espalda,
    terminos: {'rear deltoids'},
  ),
  Region.pectoral: DatosRegion(
    vista: Vista.frente,
    terminos: {'pectorals', 'chest', 'upper chest', 'serratus anterior'},
  ),
  Region.biceps: DatosRegion(
    vista: Vista.frente,
    terminos: {'biceps', 'brachialis'},
  ),
  Region.triceps: DatosRegion(vista: Vista.espalda, terminos: {'triceps'}),
  Region.antebrazo: DatosRegion(
    vista: Vista.ambas,
    terminos: {
      'forearms',
      'wrist flexors',
      'wrist extensors',
      'wrists',
      'grip muscles',
      'hands',
    },
  ),
  Region.dorsal: DatosRegion(
    vista: Vista.espalda,
    terminos: {'lats', 'latissimus dorsi'},
  ),
  Region.espaldaAlta: DatosRegion(
    vista: Vista.espalda,
    terminos: {'upper back', 'rhomboids', 'back'},
  ),
  Region.lumbar: DatosRegion(
    vista: Vista.espalda,
    terminos: {'lower back', 'spine'},
  ),
  Region.abdomen: DatosRegion(
    vista: Vista.frente,
    terminos: {'abs', 'abdominals', 'core', 'lower abs'},
  ),
  Region.oblicuo: DatosRegion(vista: Vista.frente, terminos: {'obliques'}),
  Region.gluteo: DatosRegion(vista: Vista.espalda, terminos: {'glutes'}),
  Region.cuadriceps: DatosRegion(
    vista: Vista.frente,
    terminos: {'quads', 'quadriceps'},
  ),
  Region.isquiotibial: DatosRegion(
    vista: Vista.espalda,
    terminos: {'hamstrings'},
  ),
  Region.aductor: DatosRegion(
    vista: Vista.frente,
    terminos: {'adductors', 'inner thighs', 'groin'},
  ),
  Region.abductor: DatosRegion(vista: Vista.frente, terminos: {'abductors'}),
  Region.flexorCadera: DatosRegion(
    vista: Vista.frente,
    terminos: {'hip flexors'},
  ),
  Region.gemelo: DatosRegion(
    vista: Vista.ambas,
    terminos: {'calves', 'soleus'},
  ),
  Region.tibial: DatosRegion(
    vista: Vista.frente,
    terminos: {'shins', 'ankles', 'ankle stabilizers', 'feet'},
  ),
};

/// Términos del catálogo que **a propósito** no son ninguna región.
///
/// `cardiovascular system` es el `target` de 29 ejercicios (correr, saltar a la
/// comba, burpees): no es un músculo y no se puede pintar en el modelo. Que el
/// término no tenga región **no deja fuera al ejercicio**: los 29 traen
/// `muscleGroup` y `secondaryMuscles` reales —25 de ellos cuádriceps— y siguen
/// repartiendo por esas dos vías. Un burpee trabaja las piernas, y decir que no
/// sería peor dato que no decir nada.
const terminosSinRegion = <String>{'cardiovascular system'};

/// Índice invertido término → región, construido una sola vez.
final Map<String, Region> _indice = _construirIndice();

Map<String, Region> _construirIndice() {
  final indice = <String, Region>{};
  for (final MapEntry(key: region, value: datos) in regiones.entries) {
    for (final termino in datos.terminos) {
      final anterior = indice[termino];
      // Un término en dos regiones repartiría el mismo trabajo dos veces. Es un
      // error de la tabla, no un caso a tolerar en silencio.
      if (anterior != null) {
        throw StateError('«$termino» está en $anterior y en $region');
      }
      indice[termino] = region;
    }
  }
  return indice;
}

/// La región de un valor del catálogo, o `null` si no tiene ninguna.
Region? regionDe(String? termino) {
  if (termino == null || termino.isEmpty) return null;
  return _indice[termino.toLowerCase().trim()];
}

// ── Atribución ───────────────────────────────────────────────────────────────

/// Peso del músculo objetivo: es lo que el ejercicio entrena, y el dato más
/// fiable del dataset.
const pesoTarget = 1.0;

/// Peso del grupo muscular: redundante o inconsistente en muchas filas
/// (`forearms` aparece 165 veces como grupo), así que cuenta a la mitad.
const pesoGrupo = 0.5;

/// Peso de los músculos secundarios: trabajo real, pero secundario.
const pesoSecundario = 0.3;

/// Peso mínimo con el que cuenta una serie.
///
/// Las dominadas y los fondos se registran con `peso = 0`, así que su volumen
/// sería nulo y no aparecerían en el mapa. El mapa mide **atención dedicada**,
/// no carga absoluta, y por eso usa `max(peso, 1)`. Es una aproximación
/// consciente y exclusiva de aquí: el 1RM y el resumen semanal (C16, C17) no
/// aplican esta corrección. Se aplica en el SQL de la consulta.
const pesoEfectivoMinimo = 1.0;

/// Cuánto aporta un ejercicio a cada región, entre 0 y 1.
///
/// Si una región recibe peso por varias vías **se toma el mayor, no la suma**:
/// un curl con `target = biceps` y `muscleGroup = biceps` vale 1,0 y no 1,5, o
/// los ejercicios bien etiquetados pesarían más solo por estarlo.
Map<Region, double> regionesDeTerminos({
  required String target,
  required String muscleGroup,
  required Iterable<String> secundarios,
}) {
  final pesos = <Region, double>{};
  void anotar(String? termino, double peso) {
    final region = regionDe(termino);
    if (region == null) return;
    final anterior = pesos[region];
    if (anterior == null || peso > anterior) pesos[region] = peso;
  }

  anotar(target, pesoTarget);
  anotar(muscleGroup, pesoGrupo);
  for (final musculo in secundarios) {
    anotar(musculo, pesoSecundario);
  }
  return pesos;
}

/// Lo mismo desde una ficha del catálogo, parseando el JSON de secundarios.
Map<Region, double> regionesDeEjercicio(FichaCatalogo ficha) =>
    regionesDeTerminos(
      target: ficha.target,
      muscleGroup: ficha.muscleGroup,
      secundarios: formato.listaJson(ficha.secondaryMuscles),
    );

/// Las regiones de una fila del histórico.
Map<Region, double> _regionesDe(TrabajoMuscular fila) => regionesDeTerminos(
  target: fila.target,
  muscleGroup: fila.muscleGroup,
  secundarios: formato.listaJson(fila.secondaryMuscles),
);

// ── Reparto por región ───────────────────────────────────────────────────────

/// Lo que una región recibió dentro de una ventana de tiempo.
class TrabajoRegion {
  const TrabajoRegion({
    required this.puntos,
    required this.volumen,
    required this.nSeries,
    required this.nSesiones,
    required this.ultima,
  });

  /// Series efectivas ponderadas por el peso de atribución.
  ///
  /// **Es lo que colorea el mapa**, y no el volumen. Cuatro series de curl y
  /// cuatro de sentadilla son cuatro y cuatro; en kilos por repetición serían
  /// 500 contra 60, que es una propiedad del ejercicio y no del entrenamiento.
  final double puntos;

  /// Volumen en kilos × repeticiones, ponderado, con [pesoEfectivoMinimo].
  ///
  /// Se enseña como cifra en la hoja del músculo, donde se compara consigo
  /// mismo en el tiempo y sí significa algo.
  final double volumen;

  /// Series efectivas que tocaron la región, sin ponderar.
  final int nSeries;

  /// Sesiones distintas en las que apareció.
  final int nSesiones;

  /// La más reciente dentro de la ventana.
  final DateTime? ultima;
}

/// Reparte por región el trabajo de [filas] entre [desde] y [hasta].
///
/// Es una función pura **sobre datos ya cargados**: cambiar el periodo de 7 a
/// 90 días recorre otra vez la misma lista, no vuelve a la base. Solo devuelve
/// las regiones que recibieron algo.
Map<Region, TrabajoRegion> trabajoPorRegion(
  List<TrabajoMuscular> filas, {
  required DateTime desde,
  DateTime? hasta,
}) {
  final puntos = <Region, double>{};
  final volumen = <Region, double>{};
  final series = <Region, int>{};
  final sesiones = <Region, Set<int>>{};
  final ultima = <Region, DateTime>{};

  for (final fila in filas) {
    if (fila.fecha.isBefore(desde)) continue;
    if (hasta != null && fila.fecha.isAfter(hasta)) continue;
    for (final MapEntry(key: region, value: peso) in _regionesDe(
      fila,
    ).entries) {
      puntos[region] = (puntos[region] ?? 0) + fila.nSeries * peso;
      volumen[region] = (volumen[region] ?? 0) + fila.volumen * peso;
      series[region] = (series[region] ?? 0) + fila.nSeries;
      (sesiones[region] ??= <int>{}).add(fila.idEntrenamiento);
      final anterior = ultima[region];
      if (anterior == null || fila.fecha.isAfter(anterior)) {
        ultima[region] = fila.fecha;
      }
    }
  }

  return {
    for (final region in puntos.keys)
      region: TrabajoRegion(
        puntos: puntos[region]!,
        volumen: volumen[region]!,
        nSeries: series[region]!,
        nSesiones: sesiones[region]!.length,
        ultima: ultima[region],
      ),
  };
}

/// La última vez que se trabajó cada región, sobre **toda** la lista.
///
/// No se saca de [trabajoPorRegion]: la lista de «Menos trabajados» tiene que
/// poder decir «sin entrenar 84 días» aunque el periodo elegido sean 7.
Map<Region, DateTime> ultimaPorRegion(List<TrabajoMuscular> filas) {
  final ultima = <Region, DateTime>{};
  for (final fila in filas) {
    for (final region in _regionesDe(fila).keys) {
      final anterior = ultima[region];
      if (anterior == null || fila.fecha.isAfter(anterior)) {
        ultima[region] = fila.fecha;
      }
    }
  }
  return ultima;
}

/// Las regiones más abandonadas, primero las que no se han trabajado nunca.
///
/// El `int?` son los días desde la última vez; `null` es «nunca».
List<(Region, int?)> menosTrabajados(
  List<TrabajoMuscular> filas, {
  required DateTime hoy,
  int limite = 5,
}) {
  final ultima = ultimaPorRegion(filas);
  final dias = <(Region, int?)>[
    for (final region in Region.values)
      (
        region,
        switch (ultima[region]) {
          null => null,
          final fecha => hoy.difference(fecha).inDays,
        },
      ),
  ];
  // Las que nunca se han tocado van delante; luego, de más a menos abandonadas.
  dias.sort((a, b) {
    if (a.$2 == null && b.$2 == null) return a.$1.index.compareTo(b.$1.index);
    if (a.$2 == null) return -1;
    if (b.$2 == null) return 1;
    return b.$2!.compareTo(a.$2!);
  });
  return dias.take(limite).toList();
}

// ── Escala de color ──────────────────────────────────────────────────────────

/// Los cinco niveles de la escala, del 0 (sin trabajar) al 4.
const nivelesColor = 5;

/// Opacidad del acento en cada nivel.
///
/// El nivel 0 no usa el acento sino `context.relleno`: distinguirlo del 1 es lo
/// que responde a la pregunta importante, «¿qué no estoy tocando?». Es una
/// escala secuencial de un solo tono y no un semáforo, porque aquí «mucho» no
/// es bueno ni malo, es simplemente más; y así además funciona con daltonismo.
const opacidadesNivel = <double>[0, 0.25, 0.5, 0.75, 1];

/// El nivel de una región según su proporción del máximo del periodo.
///
/// Relativo y no absoluto: comparar gemelos con cuádriceps en valor absoluto
/// pintaría siempre el mapa igual. Cualquier trabajo por poco que sea es al
/// menos nivel 1, que es lo que separa «poco» de «nada».
int nivelDe(double valor, double maximo) {
  if (valor <= 0 || maximo <= 0) return 0;
  final proporcion = valor / maximo;
  if (proporcion <= 0.25) return 1;
  if (proporcion <= 0.5) return 2;
  if (proporcion <= 0.75) return 3;
  return 4;
}

/// El nivel de las 21 regiones, incluidas las que no aparecen en [trabajo].
///
/// Devuelve siempre el mapa completo: el pintor necesita un nivel para cada
/// región y no tiene por qué ocuparse de las que faltan.
Map<Region, int> nivelesPorRegion(Map<Region, TrabajoRegion> trabajo) {
  var maximo = 0.0;
  for (final t in trabajo.values) {
    if (t.puntos > maximo) maximo = t.puntos;
  }
  return {
    for (final region in Region.values)
      region: nivelDe(trabajo[region]?.puntos ?? 0, maximo),
  };
}

// ── Sesiones de una región ───────────────────────────────────────────────────

/// Una sesión que trabajó una región, para la hoja del músculo.
class SesionDeRegion {
  const SesionDeRegion({
    required this.idEntrenamiento,
    required this.idRutina,
    required this.fecha,
    required this.ejercicio,
    required this.nSeries,
    required this.volumen,
  });

  final int idEntrenamiento;
  final int idRutina;
  final DateTime fecha;

  /// El ejercicio que más aportó a la región en esa sesión.
  final String ejercicio;

  final int nSeries;
  final double volumen;
}

/// Las últimas sesiones que trabajaron [region], de la más reciente hacia atrás.
///
/// Cuando una sesión tocó la región con varios ejercicios se queda con el que
/// más aportó y devuelve **una** entrada: la hoja pide «el ejercicio concreto»,
/// no una lista dentro de otra.
List<SesionDeRegion> sesionesDeRegion(
  List<TrabajoMuscular> filas,
  Region region, {
  int limite = 5,
}) {
  final porSesion = <int, SesionDeRegion>{};
  final aporte = <int, double>{};

  for (final fila in filas) {
    final peso = _regionesDe(fila)[region];
    if (peso == null) continue;
    final suyo = fila.volumen * peso;
    final anterior = aporte[fila.idEntrenamiento];
    final acumulado = (anterior ?? 0) + suyo;
    // El mejor ejercicio manda en el nombre; las series y el volumen suman
    // todos los de la sesión, que es lo que el usuario entrenó ese día.
    final previo = porSesion[fila.idEntrenamiento];
    final mejor = previo == null || suyo > (previo.volumen * peso);
    porSesion[fila.idEntrenamiento] = SesionDeRegion(
      idEntrenamiento: fila.idEntrenamiento,
      idRutina: fila.idRutina,
      fecha: fila.fecha,
      ejercicio: mejor ? fila.ejercicio : previo.ejercicio,
      nSeries: (previo?.nSeries ?? 0) + fila.nSeries,
      volumen: (previo?.volumen ?? 0) + fila.volumen,
    );
    aporte[fila.idEntrenamiento] = acumulado;
  }

  final sesiones = porSesion.values.toList()
    ..sort((a, b) => b.fecha.compareTo(a.fecha));
  return sesiones.take(limite).toList();
}

// ── Lo que se queda fuera del modelo ─────────────────────────────────────────

/// Ejercicios entrenados que el modelo no puede representar.
class SinRepresentar {
  const SinRepresentar({required this.personalizados, required this.cardio});

  /// Ejercicios personalizados distintos (sin ficha del catálogo).
  final int personalizados;

  /// Ejercicios del catálogo distintos que no caen en ninguna región.
  final int cardio;

  bool get hayAlgo => personalizados > 0 || cardio > 0;
}

/// Cuenta los ejercicios entrenados desde [desde] que no salen en el modelo.
///
/// Se avisa al pie de la pantalla: un ejercicio personalizado no tiene músculo
/// asignado —el dataset es lo único que clasifica— y quedarse fuera del mapa
/// sin decirlo haría pensar que ese trabajo no cuenta para nada.
SinRepresentar sinRepresentar(
  List<TrabajoMuscular> filas, {
  required DateTime desde,
}) {
  final personalizados = <int>{};
  final cardio = <String>{};
  for (final fila in filas) {
    if (fila.fecha.isBefore(desde)) continue;
    if (fila.idCatalogo == null) {
      personalizados.add(fila.idEjercicio);
    } else if (_regionesDe(fila).isEmpty) {
      cardio.add(fila.idCatalogo!);
    }
  }
  return SinRepresentar(
    personalizados: personalizados.length,
    cardio: cardio.length,
  );
}

// ── Regiones en las rutinas del usuario ──────────────────────────────────────

/// En qué rutinas del usuario aparece cada región, sin repetir nombres.
Map<Region, List<String>> regionesEnRutinas(List<EjercicioEnRutina> filas) {
  final porRegion = <Region, List<String>>{};
  for (final fila in filas) {
    for (final region in regionesDeEjercicio(fila.ficha).keys) {
      final nombres = porRegion[region] ??= <String>[];
      if (!nombres.contains(fila.rutina)) nombres.add(fila.rutina);
    }
  }
  return porRegion;
}

/// Los términos del catálogo con los que se filtra una región.
///
/// Es el mismo conjunto que usa la atribución, y por eso el mapa y la lista de
/// ejercicios de la hoja no pueden discrepar: hay un test que fija que el
/// recuento por región coincide por las dos vías.
Set<String> terminosDe(Region region) => regiones[region]!.terminos;
