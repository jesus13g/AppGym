/// Esquema y consultas de la base de datos.
///
/// drift devuelve clases de datos planas, no objetos atados a una sesión: una
/// fila leída se puede pasar a la interfaz sin más y no hay que preocuparse de
/// accesos perezosos con la sesión ya cerrada.
///
/// Las consultas preagregadas ([resumenRutinas], [seriesConFecha],
/// [coloresRutinas], [ejerciciosDeRutina] con su join a la ficha) ahorran una
/// consulta por fila en las pantallas que pintan listas. Al añadir una vista,
/// añade también la consulta que le dé los datos ya resueltos.
library;

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../l10n/textos.dart';
import 'ajustes.dart';
import 'esquemas.dart';
// Solo por el umbral de repeticiones fiables, que las agregaciones de 1RM
// necesitan escribir en el SQL. `metricas.dart` importa a su vez este fichero
// por los tipos de sus parámetros; el ciclo es legal en Dart y preferible a
// tener el mismo 12 escrito en dos sitios.
import 'metricas.dart' show maxRepeticionesFiables;
import 'respaldo.dart';

// Los tipos de las preferencias se reexportan para que las pantallas sigan
// pidiéndolos donde ya los pedían. Las claves y los valores admitidos viven en
// `ajustes.dart` y solo los necesita la pantalla de Ajustes.
export 'ajustes.dart'
    show Ajustes, EscalaEsfuerzo, Formula, Idioma, Perfil, Tema, Unidad;

/// `Value` sale por aquí para que las pantallas no tengan que importar drift.
///
/// Lo pide `fijarProgresionEjercicio`, donde `null` es un valor con significado
/// —«como el global»— y hace falta distinguirlo de «esta llamada no toca esa
/// columna». Es el único símbolo de drift que asoma fuera de `datos/`.
export 'package:drift/drift.dart' show Value;

part 'bd.g.dart';

/// Paleta de iOS que se reparte entre las rutinas para identificarlas en el
/// calendario. Son los únicos colores literales de la app: el resto salen de los
/// semánticos de Cupertino, que ya se adaptan a claro y oscuro.
const coloresRutina = <String>[
  '#0A84FF', // azul
  '#30D158', // verde
  '#FF9F0A', // naranja
  '#FF375F', // rosa
  '#BF5AF2', // morado
  '#40C8E0', // turquesa
  '#5E5CE6', // índigo
  '#FFD60A', // amarillo
];

@DataClassName('Rutina')
class Rutinas extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// No se permiten nombres duplicados.
  TextColumn get nombre => text().unique()();

  /// Color con el que se pinta en el calendario.
  TextColumn get color => text().nullable()();
}

@DataClassName('Entrenamiento')
class Entrenamientos extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get idRutina =>
      integer().references(Rutinas, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get fecha => dateTime()();

  /// Texto libre de la sesión: «me dolía el hombro», «con cinturón».
  ///
  /// Es la información que explica un bajón en el gráfico tres semanas después.
  TextColumn get nota => text().nullable()();

  /// Cuánto duró, en segundos, si se registró con la sesión viva.
  ///
  /// Nulo en las sesiones anotadas a posteriori con el formulario: ahí no hay
  /// cronómetro que valga y un cero mentiría.
  IntColumn get duracionSeg => integer().nullable()();
}

/// Borrador de la sesión que se está entrenando ahora mismo.
///
/// Es lo que permite que matar la app a mitad de entrenamiento no se lleve por
/// delante la hora que llevabas anotando. Como mucho hay una fila.
///
/// El estado va como JSON y no normalizado a propósito: es un dato efímero, se
/// reescribe entero en cada cambio y nadie lo consulta por partes. Normalizarlo
/// solo añadiría una tabla de series que hay que mantener en paralelo con la de
/// verdad.
@DataClassName('SesionActiva')
class SesionesActivas extends Table {
  @override
  String get tableName => 'sesiones_activas';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get idRutina =>
      integer().references(Rutinas, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get inicio => dateTime()();
  DateTimeColumn get actualizado => dateTime()();

  /// JSON con las series y cuáles van marcadas.
  TextColumn get estado => text()();
}

/// Ejercicio del catálogo marcado con estrella.
///
/// **Sin clave foránea a propósito.** `sembrarCatalogo` borra y reinserta el
/// catálogo entero cuando el dataset cambia, y con la clave puesta esa
/// operación fallaría —o se llevaría por delante los favoritos— en cuanto
/// hubiera uno guardado. Un favorito cuyo id ya no exista se cae solo del
/// `join` de [AppBD.favoritos], que es el peor caso admisible.
@DataClassName('Favorito')
class Favoritos extends Table {
  TextColumn get idCatalogo => text()();
  DateTimeColumn get creado => dateTime()();

  @override
  Set<Column> get primaryKey => {idCatalogo};
}

/// Ficha abierta recientemente. Se conservan las 10 últimas.
///
/// Sin clave foránea por lo mismo que [Favoritos].
@DataClassName('Visto')
class Vistos extends Table {
  TextColumn get idCatalogo => text()();
  DateTimeColumn get fecha => dateTime()();

  @override
  Set<Column> get primaryKey => {idCatalogo};
}

/// Una medida del cuerpo con su fecha.
///
/// Tabla genérica en vez de una columna por medida: añadir «cuello» dentro de
/// un año no debería costar una migración.
@DataClassName('Medida')
class Medidas extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Siempre a medianoche: una entrada por día y tipo.
  DateTimeColumn get fecha => dateTime()();

  /// Uno de [tiposMedida].
  TextColumn get tipo => text()();

  /// Kilos, centímetros o por ciento, según el tipo.
  RealColumn get valor => real()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {fecha, tipo},
  ];
}

/// Las medidas que se pueden registrar, con su unidad y su etiqueta.
///
/// El peso corporal va primero porque es el que da contexto a las cargas: subir
/// 5 kg en press perdiendo 3 kg de peso no es lo mismo que subirlos ganando 4.
/// La constante se queda con lo que no depende del idioma: la clave y la
/// unidad. **La clave no se traduce nunca**: está escrita en la columna `tipo`
/// de la tabla `medidas` de todos los móviles instalados y en todas las copias
/// de seguridad exportadas, así que traducirla sería perder los datos.
const tiposMedida = <(String, String)>[
  ('peso', 'kg'),
  ('grasa', '%'),
  ('cintura', 'cm'),
  ('pecho', 'cm'),
  ('brazo', 'cm'),
  ('muslo', 'cm'),
];

/// Etiqueta y unidad de un tipo de medida.
///
/// La etiqueta no puede salir de una constante: depende del idioma, que depende
/// del `BuildContext`. El `switch` no es exhaustivo porque la clave es texto,
/// así que un tipo desconocido se enseña tal cual en vez de romper.
(String, String) etiquetaMedida(Textos t, String tipo) {
  final etiqueta = switch (tipo) {
    'peso' => t.medidaPeso,
    'grasa' => t.medidaGrasa,
    'cintura' => t.medidaCintura,
    'pecho' => t.medidaPecho,
    'brazo' => t.medidaBrazo,
    'muslo' => t.medidaMuslo,
    _ => tipo,
  };
  for (final (clave, unidad) in tiposMedida) {
    if (clave == tipo) return (etiqueta, unidad);
  }
  return (etiqueta, '');
}

/// Preferencias de la app, en clave/valor.
///
/// Una tabla de dos columnas en vez de un fichero aparte: entra en la misma
/// copia de seguridad y en la misma transacción que el resto de los datos.
@DataClassName('Ajuste')
class AjustesTabla extends Table {
  @override
  String get tableName => 'ajustes';

  TextColumn get clave => text()();
  TextColumn get valor => text()();

  @override
  Set<Column> get primaryKey => {clave};
}

/// Ejercicio del catálogo, sembrado desde assets/ejercicios.es.json.
///
/// Es de solo lectura: se rellena al arrancar y la app nunca lo modifica.
@DataClassName('FichaCatalogo')
@TableIndex(name: 'idx_catalogo_busqueda', columns: {#busqueda})
@TableIndex(name: 'idx_catalogo_body_part', columns: {#bodyPart})
@TableIndex(name: 'idx_catalogo_equipment', columns: {#equipment})
// `target` es la clasificación más útil para buscar —abs 169, pectorals 158,
// biceps 151— y hasta ahora era la única de las tres sin índice.
@TableIndex(name: 'idx_catalogo_target', columns: {#target})
class CatalogoEjercicios extends Table {
  /// Identificador del dataset original ("0001").
  TextColumn get id => text()();

  /// En inglés, tal cual viene del dataset.
  TextColumn get nombre => text()();
  TextColumn get bodyPart => text()();
  TextColumn get equipment => text()();
  TextColumn get target => text()();
  TextColumn get muscleGroup => text()();

  /// JSON: lista de músculos.
  TextColumn get secondaryMuscles => text()();

  /// JSON: lista de pasos en español.
  TextColumn get instrucciones => text()();

  /// Rutas relativas dentro del dataset.
  TextColumn get image => text()();
  TextColumn get gif => text()();

  /// Índice de búsqueda: nombre en inglés más las traducciones, sin acentos.
  TextColumn get busqueda => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Ejercicio dentro de una rutina.
///
/// Si [idCatalogo] apunta a una ficha, hereda de ella imagen, músculos e
/// instrucciones. Si es nulo, es un ejercicio personalizado del usuario.
@DataClassName('Ejercicio')
class Ejercicios extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get idRutina =>
      integer().references(Rutinas, #id, onDelete: KeyAction.cascade)();
  TextColumn get idCatalogo =>
      text().nullable().references(CatalogoEjercicios, #id)();
  TextColumn get nombre => text()();
  TextColumn get descripcion => text().nullable()();

  /// Posición dentro de la rutina, de 0 en adelante.
  ///
  /// En una rutina el orden **es** la rutina: no da igual hacer las aperturas
  /// antes o después del press. Se desempata por `id` por si dos filas
  /// comparten posición.
  IntColumn get orden => integer().withDefault(const Constant(0))();

  /// Descanso propio, en segundos. Nulo significa «usa el valor global».
  ///
  /// Los descansos de sentadilla y de curl de bíceps no son iguales, y obligar
  /// a que lo sean deja el temporizador inservible para la mitad de la rutina.
  IntColumn get descansoSeg => integer().nullable()();

  /// Suelo del rango de repeticiones. Nulo: el de los ajustes.
  ///
  /// 8–12 va bien en accesorios y es absurdo en un peso muerto pesado o en
  /// gemelos, así que el rango global se puede sobrescribir aquí.
  IntColumn get repMin => integer().nullable()();

  /// Tope del rango de repeticiones. Nulo: el de los ajustes.
  IntColumn get repMax => integer().nullable()();

  /// Escalón de peso propio, **en kilogramos**. Nulo: el de los ajustes.
  ///
  /// Ojo con la unidad: `ajustes.pasoPeso` está en la unidad activa y esto no.
  /// Aquí se guardan kilos porque es lo que se guarda en `serie.peso`.
  RealColumn get incrementoKg => real().nullable()();

  /// Estrategia de progresión, por el índice de `progresion.Estrategia`.
  ///
  /// Nulo es «la global»; 0 desactivada, 1 doble progresión, 2 solo
  /// repeticiones. Se guarda el índice y no el nombre para que la columna sea
  /// un entero como las demás preferencias por ejercicio.
  IntColumn get estrategia => integer().nullable()();
}

/// Una serie registrada: una fila por serie hecha.
@DataClassName('Serie')
class SeriesTabla extends Table {
  @override
  String get tableName => 'serie';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get idEntrenamiento =>
      integer().references(Entrenamientos, #id, onDelete: KeyAction.cascade)();
  IntColumn get idEjercicio =>
      integer().references(Ejercicios, #id, onDelete: KeyAction.cascade)();

  /// Índice de la serie, de 1 a N, dentro del ejercicio en esa sesión.
  ///
  /// **Ojo con el nombre**: en el esquema v1 esta columna guardaba el *recuento*
  /// de series de una única fila agregada por ejercicio y sesión, de forma que
  /// las cuatro series compartían repeticiones y peso. Desde la v2 hay una fila
  /// por serie y esto es su índice. El nombre se conservó para no reescribir el
  /// resto de consultas; la semántica es la nueva.
  IntColumn get nSerie => integer()();

  IntColumn get repeticiones => integer()();
  RealColumn get peso => real()();

  /// Serie de calentamiento: se guarda, pero queda fuera del volumen, de los
  /// máximos y del 1RM estimado.
  BoolColumn get calentamiento =>
      boolean().withDefault(const Constant(false))();

  /// Esfuerzo percibido, de 6 a 10 en medios puntos.
  ///
  /// Se guarda **siempre en escala RPE**, aunque el usuario haya elegido ver
  /// RIR en los ajustes: así cambiar de escala reinterpreta lo guardado en vez
  /// de migrarlo.
  RealColumn get rpe => real().nullable()();

  /// Frase corta sobre esta serie: «fallo en la última», «con ayuda».
  TextColumn get nota => text().nullable()();
}

// ── Resultados de las consultas preagregadas ─────────────────────────────────

/// Una rutina con lo que la lista de rutinas necesita pintar de un tirón.
class ResumenRutina {
  const ResumenRutina({
    required this.id,
    required this.nombre,
    required this.color,
    required this.nEjercicios,
    required this.ultimaFecha,
  });

  final int id;
  final String nombre;
  final String? color;
  final int nEjercicios;
  final DateTime? ultimaFecha;
}

/// Una serie registrada junto a la fecha de su entrenamiento.
class RegistroSerie {
  const RegistroSerie({
    required this.fecha,
    required this.nSerie,
    required this.repeticiones,
    required this.peso,
    required this.calentamiento,
  });

  final DateTime fecha;
  final int nSerie;
  final int repeticiones;
  final double peso;
  final bool calentamiento;
}

/// Lo que una sesión dio de sí en un ejercicio, ya agregado.
///
/// El calentamiento no cuenta en ninguna de las cifras.
class ResumenSesionEjercicio {
  const ResumenSesionEjercicio({
    required this.idEntrenamiento,
    required this.fecha,
    required this.nSeries,
    required this.repeticiones,
    required this.volumen,
    required this.pesoMaximo,
    required this.mejor1RM,
    required this.mejor1RMFiable,
  });

  final int idEntrenamiento;
  final DateTime fecha;
  final int nSeries;

  /// Suma de las repeticiones de todas las series efectivas.
  ///
  /// No es una cifra que se pinte: la usa `progresion.dart` para saber si la
  /// sesión completó el rango y si el ejercicio lleva tres sin mejorar. Sale del
  /// mismo `GROUP BY` que las demás, así que no cuesta una consulta.
  final int repeticiones;

  /// Suma de peso × repeticiones de todas las series efectivas.
  final double volumen;

  final double pesoMaximo;

  /// El mejor 1RM estimado de la sesión, con la fórmula que pidió quien
  /// consultó.
  final double mejor1RM;

  /// El mejor 1RM contando **solo las series fiables** (hasta doce
  /// repeticiones).
  ///
  /// `null` cuando todas las series de la sesión pasaron de ahí: se sigue
  /// enseñando [mejor1RM], pero marcado como estimación de baja confianza y sin
  /// contar para un récord.
  final double? mejor1RMFiable;

  /// Si el [mejor1RM] de la sesión sale de una serie de las de fiar.
  bool get fiable => mejor1RMFiable != null && mejor1RMFiable == mejor1RM;
}

/// El historial por sesión de **un** ejercicio, con su nombre y su rutina.
///
/// Existe para poder traer el de todos los ejercicios en una sola consulta
/// ([AppBD.resumenSesionesTodos]) sin perder de vista a quién pertenece cada
/// lista.
class SesionesDeEjercicio {
  const SesionesDeEjercicio({
    required this.idRutina,
    required this.idEjercicio,
    required this.nombre,
    required this.sesiones,
  });

  final int idRutina;
  final int idEjercicio;
  final String nombre;

  /// De la más antigua a la más reciente, como las devuelve la consulta.
  final List<ResumenSesionEjercicio> sesiones;
}

/// Una sesión vista desde el calendario.
///
/// Trae ya las cifras que pinta la hoja del día: el calendario solo necesita el
/// color de la rutina, pero pulsar una celda no puede desatar una consulta por
/// sesión mostrada.
class SesionDelDia {
  const SesionDelDia({
    required this.id,
    required this.idRutina,
    required this.fecha,
    this.duracionSeg,
    this.nEjercicios = 0,
    this.nSeries = 0,
    this.volumen = 0,
  });

  final int id;
  final int idRutina;
  final DateTime fecha;

  /// Solo lo tienen las sesiones registradas en vivo.
  final int? duracionSeg;

  final int nEjercicios;
  final int nSeries;

  /// Sin contar el calentamiento.
  final double volumen;
}

/// Una sesión con su volumen ya sumado, para los cálculos de la semana.
///
/// Es deliberadamente escueta: el resumen semanal necesita muchas sesiones a la
/// vez —hasta dos años atrás para la racha— y de cada una solo cuándo fue, de
/// qué rutina y cuánto se movió.
class SesionConVolumen {
  const SesionConVolumen({
    required this.id,
    required this.idRutina,
    required this.fecha,
    required this.volumen,
  });

  final int id;
  final int idRutina;
  final DateTime fecha;

  /// Sin contar el calentamiento.
  final double volumen;
}

/// Una sesión en la lista del historial, con sus cifras ya calculadas.
class ResumenSesion {
  const ResumenSesion({
    required this.id,
    required this.fecha,
    required this.nEjercicios,
    required this.nSeries,
    required this.volumen,
    required this.tieneNota,
  });

  final int id;
  final DateTime fecha;
  final int nEjercicios;
  final int nSeries;

  /// Sin contar el calentamiento.
  final double volumen;

  /// La sesión, o alguna de sus series, tiene algo escrito.
  final bool tieneNota;
}

/// Un ejercicio dentro de una sesión, con las series que se le hicieron.
class EjercicioDeSesion {
  const EjercicioDeSesion(this.ejercicio, this.series);

  final EjercicioConFicha ejercicio;
  final List<ValoresSerie> series;

  double get volumen => series
      .where((s) => !s.calentamiento)
      .fold(0, (suma, s) => suma + s.peso * s.repeticiones);
}

/// Una sesión con todo lo necesario para pintarla o para reeditarla.
class SesionCompleta {
  const SesionCompleta({required this.entrenamiento, required this.ejercicios});

  final Entrenamiento entrenamiento;
  final List<EjercicioDeSesion> ejercicios;

  int get id => entrenamiento.id;
  int get idRutina => entrenamiento.idRutina;
  DateTime get fecha => entrenamiento.fecha;
  String? get nota => entrenamiento.nota;

  double get volumen => ejercicios.fold(0, (suma, e) => suma + e.volumen);

  /// Las series por id de ejercicio, tal y como las espera
  /// [AppBD.actualizarEntrenamiento].
  Map<int, List<ValoresSerie>> get series => {
    for (final e in ejercicios) e.ejercicio.id: e.series,
  };
}

/// Un ejercicio de rutina con su ficha de catálogo ya resuelta.
///
/// Equivale al `joinedload(Ejercicio.catalogo)` de SQLAlchemy: evita que la
/// vista tenga que pedir la ficha por separado para cada fila.
class EjercicioConFicha {
  const EjercicioConFicha(this.ejercicio, this.ficha);

  final Ejercicio ejercicio;
  final FichaCatalogo? ficha;

  int get id => ejercicio.id;
  String get nombre => ejercicio.nombre;
}

/// Lo que un ejercicio dio de sí dentro de una sesión, con la clasificación
/// muscular de su ficha ya resuelta. Es la fila del mapa muscular.
///
/// Los tres campos de clasificación llegan **crudos**, tal cual están en las
/// columnas: `secondaryMuscles` es una lista JSON en texto y quien la parsea es
/// `musculos.dart`, que es también quien sabe traducirlos a regiones.
///
/// En un ejercicio personalizado [idCatalogo] es nulo y los tres son cadena
/// vacía: llegan igualmente, porque hay que poder contarlos para el aviso de
/// «no están representados en el modelo».
class TrabajoMuscular {
  const TrabajoMuscular({
    required this.idEntrenamiento,
    required this.idRutina,
    required this.fecha,
    required this.idEjercicio,
    required this.ejercicio,
    required this.idCatalogo,
    required this.target,
    required this.muscleGroup,
    required this.secondaryMuscles,
    required this.nSeries,
    required this.volumen,
  });

  final int idEntrenamiento;
  final int idRutina;
  final DateTime fecha;
  final int idEjercicio;
  final String ejercicio;
  final String? idCatalogo;
  final String target;
  final String muscleGroup;
  final String secondaryMuscles;

  /// Series efectivas del ejercicio en esa sesión. El calentamiento no cuenta.
  final int nSeries;

  /// Repeticiones × peso, con el peso elevado a un mínimo de 1 para que el
  /// trabajo con el propio peso corporal no sume cero. Es exclusivo del mapa.
  final double volumen;
}

/// Un ejercicio de una rutina del usuario que viene del catálogo.
///
/// Trae el nombre de la rutina y no su id porque quien lo usa —la hoja del
/// músculo— lo que enseña es «aparece en Empuje y en Full body».
class EjercicioEnRutina {
  const EjercicioEnRutina(this.rutina, this.ficha);

  final String rutina;
  final FichaCatalogo ficha;
}

/// Los valores de **una** serie, tal y como se registran o se precargan.
///
/// Sustituye a la antigua `UltimaSerie`, que además de guardar el recuento de
/// series sugería por el nombre que solo servía para lo último registrado.
class ValoresSerie {
  const ValoresSerie({
    required this.repeticiones,
    required this.peso,
    this.calentamiento = false,
    this.rpe,
    this.nota,
  });

  final int repeticiones;
  final double peso;
  final bool calentamiento;

  /// Siempre en escala RPE (6–10), aunque se muestre como RIR.
  final double? rpe;

  final String? nota;

  /// Copia cambiando algún valor. Para vaciar el RPE o la nota, [sinRpe] y
  /// [sinNota]: un `null` en los parámetros significa «déjalo como está».
  ValoresSerie copiar({
    int? repeticiones,
    double? peso,
    bool? calentamiento,
    double? rpe,
    String? nota,
    bool sinRpe = false,
    bool sinNota = false,
  }) => ValoresSerie(
    repeticiones: repeticiones ?? this.repeticiones,
    peso: peso ?? this.peso,
    calentamiento: calentamiento ?? this.calentamiento,
    rpe: sinRpe ? null : (rpe ?? this.rpe),
    nota: sinNota ? null : (nota ?? this.nota),
  );

  @override
  bool operator ==(Object other) =>
      other is ValoresSerie &&
      other.repeticiones == repeticiones &&
      other.peso == peso &&
      other.calentamiento == calentamiento &&
      other.rpe == rpe &&
      other.nota == nota;

  @override
  int get hashCode => Object.hash(repeticiones, peso, calentamiento, rpe, nota);

  @override
  String toString() =>
      'ValoresSerie($repeticiones × $peso kg'
      '${calentamiento ? ', calentamiento' : ''}'
      '${rpe == null ? '' : ', RPE $rpe'}'
      '${nota == null ? '' : ', «$nota»'})';
}

/// Qué récord se ha batido.
enum TipoRecord {
  /// El peso más alto movido en una serie efectiva.
  peso,

  /// El mejor 1RM estimado, contando solo series de hasta doce repeticiones.
  unoRm,

  /// El volumen de la sesión en ese ejercicio.
  volumen,
}

/// Un ejercicio en el que la sesión recién cerrada batió algún récord.
///
/// Se calcula al terminar para el resumen de cierre: es la respuesta a «¿ha
/// servido de algo lo de hoy?», y sale de comparar con lo que había **antes**
/// de esta misma sesión.
class RecordSesion {
  const RecordSesion({
    required this.nombre,
    required this.pesoMaximo,
    required this.mejor1RM,
    required this.volumen,
    required this.pesoAnterior,
    required this.unoRmAnterior,
    required this.volumenAnterior,
  });

  final String nombre;

  final double pesoMaximo;

  /// El mejor 1RM estimado **de las series fiables**; `null` si ninguna lo era.
  final double? mejor1RM;

  final double volumen;

  /// Lo mejor anterior a esta sesión, o `null` si es la primera vez.
  final double? pesoAnterior;
  final double? unoRmAnterior;
  final double? volumenAnterior;

  /// Cuáles de los tres se han batido. Nunca está vacío: la consulta solo
  /// devuelve ejercicios en los que se batió alguno.
  Set<TipoRecord> get batidos => {
    if (pesoAnterior == null || pesoMaximo > pesoAnterior!) TipoRecord.peso,
    if (mejor1RM != null &&
        (unoRmAnterior == null || mejor1RM! > unoRmAnterior!))
      TipoRecord.unoRm,
    if (volumenAnterior == null || volumen > volumenAnterior!)
      TipoRecord.volumen,
  };
}

@DriftDatabase(
  tables: [
    Rutinas,
    Entrenamientos,
    CatalogoEjercicios,
    Ejercicios,
    SeriesTabla,
    AjustesTabla,
    SesionesActivas,
    Favoritos,
    Vistos,
    Medidas,
  ],
)
class AppBD extends _$AppBD {
  /// Sin [executor] abre el fichero de siempre; los tests pasan el suyo en
  /// memoria.
  ///
  /// La ruta se calcula a mano en vez de dejársela a `drift_flutter` porque
  /// `databasePath` es el único punto que se ejecuta con la base todavía
  /// cerrada, que es cuando se puede respaldar el fichero antes de migrarlo.
  /// Es la misma ruta por defecto del paquete, no una nueva.
  AppBD([QueryExecutor? executor])
    : super(
        executor ??
            driftDatabase(
              name: 'appgym',
              native: DriftNativeOptions(databasePath: rutaBaseDeDatos),
            ),
      );

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    // Los pasos se escriben contra el esquema *de esa versión* (`esquemas.dart`,
    // generado con `drift_dev schema steps`), no contra las tablas de arriba:
    // así una migración vieja no se rompe cuando el modelo actual cambie.
    onUpgrade: stepByStep(
      from1To2: _de1A2,
      from2To3: _de2A3,
      from3To4: _de3A4,
      from4To5: _de4A5,
      from5To6: _de5A6,
      from6To7: _de6A7,
    ),
    beforeOpen: (details) async {
      // Sin esto SQLite ignora las claves foráneas y los ON DELETE CASCADE
      // no llegan a ejecutarse.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// v1 → v2: cada fila agregada se expande en una fila por serie.
  ///
  /// Es la única migración del proyecto que transforma datos. No se puede
  /// insertar en `serie` mientras se la está recorriendo, así que las filas
  /// viejas se apartan primero a una tabla temporal. Lo que sale es fiel a lo
  /// que el usuario quiso decir: cuatro series de 10×60 kg se convierten en
  /// cuatro filas de 10×60 kg, y el volumen total no cambia.
  Future<void> _de1A2(Migrator m, Schema2 esquema) async {
    await m.addColumn(esquema.serie, esquema.serie.calentamiento);

    await customStatement(
      'CREATE TEMPORARY TABLE serie_v1 AS SELECT * FROM serie',
    );
    await customStatement('DELETE FROM serie');
    await customStatement('''
      WITH RECURSIVE indices(i) AS (
        SELECT 1
        UNION ALL
        SELECT i + 1 FROM indices
        WHERE i < (SELECT COALESCE(MAX(n_serie), 0) FROM serie_v1)
      )
      INSERT INTO serie (
        id_entrenamiento, id_ejercicio, n_serie, repeticiones, peso, calentamiento
      )
      SELECT v.id_entrenamiento, v.id_ejercicio, i.i, v.repeticiones, v.peso, 0
      FROM serie_v1 v
      JOIN indices i ON i.i <= v.n_serie
      ORDER BY v.id, i.i
    ''');
    await customStatement('DROP TABLE serie_v1');
  }

  /// v3 → v4: notas, RPE y la tabla de ajustes.
  ///
  /// Solo añade; no hay nada que transformar.
  Future<void> _de3A4(Migrator m, Schema4 esquema) async {
    await m.addColumn(esquema.entrenamientos, esquema.entrenamientos.nota);
    await m.addColumn(esquema.serie, esquema.serie.rpe);
    await m.addColumn(esquema.serie, esquema.serie.nota);
    await m.createTable(esquema.ajustes);
  }

  /// v4 → v5: el descanso por ejercicio, la duración y el borrador en curso.
  ///
  /// Solo añade. Las sesiones ya guardadas se quedan con `duracionSeg` nulo,
  /// que es la verdad: nadie las cronometró.
  Future<void> _de4A5(Migrator m, Schema5 esquema) async {
    await m.addColumn(esquema.ejercicios, esquema.ejercicios.descansoSeg);
    await m.addColumn(
      esquema.entrenamientos,
      esquema.entrenamientos.duracionSeg,
    );
    await m.createTable(esquema.sesionesActivas);
  }

  /// v5 → v6: favoritos, vistos, medidas y el índice por músculo objetivo.
  ///
  /// Solo añade tablas y un índice; no hay nada que transformar.
  Future<void> _de5A6(Migrator m, Schema6 esquema) async {
    await m.createTable(esquema.favoritos);
    await m.createTable(esquema.vistos);
    await m.createTable(esquema.medidas);
    await m.createIndex(esquema.idxCatalogoTarget);
  }

  /// v6 → v7: la configuración de progresión por ejercicio.
  ///
  /// La migración más inocua del proyecto: cuatro columnas anulables y nada
  /// que transformar. Las filas existentes quedan a `null`, que significa «como
  /// el global» y es el comportamiento correcto para todo lo ya creado.
  Future<void> _de6A7(Migrator m, Schema7 esquema) async {
    await m.addColumn(esquema.ejercicios, esquema.ejercicios.repMin);
    await m.addColumn(esquema.ejercicios, esquema.ejercicios.repMax);
    await m.addColumn(esquema.ejercicios, esquema.ejercicios.incrementoKg);
    await m.addColumn(esquema.ejercicios, esquema.ejercicios.estrategia);
  }

  /// v2 → v3: los ejercicios ganan su posición dentro de la rutina.
  ///
  /// Las rutinas existentes conservan el orden que tenían, que era el de
  /// inserción: a cada ejercicio le toca el número de ejercicios de su rutina
  /// con un `id` menor. Una subconsulta correlacionada basta y no depende de
  /// que la versión de SQLite del móvil traiga funciones de ventana.
  Future<void> _de2A3(Migrator m, Schema3 esquema) async {
    await m.addColumn(esquema.ejercicios, esquema.ejercicios.orden);
    await customStatement('''
      UPDATE ejercicios SET orden = (
        SELECT COUNT(*) FROM ejercicios AS previos
        WHERE previos.id_rutina = ejercicios.id_rutina
          AND previos.id < ejercicios.id
      )
    ''');
  }

  // ── Rutinas ────────────────────────────────────────────────────────────────

  /// Inserta una rutina y le asigna un color de la paleta.
  ///
  /// Devuelve el id de la rutina creada, o `null` si ya existía una con ese
  /// nombre.
  Future<int?> insertarRutina(String nombre) async {
    final existente =
        await (select(rutinas)
              ..where((r) => r.nombre.equals(nombre))
              ..limit(1))
            .getSingleOrNull();
    if (existente != null) return null;

    final usadas = await rutinas.count().getSingle();
    return into(rutinas).insert(
      RutinasCompanion.insert(
        nombre: nombre,
        color: Value(coloresRutina[usadas % coloresRutina.length]),
      ),
    );
  }

  /// Crea una rutina con sus ejercicios de golpe, en una transacción.
  ///
  /// [deCatalogo] son pares `(idCatalogo, nombre)` en el orden en que deben
  /// quedar. Es lo que usan las plantillas y la importación; devuelve `null` si
  /// el nombre ya está cogido, igual que [insertarRutina].
  Future<int?> crearRutinaConEjercicios(
    String nombre,
    List<(String?, String)> deCatalogo,
  ) => transaction(() async {
    final id = await insertarRutina(nombre);
    if (id == null) return null;

    for (final (idCatalogo, nombreEjercicio) in deCatalogo) {
      await insertarEjercicio(id, nombreEjercicio, idCatalogo: idCatalogo);
    }
    return id;
  });

  /// Copia una rutina con sus ejercicios y su orden, **sin el histórico**.
  ///
  /// «Empuje A» y «Empuje B» comparten el 80 % de los ejercicios y hoy hay que
  /// construirlas dos veces desde cero. Lo que no se copia son las sesiones: la
  /// rutina nueva no se ha entrenado nunca, y arrastrar el histórico de la
  /// original falsearía su gráfico desde el primer día.
  ///
  /// Devuelve el id de la copia, o `null` si la rutina no existe o el nombre
  /// propuesto ya está cogido.
  Future<int?> duplicarRutina(int idRutina, {String? nuevoNombre}) async {
    final original = await rutina(idRutina);
    if (original == null) return null;

    final fuente = await ejerciciosDeRutina(idRutina);
    final copia = await crearRutinaConEjercicios(
      nuevoNombre ?? '${original.nombre} (copia)',
      [for (final e in fuente) (e.ejercicio.idCatalogo, e.nombre)],
    );
    if (copia == null) return null;

    // El descanso propio de cada ejercicio y su progresión viajan con él: forman
    // parte de cómo se entrena esa rutina tanto como el orden.
    final destino = await ejerciciosDeRutina(copia);
    for (final (indice, e) in destino.indexed) {
      if (indice >= fuente.length) break;
      final original = fuente[indice].ejercicio;
      if (original.descansoSeg != null) {
        await fijarDescansoEjercicio(e.id, original.descansoSeg);
      }
      await fijarProgresionEjercicio(
        e.id,
        repMin: Value(original.repMin),
        repMax: Value(original.repMax),
        incrementoKg: Value(original.incrementoKg),
        estrategia: Value(original.estrategia),
      );
    }
    return copia;
  }

  /// Elimina una rutina con sus entrenamientos y ejercicios (por el cascade).
  Future<void> borrarRutina(int idRutina) =>
      (delete(rutinas)..where((r) => r.id.equals(idRutina))).go();

  /// Renombra una rutina. Devuelve `false` si el nombre ya lo usa otra.
  Future<bool> renombrarRutina(int idRutina, String nombre) async {
    final choca =
        await (select(rutinas)
              ..where(
                (r) => r.nombre.equals(nombre) & r.id.equals(idRutina).not(),
              )
              ..limit(1))
            .getSingleOrNull();
    if (choca != null) return false;

    final filas = await (update(rutinas)..where((r) => r.id.equals(idRutina)))
        .write(RutinasCompanion(nombre: Value(nombre)));
    return filas > 0;
  }

  Future<Rutina?> rutina(int idRutina) =>
      (select(rutinas)..where((r) => r.id.equals(idRutina))).getSingleOrNull();

  Future<List<Rutina>> todasLasRutinas() =>
      (select(rutinas)..orderBy([(r) => OrderingTerm(expression: r.id)])).get();

  /// Nombre, color, número de ejercicios y última fecha entrenada de cada rutina.
  ///
  /// Se resuelve en tres consultas agregadas en vez de una por rutina, porque la
  /// lista de rutinas es la primera pantalla y se repinta constantemente.
  Future<List<ResumenRutina>> resumenRutinas() async {
    final cuenta = ejercicios.id.count();
    final consultaConteos = selectOnly(ejercicios)
      ..addColumns([ejercicios.idRutina, cuenta])
      ..groupBy([ejercicios.idRutina]);
    final conteos = {
      for (final f in await consultaConteos.get())
        f.read(ejercicios.idRutina)!: f.read(cuenta) ?? 0,
    };

    final maxima = entrenamientos.fecha.max();
    final consultaUltimas = selectOnly(entrenamientos)
      ..addColumns([entrenamientos.idRutina, maxima])
      ..groupBy([entrenamientos.idRutina]);
    final ultimas = {
      for (final f in await consultaUltimas.get())
        f.read(entrenamientos.idRutina)!: f.read(maxima),
    };

    return [
      for (final r in await todasLasRutinas())
        ResumenRutina(
          id: r.id,
          nombre: r.nombre,
          color: r.color,
          nEjercicios: conteos[r.id] ?? 0,
          ultimaFecha: ultimas[r.id],
        ),
    ];
  }

  /// Mapa id de rutina -> (nombre, color), para la leyenda del calendario.
  Future<Map<int, (String, String)>> coloresRutinas() async {
    final filas = await todasLasRutinas();
    return {
      for (final r in filas)
        r.id: (
          r.nombre,
          r.color ?? coloresRutina[(r.id - 1) % coloresRutina.length],
        ),
    };
  }

  // ── Ejercicios de una rutina ───────────────────────────────────────────────

  /// Añade un ejercicio a una rutina.
  ///
  /// El duplicado se comprueba **dentro de la rutina**: dos rutinas distintas sí
  /// pueden compartir el mismo ejercicio del catálogo.
  Future<bool> insertarEjercicio(
    int idRutina,
    String nombre, {
    String? descripcion,
    String? idCatalogo,
  }) async {
    final consulta = select(ejercicios)
      ..where((e) => e.idRutina.equals(idRutina))
      ..limit(1);
    if (idCatalogo != null) {
      consulta.where((e) => e.idCatalogo.equals(idCatalogo));
    } else {
      consulta.where((e) => e.idCatalogo.isNull() & e.nombre.equals(nombre));
    }
    if (await consulta.getSingleOrNull() != null) return false;

    await into(ejercicios).insert(
      EjerciciosCompanion.insert(
        idRutina: idRutina,
        idCatalogo: Value(idCatalogo),
        nombre: nombre,
        descripcion: Value(descripcion),
        orden: Value(await _siguienteOrden(idRutina)),
      ),
    );
    return true;
  }

  /// Posición para un ejercicio nuevo: al final de su rutina.
  Future<int> _siguienteOrden(int idRutina) async {
    final maximo = ejercicios.orden.max();
    final consulta = selectOnly(ejercicios)
      ..addColumns([maximo])
      ..where(ejercicios.idRutina.equals(idRutina));
    final actual = await consulta.map((f) => f.read(maximo)).getSingle();
    return actual == null ? 0 : actual + 1;
  }

  /// Fija el orden de los ejercicios de una rutina, en una transacción.
  ///
  /// [idsEnOrden] es la lista completa tal y como quedó tras arrastrar.
  Future<void> reordenarEjercicios(int idRutina, List<int> idsEnOrden) =>
      transaction(() async {
        for (final (posicion, id) in idsEnOrden.indexed) {
          await (update(ejercicios)
                ..where((e) => e.id.equals(id) & e.idRutina.equals(idRutina)))
              .write(EjerciciosCompanion(orden: Value(posicion)));
        }
      });

  /// Mueve un ejercicio a otra rutina conservando su histórico de series.
  ///
  /// Las series no se tocan: siguen colgando de las sesiones en las que se
  /// hicieron, que son las de la rutina de origen —es lo que de verdad pasó
  /// aquel día—, así que ahí se siguen viendo. Lo que viaja con el ejercicio es
  /// la precarga del registro ([ultimasSeriesEjercicio], que no mira la
  /// rutina); el gráfico de la rutina de destino empieza de cero.
  ///
  /// Devuelve `false` si en la rutina de destino ya está ese ejercicio: es la
  /// misma regla de duplicado que aplica [insertarEjercicio], solo que aquí el
  /// choque se descubre al mover.
  Future<bool> moverEjercicio(int idEjercicio, int idRutinaDestino) async {
    final ejercicio = await (select(
      ejercicios,
    )..where((e) => e.id.equals(idEjercicio))).getSingleOrNull();
    if (ejercicio == null) return false;
    if (ejercicio.idRutina == idRutinaDestino) return false;

    final consulta = select(ejercicios)
      ..where((e) => e.idRutina.equals(idRutinaDestino))
      ..limit(1);
    if (ejercicio.idCatalogo case final idCatalogo?) {
      consulta.where((e) => e.idCatalogo.equals(idCatalogo));
    } else {
      consulta.where(
        (e) => e.idCatalogo.isNull() & e.nombre.equals(ejercicio.nombre),
      );
    }
    if (await consulta.getSingleOrNull() != null) return false;

    await (update(ejercicios)..where((e) => e.id.equals(idEjercicio))).write(
      EjerciciosCompanion(
        idRutina: Value(idRutinaDestino),
        orden: Value(await _siguienteOrden(idRutinaDestino)),
      ),
    );
    return true;
  }

  /// Quita un ejercicio de una rutina, con sus series (por el cascade).
  Future<void> borrarEjercicio(int idRutina, int idEjercicio) => (delete(
    ejercicios,
  )..where((e) => e.idRutina.equals(idRutina) & e.id.equals(idEjercicio))).go();

  /// Un ejercicio con su ficha de catálogo resuelta.
  Future<EjercicioConFicha?> ejercicio(int idEjercicio) async {
    final filas =
        await (select(
          ejercicios,
        )..where((e) => e.id.equals(idEjercicio))).join([
          leftOuterJoin(
            catalogoEjercicios,
            catalogoEjercicios.id.equalsExp(ejercicios.idCatalogo),
          ),
        ]).get();
    if (filas.isEmpty) return null;
    return EjercicioConFicha(
      filas.first.readTable(ejercicios),
      filas.first.readTableOrNull(catalogoEjercicios),
    );
  }

  /// Todos los ejercicios de una rutina, con su ficha de catálogo resuelta.
  Future<List<EjercicioConFicha>> ejerciciosDeRutina(int idRutina) async {
    final consulta = select(ejercicios)
      ..where((e) => e.idRutina.equals(idRutina))
      ..orderBy([
        (e) => OrderingTerm(expression: e.orden),
        // Desempate defensivo: si dos filas comparten posición, manda el id.
        (e) => OrderingTerm(expression: e.id),
      ]);
    final filas = await consulta.join([
      leftOuterJoin(
        catalogoEjercicios,
        catalogoEjercicios.id.equalsExp(ejercicios.idCatalogo),
      ),
    ]).get();
    return [
      for (final f in filas)
        EjercicioConFicha(
          f.readTable(ejercicios),
          f.readTableOrNull(catalogoEjercicios),
        ),
    ];
  }

  Future<int> contarEjerciciosDeRutina(int idRutina) {
    final cuenta = ejercicios.id.count();
    final consulta = selectOnly(ejercicios)
      ..addColumns([cuenta])
      ..where(ejercicios.idRutina.equals(idRutina));
    return consulta.map((f) => f.read(cuenta) ?? 0).getSingle();
  }

  /// Ids de catálogo ya añadidos a una rutina.
  ///
  /// Lo usa el buscador para marcar con un check lo que ya está en la rutina.
  Future<Set<String>> idsCatalogoEnRutina(int idRutina) async {
    final consulta = selectOnly(ejercicios)
      ..addColumns([ejercicios.idCatalogo])
      ..where(
        ejercicios.idRutina.equals(idRutina) &
            ejercicios.idCatalogo.isNotNull(),
      );
    final filas = await consulta.get();
    return {for (final f in filas) ?f.read(ejercicios.idCatalogo)};
  }

  // ── Catálogo ───────────────────────────────────────────────────────────────

  Future<int> contarCatalogo() => catalogoEjercicios.count().getSingle();

  /// Busca en el catálogo. Todos los filtros son opcionales y se combinan con AND.
  ///
  /// [texto] se busca palabra a palabra en la columna `busqueda`, que guarda el
  /// nombre en inglés más las traducciones, normalizado y sin acentos.
  /// [bodyPart], [equipment] y [target] son los valores originales en inglés.
  /// [musculos] es un conjunto de valores del catálogo que casa contra
  /// `target`, `muscleGroup` **o** `secondaryMuscles`; lo usa el mapa muscular,
  /// que agrupa varios términos en cada región.
  Future<List<FichaCatalogo>> buscarCatalogo({
    String? texto,
    String? bodyPart,
    String? equipment,
    String? target,
    Set<String>? musculos,
    int limite = 40,
    int desplazamiento = 0,
  }) {
    final consulta = select(catalogoEjercicios);
    if (texto != null && texto.isNotEmpty) {
      for (final palabra in texto.split(RegExp(r'\s+'))) {
        if (palabra.isEmpty) continue;
        consulta.where((c) => c.busqueda.like('%$palabra%'));
      }
    }
    if (bodyPart != null) {
      consulta.where((c) => c.bodyPart.equals(bodyPart));
    }
    if (equipment != null) {
      consulta.where((c) => c.equipment.equals(equipment));
    }
    if (target != null) {
      consulta.where((c) => c.target.equals(target));
    }
    if (musculos != null && musculos.isNotEmpty) {
      consulta.where((c) => _casaMusculos(c, musculos));
    }
    consulta
      ..orderBy([(c) => OrderingTerm(expression: c.nombre)])
      ..limit(limite, offset: desplazamiento);
    return consulta.get();
  }

  /// Cuántos ejercicios del catálogo casan con un conjunto de músculos.
  ///
  /// Va aparte de [contarCatalogo], que no lleva filtros a propósito: la usa
  /// `semilla.dart` para decidir si hay que resembrar y añadirle parámetros
  /// sería tocar el arranque de la app para nada.
  Future<int> contarCatalogoPorMusculos(Set<String> musculos) {
    if (musculos.isEmpty) return Future.value(0);
    final cuenta = catalogoEjercicios.id.count();
    final consulta = selectOnly(catalogoEjercicios)
      ..addColumns([cuenta])
      ..where(_casaMusculos(catalogoEjercicios, musculos));
    return consulta.map((f) => f.read(cuenta)!).getSingle();
  }

  /// Un ejercicio casa si el músculo está en su objetivo, en su grupo o entre
  /// sus secundarios.
  ///
  /// Los secundarios son una lista JSON en una columna de texto, así que se
  /// buscan con `LIKE` **entrecomillados**: `"back"` no casa dentro de
  /// `"upper back"` ni `"traps"` dentro de `"trapezius"`, que es justo lo que
  /// pasaría sin las comillas. Ninguno de los 40 valores del dataset lleva `%`
  /// ni `_`, de modo que no hace falta escaparlos.
  Expression<bool> _casaMusculos(
    $CatalogoEjerciciosTable c,
    Set<String> musculos,
  ) {
    var condicion = c.target.isIn(musculos) | c.muscleGroup.isIn(musculos);
    for (final musculo in musculos) {
      condicion = condicion | c.secondaryMuscles.like('%"$musculo"%');
    }
    return condicion;
  }

  /// Músculos objetivo presentes en el catálogo, con cuántos ejercicios tiene
  /// cada uno.
  ///
  /// El recuento es lo que hace útil el filtro: en la hoja se lee «Bíceps 151»
  /// y se sabe de antemano si merece la pena entrar.
  Future<List<(String, int)>> objetivosDisponibles() async {
    final cuenta = catalogoEjercicios.id.count();
    final consulta = selectOnly(catalogoEjercicios)
      ..addColumns([catalogoEjercicios.target, cuenta])
      ..where(catalogoEjercicios.target.equals('').not())
      ..groupBy([catalogoEjercicios.target]);

    final filas = await consulta.get();
    return [
      for (final f in filas)
        if (f.read(catalogoEjercicios.target) case final valor?)
          (valor, f.read(cuenta) ?? 0),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
  }

  // ── Favoritos y vistos recientemente ───────────────────────────────────────

  /// Marca o desmarca un ejercicio del catálogo como favorito.
  Future<void> marcarFavorito(String idCatalogo, bool valor) async {
    if (!valor) {
      await (delete(
        favoritos,
      )..where((f) => f.idCatalogo.equals(idCatalogo))).go();
      return;
    }
    await into(favoritos).insertOnConflictUpdate(
      FavoritosCompanion.insert(idCatalogo: idCatalogo, creado: DateTime.now()),
    );
  }

  /// Los favoritos, del más reciente al más antiguo.
  ///
  /// No se llama `favoritos` porque ese nombre ya lo ocupa el accesor que drift
  /// genera para la tabla.
  Future<List<FichaCatalogo>> fichasFavoritas() async {
    final filas =
        await (select(favoritos)..orderBy([
              (f) =>
                  OrderingTerm(expression: f.creado, mode: OrderingMode.desc),
            ]))
            .join([
              // `innerJoin`, no `leftOuterJoin`: un favorito cuyo id ya no esté
              // en el catálogo —porque el dataset cambió— sencillamente no se
              // pinta, en vez de aparecer como una fila vacía.
              innerJoin(
                catalogoEjercicios,
                catalogoEjercicios.id.equalsExp(favoritos.idCatalogo),
              ),
            ])
            .get();
    return [for (final f in filas) f.readTable(catalogoEjercicios)];
  }

  /// Ids marcados como favoritos, para pintar la estrella en la lista.
  Future<Set<String>> idsFavoritos() async {
    final filas = await select(favoritos).get();
    return {for (final f in filas) f.idCatalogo};
  }

  /// Anota que se ha abierto una ficha y conserva solo las 10 últimas.
  ///
  /// La poda va aquí y no en la lectura para que la tabla no crezca sin límite
  /// con cada ficha que se abre.
  ///
  /// Se borra y se reinserta en vez de hacer *upsert*: drift guarda las fechas
  /// con precisión de **segundo**, así que dos fichas abiertas seguidas empatan
  /// y el orden quedaría al azar. Reinsertando, la recién vista es siempre la
  /// del `rowid` más alto, y ese es el desempate.
  Future<void> registrarVisto(String idCatalogo, {int conservar = 10}) =>
      transaction(() async {
        await (delete(
          vistos,
        )..where((v) => v.idCatalogo.equals(idCatalogo))).go();
        await into(vistos).insert(
          VistosCompanion.insert(idCatalogo: idCatalogo, fecha: DateTime.now()),
        );
        await customStatement(
          '''
          DELETE FROM vistos WHERE rowid NOT IN (
            SELECT rowid FROM vistos ORDER BY fecha DESC, rowid DESC LIMIT ?
          )
          ''',
          [conservar],
        );
      });

  /// Las últimas fichas abiertas, de la más reciente a la más antigua.
  Future<List<FichaCatalogo>> vistosRecientes({int limite = 10}) async {
    // Con `customSelect` porque el desempate es por `rowid`, que no es una
    // columna del modelo pero sí la que ordena bien dentro del mismo segundo.
    final filas = await customSelect(
      '''
      SELECT c.* FROM vistos v
      JOIN catalogo_ejercicios c ON c.id = v.id_catalogo
      ORDER BY v.fecha DESC, v.rowid DESC
      LIMIT ?
      ''',
      variables: [Variable.withInt(limite)],
      readsFrom: {vistos, catalogoEjercicios},
    ).get();
    return [for (final f in filas) catalogoEjercicios.map(f.data)];
  }

  /// Rutinas en las que ya está ese ejercicio del catálogo.
  ///
  /// Es lo que responde «¿lo tengo ya en algún sitio?» sin salir de la ficha.
  Future<List<Rutina>> rutinasQueContienen(String idCatalogo) async {
    final filas =
        await (select(
          ejercicios,
        )..where((e) => e.idCatalogo.equals(idCatalogo))).join([
          innerJoin(rutinas, rutinas.id.equalsExp(ejercicios.idRutina)),
        ]).get();

    final porId = {
      for (final f in filas) f.readTable(rutinas).id: f.readTable(rutinas),
    };
    return porId.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  }

  // ── Medidas del cuerpo ─────────────────────────────────────────────────────

  /// Registra una medida. Repetir el mismo día y tipo sustituye el valor.
  ///
  /// La fecha se lleva a medianoche antes de guardar: es lo que hace que la
  /// clave única `(fecha, tipo)` signifique de verdad «una por día».
  /// El `onConflict` apunta a la clave única `(fecha, tipo)` y no a la
  /// primaria: la primaria es el `id` autoincremental, que nunca choca, de modo
  /// que un `insertOnConflictUpdate` normal reventaría contra el índice único
  /// en vez de sustituir el valor del día.
  Future<void> registrarMedida(DateTime fecha, String tipo, double valor) {
    final dia = DateTime(fecha.year, fecha.month, fecha.day);
    return into(medidas).insert(
      MedidasCompanion.insert(fecha: dia, tipo: tipo, valor: valor),
      onConflict: DoUpdate(
        (_) => MedidasCompanion(valor: Value(valor)),
        target: [medidas.fecha, medidas.tipo],
      ),
    );
  }

  /// Una medida a lo largo del tiempo, de la más antigua a la más reciente.
  Future<List<Medida>> serieMedida(
    String tipo, {
    DateTime? desde,
    DateTime? hasta,
  }) {
    final consulta = select(medidas)..where((m) => m.tipo.equals(tipo));
    if (desde != null) {
      consulta.where((m) => m.fecha.isBiggerOrEqualValue(desde));
    }
    if (hasta != null) consulta.where((m) => m.fecha.isSmallerThanValue(hasta));
    consulta.orderBy([(m) => OrderingTerm(expression: m.fecha)]);
    return consulta.get();
  }

  Future<Medida?> ultimaMedida(String tipo) =>
      (select(medidas)
            ..where((m) => m.tipo.equals(tipo))
            ..orderBy([
              (m) => OrderingTerm(expression: m.fecha, mode: OrderingMode.desc),
            ])
            ..limit(1))
          .getSingleOrNull();

  Future<void> borrarMedida(DateTime fecha, String tipo) =>
      (delete(medidas)..where(
            (m) =>
                m.fecha.equals(DateTime(fecha.year, fecha.month, fecha.day)) &
                m.tipo.equals(tipo),
          ))
          .go();

  Future<List<Medida>> todasLasMedidas() =>
      (select(medidas)..orderBy([
            (m) => OrderingTerm(expression: m.fecha),
            (m) => OrderingTerm(expression: m.tipo),
          ]))
          .get();

  Future<FichaCatalogo?> ficha(String idCatalogo) => (select(
    catalogoEjercicios,
  )..where((c) => c.id.equals(idCatalogo))).getSingleOrNull();

  /// Lista ordenada de equipamientos presentes en el catálogo.
  Future<List<String>> equipamientosDisponibles() async {
    final consulta = selectOnly(catalogoEjercicios, distinct: true)
      ..addColumns([catalogoEjercicios.equipment]);
    final filas = await consulta.get();
    final valores = [
      for (final f in filas)
        if (f.read(catalogoEjercicios.equipment) case final e?)
          if (e.isNotEmpty) e,
    ]..sort();
    return valores;
  }

  /// Vuelca el catálogo entero. Solo lo llama la semilla.
  Future<void> sembrarCatalogo(List<CatalogoEjerciciosCompanion> filas) =>
      transaction(() async {
        await delete(catalogoEjercicios).go();
        await batch((b) => b.insertAll(catalogoEjercicios, filas));
      });

  // ── Entrenamientos y series ────────────────────────────────────────────────

  /// Guarda un entrenamiento con todas las series de cada ejercicio.
  ///
  /// [series] va de id de ejercicio a la lista de series que se hicieron, en
  /// orden. Un ejercicio con la lista vacía sencillamente no se guarda, que es
  /// lo que sustituye al antiguo interruptor de «incluir ejercicio».
  ///
  /// Con [descartarBorrador] se borra en la **misma transacción** el borrador
  /// de la sesión viva. Si fueran dos operaciones habría un instante con la
  /// sesión ya guardada y el borrador todavía vivo, y reabrir la app justo ahí
  /// preguntaría por un entrenamiento en curso que ya no existe.
  ///
  /// Devuelve el id de la sesión creada, o `null` si no había ninguna serie.
  Future<int?> insertarEntrenamiento(
    int idRutina,
    DateTime fecha,
    Map<int, List<ValoresSerie>> series, {
    String? nota,
    int? duracionSeg,
    bool descartarBorrador = false,
  }) async {
    final conSeries = _soloConSeries(series);
    if (conSeries.isEmpty) return null;

    return transaction(() async {
      final idEntrenamiento = await into(entrenamientos).insert(
        EntrenamientosCompanion.insert(
          idRutina: idRutina,
          fecha: fecha,
          nota: Value(_limpiar(nota)),
          duracionSeg: Value(duracionSeg),
        ),
      );
      await _insertarSeries(idEntrenamiento, conSeries);
      if (descartarBorrador) await delete(sesionesActivas).go();
      return idEntrenamiento;
    });
  }

  /// Una nota en blanco es no tener nota: así el icono del historial no
  /// aparece por un espacio suelto.
  String? _limpiar(String? texto) {
    final limpio = texto?.trim();
    return (limpio == null || limpio.isEmpty) ? null : limpio;
  }

  Map<int, List<ValoresSerie>> _soloConSeries(
    Map<int, List<ValoresSerie>> series,
  ) => {
    for (final entrada in series.entries)
      if (entrada.value.isNotEmpty) entrada.key: entrada.value,
  };

  /// Reemplaza en bloque la fecha y las series de una sesión ya guardada.
  ///
  /// Borra las series y las reinserta en vez de calcular la diferencia: para
  /// este tamaño de datos el *diff* no aporta nada y sí complica el código.
  /// Devuelve `false` si la sesión no existe o si se queda sin ninguna serie,
  /// en cuyo caso no se toca nada.
  Future<bool> actualizarEntrenamiento(
    int idEntrenamiento,
    DateTime fecha,
    Map<int, List<ValoresSerie>> series, {
    String? nota,
  }) async {
    // La duración no se toca al editar: se cronometró aquel día y corregir un
    // peso tres semanas después no cambia lo que duró la sesión.
    final conSeries = _soloConSeries(series);
    if (conSeries.isEmpty) return false;

    final existe = await (select(
      entrenamientos,
    )..where((e) => e.id.equals(idEntrenamiento))).getSingleOrNull();
    if (existe == null) return false;

    await transaction(() async {
      await (update(
        entrenamientos,
      )..where((e) => e.id.equals(idEntrenamiento))).write(
        EntrenamientosCompanion(
          fecha: Value(fecha),
          nota: Value(_limpiar(nota)),
        ),
      );
      await (delete(
        seriesTabla,
      )..where((s) => s.idEntrenamiento.equals(idEntrenamiento))).go();
      await _insertarSeries(idEntrenamiento, conSeries);
    });
    return true;
  }

  /// Borra una sesión con sus series (por el cascade).
  Future<void> borrarEntrenamiento(int idEntrenamiento) =>
      (delete(entrenamientos)..where((e) => e.id.equals(idEntrenamiento))).go();

  Future<void> _insertarSeries(
    int idEntrenamiento,
    Map<int, List<ValoresSerie>> series,
  ) => batch((b) {
    b.insertAll(seriesTabla, [
      for (final entrada in series.entries)
        for (final (indice, valores) in entrada.value.indexed)
          SeriesTablaCompanion.insert(
            idEntrenamiento: idEntrenamiento,
            idEjercicio: entrada.key,
            nSerie: indice + 1,
            repeticiones: valores.repeticiones,
            peso: valores.peso,
            calentamiento: Value(valores.calentamiento),
            rpe: Value(valores.rpe),
            nota: Value(_limpiar(valores.nota)),
          ),
    ]);
  });

  /// Series de un ejercicio en una rutina, una entrada por serie.
  ///
  /// Devolver la fecha aquí evita que la pantalla de progreso tenga que navegar
  /// de la serie a su entrenamiento fila a fila. Quien necesite el dato
  /// agregado por sesión tiene [resumenSesionesEjercicio]; esto son las series
  /// en crudo, calentamientos incluidos.
  Future<List<RegistroSerie>> seriesConFecha(
    int idRutina,
    int idEjercicio,
  ) async {
    final consulta =
        select(seriesTabla).join([
            innerJoin(
              entrenamientos,
              entrenamientos.id.equalsExp(seriesTabla.idEntrenamiento),
            ),
          ])
          ..where(
            entrenamientos.idRutina.equals(idRutina) &
                seriesTabla.idEjercicio.equals(idEjercicio),
          )
          ..orderBy([
            OrderingTerm(expression: entrenamientos.fecha),
            OrderingTerm(expression: seriesTabla.idEntrenamiento),
            OrderingTerm(expression: seriesTabla.nSerie),
          ]);

    return [
      for (final f in await consulta.get())
        RegistroSerie(
          fecha: f.readTable(entrenamientos).fecha,
          nSerie: f.readTable(seriesTabla).nSerie,
          repeticiones: f.readTable(seriesTabla).repeticiones,
          peso: f.readTable(seriesTabla).peso,
          calentamiento: f.readTable(seriesTabla).calentamiento,
        ),
    ];
  }

  /// La expresión SQL del 1RM estimado de una serie, según la fórmula.
  ///
  /// Se compone aquí y no se incrusta en cada consulta para que las dos que lo
  /// estiman —el histórico de un ejercicio y los récords de una sesión— no
  /// puedan discrepar. `alias` es el de la tabla `serie` en la consulta.
  ///
  /// Con una repetición devuelve el peso tal cual, igual que `metricas.unoRm`:
  /// levantar 100 kg una vez es un máximo de 100, no de 103,3. Brzycki se
  /// satura en 36 repeticiones, que es donde su denominador llega a cero.
  static String _expresion1RM(
    Formula formula,
    String alias,
  ) => switch (formula) {
    Formula.epley =>
      'CASE WHEN $alias.repeticiones <= 1 THEN $alias.peso '
          'ELSE $alias.peso * (1 + $alias.repeticiones / 30.0) END',
    Formula.brzycki =>
      'CASE WHEN $alias.repeticiones <= 1 THEN $alias.peso '
          'ELSE $alias.peso * 36.0 / (37 - MIN($alias.repeticiones, 36)) END',
  };

  /// Lo que dio de sí cada **sesión** en un ejercicio, de la más antigua a la
  /// más reciente.
  ///
  /// Es lo que consumen el gráfico y las listas de progreso: con
  /// [seriesConFecha] pintarían una barra por serie en vez de una por sesión.
  /// Las series de calentamiento no entran en ninguna de las cifras, así que
  /// una sesión que solo fuera calentamiento no aparece aquí.
  ///
  /// De cada sesión salen **dos** estimaciones de 1RM: la mejor de todas y la
  /// mejor entre las series de hasta doce repeticiones. La segunda es la que
  /// vale para un récord; la primera se enseña igual, marcada.
  Future<List<ResumenSesionEjercicio>> resumenSesionesEjercicio(
    int idRutina,
    int idEjercicio, {
    Formula formula = Formula.epley,
  }) async {
    final estimado = _expresion1RM(formula, 's');
    // `MAX(CASE WHEN ...)` en vez de `FILTER`, que es más legible pero exige
    // SQLite 3.30 y no hay motivo para poner ese suelo.
    final filas = await customSelect(
      '''
      SELECT e.id            AS id,
             e.fecha         AS fecha,
             COUNT(*)        AS n_series,
             SUM(s.repeticiones)          AS repeticiones,
             SUM(s.peso * s.repeticiones) AS volumen,
             MAX(s.peso)                  AS maximo,
             MAX($estimado)               AS mejor_1rm,
             MAX(CASE WHEN s.repeticiones <= $maxRepeticionesFiables
                      THEN $estimado END) AS mejor_1rm_fiable
      FROM serie s
      JOIN entrenamientos e ON e.id = s.id_entrenamiento
      WHERE e.id_rutina = ? AND s.id_ejercicio = ? AND s.calentamiento = 0
      GROUP BY e.id
      ORDER BY e.fecha, e.id
      ''',
      variables: [Variable.withInt(idRutina), Variable.withInt(idEjercicio)],
      readsFrom: {seriesTabla, entrenamientos},
    ).get();

    return [
      for (final f in filas)
        ResumenSesionEjercicio(
          idEntrenamiento: f.read<int>('id'),
          fecha: f.read<DateTime>('fecha'),
          nSeries: f.read<int>('n_series'),
          repeticiones: f.read<int>('repeticiones'),
          volumen: f.read<double>('volumen'),
          pesoMaximo: f.read<double>('maximo'),
          mejor1RM: f.read<double>('mejor_1rm'),
          mejor1RMFiable: f.read<double?>('mejor_1rm_fiable'),
        ),
    ];
  }

  /// El mismo agregado por sesión, pero de **todos** los ejercicios a la vez.
  ///
  /// Es lo que alimenta la línea de ejercicios estancados del resumen semanal.
  /// Va en una sola consulta y no en una por ejercicio: la detección la hace
  /// `progresion.estancados` sobre lo que esto devuelve, igual que los récords
  /// se calculan sobre el historial que la pantalla ya tiene.
  Future<List<SesionesDeEjercicio>> resumenSesionesTodos({
    Formula formula = Formula.epley,
  }) async {
    final estimado = _expresion1RM(formula, 's');
    final filas = await customSelect(
      '''
      SELECT j.id            AS id_ejercicio,
             j.id_rutina     AS id_rutina,
             j.nombre        AS nombre,
             e.id            AS id,
             e.fecha         AS fecha,
             COUNT(*)        AS n_series,
             SUM(s.repeticiones)          AS repeticiones,
             SUM(s.peso * s.repeticiones) AS volumen,
             MAX(s.peso)                  AS maximo,
             MAX($estimado)               AS mejor_1rm,
             MAX(CASE WHEN s.repeticiones <= $maxRepeticionesFiables
                      THEN $estimado END) AS mejor_1rm_fiable
      FROM serie s
      JOIN entrenamientos e ON e.id = s.id_entrenamiento
      JOIN ejercicios j     ON j.id = s.id_ejercicio
      WHERE s.calentamiento = 0
      GROUP BY j.id, e.id
      ORDER BY j.id, e.fecha, e.id
      ''',
      readsFrom: {seriesTabla, entrenamientos, ejercicios},
    ).get();

    final porEjercicio = <int, SesionesDeEjercicio>{};
    for (final f in filas) {
      final idEjercicio = f.read<int>('id_ejercicio');
      final grupo = porEjercicio.putIfAbsent(
        idEjercicio,
        () => SesionesDeEjercicio(
          idRutina: f.read<int>('id_rutina'),
          idEjercicio: idEjercicio,
          nombre: f.read<String>('nombre'),
          sesiones: [],
        ),
      );
      grupo.sesiones.add(
        ResumenSesionEjercicio(
          idEntrenamiento: f.read<int>('id'),
          fecha: f.read<DateTime>('fecha'),
          nSeries: f.read<int>('n_series'),
          repeticiones: f.read<int>('repeticiones'),
          volumen: f.read<double>('volumen'),
          pesoMaximo: f.read<double>('maximo'),
          mejor1RM: f.read<double>('mejor_1rm'),
          mejor1RMFiable: f.read<double?>('mejor_1rm_fiable'),
        ),
      );
    }
    return porEjercicio.values.toList();
  }

  /// Series de la **última sesión** de un ejercicio, para precargar el registro.
  ///
  /// Devuelve tantas entradas como series tuvo aquel día, con sus valores; la
  /// lista vacía significa que el ejercicio nunca se ha entrenado.
  Future<List<ValoresSerie>> ultimasSeriesEjercicio(int idEjercicio) async {
    final ultima =
        await (select(seriesTabla).join([
                innerJoin(
                  entrenamientos,
                  entrenamientos.id.equalsExp(seriesTabla.idEntrenamiento),
                ),
              ])
              ..where(seriesTabla.idEjercicio.equals(idEjercicio))
              ..orderBy([
                OrderingTerm(
                  expression: entrenamientos.fecha,
                  mode: OrderingMode.desc,
                ),
                OrderingTerm(
                  expression: entrenamientos.id,
                  mode: OrderingMode.desc,
                ),
              ])
              ..limit(1))
            .getSingleOrNull();
    if (ultima == null) return const [];

    final idEntrenamiento = ultima.readTable(entrenamientos).id;
    final series =
        await (select(seriesTabla)
              ..where(
                (s) =>
                    s.idEjercicio.equals(idEjercicio) &
                    s.idEntrenamiento.equals(idEntrenamiento),
              )
              ..orderBy([(s) => OrderingTerm(expression: s.nSerie)]))
            .get();

    return [
      for (final s in series)
        ValoresSerie(
          repeticiones: s.repeticiones,
          peso: s.peso,
          calentamiento: s.calentamiento,
          rpe: s.rpe,
          nota: s.nota,
        ),
    ];
  }

  /// Sesiones de una rutina, de la más reciente a la más antigua.
  ///
  /// Trae las tres cifras que pinta la lista —ejercicios, series y volumen— ya
  /// agregadas, para no consultar una vez por fila. Las sesiones sin ninguna
  /// serie (que no deberían existir, pero podrían) también aparecen: si no, no
  /// habría forma de borrarlas desde la app.
  Future<List<ResumenSesion>> historialRutina(
    int idRutina, {
    int limite = 50,
    int desplazamiento = 0,
  }) async {
    final filas = await customSelect(
      '''
      SELECT e.id                          AS id,
             e.fecha                       AS fecha,
             COUNT(DISTINCT s.id_ejercicio) AS n_ejercicios,
             COUNT(s.id)                   AS n_series,
             COALESCE(SUM(
               CASE WHEN s.calentamiento = 0 THEN s.peso * s.repeticiones ELSE 0 END
             ), 0)                         AS volumen,
             (e.nota IS NOT NULL OR COUNT(s.nota) > 0) AS tiene_nota
      FROM entrenamientos e
      LEFT JOIN serie s ON s.id_entrenamiento = e.id
      WHERE e.id_rutina = ?
      GROUP BY e.id
      ORDER BY e.fecha DESC, e.id DESC
      LIMIT ? OFFSET ?
      ''',
      variables: [
        Variable.withInt(idRutina),
        Variable.withInt(limite),
        Variable.withInt(desplazamiento),
      ],
      readsFrom: {entrenamientos, seriesTabla},
    ).get();

    return [
      for (final f in filas)
        ResumenSesion(
          id: f.read<int>('id'),
          fecha: f.read<DateTime>('fecha'),
          nEjercicios: f.read<int>('n_ejercicios'),
          nSeries: f.read<int>('n_series'),
          volumen: f.read<double>('volumen'),
          tieneNota: f.read<bool>('tiene_nota'),
        ),
    ];
  }

  /// Una sesión con sus ejercicios y series, o `null` si ya no existe.
  ///
  /// Es lo que pinta el detalle y lo que precarga la edición, así que resuelve
  /// también la ficha de catálogo de cada ejercicio.
  Future<SesionCompleta?> sesion(int idEntrenamiento) async {
    final entrenamiento = await (select(
      entrenamientos,
    )..where((e) => e.id.equals(idEntrenamiento))).getSingleOrNull();
    if (entrenamiento == null) return null;

    final filas =
        await (select(
          seriesTabla,
        )..where((s) => s.idEntrenamiento.equals(idEntrenamiento))).join([
          innerJoin(
            ejercicios,
            ejercicios.id.equalsExp(seriesTabla.idEjercicio),
          ),
          leftOuterJoin(
            catalogoEjercicios,
            catalogoEjercicios.id.equalsExp(ejercicios.idCatalogo),
          ),
        ]).get();

    // Se agrupa en memoria manteniendo el orden de la rutina y, dentro de cada
    // ejercicio, el de las series.
    final porEjercicio = <int, List<Serie>>{};
    final fichas = <int, EjercicioConFicha>{};
    for (final f in filas) {
      final ejercicio = f.readTable(ejercicios);
      fichas[ejercicio.id] = EjercicioConFicha(
        ejercicio,
        f.readTableOrNull(catalogoEjercicios),
      );
      (porEjercicio[ejercicio.id] ??= []).add(f.readTable(seriesTabla));
    }

    // El orden de la rutina, con el id de desempate, igual que en
    // [ejerciciosDeRutina].
    final ordenados = fichas.keys.toList()
      ..sort((a, b) {
        final porOrden = fichas[a]!.ejercicio.orden.compareTo(
          fichas[b]!.ejercicio.orden,
        );
        return porOrden != 0 ? porOrden : a.compareTo(b);
      });
    return SesionCompleta(
      entrenamiento: entrenamiento,
      ejercicios: [
        for (final id in ordenados)
          EjercicioDeSesion(fichas[id]!, [
            for (final s
                in porEjercicio[id]!
                  ..sort((a, b) => a.nSerie.compareTo(b.nSerie)))
              ValoresSerie(
                repeticiones: s.repeticiones,
                peso: s.peso,
                calentamiento: s.calentamiento,
                rpe: s.rpe,
                nota: s.nota,
              ),
          ]),
      ],
    );
  }

  /// Ejercicios en los que la sesión [idEntrenamiento] batió algún récord.
  ///
  /// Los tres de C16: peso máximo en una serie, 1RM estimado —solo con las
  /// series de hasta doce repeticiones, que son las que dan una estimación de
  /// fiar— y volumen de la sesión.
  ///
  /// La comparación es contra lo anterior **a esta sesión** dentro de la misma
  /// rutina, así que llamarlo dos veces devuelve lo mismo: no depende de cuándo
  /// se pregunte, ni editar una sesión antigua convierte retroactivamente en
  /// récord algo que no lo fue. Un ejercicio estrenado ese día también cuenta,
  /// con los «anterior» nulos. El calentamiento no entra.
  Future<List<RecordSesion>> recordsDeSesion(
    int idEntrenamiento, {
    Formula formula = Formula.epley,
  }) async {
    final estimado = _expresion1RM(formula, 's');
    final estimadoPrevio = _expresion1RM(formula, 'sp');

    // Las tres subconsultas comparten el mismo «antes de esta sesión»:
    // fecha anterior, o la misma fecha con id menor. Es el desempate que ya usa
    // el resto de la app para ordenar dos sesiones del mismo día.
    final filas = await customSelect(
      '''
      SELECT ej.nombre       AS nombre,
             MAX(s.peso)     AS maximo,
             MAX(CASE WHEN s.repeticiones <= $maxRepeticionesFiables
                      THEN $estimado END)      AS mejor_1rm,
             SUM(s.peso * s.repeticiones)      AS volumen,
             (SELECT MAX(sp.peso)
                FROM serie sp
                JOIN entrenamientos ep ON ep.id = sp.id_entrenamiento
               WHERE sp.id_ejercicio = s.id_ejercicio
                 AND sp.calentamiento = 0
                 AND ep.id_rutina = e.id_rutina
                 AND (ep.fecha < e.fecha
                      OR (ep.fecha = e.fecha AND ep.id < e.id))) AS anterior,
             (SELECT MAX(CASE WHEN sp.repeticiones <= $maxRepeticionesFiables
                              THEN $estimadoPrevio END)
                FROM serie sp
                JOIN entrenamientos ep ON ep.id = sp.id_entrenamiento
               WHERE sp.id_ejercicio = s.id_ejercicio
                 AND sp.calentamiento = 0
                 AND ep.id_rutina = e.id_rutina
                 AND (ep.fecha < e.fecha
                      OR (ep.fecha = e.fecha AND ep.id < e.id))) AS anterior_1rm,
             (SELECT MAX(previo.total)
                FROM (SELECT SUM(sp.peso * sp.repeticiones) AS total
                        FROM serie sp
                        JOIN entrenamientos ep ON ep.id = sp.id_entrenamiento
                       WHERE sp.id_ejercicio = s.id_ejercicio
                         AND sp.calentamiento = 0
                         AND ep.id_rutina = e.id_rutina
                         AND (ep.fecha < e.fecha
                              OR (ep.fecha = e.fecha AND ep.id < e.id))
                       GROUP BY ep.id) AS previo) AS anterior_volumen
      FROM serie s
      JOIN entrenamientos e ON e.id = s.id_entrenamiento
      JOIN ejercicios ej    ON ej.id = s.id_ejercicio
      WHERE s.id_entrenamiento = ? AND s.calentamiento = 0
      GROUP BY s.id_ejercicio
      HAVING (anterior IS NULL OR MAX(s.peso) > anterior)
          OR (mejor_1rm IS NOT NULL
              AND (anterior_1rm IS NULL OR mejor_1rm > anterior_1rm))
          OR (anterior_volumen IS NULL
              OR SUM(s.peso * s.repeticiones) > anterior_volumen)
      ORDER BY ej.orden, ej.id
      ''',
      variables: [Variable.withInt(idEntrenamiento)],
      readsFrom: {seriesTabla, entrenamientos, ejercicios},
    ).get();

    return [
      for (final f in filas)
        RecordSesion(
          nombre: f.read<String>('nombre'),
          pesoMaximo: f.read<double>('maximo'),
          mejor1RM: f.read<double?>('mejor_1rm'),
          volumen: f.read<double>('volumen'),
          pesoAnterior: f.read<double?>('anterior'),
          unoRmAnterior: f.read<double?>('anterior_1rm'),
          volumenAnterior: f.read<double?>('anterior_volumen'),
        ),
    ];
  }

  /// Fecha del último entrenamiento de una rutina.
  Future<DateTime?> ultimoEntrenamientoRutina(int idRutina) {
    final maxima = entrenamientos.fecha.max();
    final consulta = selectOnly(entrenamientos)
      ..addColumns([maxima])
      ..where(entrenamientos.idRutina.equals(idRutina));
    return consulta.map((f) => f.read(maxima)).getSingle();
  }

  Future<int> contarEntrenamientosRutina(int idRutina) {
    final cuenta = entrenamientos.id.count();
    final consulta = selectOnly(entrenamientos)
      ..addColumns([cuenta])
      ..where(entrenamientos.idRutina.equals(idRutina));
    return consulta.map((f) => f.read(cuenta) ?? 0).getSingle();
  }

  // ── Ajustes ────────────────────────────────────────────────────────────────

  /// Las preferencias, ya interpretadas y con sus valores por defecto.
  ///
  /// Se leen en casi cada pantalla, así que van todas de una vez: quien las
  /// necesite mira el `ajustesProvider`, que las tiene en memoria.
  Future<Ajustes> ajustes() async => Ajustes.desdeMapa(await ajustesCrudos());

  /// Las filas tal cual. Solo lo usa la copia de seguridad.
  Future<Map<String, String>> ajustesCrudos() async {
    final filas = await select(ajustesTabla).get();
    return {for (final f in filas) f.clave: f.valor};
  }

  Future<void> fijarAjuste(String clave, String valor) =>
      into(ajustesTabla).insertOnConflictUpdate(
        AjustesTablaCompanion.insert(clave: clave, valor: valor),
      );

  /// Escribe varias preferencias de golpe, en una transacción.
  Future<void> fijarAjustes(Map<String, String> valores) =>
      transaction(() async {
        for (final entrada in valores.entries) {
          await fijarAjuste(entrada.key, entrada.value);
        }
      });

  // ── Sesión en curso ────────────────────────────────────────────────────────

  /// Guarda (o pisa) el borrador de la sesión que se está entrenando.
  ///
  /// Como mucho hay una fila: si ya había un borrador de otra rutina, este lo
  /// sustituye. Empezar un entrenamiento nuevo con otro a medias es una
  /// decisión del usuario, no un caso que haya que conservar por duplicado.
  Future<void> guardarSesionActiva(
    int idRutina,
    DateTime inicio,
    String estadoJson,
  ) => transaction(() async {
    await delete(sesionesActivas).go();
    await into(sesionesActivas).insert(
      SesionesActivasCompanion.insert(
        idRutina: idRutina,
        inicio: inicio,
        actualizado: DateTime.now(),
        estado: estadoJson,
      ),
    );
  });

  Future<SesionActiva?> sesionActiva() =>
      (select(sesionesActivas)..limit(1)).getSingleOrNull();

  Future<void> descartarSesionActiva() => delete(sesionesActivas).go();

  // ── Descanso y progresión por ejercicio ────────────────────────────────────

  /// Fija el descanso propio de un ejercicio. `null` vuelve al valor global.
  Future<void> fijarDescansoEjercicio(int idEjercicio, int? segundos) =>
      (update(ejercicios)..where((e) => e.id.equals(idEjercicio))).write(
        EjerciciosCompanion(descansoSeg: Value(segundos)),
      );

  /// Fija la configuración de progresión propia de un ejercicio.
  ///
  /// Los parámetros son `Value<T>` y no `T?` a propósito: aquí `null` es un
  /// valor con significado —«como el global»— y hace falta poder distinguirlo de
  /// «esta llamada no toca esa columna». `Value.absent()` es lo segundo, que es
  /// además el valor por defecto, así que cada fila de la hoja de opciones
  /// escribe solo la suya.
  Future<void> fijarProgresionEjercicio(
    int idEjercicio, {
    Value<int?> repMin = const Value.absent(),
    Value<int?> repMax = const Value.absent(),
    Value<double?> incrementoKg = const Value.absent(),
    Value<int?> estrategia = const Value.absent(),
  }) => (update(ejercicios)..where((e) => e.id.equals(idEjercicio))).write(
    EjerciciosCompanion(
      repMin: repMin,
      repMax: repMax,
      incrementoKg: incrementoKg,
      estrategia: estrategia,
    ),
  );

  /// Sesiones de cada día dentro del rango pedido, en orden.
  ///
  /// Un día puede tener varias, de la misma rutina o de rutinas distintas: la
  /// versión anterior devolvía `Map<DateTime, int>` y la segunda sesión del día
  /// pisaba a la primera, de modo que el calendario solo pintaba una.
  ///
  /// El rango no es un adorno: antes se cargaban en memoria todos los
  /// entrenamientos de la historia para pintar un solo mes.
  ///
  /// Trae de paso las cifras de cada sesión, que el calendario en sí no
  /// necesita pero sí la hoja que se abre al pulsar un día (C19): sin ellas,
  /// pulsar una celda dispararía una consulta por sesión listada.
  Future<Map<DateTime, List<SesionDelDia>>> entrenamientosPorDia({
    required DateTime desde,
    required DateTime hasta,
  }) async {
    final filas = await customSelect(
      '''
      SELECT e.id                           AS id,
             e.id_rutina                    AS id_rutina,
             e.fecha                        AS fecha,
             e.duracion_seg                 AS duracion_seg,
             COUNT(DISTINCT s.id_ejercicio) AS n_ejercicios,
             COUNT(s.id)                    AS n_series,
             COALESCE(SUM(
               CASE WHEN s.calentamiento = 0 THEN s.peso * s.repeticiones ELSE 0 END
             ), 0)                          AS volumen
      FROM entrenamientos e
      LEFT JOIN serie s ON s.id_entrenamiento = e.id
      WHERE e.fecha >= ? AND e.fecha < ?
      GROUP BY e.id
      ORDER BY e.fecha, e.id
      ''',
      variables: [Variable.withDateTime(desde), Variable.withDateTime(hasta)],
      readsFrom: {entrenamientos, seriesTabla},
    ).get();

    final porDia = <DateTime, List<SesionDelDia>>{};
    for (final f in filas) {
      final fecha = f.read<DateTime>('fecha');
      final dia = DateTime(fecha.year, fecha.month, fecha.day);
      (porDia[dia] ??= []).add(
        SesionDelDia(
          id: f.read<int>('id'),
          idRutina: f.read<int>('id_rutina'),
          fecha: fecha,
          duracionSeg: f.read<int?>('duracion_seg'),
          nEjercicios: f.read<int>('n_ejercicios'),
          nSeries: f.read<int>('n_series'),
          volumen: f.read<double>('volumen'),
        ),
      );
    }
    return porDia;
  }

  /// Cada sesión con su volumen ya sumado, de la más reciente hacia atrás.
  ///
  /// Es **la única consulta** del resumen semanal: de aquí salen las sesiones y
  /// el volumen de esta semana, los de la anterior y la racha, porque el
  /// reparto por semanas se hace en Dart (`metricas.porSemana`). Las funciones
  /// de fecha de SQLite trabajan en UTC y partirían mal las semanas en huso
  /// local.
  Future<List<SesionConVolumen>> sesionesConVolumen({DateTime? desde}) async {
    final filas = await customSelect(
      '''
      SELECT e.id        AS id,
             e.id_rutina AS id_rutina,
             e.fecha     AS fecha,
             COALESCE(SUM(
               CASE WHEN s.calentamiento = 0 THEN s.peso * s.repeticiones ELSE 0 END
             ), 0)       AS volumen
      FROM entrenamientos e
      LEFT JOIN serie s ON s.id_entrenamiento = e.id
      ${desde == null ? '' : 'WHERE e.fecha >= ?'}
      GROUP BY e.id
      ORDER BY e.fecha DESC, e.id DESC
      ''',
      variables: [if (desde != null) Variable.withDateTime(desde)],
      readsFrom: {entrenamientos, seriesTabla},
    ).get();

    return [
      for (final f in filas)
        SesionConVolumen(
          id: f.read<int>('id'),
          idRutina: f.read<int>('id_rutina'),
          fecha: f.read<DateTime>('fecha'),
          volumen: f.read<double>('volumen'),
        ),
    ];
  }

  // ── Mapa muscular ──────────────────────────────────────────────────────────

  /// Todo el trabajo por ejercicio y sesión desde [desde], con la clasificación
  /// muscular de la ficha del catálogo.
  ///
  /// Es **la única consulta** del mapa muscular. El reparto entre regiones, el
  /// corte por periodo y los niveles de color se hacen luego en Dart, en
  /// `musculos.dart`, igual que el resumen semanal reparte con `porSemana`. Por
  /// eso cambiar el periodo de 7 a 90 días recorre otra vez la misma lista y no
  /// vuelve a la base.
  ///
  /// El `LEFT JOIN` al catálogo es deliberado: los ejercicios personalizados no
  /// tienen ficha y aun así tienen que llegar, porque se cuentan en el aviso de
  /// «no están representados».
  Future<List<TrabajoMuscular>> trabajoPorMusculo({
    required DateTime desde,
  }) async {
    final filas = await customSelect(
      '''
      SELECT e.id           AS id_entrenamiento,
             e.id_rutina    AS id_rutina,
             e.fecha        AS fecha,
             j.id           AS id_ejercicio,
             j.nombre       AS ejercicio,
             j.id_catalogo  AS id_catalogo,
             COALESCE(c.target, '')            AS target,
             COALESCE(c.muscle_group, '')      AS muscle_group,
             COALESCE(c.secondary_muscles, '') AS secondary_muscles,
             COUNT(*)                          AS n_series,
             -- El peso se eleva a un mínimo de 1 para que las dominadas, que se
             -- registran con peso 0, no sumen cero: el mapa mide atención
             -- dedicada y no carga. El literal va con decimal para que SUM
             -- devuelva REAL aunque todas las series sean de peso corporal.
             SUM(s.repeticiones *
                 CASE WHEN s.peso < 1.0 THEN 1.0 ELSE s.peso END) AS volumen
      FROM serie s
      JOIN entrenamientos e ON e.id = s.id_entrenamiento
      JOIN ejercicios j     ON j.id = s.id_ejercicio
      LEFT JOIN catalogo_ejercicios c ON c.id = j.id_catalogo
      WHERE s.calentamiento = 0 AND e.fecha >= ?
      GROUP BY e.id, j.id
      ORDER BY e.fecha DESC, e.id DESC
      ''',
      variables: [Variable.withDateTime(desde)],
      readsFrom: {seriesTabla, entrenamientos, ejercicios, catalogoEjercicios},
    ).get();

    return [
      for (final f in filas)
        TrabajoMuscular(
          idEntrenamiento: f.read<int>('id_entrenamiento'),
          idRutina: f.read<int>('id_rutina'),
          fecha: f.read<DateTime>('fecha'),
          idEjercicio: f.read<int>('id_ejercicio'),
          ejercicio: f.read<String>('ejercicio'),
          idCatalogo: f.read<String?>('id_catalogo'),
          target: f.read<String>('target'),
          muscleGroup: f.read<String>('muscle_group'),
          secondaryMuscles: f.read<String>('secondary_muscles'),
          nSeries: f.read<int>('n_series'),
          volumen: f.read<double>('volumen'),
        ),
    ];
  }

  /// Los ejercicios del catálogo que el usuario tiene en alguna rutina.
  ///
  /// Sirve para dos cosas de la hoja del músculo a la vez: decir en qué rutinas
  /// aparece un músculo y poner delante, en la lista de ejercicios, los que ya
  /// se usan. Son decenas de filas, así que se trae entera.
  Future<List<EjercicioEnRutina>> catalogoEnRutinas() async {
    final filas = await select(ejercicios).join([
      innerJoin(rutinas, rutinas.id.equalsExp(ejercicios.idRutina)),
      innerJoin(
        catalogoEjercicios,
        catalogoEjercicios.id.equalsExp(ejercicios.idCatalogo),
      ),
    ]).get();
    return [
      for (final f in filas)
        EjercicioEnRutina(
          f.readTable(rutinas).nombre,
          f.readTable(catalogoEjercicios),
        ),
    ];
  }

  // ── Volcado completo, para la copia de seguridad ───────────────────────────

  /// Sesiones de una rutina, de la más antigua a la más reciente.
  Future<List<Entrenamiento>> entrenamientosDeRutina(int idRutina) =>
      (select(entrenamientos)
            ..where((e) => e.idRutina.equals(idRutina))
            ..orderBy([
              (e) => OrderingTerm(expression: e.fecha),
              (e) => OrderingTerm(expression: e.id),
            ]))
          .get();

  /// Todas las series de una rutina, agrupadas por sesión.
  ///
  /// Una consulta para la rutina entera: exportar con [sesion] por cada
  /// entrenamiento serían tantas consultas como sesiones tenga el histórico.
  Future<Map<int, List<Serie>>> seriesPorEntrenamiento(int idRutina) async {
    final filas =
        await (select(seriesTabla)..orderBy([
              (s) => OrderingTerm(expression: s.idEjercicio),
              (s) => OrderingTerm(expression: s.nSerie),
            ]))
            .join([
              innerJoin(
                entrenamientos,
                entrenamientos.id.equalsExp(seriesTabla.idEntrenamiento) &
                    entrenamientos.idRutina.equals(idRutina),
              ),
            ])
            .get();

    final porSesion = <int, List<Serie>>{};
    for (final f in filas) {
      final serie = f.readTable(seriesTabla);
      (porSesion[serie.idEntrenamiento] ??= []).add(serie);
    }
    return porSesion;
  }

  // ── Restauración de una copia de seguridad ─────────────────────────────────
  //
  // Escriben lo que viene del fichero **tal cual**, sin las reglas que aplican
  // los métodos normales: la copia ya trae su color, su orden y sus fechas, y
  // recalcularlos aquí sería reinterpretar los datos del usuario. Quien las
  // llama es `copia.dart`, siempre dentro de una `transaction()`.

  Future<int> restaurarRutina(String nombre, String? color) => into(
    rutinas,
  ).insert(RutinasCompanion.insert(nombre: nombre, color: Value(color)));

  Future<int> restaurarEjercicio(
    int idRutina, {
    required String nombre,
    required int orden,
    String? idCatalogo,
    String? descripcion,
    int? descansoSeg,
    int? repMin,
    int? repMax,
    double? incrementoKg,
    int? estrategia,
  }) => into(ejercicios).insert(
    EjerciciosCompanion.insert(
      idRutina: idRutina,
      nombre: nombre,
      orden: Value(orden),
      idCatalogo: Value(idCatalogo),
      descripcion: Value(descripcion),
      descansoSeg: Value(descansoSeg),
      repMin: Value(repMin),
      repMax: Value(repMax),
      incrementoKg: Value(incrementoKg),
      estrategia: Value(estrategia),
    ),
  );

  Future<int> restaurarEntrenamiento(
    int idRutina,
    DateTime fecha, {
    String? nota,
    int? duracionSeg,
  }) => into(entrenamientos).insert(
    EntrenamientosCompanion.insert(
      idRutina: idRutina,
      fecha: fecha,
      nota: Value(_limpiar(nota)),
      duracionSeg: Value(duracionSeg),
    ),
  );

  /// Series de una sesión restaurada, por id de ejercicio.
  Future<void> restaurarSeries(
    int idEntrenamiento,
    Map<int, List<ValoresSerie>> series,
  ) => _insertarSeries(idEntrenamiento, _soloConSeries(series));

  Future<Set<String>> nombresDeRutinas() async {
    final filas = await todasLasRutinas();
    return {for (final r in filas) r.nombre};
  }

  /// De los ids propuestos, los que existen de verdad en el catálogo.
  ///
  /// Una copia hecha con otra versión del dataset puede traer ids que aquí ya
  /// no están; esos ejercicios se importan como personalizados en vez de
  /// perderse o de dejar una referencia rota.
  Future<Set<String>> idsDeCatalogoExistentes(Set<String> candidatos) async {
    if (candidatos.isEmpty) return const {};
    final consulta = selectOnly(catalogoEjercicios)
      ..addColumns([catalogoEjercicios.id])
      ..where(catalogoEjercicios.id.isIn(candidatos));
    final filas = await consulta.get();
    return {for (final f in filas) ?f.read(catalogoEjercicios.id)};
  }

  /// Borra todo lo que es del usuario y **conserva el catálogo**.
  ///
  /// El catálogo son 1.324 filas regenerables desde el asset, así que borrarlo
  /// solo serviría para que el siguiente arranque tardara más. Lo demás —
  /// rutinas con su cascade, medidas, favoritos, vistos, el borrador en curso y
  /// las preferencias— sí se va, en una sola transacción.
  ///
  /// **Salvo las claves de dispositivo** (`Claves.locales`). No son datos del
  /// usuario: son de este móvil. Borrarlas aquí desconectaría la copia
  /// automática sin haberlo pedido —el botón dice «rutinas, sesiones y
  /// medidas»—, y dejaría además la cuenta olvidada en la tabla con su token
  /// todavía en el almacén seguro. Por lo mismo, importar una copia con
  /// «reemplazar» no apaga la copia automática de este dispositivo.
  Future<void> borrarTodosLosDatos() => transaction(() async {
    final locales = {
      for (final entrada in (await ajustesCrudos()).entries)
        if (Claves.locales.contains(entrada.key)) entrada.key: entrada.value,
    };

    await delete(sesionesActivas).go();
    await delete(rutinas).go();
    await delete(medidas).go();
    await delete(favoritos).go();
    await delete(vistos).go();
    await delete(ajustesTabla).go();

    await fijarAjustes(locales);
  });
}
