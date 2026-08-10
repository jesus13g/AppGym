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
import 'package:appgym/datos/sincro/motor.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'esquemas/schema.dart';
import 'esquemas/schema_v1.dart' as v1;
import 'esquemas/schema_v2.dart' as v2;
import 'esquemas/schema_v3.dart' as v3;
import 'esquemas/schema_v4.dart' as v4;
import 'esquemas/schema_v5.dart' as v5;
import 'esquemas/schema_v6.dart' as v6;
import 'esquemas/schema_v7.dart' as v7;
import 'sincro_falso.dart';

/// Segundos desde época, que es como drift guarda las fechas aquí.
int _epoca(DateTime fecha) => fecha.millisecondsSinceEpoch ~/ 1000;

void main() {
  late SchemaVerifier verificador;

  setUpAll(() => verificador = SchemaVerifier(GeneratedHelper()));

  test('v1 → última: cada fila agregada se expande en una fila por serie', () async {
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
    // Se migra hasta la versión actual —que es lo que le pasará a quien tenga
    // la app instalada desde entonces— y de paso se compara el esquema
    // resultante con el volcado de esa versión: es lo que caza una columna que
    // se añadió al modelo y no a la migración.
    await verificador.migrateAndValidate(bd, bd.schemaVersion);

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

  test('v1 → última: una base sin entrenamientos migra igual', () async {
    final esquema = await verificador.schemaAt(1);

    final vieja = v1.DatabaseAtV1(esquema.newConnection());
    await vieja.customStatement(
      "INSERT INTO rutinas (id, nombre, color) VALUES (1, 'Pierna', '#30D158')",
    );
    await vieja.close();

    final bd = AppBD(esquema.newConnection());
    await verificador.migrateAndValidate(bd, bd.schemaVersion);

    expect((await bd.resumenRutinas()).single.nombre, 'Pierna');
    expect(await bd.seriesConFecha(1, 1), isEmpty);

    await bd.close();
  });

  test('v2 → última: los ejercicios conservan su orden de inserción', () async {
    final esquema = await verificador.schemaAt(2);

    final vieja = v2.DatabaseAtV2(esquema.newConnection());
    await vieja.customStatement(
      "INSERT INTO rutinas (id, nombre, color) VALUES (1, 'Empuje', '#0A84FF'), "
      "(2, 'Pierna', '#30D158')",
    );
    await vieja.customStatement(
      'INSERT INTO ejercicios (id, id_rutina, nombre) VALUES '
      "(1, 1, 'Press banca'), (2, 1, 'Aperturas'), (3, 2, 'Sentadilla'), "
      "(4, 1, 'Fondos'), (5, 2, 'Prensa')",
    );
    await vieja.close();

    final bd = AppBD(esquema.newConnection());
    await verificador.migrateAndValidate(bd, bd.schemaVersion);

    // Cada rutina numera desde 0, siguiendo el id, que era el orden que tenía.
    expect((await bd.ejerciciosDeRutina(1)).map((e) => e.nombre), [
      'Press banca',
      'Aperturas',
      'Fondos',
    ]);
    expect((await bd.ejerciciosDeRutina(1)).map((e) => e.ejercicio.orden), [
      0,
      1,
      2,
    ]);
    expect((await bd.ejerciciosDeRutina(2)).map((e) => e.ejercicio.orden), [
      0,
      1,
    ]);

    await bd.close();
  });

  test('v3 → última: llegan las notas, el RPE y los ajustes', () async {
    final esquema = await verificador.schemaAt(3);

    final vieja = v3.DatabaseAtV3(esquema.newConnection());
    await vieja.customStatement(
      "INSERT INTO rutinas (id, nombre, color) VALUES (1, 'Empuje', '#0A84FF')",
    );
    await vieja.customStatement(
      "INSERT INTO ejercicios (id, id_rutina, nombre, orden) "
      "VALUES (1, 1, 'Press banca', 0)",
    );
    await vieja.customStatement(
      'INSERT INTO entrenamientos (id, id_rutina, fecha) '
      'VALUES (1, 1, ${_epoca(DateTime(2026, 3, 1))})',
    );
    await vieja.customStatement(
      'INSERT INTO serie (id_entrenamiento, id_ejercicio, n_serie, '
      'repeticiones, peso, calentamiento) VALUES (1, 1, 1, 10, 60.0, 0)',
    );
    await vieja.close();

    final bd = AppBD(esquema.newConnection());
    await verificador.migrateAndValidate(bd, bd.schemaVersion);

    // Lo de antes sigue ahí, sin nota ni esfuerzo.
    final sesion = (await bd.sesion(1))!;
    expect(sesion.nota, isNull);
    expect(sesion.ejercicios.single.series.single.rpe, isNull);
    expect(sesion.ejercicios.single.series.single.repeticiones, 10);

    // Y la tabla de ajustes existe, con sus valores por defecto.
    final ajustes = await bd.ajustes();
    expect(ajustes.esfuerzoActivo, isFalse);
    expect(ajustes.escala, EscalaEsfuerzo.rpe);

    await bd.close();
  });

  test('v4 → última: llegan el descanso, la duración y el borrador', () async {
    final esquema = await verificador.schemaAt(4);

    final vieja = v4.DatabaseAtV4(esquema.newConnection());
    await vieja.customStatement(
      "INSERT INTO rutinas (id, nombre, color) VALUES (1, 'Empuje', '#0A84FF')",
    );
    await vieja.customStatement(
      'INSERT INTO ejercicios (id, id_rutina, nombre, orden) '
      "VALUES (1, 1, 'Press banca', 0)",
    );
    await vieja.customStatement(
      'INSERT INTO entrenamientos (id, id_rutina, fecha, nota) '
      "VALUES (1, 1, ${_epoca(DateTime(2026, 3, 1))}, 'Buen día')",
    );
    await vieja.customStatement(
      'INSERT INTO serie (id_entrenamiento, id_ejercicio, n_serie, '
      'repeticiones, peso, calentamiento, rpe) VALUES (1, 1, 1, 10, 60.0, 0, 8)',
    );
    await vieja.customStatement(
      "INSERT INTO ajustes (clave, valor) VALUES ('esfuerzo_activo', '1')",
    );
    await vieja.close();

    final bd = AppBD(esquema.newConnection());
    await verificador.migrateAndValidate(bd, bd.schemaVersion);

    // Lo de antes sigue igual, notas y RPE incluidos.
    final sesion = (await bd.sesion(1))!;
    expect(sesion.nota, 'Buen día');
    expect(sesion.ejercicios.single.series.single.rpe, 8);
    expect((await bd.ajustes()).esfuerzoActivo, isTrue);

    // Y lo nuevo está, vacío: nadie cronometró aquellas sesiones ni fijó un
    // descanso propio, y decirlo con un nulo es más honesto que con un cero.
    expect(sesion.entrenamiento.duracionSeg, isNull);
    expect(
      (await bd.ejerciciosDeRutina(1)).single.ejercicio.descansoSeg,
      isNull,
    );
    expect(await bd.sesionActiva(), isNull);
    await bd.guardarSesionActiva(1, DateTime(2026, 8, 1), '{}');
    expect(await bd.sesionActiva(), isNotNull);

    await bd.close();
  });

  test('v5 → última: llegan favoritos, vistos y medidas', () async {
    final esquema = await verificador.schemaAt(5);

    final vieja = v5.DatabaseAtV5(esquema.newConnection());
    await vieja.customStatement(
      "INSERT INTO rutinas (id, nombre, color) VALUES (1, 'Pierna', '#30D158')",
    );
    await vieja.customStatement(
      'INSERT INTO ejercicios (id, id_rutina, nombre, orden, descanso_seg) '
      "VALUES (1, 1, 'Sentadilla', 0, 180)",
    );
    await vieja.customStatement(
      'INSERT INTO catalogo_ejercicios (id, nombre, body_part, equipment, '
      'target, muscle_group, secondary_muscles, instrucciones, image, gif, '
      "busqueda) VALUES ('0043', 'barbell full squat', 'upper legs', "
      "'barbell', 'glutes', 'upper legs', '[]', '[]', '', '', 'squat')",
    );
    await vieja.close();

    final bd = AppBD(esquema.newConnection());
    await verificador.migrateAndValidate(bd, bd.schemaVersion);

    expect((await bd.ejerciciosDeRutina(1)).single.ejercicio.descansoSeg, 180);

    // Las tablas nuevas están y funcionan, incluido el índice sobre `target`
    // que la validación del esquema ya habrá comprobado.
    await bd.marcarFavorito('0043', true);
    await bd.registrarVisto('0043');
    await bd.registrarMedida(DateTime(2026, 8, 1), 'peso', 78.4);

    expect((await bd.fichasFavoritas()).single.id, '0043');
    expect((await bd.vistosRecientes()).single.id, '0043');
    expect((await bd.ultimaMedida('peso'))!.valor, 78.4);
    expect((await bd.buscarCatalogo(target: 'glutes')), hasLength(1));

    await bd.close();
  });

  test('v6 → última: la progresión por ejercicio entra vacía', () async {
    final esquema = await verificador.schemaAt(6);

    final vieja = v6.DatabaseAtV6(esquema.newConnection());
    await vieja.customStatement(
      "INSERT INTO rutinas (id, nombre, color) VALUES (1, 'Empuje', '#0A84FF')",
    );
    await vieja.customStatement(
      'INSERT INTO ejercicios (id, id_rutina, nombre, orden, descanso_seg) '
      "VALUES (1, 1, 'Press banca', 0, 120)",
    );
    await vieja.close();

    final bd = AppBD(esquema.newConnection());
    await verificador.migrateAndValidate(bd, bd.schemaVersion);

    // Las cuatro columnas nuevas quedan a null, que significa «como el global»:
    // es el comportamiento correcto para todo lo ya creado.
    final ejercicio = (await bd.ejerciciosDeRutina(1)).single.ejercicio;
    expect(ejercicio.descansoSeg, 120);
    expect(ejercicio.repMin, isNull);
    expect(ejercicio.repMax, isNull);
    expect(ejercicio.incrementoKg, isNull);
    expect(ejercicio.estrategia, isNull);

    // Y se pueden escribir una a una sin tocar las demás.
    await bd.fijarProgresionEjercicio(1, repMin: const Value(5));
    await bd.fijarProgresionEjercicio(1, incrementoKg: const Value(1.25));

    final configurado = (await bd.ejerciciosDeRutina(1)).single.ejercicio;
    expect(configurado.repMin, 5);
    expect(configurado.incrementoKg, 1.25);
    expect(configurado.repMax, isNull);

    await bd.close();
  });

  test('v7 → última: todo lo que se sincroniza sale con identidad', () async {
    final esquema = await verificador.schemaAt(7);

    final vieja = v7.DatabaseAtV7(esquema.newConnection());
    await vieja.customStatement(
      "INSERT INTO rutinas (id, nombre, color) VALUES (1, 'Empuje', '#0A84FF'), "
      "(2, 'Tirón', '#30D158')",
    );
    await vieja.customStatement(
      'INSERT INTO ejercicios (id, id_rutina, nombre, orden) '
      "VALUES (1, 1, 'Press banca', 0), (2, 2, 'Dominadas', 0)",
    );
    await vieja.customStatement(
      'INSERT INTO entrenamientos (id, id_rutina, fecha) '
      'VALUES (1, 1, ${_epoca(DateTime(2026, 3, 1))}), '
      '(2, 1, ${_epoca(DateTime(2026, 3, 8))})',
    );
    await vieja.customStatement(
      'INSERT INTO serie (id_entrenamiento, id_ejercicio, n_serie, repeticiones, peso) '
      'VALUES (1, 1, 1, 10, 60.0), (2, 1, 1, 8, 65.0)',
    );
    await vieja.customStatement(
      'INSERT INTO medidas (fecha, tipo, valor) '
      "VALUES (${_epoca(DateTime(2026, 3, 1))}, 'peso', 80.0)",
    );
    await vieja.customStatement(
      "INSERT INTO favoritos (id_catalogo, creado) VALUES ('0001', "
      '${_epoca(DateTime(2026, 3, 1))})',
    );
    await vieja.customStatement(
      "INSERT INTO ajustes (clave, valor) VALUES ('unidad', 'lb')",
    );
    await vieja.close();

    final bd = AppBD(esquema.newConnection());
    await verificador.migrateAndValidate(bd, bd.schemaVersion);

    // Cada fila con identidad tiene la suya, y no la comparte con nadie.
    final rutinas = await bd.todasLasRutinas();
    final uuids = {
      for (final r in rutinas) r.uuid,
      for (final e in await bd.ejerciciosDesde(-1)) e.uuid,
      for (final t in await bd.entrenamientosDesde(-1)) t.uuid,
    };
    expect(uuids, hasLength(6));
    expect(uuids, everyElement(hasLength(36)));

    // Y todo lo que se sincroniza queda sellado y, por tanto, pendiente de
    // subir: son datos que este móvil tiene y la cuenta todavía no.
    final motor = MotorSincro(bd, SincroFalso());
    final pendientes = await motor.pendientes(0);
    expect(pendientes.map((f) => f.tabla).toSet(), {
      'rutinas',
      'ejercicios',
      'entrenamientos',
      'medidas',
      'favoritos',
      'ajustes',
    });
    expect(pendientes, hasLength(9));
    for (final f in pendientes) {
      expect(f.actualizado, greaterThan(0), reason: '${f.id} sin sellar');
    }

    // Las series no se tocan —viajan dentro de su sesión— y siguen ahí.
    final sesion = pendientes.firstWhere((f) => f.tabla == 'entrenamientos');
    expect(sesion.datos!['series'], hasLength(1));

    // La contabilidad de la sincronización empieza en blanco.
    expect((await bd.estadoSincro()).cursorSubida, 0);
    expect(await bd.lapidasDesde(-1), isEmpty);

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

    test('respalda también antes de la v8, con su propio nombre', () async {
      await crearBase(7);

      await respaldarSiHaceFalta(fichero);

      final copia = File('${directorio.path}/appgym.bak-v7.sqlite');
      expect(copia.existsSync(), isTrue);
      expect(await versionDeEsquema(copia), 7);
    });

    test('no rehace la copia ni respalda una base ya migrada', () async {
      await crearBase(1);
      await respaldarSiHaceFalta(fichero);

      final copia = File('${directorio.path}/appgym.bak-v1.sqlite');
      final marca = copia.lastModifiedSync();

      // Segundo arranque con la misma versión: la copia buena no se toca.
      await respaldarSiHaceFalta(fichero);
      expect(copia.lastModifiedSync(), marca);
      expect(await versionDeEsquema(copia), 1);

      // Y una base ya en la última versión no tiene por delante ninguna
      // migración de las que transforman datos, así que no se respalda.
      await fichero.delete();
      await crearBase(8);
      await respaldarSiHaceFalta(fichero);

      expect(
        File('${directorio.path}/appgym.bak-v8.sqlite').existsSync(),
        isFalse,
      );
    });

    test('con la base sin crear no hay nada que respaldar', () async {
      await respaldarSiHaceFalta(fichero);
      expect(directorio.listSync(), isEmpty);
    });
  });

  // ── I2: las claves persistidas no se traducen ────────────────────────────────

  /// El riesgo caro del bloque de internacionalización: traducir por error una
  /// clave que está escrita en la base de todos los móviles instalados y en
  /// todas las copias exportadas. Estas dos listas son contratos, no textos.
  group('claves que nunca cambian de valor', () {
    test('los tipos de medida siguen siendo los mismos', () {
      expect(tiposMedida.map((t) => t.$1), [
        'peso',
        'grasa',
        'cintura',
        'pecho',
        'brazo',
        'muslo',
      ]);
    });

    test('una base de la v7 conserva sus medidas y sus ajustes', () async {
      final esquema = await verificador.schemaAt(7);

      final vieja = v7.DatabaseAtV7(esquema.newConnection());
      // La fecha va como segundos desde la época, que es como la guarda drift.
      await vieja.customStatement(
        'INSERT INTO medidas (id, fecha, tipo, valor) '
        "VALUES (1, ?, 'peso', 78.4)",
        [DateTime(2026, 8, 1).millisecondsSinceEpoch ~/ 1000],
      );
      await vieja.customStatement(
        "INSERT INTO ajustes (clave, valor) VALUES ('unidad', 'lb')",
      );
      await vieja.close();

      final bd = AppBD(esquema.newConnection());
      await verificador.migrateAndValidate(bd, bd.schemaVersion);

      // Si «peso» se hubiera traducido, la medida existiría pero nadie la
      // encontraría: el histórico se perdería en silencio.
      expect((await bd.ultimaMedida('peso'))!.valor, 78.4);
      expect((await bd.ajustes()).unidad, Unidad.lb);
      expect((await bd.ajustesCrudos()).keys, contains('unidad'));

      await bd.close();
    });
  });
}
