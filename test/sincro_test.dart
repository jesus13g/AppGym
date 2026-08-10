/// Los escenarios de K10, con dos móviles y un servidor de mentira.
///
/// Dos `AppBD` en `NativeDatabase.memory()` y un [SincroFalso] en medio. **Sin
/// red, sin cuenta y sin proveedor**: es la condición de entrega del bloque, y
/// lo que permite que la parte difícil esté probada antes de que exista el
/// adaptador de nadie.
library;

import 'package:appgym/datos/ajustes.dart';
import 'package:appgym/datos/bd.dart';
import 'package:appgym/datos/identidad.dart';
import 'package:appgym/datos/reloj.dart';
import 'package:appgym/datos/sincro/motor.dart';
import 'package:appgym/datos/sincro/transporte.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sincro_falso.dart';

/// Un móvil: su base, su motor y su cursor propio contra el mismo servidor.
class Movil {
  Movil(this.nombre, SincroFalso servidor)
    : bd = AppBD(NativeDatabase.memory()) {
    motor = MotorSincro(bd, servidor);
  }

  final String nombre;
  final AppBD bd;
  late final MotorSincro motor;

  Future<ResultadoSincro> sincronizar() => motor.sincronizar();

  Future<void> cerrar() => bd.close();

  /// Una rutina con un ejercicio, que es el mínimo para poder entrenar.
  Future<(int, int)> rutinaConEjercicio(
    String rutina, [
    String ejercicio = 'Press banca',
  ]) async {
    final idRutina = (await bd.insertarRutina(rutina))!;
    await bd.insertarEjercicio(idRutina, ejercicio);
    final ejercicios = await bd.ejerciciosDeRutina(idRutina);
    return (idRutina, ejercicios.single.id);
  }

  Future<int> entrenar(
    int idRutina,
    int idEjercicio,
    DateTime fecha,
    List<ValoresSerie> series,
  ) async =>
      (await bd.insertarEntrenamiento(idRutina, fecha, {idEjercicio: series}))!;

  /// Lo que se compara para decir que dos móviles han convergido.
  Future<List<num>> resumen() async {
    final rutinas = await bd.todasLasRutinas();
    var sesiones = 0;
    var series = 0;
    var volumen = 0.0;
    for (final r in rutinas) {
      for (final s in await bd.entrenamientosDeRutina(r.id)) {
        sesiones++;
        for (final serie in await bd.seriesDeEntrenamiento(s.id)) {
          series++;
          volumen += serie.peso * serie.repeticiones;
        }
      }
    }
    return [rutinas.length, sesiones, series, volumen];
  }
}

ValoresSerie serie(int repeticiones, double peso) =>
    ValoresSerie(repeticiones: repeticiones, peso: peso);

void main() {
  late SincroFalso servidor;
  late Movil a;
  late Movil b;

  setUpAll(() {
    // Dos móviles son dos bases, y drift avisa de que se ha creado la clase
    // más de una vez. Aquí es a propósito: cada una tiene su ejecutor en
    // memoria y no comparten nada.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() {
    // El contador de sellos es global —lo tiene que ser, porque lo usa la
    // definición de las tablas—, así que cada test empieza con él a cero.
    reiniciarSellos();
    servidor = SincroFalso();
    a = Movil('A', servidor);
    b = Movil('B', servidor);
  });

  tearDown(() async {
    fijarReloj(null);
    await a.cerrar();
    await b.cerrar();
  });

  // ── 1. Lo que uno crea, el otro lo ve ──────────────────────────────────────

  group('propagación', () {
    test('A crea, sincroniza, B sincroniza y lo ve', () async {
      final (rutina, ejercicio) = await a.rutinaConEjercicio('Empuje');
      await a.entrenar(rutina, ejercicio, DateTime(2026, 3, 1), [
        serie(10, 60),
        serie(8, 65),
      ]);

      final subida = await a.sincronizar();
      expect(subida.subidas, 3, reason: 'rutina, ejercicio y sesión');
      expect(subida.bajadas, 0);

      final bajada = await b.sincronizar();
      expect(bajada.bajadas, 3);

      expect(await b.resumen(), await a.resumen());
      final deB = (await b.bd.todasLasRutinas()).single;
      expect(deB.nombre, 'Empuje');
      // La identidad viaja; la clave primaria no. En B puede ser otro entero.
      expect(deB.uuid, (await a.bd.todasLasRutinas()).single.uuid);
    });

    test('las medidas, los favoritos y los ajustes también viajan', () async {
      await a.bd.registrarMedida(DateTime(2026, 3, 1), 'peso', 81.5);
      await a.bd.marcarFavorito('0001', true);
      await a.bd.fijarAjuste(Claves.unidad, 'lb');
      await a.sincronizar();

      await b.sincronizar();

      expect((await b.bd.ultimaMedida('peso'))!.valor, 81.5);
      expect(await b.bd.favoritoPorId('0001'), isNotNull);
      expect((await b.bd.ajustesCrudos())[Claves.unidad], 'lb');
    });

    test('las claves de dispositivo no salen de su móvil', () async {
      await a.bd.fijarAjuste(Claves.copiaNubeCuenta, 'yo@ejemplo.com');
      await a.bd.fijarAjuste(Claves.unidad, 'lb');

      await a.sincronizar();

      expect(
        servidor.deTabla('ajustes').map((f) => f.clave),
        [Claves.unidad],
        reason: 'la cuenta conectada de este móvil no es una preferencia',
      );
    });

    test('lo bajado no se vuelve a subir', () async {
      final (rutina, ejercicio) = await a.rutinaConEjercicio('Empuje');
      await a.entrenar(rutina, ejercicio, DateTime(2026, 3, 1), [
        serie(10, 60),
      ]);
      await a.sincronizar();

      // B baja tres filas. No son suyas: llevan el sello del servidor y no
      // están pendientes de nada.
      expect((await b.sincronizar()).bajadas, 3);
      expect(
        await b.motor.pendientes((await b.bd.estadoSincro()).cursorSubida),
        isEmpty,
      );

      // Y si no lo estuvieran, los dos móviles se devolverían las mismas filas
      // sin parar. Cuatro pasadas más y el servidor no recibe ni una subida.
      final subidasAntes = servidor.subidas;
      for (var i = 0; i < 4; i++) {
        expect((await b.sincronizar()).algoCambio, isFalse);
        expect((await a.sincronizar()).algoCambio, isFalse);
      }
      expect(servidor.subidas, subidasAntes);
    });

    test('un cambio hecho mientras se baja no se pierde', () async {
      final (rutina, _) = await a.rutinaConEjercicio('Empuje');
      await a.sincronizar();
      await b.sincronizar();

      // A cambia algo y, antes de que le dé tiempo a subirlo, B escribe en la
      // cuenta y adelanta el reloj del servidor por delante del sello de A.
      await a.bd.renombrarRutina(rutina, 'Torso');
      await b.bd.insertarRutina('Pierna');
      await b.sincronizar();

      await a.sincronizar();

      expect(
        (await a.bd.rutinaPorUuid((await a.bd.rutina(rutina))!.uuid))!.nombre,
        'Torso',
      );
      expect(
        servidor.deTabla('rutinas').map((f) => f.datos!['nombre']).toSet(),
        {'Torso', 'Pierna'},
      );
    });

    test('sincronizar dos veces seguidas no duplica nada', () async {
      final (rutina, ejercicio) = await a.rutinaConEjercicio('Empuje');
      await a.entrenar(rutina, ejercicio, DateTime(2026, 3, 1), [
        serie(10, 60),
      ]);
      await a.sincronizar();
      await b.sincronizar();

      await b.sincronizar();
      await a.sincronizar();

      expect(await a.resumen(), [1, 1, 1, 600]);
      expect(await b.resumen(), [1, 1, 1, 600]);
    });
  });

  // ── 2. Conflictos ──────────────────────────────────────────────────────────

  group('conflictos', () {
    /// Deja a los dos móviles con la misma rutina ya sincronizada.
    Future<String> mismaRutina() async {
      await a.rutinaConEjercicio('Empuje');
      await a.sincronizar();
      await b.sincronizar();
      return (await a.bd.todasLasRutinas()).single.uuid;
    }

    test(
      'A y B editan lo mismo sin conexión: gana quien sincroniza después',
      () async {
        final uuid = await mismaRutina();

        await a.bd.renombrarRutina(
          (await a.bd.rutinaPorUuid(uuid))!.id,
          'Torso',
        );
        await b.bd.renombrarRutina(
          (await b.bd.rutinaPorUuid(uuid))!.id,
          'Pecho',
        );

        await a.sincronizar();
        await b.sincronizar();

        // B llegó el último, así que la cuenta se queda con lo suyo, entero.
        expect(servidor.deTabla('rutinas').single.datos!['nombre'], 'Pecho');
        expect((await b.bd.rutinaPorUuid(uuid))!.nombre, 'Pecho');

        // Y A lo recoge en su siguiente pasada.
        await a.sincronizar();
        expect((await a.bd.rutinaPorUuid(uuid))!.nombre, 'Pecho');
      },
    );

    test('lo cambiado aquí y todavía sin subir gana a lo que baja', () async {
      final uuid = await mismaRutina();

      // B cambia y sube; A cambia y todavía no ha subido.
      await b.bd.renombrarRutina((await b.bd.rutinaPorUuid(uuid))!.id, 'Pecho');
      await b.sincronizar();
      await a.bd.renombrarRutina((await a.bd.rutinaPorUuid(uuid))!.id, 'Torso');

      await a.sincronizar();

      // A conserva lo suyo y lo sube en la misma pasada, así que la cuenta
      // acaba con la versión de A y los dos móviles convergen ahí.
      expect((await a.bd.rutinaPorUuid(uuid))!.nombre, 'Torso');
      expect(servidor.deTabla('rutinas').single.datos!['nombre'], 'Torso');
      await b.sincronizar();
      expect((await b.bd.rutinaPorUuid(uuid))!.nombre, 'Torso');
    });

    test('A borra y B edita: la lápida se propaga', () async {
      final uuid = await mismaRutina();

      await a.bd.borrarRutina((await a.bd.rutinaPorUuid(uuid))!.id);
      await a.sincronizar();
      await b.sincronizar();

      expect(await b.bd.todasLasRutinas(), isEmpty);
      // Y el borrado no vuelve: bajar otra vez no la resucita.
      await b.sincronizar();
      await a.sincronizar();
      expect(await a.bd.todasLasRutinas(), isEmpty);
      expect(await b.bd.todasLasRutinas(), isEmpty);
    });

    test('lo borrado aquí y sin subir gana a lo que baja editado', () async {
      final uuid = await mismaRutina();

      await b.bd.renombrarRutina((await b.bd.rutinaPorUuid(uuid))!.id, 'Pecho');
      await b.sincronizar();
      await a.bd.borrarRutina((await a.bd.rutinaPorUuid(uuid))!.id);

      await a.sincronizar();

      expect(await a.bd.todasLasRutinas(), isEmpty);
      await b.sincronizar();
      expect(await b.bd.todasLasRutinas(), isEmpty);
    });

    test('una sesión editada en los dos no mezcla series', () async {
      final (rutina, ejercicio) = await a.rutinaConEjercicio('Empuje');
      final sesion = await a.entrenar(rutina, ejercicio, DateTime(2026, 3, 1), [
        serie(10, 60),
        serie(10, 60),
      ]);
      final uuid = (await a.bd.entrenamientosDeRutina(rutina)).single.uuid;
      await a.sincronizar();
      await b.sincronizar();

      // A añade una quinta serie; B corrige el peso de la segunda.
      await a.bd.actualizarEntrenamiento(sesion, DateTime(2026, 3, 1), {
        ejercicio: [serie(10, 60), serie(10, 60), serie(8, 62.5)],
      });
      final enB = (await b.bd.entrenamientoPorUuid(uuid))!;
      final ejercicioB = (await b.bd.ejerciciosDeRutina(
        enB.idRutina,
      )).single.id;
      await b.bd.actualizarEntrenamiento(enB.id, DateTime(2026, 3, 1), {
        ejercicioB: [serie(10, 60), serie(10, 80)],
      });

      await a.sincronizar();
      await b.sincronizar();
      await a.sincronizar();

      // Gana la de B entera: dos series, la segunda a 80. Nunca una mezcla de
      // tres series con el peso de la de B.
      for (final movil in [a, b]) {
        final sesiones = await movil.bd.entrenamientosDeRutina(
          (await movil.bd.todasLasRutinas()).single.id,
        );
        final series = await movil.bd.seriesDeEntrenamiento(sesiones.single.id);
        expect(
          series.map((s) => (s.repeticiones, s.peso)),
          [(10, 60.0), (10, 80.0)],
          reason: '${movil.nombre} tiene una versión completa, no una mezcla',
        );
      }
    });

    test('el choque de nombres renombra una y avisa', () async {
      // Los dos crean «Empuje» sin saber el uno del otro.
      await a.rutinaConEjercicio('Empuje');
      await b.rutinaConEjercicio('Empuje');

      await a.sincronizar();
      final resultado = await b.sincronizar();

      expect(
        resultado.avisos.map((av) => av.motivo),
        contains(MotivoAviso.rutinaRenombrada),
      );
      expect((await b.bd.todasLasRutinas()).map((r) => r.nombre).toSet(), {
        'Empuje',
        'Empuje (2)',
      });

      // Y los dos móviles acaban viendo lo mismo, no cada uno su versión.
      await a.sincronizar();
      await b.sincronizar();
      await a.sincronizar();
      expect(
        (await a.bd.todasLasRutinas()).map((r) => (r.uuid, r.nombre)).toSet(),
        (await b.bd.todasLasRutinas()).map((r) => (r.uuid, r.nombre)).toSet(),
      );
    });

    test(
      'la misma sesión registrada en los dos se queda por duplicado',
      () async {
        final (rutina, ejercicio) = await a.rutinaConEjercicio('Empuje');
        await a.sincronizar();
        await b.sincronizar();

        final enB = (await b.bd.todasLasRutinas()).single;
        final ejercicioB = (await b.bd.ejerciciosDeRutina(enB.id)).single.id;
        await a.entrenar(rutina, ejercicio, DateTime(2026, 3, 1), [
          serie(10, 60),
        ]);
        await b.entrenar(enB.id, ejercicioB, DateTime(2026, 3, 1), [
          serie(10, 60),
        ]);

        await a.sincronizar();
        await b.sincronizar();
        await a.sincronizar();

        // Dos `uuid` distintos son dos sesiones: no hay forma fiable de reconocer
        // un duplicado, exactamente lo que ya decía `copia.dart` al fusionar.
        expect(await a.resumen(), [1, 2, 2, 1200]);
        expect(await b.resumen(), [1, 2, 2, 1200]);
      },
    );
  });

  // ── 3. El reloj no decide ──────────────────────────────────────────────────

  test(
    'un móvil con el reloj adelantado dos años no gana los conflictos',
    () async {
      await a.rutinaConEjercicio('Empuje');
      await a.sincronizar();
      await b.sincronizar();
      final uuid = (await a.bd.todasLasRutinas()).single.uuid;

      // A vive en 2028. Sus sellos locales salen disparados.
      fijarReloj(() => DateTime(2028, 1, 1));
      await a.bd.renombrarRutina((await a.bd.rutinaPorUuid(uuid))!.id, 'Torso');
      expect(
        (await a.bd.rutinaPorUuid(uuid))!.actualizado,
        greaterThan(DateTime(2027).millisecondsSinceEpoch),
      );
      await a.sincronizar();

      // Al confirmar la subida, el sello inflado desaparece: manda el del
      // servidor. Es lo que impide que A gane todos los conflictos para siempre.
      expect(
        (await a.bd.rutinaPorUuid(uuid))!.actualizado,
        lessThan(DateTime(2027).millisecondsSinceEpoch),
      );

      // Y B, con la hora bien puesta, sigue pudiendo ganar el siguiente.
      fijarReloj(null);
      await b.sincronizar();
      await b.bd.renombrarRutina((await b.bd.rutinaPorUuid(uuid))!.id, 'Pecho');
      await b.sincronizar();
      await a.sincronizar();

      expect((await a.bd.rutinaPorUuid(uuid))!.nombre, 'Pecho');
    },
  );

  // ── 4. Fallos del transporte ───────────────────────────────────────────────

  group('cuando el transporte falla', () {
    test('un fallo al bajar no toca nada y no mueve el cursor', () async {
      await a.rutinaConEjercicio('Empuje');
      servidor.falloAlBajar = const ErrorSincro.temporal('sin cobertura');

      await expectLater(a.sincronizar(), throwsA(isA<ErrorSincro>()));

      final estado = await a.bd.estadoSincro();
      expect(estado.cursorBajada, 0);
      expect(estado.cursorSubida, 0);
      expect(estado.ultimoError, 'sin cobertura');
      expect(servidor.subidas, 0, reason: 'ni se llegó a intentar subir');
    });

    test('un fallo a mitad de subida deja lo pendiente pendiente', () async {
      final (rutina, ejercicio) = await a.rutinaConEjercicio('Empuje');
      await a.entrenar(rutina, ejercicio, DateTime(2026, 3, 1), [
        serie(10, 60),
      ]);

      // El servidor escribe y se cae antes de contestar: lo peor que puede
      // pasar, porque el cliente no sabe si llegó.
      servidor.caerTrasEscribir = true;
      await expectLater(a.sincronizar(), throwsA(isA<ErrorSincro>()));

      // La subida no se confirmó, así que las tres filas siguen pendientes.
      final estado = await a.bd.estadoSincro();
      expect(await a.motor.pendientes(estado.cursorSubida), hasLength(3));

      // Al reintentar, lo pendiente se vuelve a subir y no duplica nada: la
      // identidad de cada fila es la misma.
      final resultado = await a.sincronizar();
      expect(resultado.subidas, 3);
      expect(servidor.deTabla('rutinas'), hasLength(1));
      expect(servidor.deTabla('entrenamientos'), hasLength(1));

      await b.sincronizar();
      expect(await b.resumen(), await a.resumen());
    });

    test('un fallo permanente se anota y la app sigue funcionando', () async {
      servidor.falloAlSubir = const ErrorSincro.reconectar('sesión revocada');
      await a.rutinaConEjercicio('Empuje');

      await expectLater(a.sincronizar(), throwsA(isA<ErrorSincro>()));

      // La base local está intacta y se puede seguir usando.
      expect(await a.bd.todasLasRutinas(), hasLength(1));
      final (rutina, ejercicio) = await a.rutinaConEjercicio('Pierna');
      await a.entrenar(rutina, ejercicio, DateTime(2026, 3, 2), [
        serie(5, 100),
      ]);
      expect(await a.resumen(), [2, 1, 1, 500]);
    });
  });

  // ── 5. Cuarentena y huérfanos ──────────────────────────────────────────────

  group('orden de aplicación', () {
    test('un paquete al revés se aplica igual', () async {
      final (rutina, ejercicio) = await a.rutinaConEjercicio('Empuje');
      await a.entrenar(rutina, ejercicio, DateTime(2026, 3, 1), [
        serie(10, 60),
      ]);
      await a.sincronizar();

      // El servidor de prueba devuelve el paquete del más nuevo al más viejo, o
      // sea con la sesión antes que su rutina. Si el motor no lo ordenara, la
      // clave foránea reventaría aquí.
      final paquete = await servidor.bajar(0);
      expect(paquete.filas.first.tabla, 'entrenamientos');
      expect(paquete.filas.last.tabla, 'rutinas');

      await b.sincronizar();
      expect(await b.resumen(), [1, 1, 1, 600]);
    });

    test('un huérfano de verdad se descarta con su aviso', () async {
      await a.rutinaConEjercicio('Empuje');
      await a.sincronizar();

      // Alguien deja en la cuenta un ejercicio de una rutina que no existe: es
      // lo que queda si el padre se borró y su lápida ya se podó.
      servidor.filas['ejercicios/suelto'] = const FilaRemota(
        tabla: 'ejercicios',
        clave: 'suelto',
        actualizado: 2000000,
        datos: {'rutina': 'no-existe', 'nombre': 'Fondos', 'orden': 0},
      );

      final resultado = await b.sincronizar();

      expect(
        resultado.avisos.map((av) => av.motivo),
        contains(MotivoAviso.sinPadre),
      );
      // Y lo que sí tenía padre entró sin problema.
      expect((await b.bd.todasLasRutinas()).single.nombre, 'Empuje');
    });

    test('una tabla que este cliente no conoce se ignora sin romper', () async {
      servidor.filas['planes/uno'] = const FilaRemota(
        tabla: 'planes',
        clave: 'uno',
        actualizado: 2000000,
        datos: {'nombre': 'Mesociclo'},
      );

      await b.sincronizar();

      expect((await b.bd.estadoSincro()).cursorBajada, greaterThan(0));
    });
  });

  // ── 6. Convergencia ────────────────────────────────────────────────────────

  test('dos móviles que trabajan a la vez acaban en el mismo sitio', () async {
    final (rutinaA, ejercicioA) = await a.rutinaConEjercicio('Empuje');
    await a.sincronizar();
    await b.sincronizar();

    final rutinaB = (await b.bd.todasLasRutinas()).single.id;
    final ejercicioB = (await b.bd.ejerciciosDeRutina(rutinaB)).single.id;

    await a.entrenar(rutinaA, ejercicioA, DateTime(2026, 3, 1), [
      serie(10, 60),
    ]);
    await b.entrenar(rutinaB, ejercicioB, DateTime(2026, 3, 3), [serie(8, 70)]);
    await b.bd.registrarMedida(DateTime(2026, 3, 3), 'peso', 80);
    await a.bd.marcarFavorito('0001', true);
    await a.bd.insertarEjercicio(rutinaA, 'Fondos');

    // Se cruzan un par de veces, como pasaría de verdad.
    await a.sincronizar();
    await b.sincronizar();
    await a.sincronizar();
    await b.sincronizar();

    expect(await a.resumen(), await b.resumen());
    expect(await a.resumen(), [1, 2, 2, 1160]);
    expect((await a.bd.ultimaMedida('peso'))!.valor, 80);
    expect(await b.bd.favoritoPorId('0001'), isNotNull);
  });

  test('borrar todos los datos se lleva también los de la cuenta', () async {
    final (rutina, ejercicio) = await a.rutinaConEjercicio('Empuje');
    await a.entrenar(rutina, ejercicio, DateTime(2026, 3, 1), [serie(10, 60)]);
    await a.bd.registrarMedida(DateTime(2026, 3, 1), 'peso', 80);
    await a.sincronizar();
    await b.sincronizar();

    await a.bd.borrarTodosLosDatos();
    await a.sincronizar();
    await b.sincronizar();

    expect(await b.resumen(), [0, 0, 0, 0]);
    expect(await b.bd.ultimaMedida('peso'), isNull);
  });
}
