/// Tests de migración: una base de una versión anterior se abre sin pérdida.
///
/// Se apoyan en los esquemas volcados en `drift_schemas/` y en los ayudantes
/// que genera drift a partir de ellos (`test/esquemas/`), de forma que la base
/// de partida es la de verdad —la que tiene instalada el usuario—, no una
/// reconstrucción a mano.
///
/// Para regenerarlos tras subir `schemaVersion`:
///
/// ```bash
/// dart run drift_dev schema dump lib/datos/bd.dart drift_schemas/
/// dart run drift_dev schema steps drift_schemas/ lib/datos/esquemas.dart
/// dart run drift_dev schema generate drift_schemas/ test/esquemas/
/// ```
library;

import 'dart:io';

import 'package:appgym/datos/bd.dart';
import 'package:appgym/datos/respaldo.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'esquemas/schema.dart';
import 'esquemas/schema_v1.dart' as v1;

/// Segundos desde época, que es como drift guarda las fechas aquí.
int _epoca(DateTime fecha) => fecha.millisecondsSinceEpoch ~/ 1000;

void main() {
  late SchemaVerifier verificador;

  setUpAll(() => verificador = SchemaVerifier(GeneratedHelper()));

  test('v1 → v2: cada fila agregada se expande en una fila por serie', () async {
    final esquema = await verificador.schemaAt(1);

    // Una base tal y como la dejaría la app antes de esta iteración: una única
    // fila por ejercicio y sesión, con el *recuento* de series en n_serie.
    final vieja = v1.DatabaseAtV1(esquema.newConnection());
    await vieja.customStatement(
      "INSERT INTO rutinas (id, nombre, color) VALUES (1, 'Empuje', '#0A84FF')",
    );
    await vieja.customStatement(
      'INSERT INTO ejercicios (id, id_rutina, nombre) '
      "VALUES (1, 1, 'Press banca'), (2, 1, 'Aperturas')",
    );
    await vieja.customStatement(
      'INSERT INTO entrenamientos (id, id_rutina, fecha) '
      'VALUES (1, 1, ${_epoca(DateTime(2026, 3, 1))}), '
      '(2, 1, ${_epoca(DateTime(2026, 3, 8))})',
    );
    await vieja.customStatement(
      'INSERT INTO serie (id_entrenamiento, id_ejercicio, n_serie, repeticiones, peso) '
      'VALUES (1, 1, 4, 10, 60.0), (1, 2, 3, 12, 20.0), (2, 1, 5, 8, 62.5)',
    );
    await vieja.close();

    final bd = AppBD(esquema.newConnection());
    // Además de migrar, compara el esquema resultante con el volcado de la v2:
    // es lo que caza una columna que se añadió al modelo y no a la migración.
    await verificador.migrateAndValidate(bd, 2);

    // Las rutinas y los ejercicios siguen ahí.
    final rutinas = await bd.resumenRutinas();
    expect(rutinas.single.nombre, 'Empuje');
    expect(rutinas.single.nEjercicios, 2);
    expect(await bd.contarEntrenamientosRutina(1), 2);

    // Y las cuatro series de la primera sesión son ahora cuatro filas iguales.
    final press = await bd.seriesConFecha(1, 1);
    expect(press.length, 9);
    expect(press.take(4).map((s) => s.nSerie), [1, 2, 3, 4]);
    expect(press.take(4).map((s) => s.peso), [60, 60, 60, 60]);
    expect(press.take(4).map((s) => s.repeticiones), [10, 10, 10, 10]);
    expect(press.map((s) => s.calentamiento), everyElement(isFalse));
    expect(press.last.nSerie, 5);

    // El volumen total no cambia: 4×10×60 + 5×8×62,5 en el press.
    final volumen = press.fold<double>(
      0,
      (suma, s) => suma + s.peso * s.repeticiones,
    );
    expect(volumen, 4 * 10 * 60 + 5 * 8 * 62.5);

    final aperturas = await bd.seriesConFecha(1, 2);
    expect(aperturas.length, 3);
    expect(
      aperturas.fold<double>(0, (suma, s) => suma + s.peso * s.repeticiones),
      3 * 12 * 20,
    );

    await bd.close();
  });

  test('v1 → v2: una base sin entrenamientos migra igual', () async {
    final esquema = await verificador.schemaAt(1);

    final vieja = v1.DatabaseAtV1(esquema.newConnection());
    await vieja.customStatement(
      "INSERT INTO rutinas (id, nombre, color) VALUES (1, 'Pierna', '#30D158')",
    );
    await vieja.close();

    final bd = AppBD(esquema.newConnection());
    await verificador.migrateAndValidate(bd, 2);

    expect((await bd.resumenRutinas()).single.nombre, 'Pierna');
    expect(await bd.seriesConFecha(1, 1), isEmpty);

    await bd.close();
  });

  group('respaldo previo', () {
    late Directory directorio;
    late File fichero;

    setUp(() async {
      directorio = await Directory.systemTemp.createTemp('appgym-respaldo');
      fichero = File('${directorio.path}/appgym.sqlite');
    });

    tearDown(() => directorio.delete(recursive: true));

    /// Deja en disco un fichero con el esquema de la versión pedida.
    Future<void> crearBase(int version) async {
      final bd = GeneratedHelper().databaseForVersion(
        NativeDatabase(fichero),
        version,
      );
      await bd.customStatement('SELECT 1');
      await bd.close();
    }

    test('copia el fichero cuando todavía es de la v1', () async {
      await crearBase(1);
      expect(await versionDeEsquema(fichero), 1);

      await respaldarSiHaceFalta(fichero);

      final copia = File('${directorio.path}/appgym.bak-v1.sqlite');
      expect(copia.existsSync(), isTrue);
      expect(await versionDeEsquema(copia), 1);
      expect(copia.lengthSync(), fichero.lengthSync());
    });

    test('no rehace la copia ni respalda una base ya migrada', () async {
      await crearBase(1);
      await respaldarSiHaceFalta(fichero);

      final copia = File('${directorio.path}/appgym.bak-v1.sqlite');
      final marca = copia.lastModifiedSync();

      // Segundo arranque: la base ya está en la v2 y la copia buena no se toca.
      await fichero.delete();
      await crearBase(2);
      await respaldarSiHaceFalta(fichero);

      expect(copia.lastModifiedSync(), marca);
      expect(await versionDeEsquema(copia), 1);
      expect(
        File('${directorio.path}/appgym.bak-v2.sqlite').existsSync(),
        isFalse,
      );
    });

    test('con la base sin crear no hay nada que respaldar', () async {
      await respaldarSiHaceFalta(fichero);
      expect(directorio.listSync(), isEmpty);
    });
  });
}
