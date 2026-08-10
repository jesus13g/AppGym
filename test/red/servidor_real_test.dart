/// El adaptador contra el servidor **de verdad**.
///
/// Es el único test del proyecto que necesita red, y por eso va marcado con la
/// etiqueta `red` y **fuera de la suite por defecto**: `flutter test` no lo
/// ejecuta. Se lanza a mano con el servidor levantado:
///
/// ```bash
/// cd servidor && docker compose up -d
/// flutter test --tags red --dart-define API_URL=https://localhost
/// ```
///
/// O contra un `uvicorn` suelto, que es lo más rápido para desarrollar:
///
/// ```bash
/// flutter test --tags red --dart-define API_URL=http://127.0.0.1:8000
/// ```
///
/// Qué aporta que no aporten los otros dos: `sincro_servidor_test.dart` prueba
/// lo que el adaptador **decide** contra un `MockClient`, y la suite de
/// `servidor/tests/` prueba lo que el servidor **hace** contra PostgreSQL. Aquí
/// se comprueba que las dos mitades se entienden: los nombres de los campos, los
/// códigos de estado, el 204 sin cuerpo y la rotación del refresco de verdad.
/// Sustituye al guion SQL que en la fase 8c había que pegar a mano en un panel.
@Tags(['red'])
library;

import 'package:appgym/datos/nube/token.dart';
import 'package:appgym/datos/sincro/servidor.dart';
import 'package:appgym/datos/sincro/transporte.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dónde está el servidor. Sin esto, el test se salta.
const _url = String.fromEnvironment('API_URL');

/// Un correo distinto en cada ejecución: el test crea una cuenta y la borra al
/// terminar, y no puede chocar con la de una ejecución anterior que se cortara.
String _correoNuevo() =>
    'prueba-${DateTime.now().microsecondsSinceEpoch}@ejemplo.com';

const _contrasena = 'unaContrasenaDePruebas1';

void main() {
  if (_url.isEmpty) {
    test('sin API_URL no hay nada que probar', () {
      markTestSkipped('pasa --dart-define API_URL=... con el servidor en pie');
    }, skip: true);
    return;
  }

  late SincroServidor sincro;
  late String correo;

  setUp(() {
    correo = _correoNuevo();
    // Almacén en memoria: este test no puede tocar el Keystore, que en
    // `flutter test` no existe.
    sincro = SincroServidor(url: _url, almacen: AlmacenEnMemoria());
  });

  tearDown(() async {
    // La cuenta de prueba se lleva sus datos por el `ON DELETE CASCADE`. Si el
    // test falló antes de entrar, no hay nada que borrar.
    try {
      if (await sincro.sesionActual() != null) await sincro.borrarCuenta();
    } on ErrorSincro {
      // Que la limpieza falle no puede enmascarar el fallo del test.
    }
  });

  test('el ciclo entero: registrar, subir, bajar, enterrar y borrarse', () async {
    // ── La cuenta ────────────────────────────────────────────────────────────
    final sesion = await sincro.registrar(correo, _contrasena);
    expect(sesion.correo, correo);
    expect(sesion.id, isNotEmpty);
    expect((await sincro.sesionActual())?.correo, correo);

    // ── El reloj ─────────────────────────────────────────────────────────────
    final primera = await sincro.subir(
      const Paquete([
        FilaRemota(
          tabla: 'rutinas',
          clave: 'r-1',
          actualizado: 1,
          datos: {'nombre': 'Empuje'},
        ),
        FilaRemota(
          tabla: 'entrenamientos',
          clave: 'e-1',
          actualizado: 2,
          datos: {'fecha': '2026-08-10'},
        ),
      ]),
    );

    // Si el reloj arrancara bajo, cada pasada resubiría el histórico entero. Es
    // la invariante que no se ve fallar hasta que el usuario tiene datos.
    expect(primera.cursorPrevio, greaterThan(1700000000000));
    expect(primera.cursor, greaterThan(primera.cursorPrevio));
    expect(primera.sellos['rutinas/r-1'], primera.cursorPrevio + 1);

    // ── Bajar ────────────────────────────────────────────────────────────────
    final todo = await sincro.bajar(0);
    expect(todo.filas.length, 2);
    expect(todo.cursor, primera.cursor);
    final rutina = todo.filas.firstWhere((f) => f.clave == 'r-1');
    expect(rutina.datos!['nombre'], 'Empuje');

    // Desde el cursor no viene nada, pero el cursor sigue llegando.
    final nada = await sincro.bajar(todo.cursor);
    expect(nada.vacio, isTrue);
    expect(nada.cursor, todo.cursor);

    // ── El resumen ───────────────────────────────────────────────────────────
    expect(
      await sincro.resumen(),
      isA<Cifras>()
          .having((c) => c.rutinas, 'rutinas', 1)
          .having((c) => c.sesiones, 'sesiones', 1),
    );

    // ── Una lápida ───────────────────────────────────────────────────────────
    final segunda = await sincro.subir(
      const Paquete([
        FilaRemota.borrada(tabla: 'rutinas', clave: 'r-1', actualizado: 3),
      ]),
    );
    expect(segunda.cursorPrevio, primera.cursor);

    final tras = await sincro.bajar(todo.cursor);
    expect(tras.filas.single.borrada, isTrue);
    // Una lápida no cuenta como rutina.
    expect((await sincro.resumen()).rutinas, 0);

    // ── Vaciar ───────────────────────────────────────────────────────────────
    await sincro.vaciar();
    expect((await sincro.resumen()).vacio, isTrue);
    // Y el reloj **no** se reinicia: si lo hiciera, repartiría sellos ya usados.
    final tercera = await sincro.subir(
      const Paquete([
        FilaRemota(
          tabla: 'rutinas',
          clave: 'r-2',
          actualizado: 1,
          datos: {'nombre': 'Tirón'},
        ),
      ]),
    );
    expect(tercera.cursorPrevio, greaterThanOrEqualTo(segunda.cursor));

    // ── Borrarse ─────────────────────────────────────────────────────────────
    await sincro.borrarCuenta();
    expect(await sincro.sesionActual(), isNull);
  });

  test(
    'entrar con la contraseña equivocada lo dice, y con la buena entra',
    () async {
      await sincro.registrar(correo, _contrasena);

      final otro = SincroServidor(url: _url, almacen: AlmacenEnMemoria());
      await expectLater(
        otro.entrar(correo, 'estaNoEsLaBuena1'),
        throwsA(
          isA<ErrorSincro>()
              .having((e) => e.motivo, 'motivo', MotivoSincro.rechazado)
              .having((e) => e.mensaje, 'mensaje', isNotEmpty),
        ),
      );

      final sesion = await otro.entrar(correo, _contrasena);
      expect(sesion.correo, correo);
    },
  );

  test('registrarse dos veces con el mismo correo se rechaza', () async {
    await sincro.registrar(correo, _contrasena);

    final otro = SincroServidor(url: _url, almacen: AlmacenEnMemoria());
    await expectLater(
      otro.registrar(correo, _contrasena),
      throwsA(
        isA<ErrorSincro>().having(
          (e) => e.motivo,
          'motivo',
          MotivoSincro.rechazado,
        ),
      ),
    );
  });

  test('salir en un dispositivo no cierra la sesión del otro', () async {
    await sincro.registrar(correo, _contrasena);

    final tableta = SincroServidor(url: _url, almacen: AlmacenEnMemoria());
    await tableta.entrar(correo, _contrasena);

    await tableta.salir();
    expect(await tableta.sesionActual(), isNull);

    // El móvil sigue dentro: K3 dice «un usuario, N dispositivos». Se comprueba
    // pidiendo algo que exige credencial viva.
    expect((await sincro.resumen()).vacio, isTrue);
  });
}
