/// El adaptador de Supabase, sin Supabase.
///
/// Con `MockClient` se ejercita todo lo que el adaptador decide: la forma de
/// cada petición, la entrada en dos pasos, la rotación del *refresh token*, el
/// reintento único ante un 401 y la traducción de cada fallo a su
/// [MotivoSincro].
///
/// Lo que queda fuera es el servidor: que las cinco funciones de
/// `supabase/esquema.sql` hagan lo que prometen no se puede comprobar aquí. El
/// guion para verificarlas a mano está en `docs/sincronizacion.md`, y el
/// contrato que tienen que cumplir es el que implementa `test/sincro_falso.dart`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appgym/datos/nube/token.dart';
import 'package:appgym/datos/sincro/supabase.dart';
import 'package:appgym/datos/sincro/transporte.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _url = 'https://proyecto.supabase.co';

/// Una sesión ya guardada, como la que dejaría un [SincroSupabase.entrar]
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

/// Lo que GoTrue contesta al canjear o al renovar.
http.Response _tokens({String refresco = 'refresco-1'}) => _json({
  'access_token': 'acceso-1',
  'refresh_token': refresco,
  'expires_in': 3600,
  'user': {'id': 'usuario-1', 'email': 'yo@ejemplo.com'},
});

/// El adaptador con un servidor de mentira detrás.
///
/// [responder] recibe cada petición y decide qué contesta; [peticiones] las
/// guarda todas para poder mirarlas después.
({SincroSupabase sincro, List<http.Request> peticiones, AlmacenEnMemoria almacen})
_montar(
  Future<http.Response> Function(http.Request) responder, {
  String? sesion,
  int filasPorLote = 200,
}) {
  final peticiones = <http.Request>[];
  final almacen = AlmacenEnMemoria(sesion);
  return (
    sincro: SincroSupabase(
      url: _url,
      clavePublica: 'clave-publica',
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

/// Un servidor que renueva el token y contesta a una función con [respuesta].
Future<http.Response> Function(http.Request) _servidor(
  Object? respuesta, {
  int codigo = 200,
  String refrescoNuevo = 'refresco-2',
}) => (peticion) async => peticion.url.path.endsWith('/token')
    ? _tokens(refresco: refrescoNuevo)
    : _json(respuesta, codigo);

void main() {
  group('entrar', () {
    test('pedir el código manda un OTP que crea la cuenta si hace falta', () async {
      final m = _montar((_) async => _json({}));

      await m.sincro.pedirCodigo('yo@ejemplo.com');

      final peticion = m.peticiones.single;
      expect(peticion.url.toString(), '$_url/auth/v1/otp');
      expect(peticion.headers['apikey'], 'clave-publica');
      final cuerpo = jsonDecode(peticion.body) as Map<String, dynamic>;
      expect(cuerpo['email'], 'yo@ejemplo.com');
      // «Crear cuenta» y «entrar» son el mismo botón, como pide K3.
      expect(cuerpo['create_user'], isTrue);
    });

    test('el código canjea una sesión y la guarda', () async {
      final m = _montar((_) async => _tokens());

      final sesion = await m.sincro.entrar('yo@ejemplo.com', '123456');

      expect(sesion.correo, 'yo@ejemplo.com');
      expect(sesion.id, 'usuario-1');

      final peticion = m.peticiones.single;
      expect(peticion.url.toString(), '$_url/auth/v1/verify');
      final cuerpo = jsonDecode(peticion.body) as Map<String, dynamic>;
      expect(cuerpo['type'], 'email');
      expect(cuerpo['token'], '123456');

      // Lo guardado tiene que bastar para renovar y para contestar quién es sin
      // volver a preguntar al servidor.
      final guardado = jsonDecode((await m.almacen.leer())!) as Map;
      expect(guardado['correo'], 'yo@ejemplo.com');
      expect(guardado['refresco'], 'refresco-1');
    });

    test('un código en blanco por los lados se limpia antes de enviarlo', () async {
      final m = _montar((_) async => _tokens());

      await m.sincro.entrar('yo@ejemplo.com', ' 123456 ');

      final cuerpo = jsonDecode(m.peticiones.single.body) as Map<String, dynamic>;
      expect(cuerpo['token'], '123456');
    });

    test('un código caducado se rechaza con el mensaje del servidor', () async {
      final m = _montar(
        (_) async => _json({
          'error_code': 'otp_expired',
          'msg': 'Token has expired or is invalid',
        }, 403),
      );

      await expectLater(
        m.sincro.entrar('yo@ejemplo.com', '000000'),
        throwsA(
          isA<ErrorSincro>()
              // Se arregla tecleando otra vez, así que no se reintenta solo...
              .having((e) => e.motivo, 'motivo', MotivoSincro.rechazado)
              .having((e) => e.seReintenta, 'seReintenta', isFalse)
              // ...y el mensaje del servidor se enseña tal cual, que es lo que
              // le explica al usuario qué ha pasado con su código.
              .having(
                (e) => e.mensaje,
                'mensaje',
                'Token has expired or is invalid',
              ),
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

      expect(m.peticiones.first.url.path, '/auth/v1/token');
      expect(
        m.peticiones.first.url.queryParameters['grant_type'],
        'refresh_token',
      );
      expect(m.peticiones.last.url.path, '/rest/v1/rpc/appgym_bajar');
      expect(m.peticiones.last.headers['Authorization'], 'Bearer acceso-1');
    });

    test('la rotación del refresh token se guarda', () async {
      final m = _montar(
        _servidor({'cursor': 7, 'filas': <Object>[]}),
        sesion: _sesionGuardada(),
      );

      await m.sincro.bajar(0);

      // GoTrue invalida el anterior en cuanto reparte uno nuevo. Si no se
      // guardase, la sesión moriría en la renovación siguiente.
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

      // Dos renovaciones canjearían el mismo refresh token dos veces y la
      // segunda llegaría con uno ya gastado: sesión muerta.
      final renovaciones = m.peticiones
          .where((p) => p.url.path.endsWith('/token'))
          .length;
      expect(renovaciones, 1);
    });

    test('un 401 se reintenta una vez tras renovar', () async {
      var llamadas = 0;
      final m = _montar((peticion) async {
        if (peticion.url.path.endsWith('/token')) return _tokens();
        llamadas++;
        return llamadas == 1
            ? _json({'message': 'JWT expired'}, 401)
            : _json({'cursor': 9, 'filas': <Object>[]});
      }, sesion: _sesionGuardada());

      final paquete = await m.sincro.bajar(0);

      expect(paquete.cursor, 9);
      expect(llamadas, 2);
    });

    test('dos 401 seguidos son reconectar, no un bucle', () async {
      var llamadas = 0;
      final m = _montar((peticion) async {
        if (peticion.url.path.endsWith('/token')) return _tokens();
        llamadas++;
        return _json({'message': 'JWT expired'}, 401);
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

    test('un refresh token gastado mata la sesión y la olvida', () async {
      final m = _montar(
        (peticion) async => peticion.url.path.endsWith('/token')
            ? _json({
                'error_code': 'refresh_token_not_found',
                'msg': 'Invalid Refresh Token',
              }, 400)
            : _json({}),
        sesion: _sesionGuardada(),
      );

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
      // Si no se olvidara, Ajustes seguiría diciendo que hay cuenta y no habría
      // forma de volver a entrar.
      expect(await m.almacen.leer(), isNull);
    });

    test('un fallo temporal al renovar no borra la sesión', () async {
      final m = _montar(
        (peticion) async => peticion.url.path.endsWith('/token')
            ? _json({'msg': 'gateway'}, 503)
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

      final cuerpo =
          jsonDecode(m.peticiones.last.body) as Map<String, dynamic>;
      expect(cuerpo['p_cursor'], 100);
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

      final cuerpo =
          jsonDecode(m.peticiones.last.body) as Map<String, dynamic>;
      final enviada = (cuerpo['p_filas'] as List).single as Map;
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
      final m = _montar((peticion) async {
        if (peticion.url.path.endsWith('/token')) return _tokens();
        lote++;
        return _json({
          'sellos': {'rutinas/r-$lote': 1000 + lote},
          'cursor': 1000 + lote,
          'cursorPrevio': 999 + lote,
        });
      }, sesion: _sesionGuardada(), filasPorLote: 200);

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
    test('salir cierra solo esta sesión y olvida', () async {
      final m = _montar(_servidor({}), sesion: _sesionGuardada());
      await m.sincro.bajar(0); // deja un token de acceso vivo
      m.peticiones.clear();

      await m.sincro.salir();

      final salida = m.peticiones.single;
      expect(salida.url.path, '/auth/v1/logout');
      // Cerrar sesión en este móvil no puede cerrar la de la tableta: K3 dice
      // «un usuario, N dispositivos».
      expect(salida.url.queryParameters['scope'], 'local');
      expect(await m.almacen.leer(), isNull);
    });

    test('salir olvida aunque el servidor falle', () async {
      final m = _montar((peticion) async {
        if (peticion.url.path.endsWith('/token')) return _tokens();
        if (peticion.url.path.endsWith('/logout')) {
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

    test('borrar la cuenta llama a su función y olvida la sesión', () async {
      final m = _montar(_servidor(null), sesion: _sesionGuardada());

      await m.sincro.borrarCuenta();

      expect(
        m.peticiones.last.url.path,
        '/rest/v1/rpc/appgym_borrar_cuenta',
      );
      expect(await m.almacen.leer(), isNull);
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
        (await falloDe(_servidor({'message': 'slow down'}, codigo: 429))).motivo,
        MotivoSincro.temporal,
      );
      expect(
        (await falloDe(_servidor({'message': 'boom'}, codigo: 503))).motivo,
        MotivoSincro.temporal,
      );
    });

    test('un corte de red es temporal', () async {
      final sinRed = await falloDe(
        (peticion) async => peticion.url.path.endsWith('/token')
            ? _tokens()
            : throw const SocketException('sin cobertura'),
      );
      expect(sinRed.motivo, MotivoSincro.temporal);

      final tarde = await falloDe(
        (peticion) async => peticion.url.path.endsWith('/token')
            ? _tokens()
            : throw TimeoutException('tardó'),
      );
      expect(tarde.motivo, MotivoSincro.temporal);
    });

    test('un 403 de la RLS pide volver a entrar', () async {
      expect(
        (await falloDe(_servidor({'message': 'sin sesión'}, codigo: 403))).motivo,
        MotivoSincro.reconectar,
      );
    });

    test('sin el esquema aplicado, se dice', () async {
      final fallo = await falloDe(
        _servidor({
          'code': 'PGRST202',
          'message': 'Could not find the function',
        }, codigo: 404),
      );
      // Esto no se arregla reintentando: hay que ejecutar el esquema.
      expect(fallo.motivo, MotivoSincro.rechazado);
      expect(fallo.mensaje, contains('esquema'));
    });

    test('un cuerpo que no es JSON no provoca un segundo fallo', () async {
      final fallo = await falloDe(
        (peticion) async => peticion.url.path.endsWith('/token')
            ? _tokens()
            : http.Response('<html>502</html>', 502),
      );
      expect(fallo.motivo, MotivoSincro.temporal);
    });
  });

  test('sin --dart-define no hay servicio', () {
    // En los tests no se pasan las credenciales, así que la sincronización está
    // apagada: es exactamente lo que le pasa a un fork y a una compilación
    // local, y lo que hace que CI siga en verde sin secretos.
    expect(sincroDisponible, isFalse);
  });
}
