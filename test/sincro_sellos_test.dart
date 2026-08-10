/// Que ninguna escritura se quede sin sellar, y que ningún borrado se quede sin
/// lápida.
///
/// Es el contrapeso de una decisión: `actualizado` lleva un `DEFAULT 0` en SQL
/// —sin él la migración a la v8 no se puede escribir sobre bases que ya
/// existen—, y drift no deja combinar eso con un `clientDefault` que sellara
/// solo. Así que el sello se pone a mano en cada escritura, y esto es lo que
/// impide que una se olvide: una fila sin sellar no se subiría **nunca**, y el
/// fallo no se vería hasta que al usuario le faltaran datos en el otro móvil.
///
/// La forma de cada caso es la misma: se da todo por sincronizado, se hace una
/// escritura y se comprueba que ha dejado algo pendiente.
library;

import 'package:appgym/datos/bd.dart';
import 'package:appgym/datos/ajustes.dart' show Claves;
import 'package:appgym/datos/identidad.dart';
import 'package:appgym/datos/sincro/motor.dart';
import 'package:appgym/datos/sincro/transporte.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sincro_falso.dart';

void main() {
  late AppBD bd;
  late MotorSincro motor;

  setUp(() {
    reiniciarSellos();
    bd = AppBD(NativeDatabase.memory());
    motor = MotorSincro(bd, SincroFalso());
  });

  tearDown(() => bd.close());

  /// Da por subido todo lo que hay ahora mismo.
  Future<int> alDia() async {
    final cursor = await bd.mayorSello();
    await bd.fijarEstadoSincro(cursorSubida: Value(cursor));
    expect(await motor.pendientes(cursor), isEmpty);
    return cursor;
  }

  /// Lo que ha quedado pendiente tras [escribir], por tabla.
  Future<List<FilaRemota>> traer(Future<void> Function() escribir) async {
    final cursor = await alDia();
    await escribir();
    return motor.pendientes(cursor);
  }

  /// Un montaje mínimo: una rutina, un ejercicio y una sesión.
  Future<(int, int, int)> montar() async {
    final rutina = (await bd.insertarRutina('Empuje'))!;
    await bd.insertarEjercicio(rutina, 'Press banca');
    final ejercicio = (await bd.ejerciciosDeRutina(rutina)).single.id;
    final sesion = (await bd.insertarEntrenamiento(
      rutina,
      DateTime(2026, 3, 1),
      {
        ejercicio: [const ValoresSerie(repeticiones: 10, peso: 60)],
      },
    ))!;
    return (rutina, ejercicio, sesion);
  }

  Matcher fila(TablaSincro tabla) => predicate<FilaRemota>(
    (f) => f.tabla == tabla.name && !f.borrada,
    'una fila de ${tabla.name}',
  );

  Matcher lapida(TablaSincro tabla) => predicate<FilaRemota>(
    (f) => f.tabla == tabla.name && f.borrada,
    'una lápida de ${tabla.name}',
  );

  group('crear deja identidad y sello', () {
    test('todo lo que se crea sale con su uuid y su sello', () async {
      final (rutina, ejercicio, sesion) = await montar();
      await bd.registrarMedida(DateTime(2026, 3, 1), 'peso', 80);
      await bd.marcarFavorito('0001', true);
      await bd.fijarAjuste(Claves.unidad, 'lb');

      expect((await bd.rutina(rutina))!.uuid, isNotEmpty);
      expect((await bd.ejercicioPorId(ejercicio))!.uuid, isNotEmpty);
      final entrenamiento = (await bd.entrenamientosDeRutina(rutina)).single;
      expect(entrenamiento.id, sesion);
      expect(entrenamiento.uuid, isNotEmpty);

      for (final f in await motor.pendientes(0)) {
        expect(f.actualizado, greaterThan(0), reason: '${f.id} sin sellar');
      }
      expect(await motor.pendientes(0), hasLength(6));
    });

    test('dos rutinas nunca comparten identidad', () async {
      await bd.insertarRutina('Empuje');
      await bd.insertarRutina('Tirón');
      final uuids = (await bd.todasLasRutinas()).map((r) => r.uuid).toSet();
      expect(uuids, hasLength(2));
    });

    test('crear una rutina con ejercicios sella las dos filas', () async {
      final pendientes = await traer(
        () => bd
            .crearRutinaConEjercicios('Pierna', [
              (null, 'Sentadilla'),
              (null, 'Prensa'),
            ])
            .then((_) {}),
      );
      expect(pendientes.where((f) => f.tabla == 'rutinas'), hasLength(1));
      expect(pendientes.where((f) => f.tabla == 'ejercicios'), hasLength(2));
    });

    test('duplicar una rutina sella la copia entera', () async {
      final (rutina, _, _) = await montar();
      final pendientes = await traer(
        () => bd.duplicarRutina(rutina).then((_) {}),
      );
      expect(pendientes.where((f) => f.tabla == 'rutinas'), hasLength(1));
      expect(pendientes.where((f) => f.tabla == 'ejercicios'), hasLength(1));
    });
  });

  group('cada escritura deja su fila pendiente', () {
    test('renombrar una rutina', () async {
      final (rutina, _, _) = await montar();
      expect(
        await traer(() => bd.renombrarRutina(rutina, 'Torso').then((_) {})),
        [fila(TablaSincro.rutinas)],
      );
    });

    test('reordenar los ejercicios', () async {
      final rutina = (await bd.insertarRutina('Empuje'))!;
      await bd.insertarEjercicio(rutina, 'Press banca');
      await bd.insertarEjercicio(rutina, 'Fondos');
      final ids = (await bd.ejerciciosDeRutina(
        rutina,
      )).map((e) => e.id).toList();

      final pendientes = await traer(
        () => bd.reordenarEjercicios(rutina, ids.reversed.toList()),
      );
      expect(pendientes, hasLength(2));
      expect(pendientes, everyElement(fila(TablaSincro.ejercicios)));
    });

    test('mover un ejercicio de rutina', () async {
      final (_, ejercicio, _) = await montar();
      final destino = (await bd.insertarRutina('Tirón'))!;
      expect(
        await traer(() => bd.moverEjercicio(ejercicio, destino).then((_) {})),
        [fila(TablaSincro.ejercicios)],
      );
    });

    test('fijar el descanso de un ejercicio', () async {
      final (_, ejercicio, _) = await montar();
      expect(await traer(() => bd.fijarDescansoEjercicio(ejercicio, 120)), [
        fila(TablaSincro.ejercicios),
      ]);
    });

    test('fijar la progresión de un ejercicio', () async {
      final (_, ejercicio, _) = await montar();
      expect(
        await traer(
          () => bd.fijarProgresionEjercicio(
            ejercicio,
            repMin: const Value(5),
            repMax: const Value(8),
          ),
        ),
        [fila(TablaSincro.ejercicios)],
      );
    });

    test('editar una sesión sella la sesión, no la serie', () async {
      final (_, ejercicio, sesion) = await montar();
      final pendientes = await traer(
        () => bd
            .actualizarEntrenamiento(sesion, DateTime(2026, 3, 2), {
              ejercicio: [const ValoresSerie(repeticiones: 12, peso: 62.5)],
            })
            .then((_) {}),
      );

      expect(pendientes, [fila(TablaSincro.entrenamientos)]);
      // Y la serie nueva viaja dentro de la sesión, que es lo que hace del
      // bloque una unidad.
      final series = pendientes.single.datos!['series'] as List;
      expect(series.single, containsPair('repeticiones', 12));
    });

    test('registrar una medida', () async {
      expect(
        await traer(() => bd.registrarMedida(DateTime(2026, 3, 4), 'peso', 79)),
        [fila(TablaSincro.medidas)],
      );
    });

    test('marcar un favorito', () async {
      expect(await traer(() => bd.marcarFavorito('0002', true)), [
        fila(TablaSincro.favoritos),
      ]);
    });

    test('cambiar una preferencia', () async {
      expect(await traer(() => bd.fijarAjuste(Claves.tema, 'oscuro')), [
        fila(TablaSincro.ajustes),
      ]);
    });

    test('cambiar varias preferencias de golpe', () async {
      final pendientes = await traer(
        () => bd.fijarAjustes({Claves.tema: 'oscuro', Claves.unidad: 'lb'}),
      );
      expect(pendientes, hasLength(2));
      expect(pendientes, everyElement(fila(TablaSincro.ajustes)));
    });

    test('lo que no se sincroniza no ensucia el delta', () async {
      final (rutina, _, _) = await montar();
      final pendientes = await traer(() async {
        await bd.registrarVisto('0001');
        await bd.guardarSesionActiva(rutina, DateTime(2026, 3, 5), '{}');
        await bd.fijarAjuste(Claves.copiaNubeUltima, '2026-03-05');
      });
      expect(pendientes, isEmpty);
    });
  });

  group('cada borrado deja su lápida', () {
    test('borrar una rutina', () async {
      final (rutina, _, _) = await montar();
      expect(
        await traer(() => bd.borrarRutina(rutina)),
        [lapida(TablaSincro.rutinas)],
        reason: 'los hijos se van con el padre por el cascade, aquí y allí',
      );
    });

    test('borrar un ejercicio', () async {
      final (rutina, ejercicio, _) = await montar();
      expect(await traer(() => bd.borrarEjercicio(rutina, ejercicio)), [
        lapida(TablaSincro.ejercicios),
      ]);
    });

    test('borrar una sesión', () async {
      final (_, _, sesion) = await montar();
      expect(await traer(() => bd.borrarEntrenamiento(sesion)), [
        lapida(TablaSincro.entrenamientos),
      ]);
    });

    test('borrar una medida', () async {
      await bd.registrarMedida(DateTime(2026, 3, 1), 'peso', 80);
      expect(await traer(() => bd.borrarMedida(DateTime(2026, 3, 1), 'peso')), [
        lapida(TablaSincro.medidas),
      ]);
    });

    test('quitar un favorito', () async {
      await bd.marcarFavorito('0001', true);
      expect(await traer(() => bd.marcarFavorito('0001', false)), [
        lapida(TablaSincro.favoritos),
      ]);
    });

    test('volver a marcar un favorito quita su lápida', () async {
      await bd.marcarFavorito('0001', true);
      await bd.marcarFavorito('0001', false);
      await bd.marcarFavorito('0001', true);

      final pendientes = await motor.pendientes(0);
      expect(pendientes, [fila(TablaSincro.favoritos)]);
    });

    test('volver a registrar una medida borrada quita su lápida', () async {
      await bd.registrarMedida(DateTime(2026, 3, 1), 'peso', 80);
      await bd.borrarMedida(DateTime(2026, 3, 1), 'peso');
      await bd.registrarMedida(DateTime(2026, 3, 1), 'peso', 81);

      expect(await motor.pendientes(0), [fila(TablaSincro.medidas)]);
    });

    test('borrar todos los datos entierra a los padres', () async {
      await montar();
      await bd.registrarMedida(DateTime(2026, 3, 1), 'peso', 80);
      await bd.marcarFavorito('0001', true);
      await bd.fijarAjuste(Claves.tema, 'oscuro');

      final pendientes = await traer(() => bd.borrarTodosLosDatos());

      expect(pendientes, hasLength(4));
      expect(pendientes, everyElement(predicate<FilaRemota>((f) => f.borrada)));
      expect(pendientes.map((f) => f.tabla).toSet(), {
        'rutinas',
        'medidas',
        'favoritos',
        'ajustes',
      });
    });

    test('borrar todos los datos sin lápidas no propaga nada', () async {
      await montar();
      expect(
        await traer(() => bd.borrarTodosLosDatos(conLapidas: false)),
        isEmpty,
      );
    });
  });

  test('importar una copia sella todo lo que entra', () async {
    // Las filas restauradas son datos nuevos de este móvil: tienen que subir.
    final cursor = await alDia();
    final rutina = await bd.restaurarRutina('Importada', '#0A84FF');
    await bd.restaurarEjercicio(rutina, nombre: 'Press banca', orden: 0);
    final ejercicio = (await bd.ejerciciosDeRutina(rutina)).single.id;
    final sesion = await bd.restaurarEntrenamiento(
      rutina,
      DateTime(2026, 2, 1),
    );
    await bd.restaurarSeries(sesion, {
      ejercicio: [const ValoresSerie(repeticiones: 10, peso: 60)],
    });

    final pendientes = await motor.pendientes(cursor);
    expect(pendientes, hasLength(3));
    expect(pendientes.map((f) => f.tabla).toSet(), {
      'rutinas',
      'ejercicios',
      'entrenamientos',
    });
    for (final f in pendientes) {
      expect(f.actualizado, greaterThan(cursor));
    }
  });
}
