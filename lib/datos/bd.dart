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
}

/// Ejercicio del catálogo, sembrado desde assets/ejercicios.es.json.
///
/// Es de solo lectura: se rellena al arrancar y la app nunca lo modifica.
@DataClassName('FichaCatalogo')
@TableIndex(name: 'idx_catalogo_busqueda', columns: {#busqueda})
@TableIndex(name: 'idx_catalogo_body_part', columns: {#bodyPart})
@TableIndex(name: 'idx_catalogo_equipment', columns: {#equipment})
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
}

@DataClassName('Serie')
class SeriesTabla extends Table {
  @override
  String get tableName => 'serie';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get idEntrenamiento =>
      integer().references(Entrenamientos, #id, onDelete: KeyAction.cascade)();
  IntColumn get idEjercicio =>
      integer().references(Ejercicios, #id, onDelete: KeyAction.cascade)();
  IntColumn get nSerie => integer()();
  IntColumn get repeticiones => integer()();
  RealColumn get peso => real()();
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
    required this.series,
    required this.repeticiones,
    required this.peso,
  });

  final DateTime fecha;
  final int series;
  final int repeticiones;
  final double peso;
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

/// Valores del último registro de un ejercicio, para precargar el formulario.
class UltimaSerie {
  const UltimaSerie({
    required this.series,
    required this.repeticiones,
    required this.peso,
  });

  final int series;
  final int repeticiones;
  final double peso;
}

@DriftDatabase(
  tables: [
    Rutinas,
    Entrenamientos,
    CatalogoEjercicios,
    Ejercicios,
    SeriesTabla,
  ],
)
class AppBD extends _$AppBD {
  AppBD([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'appgym'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    beforeOpen: (details) async {
      // Sin esto SQLite ignora las claves foráneas y los ON DELETE CASCADE
      // no llegan a ejecutarse.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

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
      ..orderBy([(e) => OrderingTerm(expression: e.id)]);
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
  /// [bodyPart] y [equipment] son los valores originales en inglés.
  Future<List<FichaCatalogo>> buscarCatalogo({
    String? texto,
    String? bodyPart,
    String? equipment,
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
    consulta
      ..orderBy([(c) => OrderingTerm(expression: c.nombre)])
      ..limit(limite, offset: desplazamiento);
    return consulta.get();
  }

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

  /// Guarda un entrenamiento con una serie por ejercicio.
  ///
  /// [series] va de id de ejercicio a los valores registrados.
  Future<bool> insertarEntrenamiento(
    int idRutina,
    DateTime fecha,
    Map<int, UltimaSerie> series,
  ) async {
    if (series.isEmpty) return false;

    await transaction(() async {
      final idEntrenamiento = await into(entrenamientos).insert(
        EntrenamientosCompanion.insert(idRutina: idRutina, fecha: fecha),
      );
      await batch((b) {
        b.insertAll(seriesTabla, [
          for (final entrada in series.entries)
            SeriesTablaCompanion.insert(
              idEntrenamiento: idEntrenamiento,
              idEjercicio: entrada.key,
              nSerie: entrada.value.series,
              repeticiones: entrada.value.repeticiones,
              peso: entrada.value.peso,
            ),
        ]);
      });
    });
    return true;
  }

  /// Series de un ejercicio en una rutina, con su fecha, ordenadas por fecha.
  ///
  /// Devolver la fecha aquí evita que la pantalla de progreso tenga que navegar
  /// de la serie a su entrenamiento fila a fila.
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
          ..orderBy([OrderingTerm(expression: entrenamientos.fecha)]);

    return [
      for (final f in await consulta.get())
        RegistroSerie(
          fecha: f.readTable(entrenamientos).fecha,
          series: f.readTable(seriesTabla).nSerie,
          repeticiones: f.readTable(seriesTabla).repeticiones,
          peso: f.readTable(seriesTabla).peso,
        ),
    ];
  }

  /// Valores del último registro de un ejercicio, o `null` si nunca se entrenó.
  Future<UltimaSerie?> ultimaSerieEjercicio(int idEjercicio) async {
    final consulta =
        select(seriesTabla).join([
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
            OrderingTerm(expression: seriesTabla.id, mode: OrderingMode.desc),
          ])
          ..limit(1);

    final fila = await consulta.getSingleOrNull();
    if (fila == null) return null;
    final serie = fila.readTable(seriesTabla);
    return UltimaSerie(
      series: serie.nSerie,
      repeticiones: serie.repeticiones,
      peso: serie.peso,
    );
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

  /// Día -> id de rutina, con todos los entrenamientos.
  ///
  /// Si un día tiene varios, se queda el más reciente, que es el que colorea la
  /// celda del calendario.
  Future<Map<DateTime, int>> entrenamientosPorDia() async {
    final filas = await (select(
      entrenamientos,
    )..orderBy([(e) => OrderingTerm(expression: e.fecha)])).get();
    return {
      for (final e in filas)
        DateTime(e.fecha.year, e.fecha.month, e.fecha.day): e.idRutina,
    };
  }
}
