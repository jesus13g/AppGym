/// El motor de la sincronización dentro de la app: los disparadores, la cuenta
/// y el primer enlace.
///
/// Es el gemelo de `copia_automatica_test.dart`. Un `ProviderContainer` con la
/// base en memoria y el transporte falso enchufados, y el reloj fijado, que es
/// lo que permite comprobar el mínimo entre vueltas sin esperar cinco minutos.
///
/// Aquí se cierran cuatro de las casillas que K12 dejó pendientes: cerrar sesión
/// conservando los datos, borrar la cuenta, la app sin servicio configurado y
/// que el servicio apagado no convierta la app en un ladrillo.
library;

import 'package:appgym/datos/ajustes.dart';
import 'package:appgym/datos/bd.dart';
import 'package:appgym/datos/identidad.dart';
import 'package:appgym/datos/reloj.dart' as reloj;
import 'package:appgym/datos/sincro/enlace.dart';
import 'package:appgym/datos/sincro/transporte.dart';
import 'package:appgym/estado/providers.dart';
import 'package:appgym/estado/sincro.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sincro_falso.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppBD bd;
  late SincroFalso servidor;
  late ProviderContainer contenedor;
  late Sincronizador motor;
  var ahora = DateTime(2026, 8, 10, 9);

  /// Entra en la cuenta y deja el interruptor encendido, que es el estado
  /// normal desde el que se dispara todo.
  Future<void> conCuenta() async {
    await motor.entrar('yo@ejemplo.com', servidor.codigo);
  }

  setUp(() async {
    ahora = DateTime(2026, 8, 10, 9);
    reloj.fijarReloj(() => ahora);
    reiniciarSellos();
    bd = AppBD(NativeDatabase.memory());
    servidor = SincroFalso();
    contenedor = ProviderContainer(
      overrides: [
        bdProvider.overrideWithValue(bd),
        sincroProvider.overrideWithValue(servidor),
      ],
    );
    motor = contenedor.read(sincronizacionProvider.notifier);
    await motor.refrescar();
  });

  tearDown(() async {
    contenedor.dispose();
    await bd.close();
    reloj.fijarReloj(null);
  });

  // ── La cuenta ──────────────────────────────────────────────────────────────

  group('la cuenta', () {
    test('entrar enciende el interruptor y enlaza sin preguntar', () async {
      final lados = await motor.entrar('yo@ejemplo.com', servidor.codigo);

      // Los dos lados vacíos no hay nada que decidir: es el primero de los tres
      // casos automáticos de K7.
      expect(lados, isNull);
      expect(contenedor.read(sincronizacionProvider).conectado, isTrue);
      expect(contenedor.read(sincronizacionProvider).activa, isTrue);
      expect(
        (await bd.ajustesCrudos())[Claves.sincroActiva],
        '1',
        reason: 'quien acaba de crear una cuenta quiere sincronizar',
      );
    });

    test('un código que no vale no deja cuenta a medias', () async {
      await expectLater(
        motor.entrar('yo@ejemplo.com', '000000'),
        throwsA(isA<ErrorSincro>()),
      );

      await motor.refrescar();
      expect(contenedor.read(sincronizacionProvider).conectado, isFalse);
    });

    test('cerrar sesión conservando los datos deja la base intacta', () async {
      final idRutina = (await bd.insertarRutina('Empuje'))!;
      await bd.insertarEjercicio(idRutina, 'Press banca');
      await conCuenta();

      await motor.salir();

      // El criterio de K12: la nube es una copia, no el original.
      expect((await bd.todasLasRutinas()).single.nombre, 'Empuje');
      expect((await bd.ejerciciosDeRutina(idRutina)).length, 1);
      expect(contenedor.read(sincronizacionProvider).conectado, isFalse);
      expect((await bd.ajustesCrudos())[Claves.sincroActiva], '');
    });

    test('cerrar sesión borrando se lleva los datos de este móvil', () async {
      await bd.insertarRutina('Empuje');
      await conCuenta();

      await motor.salir(borrandoDatos: true);

      expect(await bd.todasLasRutinas(), isEmpty);
    });

    test('al salir los cursores vuelven a cero', () async {
      await bd.insertarRutina('Empuje');
      await conCuenta();
      expect((await bd.estadoSincro()).cursorSubida, greaterThan(0));

      await motor.salir();

      // Con un cursor viejo, entrar mañana con otra cuenta haría que la primera
      // pasada se saltara el delta entero y el móvil se quedara con la mitad de
      // los datos sin que nada avisara.
      final estado = await bd.estadoSincro();
      expect(estado.cursorSubida, 0);
      expect(estado.cursorBajada, 0);
      expect(estado.ultimoError, isNull);
    });

    test('borrar la cuenta vacía el servidor y no toca lo local', () async {
      await bd.insertarRutina('Empuje');
      await conCuenta();
      expect(servidor.filas, isNotEmpty);

      await motor.borrarCuenta();

      // El otro criterio de K12, y el que más importa que sea de verdad.
      expect(servidor.filas, isEmpty);
      expect((await bd.todasLasRutinas()).single.nombre, 'Empuje');
      expect(contenedor.read(sincronizacionProvider).conectado, isFalse);
    });

    test('apagar el interruptor no desconecta la cuenta', () async {
      await conCuenta();

      await motor.activar(false);

      expect(contenedor.read(sincronizacionProvider).activa, isFalse);
      expect(contenedor.read(sincronizacionProvider).conectado, isTrue);
    });
  });

  // ── Los disparadores ───────────────────────────────────────────────────────

  group('los disparadores', () {
    test('sin cuenta no se sincroniza nada', () async {
      await bd.insertarRutina('Empuje');

      await motor.intentar(DisparadorSincro.arranque);

      expect(servidor.bajadas, 0);
      expect(servidor.subidas, 0);
    });

    test('con el interruptor apagado tampoco', () async {
      await conCuenta();
      await motor.activar(false);
      final bajadas = servidor.bajadas;

      await motor.intentar(DisparadorSincro.arranque);

      expect(servidor.bajadas, bajadas);
    });

    test('arrancar sincroniza', () async {
      await conCuenta();
      final bajadas = servidor.bajadas;
      await bd.insertarRutina('Empuje');

      await motor.intentar(DisparadorSincro.arranque);

      expect(servidor.bajadas, bajadas + 1);
      expect(servidor.deTabla('rutinas').length, 1);
    });

    test('dos vueltas seguidas solo disparan una pasada', () async {
      await conCuenta();
      await motor.intentar(DisparadorSincro.vuelta);
      final bajadas = servidor.bajadas;

      ahora = ahora.add(const Duration(minutes: 3));
      await motor.intentar(DisparadorSincro.vuelta);

      // Sin el mínimo, alternar entre la app y WhatsApp diez veces seguidas
      // dispararía diez pasadas.
      expect(servidor.bajadas, bajadas);

      ahora = ahora.add(const Duration(minutes: 3));
      await motor.intentar(DisparadorSincro.vuelta);
      expect(servidor.bajadas, bajadas + 1);
    });

    test('el manual se salta el mínimo entre vueltas', () async {
      await conCuenta();
      await motor.intentar(DisparadorSincro.vuelta);
      final bajadas = servidor.bajadas;

      ahora = ahora.add(const Duration(seconds: 10));
      await motor.intentar(DisparadorSincro.manual);

      expect(servidor.bajadas, bajadas + 1);
    });

    test('con una sesión viva abierta no se sincroniza', () async {
      await conCuenta();
      final idRutina = (await bd.insertarRutina('Empuje'))!;
      await bd.guardarSesionActiva(idRutina, ahora, '{"ejercicios":[]}');
      final bajadas = servidor.bajadas;

      await motor.intentar(DisparadorSincro.guardado);

      // El borrador se reescribe cada dos segundos: pelearse con el disco ahí
      // no aporta nada, y al guardar el entrenamiento ya no está.
      expect(servidor.bajadas, bajadas);

      await bd.descartarSesionActiva();
      await motor.intentar(DisparadorSincro.guardado);
      expect(servidor.bajadas, bajadas + 1);
    });

    test('el manual sí sincroniza con una sesión viva', () async {
      await conCuenta();
      final idRutina = (await bd.insertarRutina('Empuje'))!;
      await bd.guardarSesionActiva(idRutina, ahora, '{"ejercicios":[]}');
      final bajadas = servidor.bajadas;

      await motor.intentar(DisparadorSincro.manual);

      expect(servidor.bajadas, bajadas + 1);
    });
  });

  // ── Los fallos ─────────────────────────────────────────────────────────────

  group('los fallos', () {
    test('un fallo temporal se anota y no se propaga', () async {
      await conCuenta();
      servidor.falloAlBajar = const ErrorSincro.temporal('sin cobertura');

      // No lanza: un fallo de sincronización es un aviso, no un error.
      await motor.intentar(DisparadorSincro.manual);

      expect((await bd.estadoSincro()).ultimoError, 'sin cobertura');
      expect(contenedor.read(sincronizacionProvider).enMarcha, isFalse);
    });

    test('un servicio apagado no convierte la app en un ladrillo', () async {
      await conCuenta();
      await bd.insertarRutina('Empuje');
      servidor.falloAlBajar = const ErrorSincro.rechazado('el servicio cerró');

      await motor.intentar(DisparadorSincro.manual);
      await motor.intentar(DisparadorSincro.manual);

      // El riesgo de K11: la app avisa y sigue funcionando en local.
      expect((await bd.estadoSincro()).ultimoError, 'el servicio cerró');
      expect((await bd.todasLasRutinas()).single.nombre, 'Empuje');
      expect(
        const ErrorSincro.rechazado('x').seReintenta,
        isFalse,
        reason: 'reintentar lo que el servidor rechaza no lo arregla nunca',
      );
    });

    test('una pasada buena limpia el error anterior', () async {
      await conCuenta();
      servidor.falloAlBajar = const ErrorSincro.temporal('sin cobertura');
      await motor.intentar(DisparadorSincro.manual);
      expect((await bd.estadoSincro()).ultimoError, isNotNull);

      servidor.falloAlBajar = null;
      await motor.intentar(DisparadorSincro.manual);

      expect((await bd.estadoSincro()).ultimoError, isNull);
    });
  });

  // ── El aviso de la cabecera ────────────────────────────────────────────────

  group('el aviso de la cabecera', () {
    test('no avisa cuando todo va bien', () async {
      await conCuenta();
      await motor.intentar(DisparadorSincro.manual);

      expect(
        contenedor.read(sincronizacionProvider).avisar(ahora: ahora),
        isFalse,
        reason: 'sincronizar bien es lo normal y lo normal no se anuncia',
      );
    });

    test('avisa si la última pasada falló', () async {
      await conCuenta();
      servidor.falloAlBajar = const ErrorSincro.temporal('sin cobertura');
      await motor.intentar(DisparadorSincro.manual);

      expect(
        contenedor.read(sincronizacionProvider).avisar(ahora: ahora),
        isTrue,
      );
    });

    test('avisa si lleva más de un día sin una pasada buena', () async {
      await conCuenta();
      await motor.intentar(DisparadorSincro.manual);
      final vista = contenedor.read(sincronizacionProvider);

      expect(
        vista.avisar(ahora: ahora.add(const Duration(hours: 20))),
        isFalse,
      );
      expect(vista.avisar(ahora: ahora.add(const Duration(hours: 30))), isTrue);
    });

    test('sin cuenta no avisa de nada', () async {
      expect(
        contenedor.read(sincronizacionProvider).avisar(ahora: ahora),
        isFalse,
      );
    });
  });

  // ── El primer enlace ───────────────────────────────────────────────────────

  group('el primer enlace', () {
    /// Deja datos en la cuenta, como los habría dejado otro móvil: una rutina
    /// con su ejercicio y una sesión.
    Future<void> sembrarLaCuenta() async {
      final otra = AppBD(NativeDatabase.memory());
      addTearDown(otra.close);
      final idRutina = (await otra.insertarRutina('Tirón'))!;
      await otra.insertarEjercicio(idRutina, 'Dominadas');
      final ejercicio = (await otra.ejerciciosDeRutina(idRutina)).single;
      await otra.insertarEntrenamiento(idRutina, DateTime(2026, 8, 1), {
        ejercicio.id: [const ValoresSerie(repeticiones: 8, peso: 0)],
      });
      await Enlace(otra, servidor).enlazar();
    }

    test('con datos solo aquí se sube todo sin preguntar', () async {
      await bd.insertarRutina('Empuje');

      final lados = await motor.entrar('yo@ejemplo.com', servidor.codigo);

      expect(lados, isNull);
      expect(servidor.deTabla('rutinas').length, 1);
    });

    test('con datos solo en la cuenta se baja todo sin preguntar', () async {
      await sembrarLaCuenta();

      final lados = await motor.entrar('yo@ejemplo.com', servidor.codigo);

      expect(lados, isNull);
      expect((await bd.todasLasRutinas()).single.nombre, 'Tirón');
    });

    test('con datos a los dos lados se pregunta, con las cifras', () async {
      await sembrarLaCuenta();
      await bd.insertarRutina('Empuje');

      final lados = await motor.entrar('yo@ejemplo.com', servidor.codigo);

      // Sin números, la pregunta de qué lado manda no se puede responder.
      expect(lados, isNotNull);
      expect(lados!.hayQueDecidir, isTrue);
      expect(lados.local.rutinas, 1);
      expect(lados.local.sesiones, 0);
      expect(lados.remoto.rutinas, 1);
      expect(lados.remoto.sesiones, 1);

      // Y hasta que no se elige, no se ha tocado nada.
      expect((await bd.todasLasRutinas()).single.nombre, 'Empuje');
    });

    test('fusionar deja las dos rutinas', () async {
      await sembrarLaCuenta();
      await bd.insertarRutina('Empuje');
      await motor.entrar('yo@ejemplo.com', servidor.codigo);

      await motor.enlazar(estrategia: EstrategiaEnlace.fusionar);

      final nombres = [for (final r in await bd.todasLasRutinas()) r.nombre];
      expect(nombres, containsAll(['Empuje', 'Tirón']));
    });

    test(
      '«este dispositivo manda» vacía la cuenta y sube lo de aquí',
      () async {
        await sembrarLaCuenta();
        await bd.insertarRutina('Empuje');
        await motor.entrar('yo@ejemplo.com', servidor.codigo);

        await motor.enlazar(estrategia: EstrategiaEnlace.esteDispositivo);

        expect(servidor.vaciados, 1);
        expect((await bd.todasLasRutinas()).single.nombre, 'Empuje');
        expect(servidor.deTabla('rutinas').length, 1);
      },
    );

    test('«la cuenta manda» exige exportar una copia antes', () async {
      await sembrarLaCuenta();
      await bd.insertarRutina('Empuje');
      await motor.entrar('yo@ejemplo.com', servidor.codigo);

      // Es la salida que puede destruir dos años de datos y no se ofrece sin
      // red de seguridad.
      await expectLater(
        motor.enlazar(estrategia: EstrategiaEnlace.laCuenta),
        throwsA(isA<StateError>()),
      );
      expect((await bd.todasLasRutinas()).single.nombre, 'Empuje');
    });

    test('«la cuenta manda» respalda y sustituye lo local', () async {
      await sembrarLaCuenta();
      await bd.insertarRutina('Empuje');
      await motor.entrar('yo@ejemplo.com', servidor.codigo);

      var respaldada = false;
      await motor.enlazar(
        estrategia: EstrategiaEnlace.laCuenta,
        respaldoPrevio: () async => respaldada = true,
      );

      expect(respaldada, isTrue);
      expect((await bd.todasLasRutinas()).single.nombre, 'Tirón');
    });
  });

  // ── Sin servicio configurado ───────────────────────────────────────────────

  group('sin servicio configurado', () {
    test('el motor no existe y nada de esto hace nada', () async {
      final sinServicio = ProviderContainer(
        overrides: [
          bdProvider.overrideWithValue(bd),
          sincroProvider.overrideWithValue(null),
        ],
      );
      addTearDown(sinServicio.dispose);

      final apagado = sinServicio.read(sincronizacionProvider.notifier);
      expect(sinServicio.read(sincronizacionProvider).disponible, isFalse);

      // Es lo que le pasa a un fork y a una compilación local: la app se
      // comporta exactamente como antes de la fase 8c.
      await apagado.refrescar();
      await apagado.pedirCodigo('yo@ejemplo.com');
      expect(await apagado.entrar('yo@ejemplo.com', '123456'), isNull);
      await apagado.intentar(DisparadorSincro.arranque);

      expect(servidor.bajadas, 0);
      expect(servidor.codigosPedidos, isEmpty);
      expect(sinServicio.read(sincronizacionProvider).conectado, isFalse);
    });
  });
}
