/// El adaptador de Google Drive. **El único fichero que sabe que Google
/// existe.**
///
/// Todo lo demás de la copia automática habla con [DestinoNube], así que
/// cambiar de proveedor es escribir otro fichero como este y no tocar nada más.
///
/// ## Por qué no se usa `google_sign_in`
///
/// Un cliente OAuth de tipo *Android* va atado al `applicationId` **y a la
/// huella SHA-1 del certificado de firma**. Este proyecto firma el APK de
/// release con la clave de depuración (`android/app/build.gradle.kts`), que en
/// un runner de GitHub se genera nueva en cada ejecución: la huella cambiaría en
/// cada release y el inicio de sesión no funcionaría **nunca**. Una compilación
/// local y un fork tendrían el mismo problema.
///
/// Por eso se usa el flujo de código de autorización con **PKCE y redirección
/// al bucle local** (RFC 8252) contra un cliente de tipo *Aplicación de
/// escritorio*, que es el único que Google sigue admitiendo con
/// `http://127.0.0.1:<puerto>` y **no depende del certificado de firma**. Sale
/// además más barato: sin SDK de Google, hablando REST con el `http` que ya
/// estaba declarado.
///
/// El «secreto» del cliente va en el binario, y eso es correcto aquí: para una
/// aplicación instalada RFC 8252 dice expresamente que no es confidencial. Lo
/// que protege el canje es PKCE.
///
/// ## Por qué el ámbito es `drive.file`
///
/// Con `drive.file` la app **solo ve y modifica lo que ella misma creó**. Tres
/// consecuencias, todas buenas: es privilegio mínimo, hace imposible que la
/// rotación borre un fichero del usuario —la lista sobre la que decide no puede
/// contener otra cosa— y es un ámbito *no sensible*, así que la pantalla de
/// consentimiento no necesita verificación de Google ni evaluación de seguridad.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'nube.dart';
import 'token.dart';

/// Las credenciales entran por `--dart-define`, desde secretos de CI, igual que
/// entra `VERSION`. **No se escriben en el repositorio.**
const _clienteId = String.fromEnvironment('GOOGLE_CLIENT_ID');
const _clienteSecreto = String.fromEnvironment('GOOGLE_CLIENT_SECRET');

/// Si esta compilación lleva destino configurado.
///
/// Cuando es `false` la copia automática **no existe**: no hay grupo en Ajustes
/// y no hay disparador que haga nada. Un fork compila y funciona sin tocar nada.
bool get driveDisponible => _clienteId.isNotEmpty;

/// La carpeta donde se dejan las copias, dentro del Drive del usuario.
const carpetaCopias = 'AppGym';

const _tipoCarpeta = 'application/vnd.google-apps.folder';
const _ambitos = 'openid email https://www.googleapis.com/auth/drive.file';

/// Cuánto se espera a que el usuario termine en el navegador.
const _plazoConsentimiento = Duration(minutes: 5);

class DriveNube implements DestinoNube {
  DriveNube({
    http.Client? cliente,
    AlmacenToken? almacen,
    Future<bool> Function(Uri)? abrirNavegador,
    this.clienteId = _clienteId,
    this.clienteSecreto = _clienteSecreto,
  }) : _http = cliente ?? http.Client(),
       _almacen = almacen ?? const AlmacenSeguro(),
       _abrir =
           abrirNavegador ??
           ((uri) => launchUrl(uri, mode: LaunchMode.externalApplication));

  final http.Client _http;
  final AlmacenToken _almacen;
  final Future<bool> Function(Uri) _abrir;
  final String clienteId;
  final String clienteSecreto;

  /// El token de acceso vivo y cuándo caduca. Solo en memoria: se renueva solo
  /// desde el *refresh token*, que es lo único que se persiste.
  String? _acceso;
  DateTime? _caduca;

  /// El id de la carpeta, resuelto una vez por arranque.
  String? _carpeta;

  @override
  String get nombre => 'Google Drive';

  // ── Cuenta ─────────────────────────────────────────────────────────────────

  @override
  Future<String> conectar([String mensajeVuelta = 'Vuelve a AppGym.']) async {
    final verificador = _verificador();
    final servidor = await _escuchar();

    try {
      final redireccion = 'http://127.0.0.1:${servidor.port}';
      final autorizacion = Uri.https(
        'accounts.google.com',
        '/o/oauth2/v2/auth',
        {
          'client_id': clienteId,
          'redirect_uri': redireccion,
          'response_type': 'code',
          'scope': _ambitos,
          'code_challenge': _reto(verificador),
          'code_challenge_method': 'S256',
          // Sin `offline` no viene refresh token, y sin él habría que volver a
          // pasar por el navegador cada hora: la copia dejaría de ser
          // automática en cuanto caducara el primer acceso.
          'access_type': 'offline',
          // Google solo entrega el refresh token la primera vez que se
          // consiente; forzando el consentimiento, volver a conectar tras
          // desconectar también lo trae.
          'prompt': 'consent',
        },
      );

      if (!await _abrir(autorizacion)) {
        throw const ErrorNube.rechazado('No se pudo abrir el navegador.');
      }

      final codigo = await _esperarCodigo(servidor, mensajeVuelta);
      return await _canjear(codigo, verificador, redireccion);
    } finally {
      await servidor.close(force: true);
    }
  }

  @override
  Future<void> desconectar() async {
    final refresco = await _almacen.leer();
    _acceso = null;
    _caduca = null;
    _carpeta = null;
    await _almacen.escribir(null);

    if (refresco == null) return;
    try {
      // Revocar es cortesía y es lo correcto, pero que falle no puede impedir
      // desconectar: el token local ya no está, que es lo que el usuario pidió.
      await _http.post(
        Uri.https('oauth2.googleapis.com', '/revoke'),
        body: {'token': refresco},
      );
    } on Object {
      // Nada.
    }
  }

  // ── Ficheros ───────────────────────────────────────────────────────────────

  @override
  Future<List<CopiaRemota>> listar() async {
    final carpeta = await _carpetaCopias();
    final respuesta = await _pedir(
      'GET',
      Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q': "'$carpeta' in parents and trashed = false",
        'fields': 'files(id,name,createdTime)',
        'orderBy': 'createdTime desc',
        'pageSize': '100',
      }),
    );

    final ficheros = (_json(respuesta)['files'] as List?) ?? const [];
    return [
      for (final fichero in ficheros.cast<Map<String, dynamic>>())
        if (fichero['id'] case final String id)
          CopiaRemota(
            id: id,
            nombre: '${fichero['name']}',
            creada:
                DateTime.tryParse('${fichero['createdTime']}') ??
                DateTime.fromMillisecondsSinceEpoch(0),
          ),
    ];
  }

  @override
  Future<void> subir(String nombre, String contenido) async {
    final carpeta = await _carpetaCopias();
    final existente = (await listar())
        .where((copia) => copia.nombre == nombre)
        .firstOrNull;

    // Reemplazar en vez de duplicar: dos copias del mismo día son la misma
    // copia, y el nombre lleva la fecha.
    if (existente != null) {
      await _pedir(
        'PATCH',
        Uri.https(
          'www.googleapis.com',
          '/upload/drive/v3/files/${existente.id}',
          {'uploadType': 'media'},
        ),
        cuerpo: utf8.encode(contenido),
        tipo: 'application/json; charset=utf-8',
      );
      return;
    }

    const frontera = 'appgym-limite-de-parte';
    final metadatos = jsonEncode({
      'name': nombre,
      'parents': [carpeta],
    });
    final cuerpo = utf8.encode(
      '--$frontera\r\n'
      'Content-Type: application/json; charset=UTF-8\r\n\r\n'
      '$metadatos\r\n'
      '--$frontera\r\n'
      'Content-Type: application/json; charset=UTF-8\r\n\r\n'
      '$contenido\r\n'
      '--$frontera--\r\n',
    );

    await _pedir(
      'POST',
      Uri.https('www.googleapis.com', '/upload/drive/v3/files', {
        'uploadType': 'multipart',
      }),
      cuerpo: cuerpo,
      tipo: 'multipart/related; boundary=$frontera',
    );
  }

  @override
  Future<void> borrar(String id) =>
      _pedir('DELETE', Uri.https('www.googleapis.com', '/drive/v3/files/$id'));

  /// El id de la carpeta, buscándola o creándola.
  ///
  /// Se resuelve una vez por arranque y se guarda en memoria. No se persiste a
  /// propósito: un id guardado que apunte a una carpeta que el usuario borró
  /// desde Drive dejaría la copia rota para siempre, y buscarla cuesta una
  /// petición al día.
  Future<String> _carpetaCopias() async {
    if (_carpeta case final id?) return id;

    final respuesta = await _pedir(
      'GET',
      Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q':
            "name = '$carpetaCopias' and mimeType = '$_tipoCarpeta' "
            'and trashed = false',
        'fields': 'files(id)',
      }),
    );
    final encontradas = (_json(respuesta)['files'] as List?) ?? const [];
    if (encontradas.isNotEmpty) {
      return _carpeta = '${(encontradas.first as Map)['id']}';
    }

    final creada = await _pedir(
      'POST',
      Uri.https('www.googleapis.com', '/drive/v3/files', {'fields': 'id'}),
      cuerpo: utf8.encode(
        jsonEncode({'name': carpetaCopias, 'mimeType': _tipoCarpeta}),
      ),
      tipo: 'application/json; charset=utf-8',
    );
    return _carpeta = '${_json(creada)['id']}';
  }

  // ── PKCE y el bucle local ──────────────────────────────────────────────────

  /// 48 bytes de aleatoriedad criptográfica en base64url, que son 64 caracteres
  /// — dentro del rango 43–128 que exige RFC 7636.
  String _verificador() {
    final azar = Random.secure();
    final bytes = List<int>.generate(48, (_) => azar.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  String _reto(String verificador) => base64UrlEncode(
    sha256.convert(ascii.encode(verificador)).bytes,
  ).replaceAll('=', '');

  Future<HttpServer> _escuchar() async {
    try {
      return await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    } on SocketException catch (e) {
      throw ErrorNube.temporal(
        'No se pudo abrir el puerto local: ${e.message}',
      );
    }
  }

  /// Espera la redirección del navegador y devuelve el código.
  ///
  /// Contesta con una página mínima porque el navegador se queda abierto en
  /// ella: sin nada que leer, el usuario no sabe que ya puede volver.
  Future<String> _esperarCodigo(HttpServer servidor, String mensaje) async {
    final peticion = await servidor.first.timeout(
      _plazoConsentimiento,
      onTimeout: () => throw const ErrorNube.rechazado(
        'Se agotó el tiempo de espera del navegador.',
      ),
    );

    final codigo = peticion.uri.queryParameters['code'];
    final error = peticion.uri.queryParameters['error'];

    peticion.response
      ..statusCode = 200
      ..headers.contentType = ContentType.html
      ..write(
        '<!doctype html><meta charset="utf-8">'
        '<title>AppGym</title>'
        '<body style="font:16px system-ui;text-align:center;padding:3em">'
        '<p>${const HtmlEscape().convert(mensaje)}</p>',
      );
    await peticion.response.close();

    if (error != null) {
      throw ErrorNube.rechazado('El acceso no se concedió: $error.');
    }
    if (codigo == null) {
      throw const ErrorNube.rechazado(
        'El navegador no devolvió ningún código.',
      );
    }
    return codigo;
  }

  /// Cambia el código por los tokens y devuelve el correo de la cuenta.
  Future<String> _canjear(
    String codigo,
    String verificador,
    String redireccion,
  ) async {
    final datos = await _tokens({
      'code': codigo,
      'client_id': clienteId,
      'client_secret': clienteSecreto,
      'redirect_uri': redireccion,
      'grant_type': 'authorization_code',
      'code_verifier': verificador,
    });

    final refresco = datos['refresh_token'] as String?;
    if (refresco == null) {
      throw const ErrorNube.rechazado(
        'Google no devolvió un permiso duradero. Vuelve a intentarlo.',
      );
    }
    await _almacen.escribir(refresco);

    return _correoDe(datos['id_token'] as String?) ?? 'Google Drive';
  }

  /// El correo que viene dentro del `id_token`.
  ///
  /// **No se verifica la firma, y no hace falta**: el token no ha llegado por
  /// el navegador sino de una respuesta directa del endpoint de Google sobre
  /// TLS. Se lee solo para tener algo que enseñar en Ajustes; nada depende de
  /// él. Si viniera ilegible, se enseña el nombre del destino.
  String? _correoDe(String? idToken) {
    if (idToken == null) return null;
    try {
      final partes = idToken.split('.');
      if (partes.length < 2) return null;
      final relleno = '=' * ((4 - partes[1].length % 4) % 4);
      final carga = jsonDecode(
        utf8.decode(base64Url.decode(partes[1] + relleno)),
      );
      return carga is Map && carga['email'] is String
          ? carga['email'] as String
          : null;
    } on Object {
      return null;
    }
  }

  // ── Token de acceso ────────────────────────────────────────────────────────

  /// Un token de acceso válido, renovándolo si hace falta.
  ///
  /// Se renueva un minuto antes de caducar: pedir con un token que expira
  /// mientras vuela es un 401 evitable.
  Future<String> _accesoVivo() async {
    final vigente = _acceso;
    final caduca = _caduca;
    if (vigente != null &&
        caduca != null &&
        DateTime.now().isBefore(caduca.subtract(const Duration(minutes: 1)))) {
      return vigente;
    }

    final refresco = await _almacen.leer();
    if (refresco == null) {
      throw const ErrorNube.reconectar('No hay ninguna cuenta conectada.');
    }

    final datos = await _tokens({
      'client_id': clienteId,
      'client_secret': clienteSecreto,
      'refresh_token': refresco,
      'grant_type': 'refresh_token',
    });

    final acceso = datos['access_token'] as String?;
    if (acceso == null) {
      throw const ErrorNube.reconectar(
        'Google no devolvió un token de acceso.',
      );
    }
    _acceso = acceso;
    _caduca = DateTime.now().add(
      Duration(seconds: (datos['expires_in'] as num?)?.toInt() ?? 3600),
    );
    return acceso;
  }

  Future<Map<String, dynamic>> _tokens(Map<String, String> campos) async {
    final respuesta = await _enviar(
      () => _http.post(
        Uri.https('oauth2.googleapis.com', '/token'),
        body: campos,
      ),
    );

    if (respuesta.statusCode != 200) {
      final cuerpo = _jsonBlando(respuesta);
      final error = '${cuerpo['error'] ?? respuesta.statusCode}';
      // `invalid_grant` es el permiso revocado, el token caducado por desuso o
      // la cuenta cerrada. Reintentarlo no lo arregla nunca: hay que volver a
      // pasar por el navegador.
      throw error == 'invalid_grant'
          ? const ErrorNube.reconectar(
              'El permiso ya no vale. Vuelve a conectar la cuenta.',
            )
          : ErrorNube.rechazado('Google rechazó la petición: $error.');
    }
    return _json(respuesta);
  }

  // ── Peticiones ─────────────────────────────────────────────────────────────

  /// Una petición autenticada, reintentando **una** vez tras renovar el token.
  ///
  /// El 401 se da cuando el acceso caducó antes de lo previsto o Google lo
  /// invalidó; renovar y repetir lo arregla sin molestar al usuario. Si vuelve
  /// a fallar, es que el permiso no está.
  Future<http.Response> _pedir(
    String metodo,
    Uri url, {
    List<int>? cuerpo,
    String? tipo,
  }) async {
    var respuesta = await _lanzar(
      metodo,
      url,
      await _accesoVivo(),
      cuerpo,
      tipo,
    );
    if (respuesta.statusCode == 401) {
      _acceso = null;
      _caduca = null;
      respuesta = await _lanzar(metodo, url, await _accesoVivo(), cuerpo, tipo);
    }

    if (respuesta.statusCode >= 200 && respuesta.statusCode < 300) {
      return respuesta;
    }
    throw _comoError(respuesta);
  }

  Future<http.Response> _lanzar(
    String metodo,
    Uri url,
    String acceso,
    List<int>? cuerpo,
    String? tipo,
  ) {
    final peticion = http.Request(metodo, url)
      ..headers['Authorization'] = 'Bearer $acceso';
    if (tipo != null) peticion.headers['Content-Type'] = tipo;
    if (cuerpo != null) peticion.bodyBytes = cuerpo;

    return _enviar(
      () async => http.Response.fromStream(await _http.send(peticion)),
    );
  }

  /// Envuelve cualquier envío para convertir los fallos de red en [ErrorNube]
  /// temporales. En el gimnasio no hay cobertura la mitad de las veces y eso no
  /// puede llegar a la interfaz como una excepción sin traducir.
  Future<http.Response> _enviar(Future<http.Response> Function() envio) async {
    try {
      return await envio();
    } on SocketException catch (e) {
      throw ErrorNube.temporal('Sin conexión: ${e.message}');
    } on http.ClientException catch (e) {
      throw ErrorNube.temporal('La conexión se cortó: ${e.message}');
    } on TimeoutException {
      throw const ErrorNube.temporal('La conexión tardó demasiado.');
    }
  }

  ErrorNube _comoError(http.Response respuesta) {
    final cuerpo = _jsonBlando(respuesta);
    final error = cuerpo['error'];
    final mensaje = error is Map
        ? '${error['message']}'
        : respuesta.reasonPhrase;

    return switch (respuesta.statusCode) {
      401 || 403 when '$mensaje'.contains('insufficient') =>
        const ErrorNube.reconectar(
          'Falta el permiso sobre Drive. Vuelve a conectar la cuenta.',
        ),
      // 429 y 5xx son del servidor o de la cuota por minuto: se pasan solos.
      429 => const ErrorNube.temporal('Demasiadas peticiones seguidas.'),
      >= 500 => ErrorNube.temporal('Drive no responde ($mensaje).'),
      _ => ErrorNube.rechazado('Drive rechazó la copia: $mensaje.'),
    };
  }

  Map<String, dynamic> _json(http.Response respuesta) {
    final decodificado = jsonDecode(utf8.decode(respuesta.bodyBytes));
    return decodificado is Map<String, dynamic> ? decodificado : {};
  }

  /// Como [_json] pero sin lanzar: se usa al componer mensajes de error, donde
  /// un cuerpo que no sea JSON no puede provocar un segundo fallo.
  Map<String, dynamic> _jsonBlando(http.Response respuesta) {
    try {
      return _json(respuesta);
    } on Object {
      return const {};
    }
  }
}
