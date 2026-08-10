/// El adaptador del servidor, sin servidor.
///
/// Con `MockClient` se ejercita todo lo que el adaptador decide: la forma de
/// cada petición, entrar y registrarse, la rotación del refresco, el reintento
/// único ante un 401 y la traducción de cada fallo a su [MotivoSincro].
///
/// Lo que queda fuera es el servidor, y **ya no queda sin probar**: tiene su
/// propia suite en `servidor/tests/`, contra PostgreSQL de verdad. El contrato
/// que las dos mitades comparten es el que implementa `test/sincro_falso.dart`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appgym/datos/nube/token.dart';
import 'package:appgym/datos/sincro/servidor.dart';
import 'package:appgym/datos/sincro/transporte.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _url = 'https://appgym.ejemplo.com';
const _contrasena = 'unaContrasenaLarga1';

/// Una sesión ya guardada, como la que dejaría un [SincroServidor.entrar]
/// anterior.
String _sesionGuardada({String refresco = 'refresco-1'}) => jsonEncode({
  'id': 'usuario-1',
  'correo': 'yo@ejemplo.com',
  'refresco': refresco,
});

http.Response _json(Object? cuerpo, [int codigo = 200]) => http.Response(
  jsonEncode(cuerpo),
  codigo,
  headers: {'content-type': 'application/json'},
);

/// Lo que contesta el servidor al entrar, al registrarse y al renovar.
http.Response _sesion({String refresco = 'refresco-1'}) => _json({
  'acceso': 'acceso-1',
  'refresco': refresco,
  'expira_en': 900,
  'usuario': {'id': 'usuario-1', 'correo': 'yo@ejemplo.com'},
});

/// El adaptador con un servidor de mentira detrás.
///
/// [responder] recibe cada petición y decide qué contesta; [peticiones] las
/// guarda todas para poder mirarlas después.
({
  SincroServidor sincro,
  List<http.Request> peticiones,
  AlmacenEnMemoria almacen,
})
_montar(
  Future<http.Response> Function(http.Request) responder, {
  String? sesion,
  int filasPorLote = 200,
}) {
  final peticiones = <http.Request>[];
  final almacen = AlmacenEnMemoria(sesion);
  return (
    sincro: SincroServidor(
      url: _url,
      almacen: almacen,
      filasPorLote: filasPorLote,
      cliente: MockClient((peticion) {
        peticiones.add(peticion);
        return responder(peticion);
      }),
    ),
    peticiones: peticiones,
    almacen: almacen,
  );
}

/// Un servidor que renueva el acceso y contesta a la ruta pedida con
/// [respuesta].
Future<http.Response> Function(http.Request) _servidor(
  Object? respuesta, {
  int codigo = 200,
  String refrescoNuevo = 'refresco-2',
}) =>
    (peticion) async => peticion.url.path == '/auth/refrescar'
    ? _sesion(refresco: refrescoNuevo)
    : _json(respuesta, codigo);

void main() {
  group('entrar y registrarse', () {
    test('entrar canjea una sesión y la guarda', () async {
      final m = _montar((_) async => _sesion());

      final sesion = await m.sincro.entrar('yo@ejemplo.com', _contrasena);

      expect(sesion.correo, 'yo@ejemplo.com');
      expect(sesion.id, 'usuario-1');

      final peticion = m.peticiones.single;
      expect(peticion.url.toString(), '$_url/auth/entrar');
      final cuerpo = jsonDecode(peticion.body) as Map<String, dynamic>;
      expect(cuerpo['correo'], 'yo@ejemplo.com');
      expect(cuerpo['contrasena'], _contrasena);

      // Lo guardado tiene que bastar para renovar y para contestar quién es sin
      // volver a preguntar al servidor.
      final guardado = jsonDecode((await m.almacen.leer())!) as Map;
      expect(guardado['correo'], 'yo@ejemplo.com');
      expect(guardado['refresco'], 'refresco-1');
    });

    test('registrarse va a otra ruta y también deja sesión', () async {
      final m = _montar((_) async => _sesion());

      await m.sincro.registrar('yo@ejemplo.com', _contrasena);

      // Dos rutas y no una: con contraseña, «entrar» y «crear cuenta» no pueden
      // ser lo mismo, o un correo mal tecleado crearía una cuenta vacía.
      expect(m.peticiones.single.url.toString(), '$_url/auth/registro');
      expect(await m.almacen.leer(), isNotNull);
    });

    test('el correo se limpia por los lados antes de enviarlo', () async {
      final m = _montar((_) async => _sesion());

      await m.sincro.entrar('  yo@ejemplo.com  ', _contrasena);

      final cuerpo =
          jsonDecode(m.peticiones.single.body) as Map<String, dynamic>;
      expect(cuerpo['correo'], 'yo@ejemplo.com');
      // La contraseña **no** se toca: los espacios de una contraseña son parte
      // de la contraseña.
      expect(cuerpo['contrasena'], _contrasena);
    });

    test('unas credenciales que no valen se rechazan con su mensaje', () async {
      final m = _montar(
        (_) async =>
            _json({'mensaje': 'Correo o contraseña incorrectos.'}, 401),
      );

      await expectLater(
        m.sincro.entrar('yo@ejemplo.com', 'la que no era'),
        throwsA(
          isA<ErrorSincro>()
              // Se arregla tecleando otra vez, así que no se reintenta solo...
              .having((e) => e.motivo, 'motivo', MotivoSincro.rechazado)
              .having((e) => e.seReintenta, 'seReintenta', isFalse)
              // ...y el mensaje del servidor se enseña tal cual, que es lo que
              // le explica al usuario qué ha pasado.
              .having(
                (e) => e.mensaje,
                'mensaje',
                'Correo o contraseña incorrectos.',
              ),
        ),
      );
    });

    test('un correo ya registrado se rechaza con su mensaje', () async {
      final m = _montar(
        (_) async => _json({'mensaje': 'Ese correo ya tiene una cuenta.'}, 409),
      );

      await expectLater(
        m.sincro.registrar('yo@ejemplo.com', _contrasena),
        throwsA(
          isA<ErrorSincro>()
              .having((e) => e.motivo, 'motivo', MotivoSincro.rechazado)
              .having((e) => e.mensaje, 'mensaje', contains('ya tiene')),
        ),
      );
    });

    test('con el registro cerrado, el servidor lo dice y se enseña', () async {
      final m = _montar(
        (_) async =>
            _json({'mensaje': 'Este servidor no admite cuentas nuevas.'}, 403),
      );

      await expectLater(
        m.sincro.registrar('yo@ejemplo.com', _contrasena),
        throwsA(
          isA<ErrorSincro>()
              .having((e) => e.motivo, 'motivo', MotivoSincro.rechazado)
              .having((e) => e.mensaje, 'mensaje', contains('cuentas nuevas')),
        ),
      );
    });

    test('demasiados intentos es temporal, con su frase', () async {
      final m = _montar(
        (_) async => _json({
          'mensaje':
              'Demasiados intentos fallidos. Prueba dentro de unos minutos.',
        }, 429),
      );

      await expectLater(
        m.sincro.entrar('yo@ejemplo.com', 'la que no era'),
        throwsA(
          isA<ErrorSincro>()
              .having((e) => e.motivo, 'motivo', MotivoSincro.temporal)
              .having((e) => e.mensaje, 'mensaje', contains('intentos')),
        ),
      );
    });
  });

  group('la sesión guardada', () {
    test('se contesta sin tocar la red', () async {
      final m = _montar(
        (_) async => throw StateError('no debería pedir nada'),
        sesion: _sesionGuardada(),
      );

      final sesion = await m.sincro.sesionActual();

      expect(sesion?.correo, 'yo@ejemplo.com');
      // Es lo que evita que un móvil sin cobertura diga «sin cuenta» y el
      // usuario vuelva a entrar, cayendo otra vez por el primer enlace.
      expect(m.peticiones, isEmpty);
    });

    test('sin nada guardado no hay cuenta', () async {
      final m = _montar((_) async => _json({}));
      expect(await m.sincro.sesionActual(), isNull);
    });

    test('una sesión corrupta no es una sesión, y se limpia', () async {
      final m = _montar((_) async => _json({}), sesion: 'esto no es json');

      expect(await m.sincro.sesionActual(), isNull);
      expect(await m.almacen.leer(), isNull);
    });
  });

  group('el token de acceso', () {
    test('se renueva desde lo guardado antes de la primera llamada', () async {
      final m = _montar(
        _servidor({'cursor': 7, 'filas': <Object>[]}),
        sesion: _sesionGuardada(),
      );

      await m.sincro.bajar(0);

      expect(m.peticiones.first.url.path, '/auth/refrescar');
      expect(jsonDecode(m.peticiones.first.body)['refresco'], 'refresco-1');
      expect(m.peticiones.last.url.path, '/sincro/bajar');
      expect(m.peticiones.last.headers['Authorization'], 'Bearer acceso-1');
    });

    test('la rotación del refresco se guarda', () async {
      final m = _montar(
        _servidor({'cursor': 7, 'filas': <Object>[]}),
        sesion: _sesionGuardada(),
      );

      await m.sincro.bajar(0);

      // El servidor invalida el anterior en cuanto reparte uno nuevo, y si el
      // viejo reaparece revoca la cadena entera por si lo ha robado alguien. Sin
      // guardar el nuevo, la sesión moriría en la renovación siguiente.
      final guardado = jsonDecode((await m.almacen.leer())!) as Map;
      expect(guardado['refresco'], 'refresco-2');
      expect(guardado['correo'], 'yo@ejemplo.com');
    });

    test('dos llamadas a la vez renuevan una sola vez', () async {
      final m = _montar(
        _servidor({'cursor': 7, 'filas': <Object>[]}),
        sesion: _sesionGuardada(),
      );

      await Future.wait([m.sincro.bajar(0), m.sincro.bajar(0)]);

      // Dos renovaciones canjearían el mismo refresco dos veces, y el servidor
      // tomaría la segunda por un robo: sesión muerta.
      final renovaciones = m.peticiones
          .where((p) => p.url.path == '/auth/refrescar')
          .length;
      expect(renovaciones, 1);
    });

    test('un 401 se reintenta una vez tras renovar', () async {
      var llamadas = 0;
      final m = _montar((peticion) async {
        if (peticion.url.path == '/auth/refrescar') return _sesion();
        llamadas++;
        return llamadas == 1
            ? _json({'mensaje': 'La sesión no vale.'}, 401)
            : _json({'cursor': 9, 'filas': <Object>[]});
      }, sesion: _sesionGuardada());

      final paquete = await m.sincro.bajar(0);

      expect(paquete.cursor, 9);
      expect(llamadas, 2);
    });

    test('dos 401 seguidos son reconectar, no un bucle', () async {
      var llamadas = 0;
      final m = _montar((peticion) async {
        if (peticion.url.path == '/auth/refrescar') return _sesion();
        llamadas++;
        return _json({'mensaje': 'La sesión no vale.'}, 401);
      }, sesion: _sesionGuardada());

      await expectLater(
        m.sincro.bajar(0),
        throwsA(
          isA<ErrorSincro>().having(
            (e) => e.motivo,
            'motivo',
            MotivoSincro.reconectar,
          ),
        ),
      );
      expect(llamadas, 2);
    });

    test('un refresco gastado mata la sesión y la olvida', () async {
      final m = _montar(
        (peticion) async => peticion.url.path == '/auth/refrescar'
            ? _json({
                'mensaje':
                    'La sesión se ha cerrado por seguridad. Vuelve a entrar.',
              }, 401)
            : _json({}),
        sesion: _sesionGuardada(),
      );

      await expectLater(
        m.sincro.bajar(0),
        throwsA(
          isA<ErrorSincro>()
              .having((e) => e.motivo, 'motivo', MotivoSincro.reconectar)
              .having((e) => e.mensaje, 'mensaje', contains('seguridad')),
        ),
      );
      // Si no se olvidara, Ajustes seguiría diciendo que hay cuenta y no habría
      // forma de volver a entrar.
      expect(await m.almacen.leer(), isNull);
    });

    test('un fallo temporal al renovar no borra la sesión', () async {
      final m = _montar(
        (peticion) async => peticion.url.path == '/auth/refrescar'
            ? _json({'mensaje': 'gateway'}, 503)
            : _json({}),
        sesion: _sesionGuardada(),
      );

      await expectLater(
        m.sincro.bajar(0),
        throwsA(
          isA<ErrorSincro>().having(
            (e) => e.motivo,
            'motivo',
            MotivoSincro.temporal,
          ),
        ),
      );
      expect(await m.almacen.leer(), isNotNull);
    });
  });

  group('bajar', () {
    test('una fila sin datos es una lápida', () async {
      final m = _montar(
        _servidor({
          'cursor': 120,
          'filas': [
            {
              'tabla': 'rutinas',
              'clave': 'r-1',
              'actualizado': 110,
              'datos': {'nombre': 'Empuje'},
            },
            {
              'tabla': 'rutinas',
              'clave': 'r-2',
              'actualizado': 115,
              'datos': null,
            },
          ],
        }),
        sesion: _sesionGuardada(),
      );

      final paquete = await m.sincro.bajar(100);

      expect(paquete.cursor, 120);
      expect(paquete.filas.first.borrada, isFalse);
      expect(paquete.filas.first.datos!['nombre'], 'Empuje');
      expect(paquete.filas.last.borrada, isTrue);

      // El cursor va en la consulta, no en el cuerpo: `bajar` es un GET.
      expect(m.peticiones.last.url.queryParameters['cursor'], '100');
    });

    test('el cursor avanza aunque no venga ninguna fila', () async {
      final m = _montar(
        _servidor({'cursor': 500, 'filas': <Object>[]}),
        sesion: _sesionGuardada(),
      );

      final paquete = await m.sincro.bajar(400);

      expect(paquete.vacio, isTrue);
      expect(paquete.cursor, 500);
    });
  });

  group('subir', () {
    test('las filas viajan sin el sello del cliente', () async {
      final m = _montar(
        _servidor({
          'sellos': {'rutinas/r-1': 1770000000001},
          'cursor': 1770000000001,
          'cursorPrevio': 1770000000000,
        }),
        sesion: _sesionGuardada(),
      );

      final respuesta = await m.sincro.subir(
        const Paquete([
          FilaRemota(
            tabla: 'rutinas',
            clave: 'r-1',
            actualizado: 42,
            datos: {'nombre': 'Empuje'},
          ),
        ]),
      );

      final cuerpo = jsonDecode(m.peticiones.last.body) as Map<String, dynamic>;
      final enviada = (cuerpo['filas'] as List).single as Map;
      expect(enviada['tabla'], 'rutinas');
      expect(enviada['clave'], 'r-1');
      expect(enviada['datos'], {'nombre': 'Empuje'});
      // El reloj es del servidor: que sea imposible influir en él es mejor que
      // ignorarlo por convenio. Es el octavo escenario de K10.
      expect(enviada.containsKey('actualizado'), isFalse);

      expect(respuesta.sellos['rutinas/r-1'], 1770000000001);
      expect(respuesta.cursor, 1770000000001);
      expect(respuesta.cursorPrevio, 1770000000000);
    });

    test('un paquete grande va en lotes y se funde en una respuesta', () async {
      var lote = 0;
      final m = _montar(
        (peticion) async {
          if (peticion.url.path == '/auth/refrescar') return _sesion();
          lote++;
          return _json({
            'sellos': {'rutinas/r-$lote': 1000 + lote},
            'cursor': 1000 + lote,
            'cursorPrevio': 999 + lote,
          });
        },
        sesion: _sesionGuardada(),
        filasPorLote: 200,
      );

      final respuesta = await m.sincro.subir(
        Paquete([
          for (var i = 0; i < 450; i++)
            FilaRemota(
              tabla: 'rutinas',
              clave: 'r-$i',
              actualizado: i,
              datos: const {'nombre': 'x'},
            ),
        ]),
      );

      expect(lote, 3);
      // `cursorPrevio` es el del primer envío y `cursor` el del último: lo que
      // el servidor selló entre medias lo escribió este móvil, que es
      // exactamente lo que esa pareja significa para el motor.
      expect(respuesta.cursorPrevio, 1000);
      expect(respuesta.cursor, 1003);
      expect(respuesta.sellos.length, 3);
    });
  });

  group('la cuenta', () {
    test('salir revoca este refresco y olvida', () async {
      final m = _montar(_servidor({}), sesion: _sesionGuardada());
      await m.sincro.bajar(0); // deja un token de acceso vivo
      m.peticiones.clear();

      await m.sincro.salir();

      final salida = m.peticiones.single;
      expect(salida.url.path, '/auth/salir');
      // Cerrar sesión en este móvil no puede cerrar la de la tableta: K3 dice
      // «un usuario, N dispositivos». Por eso viaja el refresco de este móvil y
      // no basta con el token de acceso.
      expect(jsonDecode(salida.body)['refresco'], 'refresco-2');
      expect(await m.almacen.leer(), isNull);
    });

    test('salir olvida aunque el servidor falle', () async {
      final m = _montar((peticion) async {
        if (peticion.url.path == '/auth/refrescar') return _sesion();
        if (peticion.url.path == '/auth/salir') {
          throw const SocketException('sin red');
        }
        return _json({'cursor': 1, 'filas': <Object>[]});
      }, sesion: _sesionGuardada());
      await m.sincro.bajar(0);

      await m.sincro.salir();

      // Salir es lo que el usuario pidió; que el servidor no se entere hoy no
      // puede dejarle la cuenta abierta en el móvil.
      expect(await m.almacen.leer(), isNull);
    });

    test('borrar la cuenta va por DELETE y olvida la sesión', () async {
      final m = _montar(_servidor(null), sesion: _sesionGuardada());

      await m.sincro.borrarCuenta();

      expect(m.peticiones.last.url.path, '/auth/cuenta');
      expect(m.peticiones.last.method, 'DELETE');
      expect(await m.almacen.leer(), isNull);
    });

    test('una respuesta sin cuerpo (204) no revienta', () async {
      // `vaciar` y `borrar la cuenta` contestan 204 y cuerpo vacío, que no es
      // JSON: decodificarlo sin más lanzaría.
      final m = _montar(
        (peticion) async => peticion.url.path == '/auth/refrescar'
            ? _sesion()
            : http.Response('', 204),
        sesion: _sesionGuardada(),
      );

      await m.sincro.vaciar();

      expect(m.peticiones.last.url.path, '/sincro/vaciar');
    });

    test('el resumen trae las dos cifras del primer enlace', () async {
      final m = _montar(
        _servidor({'rutinas': 2, 'sesiones': 180}),
        sesion: _sesionGuardada(),
      );

      final cifras = await m.sincro.resumen();

      expect(cifras.rutinas, 2);
      expect(cifras.sesiones, 180);
      expect(cifras.vacio, isFalse);
    });
  });

  group('la traducción de los fallos', () {
    Future<ErrorSincro> falloDe(
      Future<http.Response> Function(http.Request) servidor,
    ) async {
      final m = _montar(servidor, sesion: _sesionGuardada());
      try {
        await m.sincro.bajar(0);
      } on ErrorSincro catch (e) {
        return e;
      }
      fail('tenía que haber fallado');
    }

    test('429 y 5xx se reintentan solos', () async {
      expect(
        (await falloDe(
          _servidor({
            'mensaje': 'Demasiadas peticiones seguidas.',
          }, codigo: 429),
        )).motivo,
        MotivoSincro.temporal,
      );
      expect(
        (await falloDe(_servidor({'mensaje': 'boom'}, codigo: 503))).motivo,
        MotivoSincro.temporal,
      );
    });

    test('un corte de red es temporal', () async {
      final sinRed = await falloDe(
        (peticion) async => peticion.url.path == '/auth/refrescar'
            ? _sesion()
            : throw const SocketException('sin cobertura'),
      );
      expect(sinRed.motivo, MotivoSincro.temporal);

      final tarde = await falloDe(
        (peticion) async => peticion.url.path == '/auth/refrescar'
            ? _sesion()
            : throw TimeoutException('tardó'),
      );
      expect(tarde.motivo, MotivoSincro.temporal);
    });

    test('un fallo del anclaje no se reintenta', () async {
      // O el certificado del servidor no es el que esta compilación acepta, o
      // hay algo por el medio leyendo el tráfico. Reintentar no lo arregla, y
      // sobre todo: la petición no llegó a salir.
      final fallo = await falloDe(
        (peticion) async => peticion.url.path == '/auth/refrescar'
            ? _sesion()
            : throw const TlsException('certificado no verificado'),
      );
      expect(fallo.motivo, MotivoSincro.rechazado);
      expect(fallo.mensaje, contains('verificar el servidor'));
    });

    test('un 403 pide volver a entrar', () async {
      expect(
        (await falloDe(
          _servidor({'mensaje': 'La cuenta ya no existe.'}, codigo: 403),
        )).motivo,
        MotivoSincro.reconectar,
      );
    });

    test('una URL que no es la de AppGym se dice', () async {
      final fallo = await falloDe(
        _servidor({'mensaje': 'Not Found'}, codigo: 404),
      );
      // Esto no se arregla reintentando: la URL apunta a otra cosa, o a un
      // servidor más viejo que este cliente.
      expect(fallo.motivo, MotivoSincro.rechazado);
      expect(fallo.mensaje, contains('API de AppGym'));
    });

    test('un cuerpo que no es JSON no provoca un segundo fallo', () async {
      final fallo = await falloDe(
        (peticion) async => peticion.url.path == '/auth/refrescar'
            ? _sesion()
            : http.Response('<html>502</html>', 502),
      );
      expect(fallo.motivo, MotivoSincro.temporal);
    });
  });

  test('sin --dart-define no hay servicio', () {
    // En los tests no se pasa la URL, así que la sincronización está apagada: es
    // exactamente lo que le pasa a un fork y a una compilación local, y lo que
    // hace que CI siga en verde sin secretos.
    expect(sincroDisponible, isFalse);
  });
}
