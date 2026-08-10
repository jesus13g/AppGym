/// El primer enlace (K7), en sus cuatro casos.
///
/// Es el momento más peligroso del bloque: un usuario con dos años de histórico
/// entra por primera vez en una cuenta que puede tener datos o no tenerlos. Los
/// tres casos automáticos no preguntan nada; el cuarto pregunta siempre, y la
/// salida que puede destruir el histórico exporta una copia antes.
library;

import 'package:appgym/datos/bd.dart';
import 'package:appgym/datos/identidad.dart';
import 'package:appgym/datos/sincro/enlace.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sincro_falso.dart';

ValoresSerie _serie(int repeticiones, double peso) =>
    ValoresSerie(repeticiones: repeticiones, peso: peso);

void main() {
  late SincroFalso servidor;
  late AppBD bd;
  late Enlace enlace;

  setUpAll(() {
    // Dos móviles son dos bases, y drift avisa de que se ha creado la clase
    // más de una vez. Aquí es a propósito: cada una tiene su ejecutor en
    // memoria y no comparten nada.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() {
    reiniciarSellos();
    servidor = SincroFalso();
    bd = AppBD(NativeDatabase.memory());
    enlace = Enlace(bd, servidor);
  });

  tearDown(() => bd.close());

  /// Una rutina con un ejercicio y [sesiones] sesiones, en [base].
  Future<void> sembrar(
    AppBD base,
    String rutina, {
    int sesiones = 1,
    double peso = 60,
  }) async {
    final idRutina = (await base.insertarRutina(rutina))!;
    await base.insertarEjercicio(idRutina, 'Press banca');
    final ejercicio = (await base.ejerciciosDeRutina(idRutina)).single.id;
    for (var i = 0; i < sesiones; i++) {
      await base.insertarEntrenamiento(idRutina, DateTime(2026, 3, i + 1), {
        ejercicio: [_serie(10, peso)],
      });
    }
  }

  /// Deja la cuenta con datos, subidos desde otro móvil.
  Future<void> sembrarCuenta(String rutina, {int sesiones = 1}) async {
    final otro = AppBD(NativeDatabase.memory());
    await sembrar(otro, rutina, sesiones: sesiones, peso: 80);
    await Enlace(otro, servidor).enlazar();
    await otro.close();
  }

  group('los tres casos automáticos', () {
    test('vacío y vacío: se enlaza sin preguntar', () async {
      final resultado = await enlace.enlazar();

      expect(resultado.estrategia, EstrategiaEnlace.fusionar);
      expect(resultado.sincro.algoCambio, isFalse);
      expect(await bd.todasLasRutinas(), isEmpty);
    });

    test('con datos y la cuenta vacía: se sube todo', () async {
      await sembrar(bd, 'Empuje', sesiones: 3);

      final resultado = await enlace.enlazar();

      expect(
        resultado.sincro.subidas,
        5,
        reason: 'rutina, ejercicio y 3 sesiones',
      );
      expect(servidor.deTabla('entrenamientos'), hasLength(3));
      expect(await bd.contarEntrenamientos(), 3, reason: 'lo local no se toca');
    });

    test('vacío y la cuenta con datos: se baja todo', () async {
      await sembrarCuenta('Tirón', sesiones: 2);

      final resultado = await enlace.enlazar();

      expect(resultado.sincro.bajadas, 4);
      expect((await bd.todasLasRutinas()).single.nombre, 'Tirón');
      expect(await bd.contarEntrenamientos(), 2);
    });

    test('ninguno de los tres pide decidir', () async {
      await sembrar(bd, 'Empuje');
      expect((await enlace.examinar()).hayQueDecidir, isFalse);
    });
  });

  group('con datos a los dos lados', () {
    setUp(() async {
      await sembrar(bd, 'Empuje', sesiones: 3);
      await sembrarCuenta('Tirón', sesiones: 2);
    });

    test('las cifras salen antes de preguntar', () async {
      final lados = await enlace.examinar();

      expect(lados.hayQueDecidir, isTrue);
      expect(lados.local.rutinas, 1);
      expect(lados.local.sesiones, 3);
      expect(lados.remoto.rutinas, 1);
      expect(lados.remoto.sesiones, 2);
    });

    test('sin elegir no se enlaza: se pide la decisión', () async {
      await expectLater(enlace.enlazar(), throwsA(isA<DecisionPendiente>()));
      // Y no se ha tocado nada mientras tanto.
      expect(await bd.contarEntrenamientos(), 3);
      expect(servidor.deTabla('entrenamientos'), hasLength(2));
    });

    test('fusionar deja las cinco sesiones, sin duplicar ni mezclar', () async {
      final resultado = await enlace.enlazar(
        estrategia: EstrategiaEnlace.fusionar,
      );

      expect(resultado.estrategia, EstrategiaEnlace.fusionar);
      expect(await bd.contarEntrenamientos(), 5);
      expect((await bd.todasLasRutinas()).map((r) => r.nombre).toSet(), {
        'Empuje',
        'Tirón',
      });
      expect(servidor.deTabla('entrenamientos'), hasLength(5));

      // Y volver a enlazar no vuelve a sumarlas.
      await enlace.enlazar(estrategia: EstrategiaEnlace.fusionar);
      expect(await bd.contarEntrenamientos(), 5);
    });

    test('este dispositivo manda: la cuenta se sustituye', () async {
      final resultado = await enlace.enlazar(
        estrategia: EstrategiaEnlace.esteDispositivo,
      );

      expect(resultado.estrategia, EstrategiaEnlace.esteDispositivo);
      expect(servidor.vaciados, 1);
      expect(await bd.contarEntrenamientos(), 3, reason: 'lo local, intacto');
      expect(servidor.deTabla('entrenamientos'), hasLength(3));
      expect(
        servidor.deTabla('rutinas').single.datos!['nombre'],
        'Empuje',
        reason: 'lo que había en la cuenta ya no está',
      );
    });

    test('la cuenta manda: se exporta una copia antes de tocar nada', () async {
      var copias = 0;
      var sesionesAlCopiar = -1;

      final resultado = await enlace.enlazar(
        estrategia: EstrategiaEnlace.laCuenta,
        respaldoPrevio: () async {
          copias++;
          // La copia se hace **antes** de borrar: si no, no serviría de nada.
          sesionesAlCopiar = await bd.contarEntrenamientos();
        },
      );

      expect(resultado.estrategia, EstrategiaEnlace.laCuenta);
      expect(copias, 1);
      expect(sesionesAlCopiar, 3);
      expect(await bd.contarEntrenamientos(), 2);
      expect((await bd.todasLasRutinas()).single.nombre, 'Tirón');
    });

    test('la cuenta manda sin copia previa no se ejecuta', () async {
      await expectLater(
        enlace.enlazar(estrategia: EstrategiaEnlace.laCuenta),
        throwsA(isA<StateError>()),
      );
      expect(await bd.contarEntrenamientos(), 3);
    });

    test('la cuenta manda no se lleva por delante los datos remotos', () async {
      await enlace.enlazar(
        estrategia: EstrategiaEnlace.laCuenta,
        respaldoPrevio: () async {},
      );

      // El borrado local no deja lápidas, así que la cuenta —el lado que el
      // usuario dijo que manda— sigue entera.
      expect(servidor.deTabla('entrenamientos'), hasLength(2));
      expect(servidor.deTabla('rutinas'), hasLength(1));
    });
  });
}
