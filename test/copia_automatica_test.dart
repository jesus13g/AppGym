/// La copia automática: la lógica pura y el motor entero.
///
/// Todo esto corre **sin red, sin cuenta y sin proveedor**, contra la nube
/// falsa y con el reloj de `datos/reloj.dart` fijado. Es lo que permite decidir
/// cuándo toca copiar y qué pasa al fallar con los números delante, en vez de
/// probándolo en el móvil.
library;

import 'package:appgym/datos/ajustes.dart';
import 'package:appgym/datos/bd.dart';
import 'package:appgym/datos/copia.dart' as copia;
import 'package:appgym/datos/copia_automatica.dart';
import 'package:appgym/datos/nube/nube.dart';
import 'package:appgym/datos/reloj.dart' as reloj;
import 'package:appgym/estado/copia_automatica.dart';
import 'package:appgym/estado/providers.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ayuda.dart';
import 'nube_falsa.dart';

EstadoCopiaAutomatica _estado({
  Frecuencia frecuencia = Frecuencia.diaria,
  String? cuenta = 'yo@ejemplo.com',
  DateTime? ultima,
  String? error,
}) => EstadoCopiaAutomatica(
  frecuencia: frecuencia,
  cuenta: cuenta,
  ultima: ultima,
  error: error,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── La lógica pura ─────────────────────────────────────────────────────────

  group('cuándo toca', () {
    final ahora = DateTime(2026, 3, 12, 9); // jueves

    test('sin cuenta conectada no toca nunca', () {
      expect(toca(_estado(cuenta: null), ahora: ahora), isFalse);
    });

    test('con la frecuencia desactivada no toca nunca', () {
      expect(toca(_estado(frecuencia: Frecuencia.no), ahora: ahora), isFalse);
    });

    test('conectado y sin ninguna copia todavía, toca', () {
      expect(toca(_estado(), ahora: ahora), isTrue);
    });

    test('la diaria se decide por día natural, no por 24 horas', () {
      // Anoche a las 23:50: han pasado nueve horas, pero es otro día y por
      // tanto toca. Con un «hace menos de 24 h» bastaría entrenar dos noches
      // seguidas para saltarse una copia.
      final anoche = DateTime(2026, 3, 11, 23, 50);
      expect(toca(_estado(ultima: anoche), ahora: ahora), isTrue);

      // Esta mañana temprano: mismo día, no toca.
      expect(
        toca(_estado(ultima: DateTime(2026, 3, 12, 1)), ahora: ahora),
        isFalse,
      );
    });

    test('la semanal se decide por lunes, y la semana empieza en lunes', () {
      // Domingo pasado: semana distinta aunque sean cuatro días.
      expect(
        toca(
          _estado(frecuencia: Frecuencia.semanal, ultima: DateTime(2026, 3, 8)),
          ahora: ahora,
        ),
        isTrue,
      );
      // El lunes de esta misma semana: no toca.
      expect(
        toca(
          _estado(frecuencia: Frecuencia.semanal, ultima: DateTime(2026, 3, 9)),
          ahora: ahora,
        ),
        isFalse,
      );
    });

    test('la mensual se decide por mes natural', () {
      expect(
        toca(
          _estado(
            frecuencia: Frecuencia.mensual,
            ultima: DateTime(2026, 2, 28),
          ),
          ahora: ahora,
        ),
        isTrue,
      );
      expect(
        toca(
          _estado(frecuencia: Frecuencia.mensual, ultima: DateTime(2026, 3, 1)),
          ahora: ahora,
        ),
        isFalse,
      );
    });
  });

  group('rotación', () {
    CopiaRemota copiaDe(int dia) => CopiaRemota(
      id: '$dia',
      nombre: 'copia-$dia',
      creada: DateTime(2026).add(Duration(days: dia)),
    );

    test('con diez o menos no sobra ninguna', () {
      expect(sobrantes([for (var i = 0; i < 10; i++) copiaDe(i)]), isEmpty);
    });

    test('sobran las más antiguas, y el orden no depende del proveedor', () {
      // Se pasan desordenadas a propósito: la lista que devuelve la nube no
      // tiene por qué venir ordenada.
      final desordenadas = [for (var i = 13; i >= 0; i--) copiaDe(i)]
        ..shuffle();
      final fuera = sobrantes(desordenadas);

      expect(fuera.length, 4);
      expect(fuera.map((c) => c.id), ['3', '2', '1', '0']);
    });
  });

  group('cuándo se avisa', () {
    final ahora = DateTime(2026, 3, 12);

    test('apagada o sin cuenta no avisa', () {
      expect(avisar(_estado(frecuencia: Frecuencia.no), ahora: ahora), isFalse);
      expect(avisar(_estado(cuenta: null), ahora: ahora), isFalse);
    });

    test('un fallo guardado avisa siempre', () {
      expect(
        avisar(
          _estado(ultima: ahora, error: 'sin conexión'),
          ahora: ahora,
        ),
        isTrue,
      );
    });

    test('recién conectada y sin copias todavía no avisa', () {
      // El primer disparador está a punto de hacerla; avisar aquí sería avisar
      // de algo que no ha tenido tiempo de fallar.
      expect(avisar(_estado(), ahora: ahora), isFalse);
    });

    test('un retraso de un periodo no avisa; el de dos, sí', () {
      final semanal = Frecuencia.semanal;
      expect(
        avisar(
          _estado(
            frecuencia: semanal,
            ultima: ahora.subtract(const Duration(days: 10)),
          ),
          ahora: ahora,
        ),
        isFalse,
      );
      expect(
        avisar(
          _estado(
            frecuencia: semanal,
            ultima: ahora.subtract(const Duration(days: 15)),
          ),
          ahora: ahora,
        ),
        isTrue,
      );
    });
  });

  // ── Las claves de dispositivo ──────────────────────────────────────────────

  group('claves locales', () {
    test('no salen en la copia de seguridad', () {
      final portables = copia.ajustesPortables({
        Claves.unidad: 'lb',
        Claves.copiaNubeCuenta: 'yo@ejemplo.com',
        Claves.copiaNubeUltima: '2026-03-12T09:00:00.000',
        Claves.versionIndice: '2',
      });

      expect(portables, {Claves.unidad: 'lb'});
    });
  });

  // ── El motor ───────────────────────────────────────────────────────────────

  group('el motor', () {
    late AppBD bd;
    late NubeFalsa nube;
    late ProviderContainer contenedor;
    late MotorCopiaAutomatica motor;
    var ahora = DateTime(2026, 3, 12, 9);

    Future<EstadoCopiaAutomatica> leerEstado() async =>
        EstadoCopiaAutomatica.desdeMapa(await bd.ajustesCrudos());

    setUp(() async {
      ahora = DateTime(2026, 3, 12, 9);
      reloj.fijarReloj(() => ahora);
      bd = AppBD(NativeDatabase.memory());
      nube = NubeFalsa();
      contenedor = ProviderContainer(
        overrides: [
          bdProvider.overrideWithValue(bd),
          nubeProvider.overrideWithValue(nube),
        ],
      );
      motor = contenedor.read(motorCopiaProvider.notifier);
      // Una rutina para que la exportación no sea un cascarón vacío.
      await bd.insertarRutina('Empuje');
    });

    tearDown(() async {
      contenedor.dispose();
      await bd.close();
      reloj.fijarReloj(null);
    });

    test('conectar guarda la cuenta, enciende la semanal y copia ya', () async {
      await motor.conectar('vuelve');

      final estado = await leerEstado();
      expect(estado.cuenta, 'yo@ejemplo.com');
      // Conectar sin frecuencia dejaría una cuenta que no copia nada.
      expect(estado.frecuencia, Frecuencia.semanal);
      expect(estado.ultima, ahora);
      expect(nube.subidas, 1);
      expect(nube.ficheros.keys.single, copia.nombreFichero(ahora));
    });

    test('la copia subida es el JSON que reimportaría copia.dart', () async {
      await motor.conectar('vuelve');

      final subido = copia.leer(nube.ficheros.values.single);
      expect(subido, isNotNull);
      expect(copia.validar(textosDePrueba(), subido!), isEmpty);
      expect((subido['rutinas'] as List).single['nombre'], 'Empuje');
    });

    test('la copia del mismo día reemplaza en vez de duplicar', () async {
      await motor.conectar('vuelve');
      await motor.intentar(Disparador.manual);

      expect(nube.subidas, 2);
      expect(nube.ficheros.length, 1);
    });

    test('no copia si no toca, y sí si es manual', () async {
      await motor.conectar('vuelve');
      await motor.fijarFrecuencia(Frecuencia.mensual);
      final subidasHastaAhora = nube.subidas;

      // Mismo mes: no toca.
      await motor.intentar(Disparador.arranque);
      expect(nube.subidas, subidasHastaAhora);

      // A mano sí, siempre.
      await motor.intentar(Disparador.manual);
      expect(nube.subidas, subidasHastaAhora + 1);
    });

    test('nunca copia durante una sesión viva', () async {
      await motor.conectar('vuelve');
      final subidasHastaAhora = nube.subidas;

      final rutina = (await bd.todasLasRutinas()).single;
      await bd.guardarSesionActiva(rutina.id, ahora, '{"borrador":true}');
      ahora = ahora.add(const Duration(days: 40));

      await motor.intentar(Disparador.arranque);
      expect(nube.subidas, subidasHastaAhora, reason: 'con borrador no copia');

      // Al guardar el entrenamiento el borrador ya no está, así que el
      // disparador que importa no se pierde por esto.
      await bd.descartarSesionActiva();
      await motor.intentar(Disparador.guardado);
      expect(nube.subidas, subidasHastaAhora + 1);
    });

    test(
      'vuelta del segundo plano: no dispara dos veces en cinco minutos',
      () async {
        await motor.conectar('vuelve');
        final tras = nube.subidas;

        // Un intento que falla deja la copia sin fecha —así sigue tocando— pero
        // sí cuenta como intento. Es la única forma de que el mínimo entre
        // vueltas se pueda observar por separado de «le toca».
        ahora = ahora.add(const Duration(days: 40));
        nube.fallo = const ErrorNube.temporal('sin cobertura');
        await motor.intentar(Disparador.vuelta);
        expect(nube.subidas, tras, reason: 'el intento falló');

        nube.fallo = null;
        ahora = ahora.add(const Duration(minutes: 2));
        await motor.intentar(Disparador.vuelta);
        expect(nube.subidas, tras, reason: 'demasiado pronto tras la última');

        ahora = ahora.add(minimoEntreVueltas);
        await motor.intentar(Disparador.vuelta);
        expect(nube.subidas, tras + 1);
      },
    );

    test('rota y deja solo las diez más recientes', () async {
      nube.sembrar(12);
      await motor.conectar('vuelve');

      expect(nube.ficheros.length, copiasQueSeConservan);
      expect(nube.borrados, 3, reason: '12 viejas + 1 nueva − 10');
      // La recién subida no puede ser una de las borradas.
      expect(nube.ficheros, contains(copia.nombreFichero(ahora)));
    });

    test(
      'un fallo temporal deja el error escrito y no marca la copia',
      () async {
        nube.fallo = const ErrorNube.temporal('sin cobertura');
        await motor.conectar('vuelve');

        final estado = await leerEstado();
        expect(estado.error, 'sin cobertura');
        expect(estado.ultima, isNull, reason: 'no hubo copia que fechar');
        expect(avisar(estado, ahora: ahora), isTrue);
      },
    );

    test('un fallo de permiso no se reintenta', () async {
      nube.fallo = const ErrorNube.reconectar('vuelve a conectar');
      await motor.conectar('vuelve');

      expect(
        const ErrorNube.reconectar('x').seReintenta,
        isFalse,
        reason: 'reintentar un permiso revocado no lo arregla nunca',
      );
      expect((await leerEstado()).error, 'vuelve a conectar');
    });

    test('una copia buena después de un fallo borra el error', () async {
      nube.fallo = const ErrorNube.temporal('sin cobertura');
      await motor.conectar('vuelve');
      expect((await leerEstado()).error, isNotNull);

      nube.fallo = null;
      await motor.intentar(Disparador.manual);

      final estado = await leerEstado();
      expect(estado.error, isNull);
      expect(estado.ultima, ahora);
      expect(avisar(estado, ahora: ahora), isFalse);
    });

    test('desconectar olvida la cuenta y apaga la copia', () async {
      await motor.conectar('vuelve');
      await motor.desconectar();

      final estado = await leerEstado();
      expect(estado.cuenta, isNull);
      expect(estado.conectado, isFalse);
      expect(estado.frecuencia, Frecuencia.no);
      expect(estado.ultima, isNull);
      expect(nube.desconectado, isTrue);
    });

    test('desconectar no toca los datos locales', () async {
      await motor.conectar('vuelve');
      await motor.desconectar();

      // La nube es una copia, no el original.
      expect((await bd.todasLasRutinas()).single.nombre, 'Empuje');
    });

    test('si conectar falla, no queda una cuenta a medias', () async {
      nube.falloAlConectar = const ErrorNube.rechazado('cancelado');
      await motor.conectar('vuelve');

      final estado = await leerEstado();
      expect(estado.cuenta, isNull);
      expect(estado.error, 'cancelado');
      expect(nube.subidas, 0);
    });

    test('sin destino configurado el motor no hace nada', () async {
      final sinNube = ProviderContainer(
        overrides: [
          bdProvider.overrideWithValue(bd),
          nubeProvider.overrideWithValue(null),
        ],
      );
      addTearDown(sinNube.dispose);

      final motorSinNube = sinNube.read(motorCopiaProvider.notifier);
      expect(sinNube.read(motorCopiaProvider).disponible, isFalse);
      await motorSinNube.conectar('vuelve');
      await motorSinNube.intentar(Disparador.manual);

      expect(nube.subidas, 0);
      expect((await leerEstado()).cuenta, isNull);
    });
  });
}
