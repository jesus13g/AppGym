/// El adaptador de Google Drive, sin Google.
///
/// Es la parte que parecía imposible de probar y no lo es. Con `MockClient` se
/// ejercitan el canje del código, la renovación del token y la traducción de
/// cada fallo de Drive a su [MotivoFallo]; y el bucle local se prueba **de
/// verdad**, levantando el `HttpServer` y haciendo de navegador con un `GET`.
///
/// Lo único que queda fuera es `launchUrl` —abrir el navegador del sistema— y
/// los servidores de Google.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appgym/datos/nube/drive.dart';
import 'package:appgym/datos/nube/nube.dart';
import 'package:appgym/datos/nube/token.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Un `id_token` de mentira: cabecera y firma no se miran, solo la carga.
String _idToken(String correo) {
  String trozo(Object valor) =>
      base64Url.encode(utf8.encode(jsonEncode(valor))).replaceAll('=', '');
  return '${trozo({'alg': 'none'})}.${trozo({'email': correo})}.firma';
}

/// Lo que Google contesta en `/token`.
http.Response _tokens({String? refresco = 'refresco-1', String? id}) =>
    http.Response(
      jsonEncode({
        'access_token': 'acceso-1',
        'expires_in': 3600,
        'refresh_token': ?refresco,
        'id_token': ?id,
      }),
      200,
      headers: {'content-type': 'application/json'},
    );

http.Response _json(Object cuerpo, [int codigo = 200]) => http.Response(
  jsonEncode(cuerpo),
  codigo,
  headers: {'content-type': 'application/json'},
);

void main() {
  group('el bucle local', () {
    test('recoge el código que devuelve el navegador', () async {
      final peticiones = <http.BaseRequest>[];
      final drive = DriveNube(
        clienteId: 'cliente',
        clienteSecreto: 'secreto',
        almacen: AlmacenEnMemoria(),
        cliente: MockClient((peticion) async {
          peticiones.add(peticion);
          return _tokens(id: _idToken('yo@ejemplo.com'));
        }),
        // Hace de navegador: en vez de abrir Chrome, va directo a la
        // redirección con un código, que es exactamente lo que haría Google.
        abrirNavegador: (uri) async {
          final redireccion = Uri.parse(uri.queryParameters['redirect_uri']!);
          // Sin `await`: el servidor todavía no está escuchando la respuesta,
          // porque quien lo espera es la línea siguiente del propio `conectar`.
          unawaited(
            http.get(redireccion.replace(queryParameters: {'code': 'abc'})),
          );
          return true;
        },
      );

      expect(await drive.conectar('vuelve'), 'yo@ejemplo.com');

      // El canje lleva el código, el verificador de PKCE y el secreto.
      final canje = peticiones.single as http.Request;
      expect(canje.url.host, 'oauth2.googleapis.com');
      expect(canje.bodyFields['code'], 'abc');
      expect(canje.bodyFields['grant_type'], 'authorization_code');
      expect(canje.bodyFields['code_verifier'], isNotEmpty);
    });

    test(
      'el reto de PKCE es S256 y el verificador no viaja al navegador',
      () async {
        Uri? autorizacion;
        final drive = DriveNube(
          clienteId: 'cliente',
          clienteSecreto: 'secreto',
          almacen: AlmacenEnMemoria(),
          cliente: MockClient((_) async => _tokens()),
          abrirNavegador: (uri) async {
            autorizacion = uri;
            unawaited(
              http.get(
                Uri.parse(
                  uri.queryParameters['redirect_uri']!,
                ).replace(queryParameters: {'code': 'abc'}),
              ),
            );
            return true;
          },
        );
        await drive.conectar('vuelve');

        final parametros = autorizacion!.queryParameters;
        expect(parametros['code_challenge_method'], 'S256');
        expect(parametros['code_challenge'], isNotEmpty);
        // Lo que va al navegador es el reto, nunca el verificador: si viajara,
        // PKCE no protegería de nada.
        expect(parametros.containsKey('code_verifier'), isFalse);
        // Sin `offline` no vendría refresh token y la copia dejaría de ser
        // automática en cuanto caducara el primer acceso.
        expect(parametros['access_type'], 'offline');
        expect(parametros['scope'], contains('drive.file'));
        // `drive` a secas daría acceso a todo el Drive del usuario.
        expect(parametros['scope'], isNot(contains('auth/drive ')));
      },
    );

    test(
      'si Google devuelve un error en vez de un código, se rechaza',
      () async {
        final drive = DriveNube(
          clienteId: 'cliente',
          clienteSecreto: 'secreto',
          almacen: AlmacenEnMemoria(),
          cliente: MockClient((_) async => _tokens()),
          abrirNavegador: (uri) async {
            unawaited(
              http.get(
                Uri.parse(
                  uri.queryParameters['redirect_uri']!,
                ).replace(queryParameters: {'error': 'access_denied'}),
              ),
            );
            return true;
          },
        );

        await expectLater(
          drive.conectar('vuelve'),
          throwsA(
            isA<ErrorNube>().having(
              (e) => e.motivo,
              'motivo',
              MotivoFallo.rechazado,
            ),
          ),
        );
      },
    );

    test('sin refresh token no se da por conectado', () async {
      // Es el caso en que Google no vuelve a entregarlo por haber consentido
      // antes: sin él, la copia solo funcionaría una hora.
      final drive = DriveNube(
        clienteId: 'cliente',
        clienteSecreto: 'secreto',
        almacen: AlmacenEnMemoria(),
        cliente: MockClient((_) async => _tokens(refresco: null)),
        abrirNavegador: (uri) async {
          unawaited(
            http.get(
              Uri.parse(
                uri.queryParameters['redirect_uri']!,
              ).replace(queryParameters: {'code': 'abc'}),
            ),
          );
          return true;
        },
      );

      await expectLater(drive.conectar('vuelve'), throwsA(isA<ErrorNube>()));
    });
  });

  group('el token de acceso', () {
    test('se renueva desde el refresco guardado', () async {
      final peticiones = <http.Request>[];
      final drive = DriveNube(
        clienteId: 'cliente',
        clienteSecreto: 'secreto',
        almacen: AlmacenEnMemoria('refresco-guardado'),
        cliente: MockClient((peticion) async {
          peticiones.add(peticion);
          if (peticion.url.host == 'oauth2.googleapis.com') return _tokens();
          return _json({'files': <Object>[]});
        }),
      );

      await drive.listar();

      final renovacion = peticiones.first;
      expect(renovacion.bodyFields['grant_type'], 'refresh_token');
      expect(renovacion.bodyFields['refresh_token'], 'refresco-guardado');
      // Y a partir de ahí, todo va con el Bearer.
      expect(peticiones.last.headers['Authorization'], 'Bearer acceso-1');
    });

    test('sin cuenta conectada pide reconectar, no reintenta', () async {
      final drive = DriveNube(
        clienteId: 'cliente',
        clienteSecreto: 'secreto',
        almacen: AlmacenEnMemoria(),
        cliente: MockClient((_) async => _json({})),
      );

      await expectLater(
        drive.listar(),
        throwsA(
          isA<ErrorNube>()
              .having((e) => e.motivo, 'motivo', MotivoFallo.reconectar)
              .having((e) => e.seReintenta, 'seReintenta', isFalse),
        ),
      );
    });

    test('invalid_grant es reconectar: el permiso ya no vale', () async {
      final drive = DriveNube(
        clienteId: 'cliente',
        clienteSecreto: 'secreto',
        almacen: AlmacenEnMemoria('refresco-revocado'),
        cliente: MockClient(
          (_) async => _json({'error': 'invalid_grant'}, 400),
        ),
      );

      await expectLater(
        drive.listar(),
        throwsA(
          isA<ErrorNube>().having(
            (e) => e.motivo,
            'motivo',
            MotivoFallo.reconectar,
          ),
        ),
      );
    });
  });

  group('los ficheros', () {
    /// Un Drive de mentira con su carpeta ya creada.
    DriveNube conCarpeta(
      Future<http.Response> Function(http.Request) manejar, {
      List<Object> enLaCarpeta = const [],
    }) => DriveNube(
      clienteId: 'cliente',
      clienteSecreto: 'secreto',
      almacen: AlmacenEnMemoria('refresco'),
      cliente: MockClient((peticion) async {
        if (peticion.url.host == 'oauth2.googleapis.com') return _tokens();
        final consulta = peticion.url.queryParameters['q'] ?? '';
        if (consulta.contains('mimeType')) {
          return _json({
            'files': [
              {'id': 'carpeta-1'},
            ],
          });
        }
        if (peticion.method == 'GET' && consulta.contains('in parents')) {
          return _json({'files': enLaCarpeta});
        }
        return manejar(peticion);
      }),
    );

    test('una copia nueva se sube como multipart con su carpeta', () async {
      http.Request? subida;
      final drive = conCarpeta((peticion) async {
        subida = peticion;
        return _json({'id': 'fichero-1'});
      });

      await drive.subir('appgym-copia-2026-03-12.json', '{"formato":"x"}');

      expect(subida!.method, 'POST');
      expect(subida!.url.path, '/upload/drive/v3/files');
      expect(subida!.url.queryParameters['uploadType'], 'multipart');
      expect(subida!.headers['Content-Type'], contains('multipart/related'));

      final cuerpo = utf8.decode(subida!.bodyBytes);
      expect(cuerpo, contains('appgym-copia-2026-03-12.json'));
      expect(cuerpo, contains('carpeta-1'));
      expect(cuerpo, contains('{"formato":"x"}'));
    });

    test('la copia del mismo día se reemplaza con PATCH', () async {
      http.Request? subida;
      final drive = conCarpeta(
        (peticion) async {
          subida = peticion;
          return _json({'id': 'fichero-1'});
        },
        enLaCarpeta: [
          {
            'id': 'fichero-1',
            'name': 'appgym-copia-2026-03-12.json',
            'createdTime': '2026-03-12T09:00:00Z',
          },
        ],
      );

      await drive.subir('appgym-copia-2026-03-12.json', '{"nuevo":true}');

      // Dos copias del mismo día son la misma copia: se pisa, no se duplica.
      expect(subida!.method, 'PATCH');
      expect(subida!.url.path, '/upload/drive/v3/files/fichero-1');
      expect(subida!.url.queryParameters['uploadType'], 'media');
      expect(utf8.decode(subida!.bodyBytes), '{"nuevo":true}');
    });

    test('listar devuelve lo que hay con su fecha', () async {
      final drive = conCarpeta(
        (_) async => _json({}),
        enLaCarpeta: [
          {
            'id': 'a',
            'name': 'appgym-copia-2026-03-01.json',
            'createdTime': '2026-03-01T09:00:00Z',
          },
          {
            'id': 'b',
            'name': 'appgym-copia-2026-03-12.json',
            'createdTime': '2026-03-12T09:00:00Z',
          },
        ],
      );

      final copias = await drive.listar();
      expect(copias.map((c) => c.id), ['a', 'b']);
      expect(copias.first.creada, DateTime.utc(2026, 3, 1, 9));
    });
  });

  group('la traducción de los fallos', () {
    Future<void> esperarMotivo(int codigo, MotivoFallo motivo) async {
      final drive = DriveNube(
        clienteId: 'cliente',
        clienteSecreto: 'secreto',
        almacen: AlmacenEnMemoria('refresco'),
        cliente: MockClient((peticion) async {
          if (peticion.url.host == 'oauth2.googleapis.com') return _tokens();
          return _json({
            'error': {'message': 'vaya'},
          }, codigo);
        }),
      );

      await expectLater(
        drive.listar(),
        throwsA(isA<ErrorNube>().having((e) => e.motivo, '$codigo', motivo)),
      );
    }

    test('429 y 5xx son temporales: se pasan solos', () async {
      await esperarMotivo(429, MotivoFallo.temporal);
      await esperarMotivo(500, MotivoFallo.temporal);
      await esperarMotivo(503, MotivoFallo.temporal);
    });

    test('un 400 se rechaza sin reintentar', () async {
      await esperarMotivo(400, MotivoFallo.rechazado);
    });

    test('un corte de red es temporal', () async {
      final drive = DriveNube(
        clienteId: 'cliente',
        clienteSecreto: 'secreto',
        almacen: AlmacenEnMemoria('refresco'),
        cliente: MockClient(
          (_) async => throw const SocketException('sin ruta al host'),
        ),
      );

      await expectLater(
        drive.listar(),
        throwsA(
          isA<ErrorNube>()
              .having((e) => e.motivo, 'motivo', MotivoFallo.temporal)
              .having((e) => e.seReintenta, 'seReintenta', isTrue),
        ),
      );
    });
  });

  group('desconectar', () {
    test('revoca el permiso y borra el token guardado', () async {
      final almacen = AlmacenEnMemoria('refresco-1');
      final revocaciones = <http.Request>[];
      final drive = DriveNube(
        clienteId: 'cliente',
        clienteSecreto: 'secreto',
        almacen: almacen,
        cliente: MockClient((peticion) async {
          revocaciones.add(peticion);
          return http.Response('', 200);
        }),
      );

      await drive.desconectar();

      expect(await almacen.leer(), isNull);
      expect(revocaciones.single.url.path, '/revoke');
      expect(revocaciones.single.bodyFields['token'], 'refresco-1');
    });

    test('si la revocación falla, el token local se borra igual', () async {
      final almacen = AlmacenEnMemoria('refresco-1');
      final drive = DriveNube(
        clienteId: 'cliente',
        clienteSecreto: 'secreto',
        almacen: almacen,
        cliente: MockClient((_) async => throw const SocketException('nada')),
      );

      await drive.desconectar();

      // Desconectar es lo que el usuario pidió; que Google no se entere hoy no
      // puede dejarle la cuenta conectada en el móvil.
      expect(await almacen.leer(), isNull);
    });
  });

  test('sin --dart-define no hay destino', () {
    // En los tests no se pasan las credenciales, así que la funcionalidad está
    // apagada: es exactamente lo que le pasa a un fork y a una compilación
    // local, y lo que hace que CI siga en verde sin secretos.
    expect(driveDisponible, isFalse);
  });
}
