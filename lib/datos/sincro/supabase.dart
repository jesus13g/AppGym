/// El adaptador de Supabase. **El único fichero del proyecto que sabe que
/// Supabase existe.**
///
/// ── Ningún SDK ────────────────────────────────────────────────────────────────
///
/// `supabase_flutter` arrastraría `gotrue`, `postgrest`, `realtime`, `storage` y
/// `functions_client` —con sus *websockets*, sus *deep links* y sus preferencias
/// compartidas— para usar dos endpoints de autenticación y cuatro llamadas RPC.
/// Sería con diferencia la dependencia más grande del proyecto, más que `drift`,
/// y pondría en riesgo el techo de `win32` que hoy fija `file_picker ^11` y que
/// ya mantiene a `share_plus` en la 12 y a `flutter_secure_storage` en la 9.
///
/// Se habla REST con el `http` que ya estaba, exactamente por el mismo motivo y
/// con la misma forma que `datos/nube/drive.dart`: *ningún SDK de Google, Drive
/// se habla por REST v3*. Cambiar de proveedor sigue siendo escribir otro
/// fichero como este.
///
/// ── Entrar es un código, no un enlace ─────────────────────────────────────────
///
/// Ver la nota de `entrar` en `transporte.dart`. En corto: un enlace mágico
/// exige *deep links*, un *intent-filter* y un dominio, y aquí el APK se instala
/// a mano desde una release.
///
/// ── Lo que este adaptador hace y `drive.dart` no ──────────────────────────────
///
/// Dos cosas, y las dos costarían la sesión del usuario si se copiara `drive.dart`
/// sin pensar:
///
///   1. **GoTrue rota el *refresh token***: cada renovación devuelve uno nuevo y
///      **invalida el anterior**. Google no lo hace, así que `drive.dart` guarda
///      el suyo una vez y no vuelve a tocarlo. Aquí hay que reescribir el almacén
///      en cada renovación o la sesión muere a la segunda.
///   2. **Solo puede haber una renovación en vuelo.** Dos peticiones que caduquen
///      a la vez canjearían el mismo *refresh token* dos veces, y la segunda
///      llegaría con uno ya gastado: sesión muerta y el usuario sin entender por
///      qué. Por eso [_renovando] comparte el `Future`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../nube/token.dart';
import 'transporte.dart';

/// El proyecto al que se sincroniza. Entra por `--dart-define` desde secretos de
/// CI, igual que entran `VERSION` y las credenciales de Drive. **No se escriben
/// en el repositorio.**
const _url = String.fromEnvironment('SUPABASE_URL');

/// La clave pública del proyecto. Es pública **por diseño**: lo que protege los
/// datos es la RLS del servidor, no el secreto de esta cadena. Se guarda como
/// secreto de todas formas, para no regalar la cuota del proyecto.
const _clavePublica = String.fromEnvironment('SUPABASE_ANON_KEY');

/// Si esta compilación lleva servicio configurado.
///
/// Cuando es `false` la sincronización **no existe**: `sincroProvider` da `null`,
/// el grupo de Ajustes no se pinta y no hay disparador que haga nada. Un *fork* o
/// una compilación local funcionan sin tocar nada, igual que hoy ponen `local` en
/// la versión.
bool get sincroDisponible => _url.isNotEmpty && _clavePublica.isNotEmpty;

/// Lo que se espera a una petición antes de darla por perdida.
const _plazo = Duration(seconds: 30);

/// La sesión guardada: quién es, con qué correo y con qué puede renovarse.
class _Sesion {
  const _Sesion({
    required this.id,
    required this.correo,
    required this.refresco,
  });

  final String id;
  final String correo;
  final String refresco;

  Map<String, Object?> aJson() => {
    'id': id,
    'correo': correo,
    'refresco': refresco,
  };

  /// `null` si el JSON no tiene lo que hace falta, para que una sesión a medias
  /// se trate como «no hay cuenta» en vez de reventar al arrancar.
  static _Sesion? deJson(String texto) {
    try {
      final json = jsonDecode(texto);
      if (json is! Map) return null;
      final id = json['id'];
      final correo = json['correo'];
      final refresco = json['refresco'];
      if (id is! String || correo is! String || refresco is! String) {
        return null;
      }
      return _Sesion(id: id, correo: correo, refresco: refresco);
    } on Object {
      return null;
    }
  }

  SesionRemota get remota => SesionRemota(id: id, correo: correo);
}

class SincroSupabase implements SincroTransporte {
  SincroSupabase({
    http.Client? cliente,
    AlmacenToken? almacen,
    this.url = _url,
    this.clavePublica = _clavePublica,
    this.filasPorLote = 200,
  }) : _http = cliente ?? http.Client(),
       _almacen = almacen ?? const AlmacenSeguro(clave: claveSincro);

  final http.Client _http;
  final AlmacenToken _almacen;
  final String url;
  final String clavePublica;

  /// Cuántas filas van en cada envío de [subir].
  ///
  /// El primer enlace de un histórico de dos años son miles de filas, y mandarlas
  /// en un solo cuerpo de varios megas por la wifi del gimnasio es pedir un
  /// tiempo agotado. Cada lote es atómico en el servidor por su cuenta.
  final int filasPorLote;

  /// La sesión, cacheada tras la primera lectura del almacén.
  _Sesion? _sesion;
  bool _leida = false;

  /// El token de acceso vivo y cuándo caduca. **Solo en memoria**: lo único que
  /// se persiste es lo que permite renovarlo.
  String? _acceso;
  DateTime? _caduca;

  /// La renovación en vuelo, si la hay. Ver la nota de la cabecera.
  Future<String>? _renovando;

  // ── La cuenta ──────────────────────────────────────────────────────────────

  @override
  Future<SesionRemota?> sesionActual() async => (await _leerSesion())?.remota;

  @override
  Future<void> pedirCodigo(String correo) async {
    final respuesta = await _enviar(
      () => _http.post(
        _auth('/otp'),
        headers: _cabecerasAuth,
        // `create_user` es lo que hace que «crear cuenta» y «entrar» sean el
        // mismo botón, como pide K3.
        body: jsonEncode({'email': correo, 'create_user': true}),
      ),
    );
    if (!_correcta(respuesta)) throw _errorAuth(respuesta);
  }

  @override
  Future<SesionRemota> entrar(String correo, String codigo) async {
    final respuesta = await _enviar(
      () => _http.post(
        _auth('/verify'),
        headers: _cabecerasAuth,
        body: jsonEncode({
          'type': 'email',
          'email': correo,
          'token': codigo.trim(),
        }),
      ),
    );
    if (!_correcta(respuesta)) throw _errorAuth(respuesta);

    final datos = _json(respuesta);
    final refresco = datos['refresh_token'] as String?;
    final acceso = datos['access_token'] as String?;
    if (refresco == null || acceso == null) {
      throw const ErrorSincro.rechazado(
        'El servidor no devolvió una sesión utilizable.',
      );
    }

    final usuario = datos['user'];
    final sesion = _Sesion(
      id: usuario is Map ? '${usuario['id']}' : '',
      correo: usuario is Map && usuario['email'] is String
          ? usuario['email'] as String
          : correo,
      refresco: refresco,
    );
    await _guardarSesion(sesion);
    _fijarAcceso(acceso, datos['expires_in']);
    return sesion.remota;
  }

  @override
  Future<void> salir() async {
    final sesion = await _leerSesion();
    if (sesion != null && _acceso != null) {
      try {
        // `scope=local` a propósito: cerrar sesión en este móvil no puede cerrar
        // la de la tableta. K3 dice «un usuario, N dispositivos».
        await _enviar(
          () => _http.post(
            _auth('/logout', {'scope': 'local'}),
            headers: {..._cabecerasAuth, 'Authorization': 'Bearer $_acceso'},
          ),
        );
      } on ErrorSincro {
        // Que el servidor no se entere no puede impedir salir aquí. Es lo mismo
        // que hace `drive.desconectar` cuando la revocación falla.
      }
    }
    await _olvidar();
  }

  @override
  Future<void> borrarCuenta() async {
    await _rpc('appgym_borrar_cuenta');
    // La cuenta ya no existe: quedarse con su sesión solo daría errores raros.
    await _olvidar();
  }

  // ── Los datos ──────────────────────────────────────────────────────────────

  @override
  Future<Paquete> bajar(int cursor) async {
    final datos = await _rpc('appgym_bajar', {'p_cursor': cursor});
    final filas = datos['filas'];
    return Paquete([
      if (filas is List)
        for (final fila in filas)
          if (fila is Map) _fila(fila),
    ], cursor: (datos['cursor'] as num?)?.toInt() ?? cursor);
  }

  @override
  Future<RespuestaSubida> subir(Paquete paquete) async {
    final sellos = <String, int>{};
    int? previo;
    var cursor = 0;

    // En lotes. `cursorPrevio` es el del primer envío y `cursor` el del último:
    // todo lo que el servidor selló entre medias lo escribió este móvil, que es
    // exactamente lo que esa pareja significa para el motor.
    for (var i = 0; i < paquete.filas.length; i += filasPorLote) {
      final lote = paquete.filas.skip(i).take(filasPorLote).toList();
      final datos = await _rpc('appgym_subir', {
        'p_filas': [
          for (final fila in lote)
            {
              'tabla': fila.tabla,
              'clave': fila.clave,
              // El `actualizado` del cliente no se envía: el reloj es del
              // servidor y que sea imposible influir en él es mejor que
              // ignorarlo por convenio.
              'datos': fila.datos,
            },
        ],
      });

      final devueltos = datos['sellos'];
      if (devueltos is Map) {
        for (final entrada in devueltos.entries) {
          final sello = (entrada.value as num?)?.toInt();
          if (sello != null) sellos['${entrada.key}'] = sello;
        }
      }
      previo ??= (datos['cursorPrevio'] as num?)?.toInt();
      cursor = (datos['cursor'] as num?)?.toInt() ?? cursor;
    }

    // El motor no llega aquí con el paquete vacío (`motor.dart` corta antes con
    // `if (filas.isEmpty) return 0`), pero devolver ceros es lo honesto: no se
    // ha sellado nada y no hay cursor que mover.
    return RespuestaSubida(sellos, cursor: cursor, cursorPrevio: previo ?? 0);
  }

  @override
  Future<void> vaciar() => _rpc('appgym_vaciar');

  @override
  Future<Cifras> resumen() async {
    final datos = await _rpc('appgym_resumen');
    return Cifras(
      rutinas: (datos['rutinas'] as num?)?.toInt() ?? 0,
      sesiones: (datos['sesiones'] as num?)?.toInt() ?? 0,
    );
  }

  // ── La sesión guardada ─────────────────────────────────────────────────────

  Future<_Sesion?> _leerSesion() async {
    if (_leida) return _sesion;
    final texto = await _almacen.leer();
    _leida = true;
    if (texto == null) return _sesion = null;

    final sesion = _Sesion.deJson(texto);
    // Un JSON corrupto —o el token pelado de una versión anterior— no es una
    // sesión: se limpia, para que Ajustes no diga que hay cuenta cuando no la
    // hay y el usuario pueda volver a entrar.
    if (sesion == null) await _almacen.escribir(null);
    return _sesion = sesion;
  }

  Future<void> _guardarSesion(_Sesion sesion) async {
    _sesion = sesion;
    _leida = true;
    await _almacen.escribir(jsonEncode(sesion.aJson()));
  }

  Future<void> _olvidar() async {
    _sesion = null;
    _leida = true;
    _acceso = null;
    _caduca = null;
    _renovando = null;
    await _almacen.escribir(null);
  }

  void _fijarAcceso(String acceso, Object? caducaEn) {
    _acceso = acceso;
    _caduca = DateTime.now().add(
      Duration(seconds: (caducaEn as num?)?.toInt() ?? 3600),
    );
  }

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

    // Una sola renovación en vuelo: ver la nota de la cabecera. Quien llega
    // segundo espera al mismo `Future` en vez de canjear otra vez.
    //
    // El `Future` se limpia en un `finally` del que lo creó, y no con un
    // `whenComplete` sobre él: `whenComplete` devuelve **otro** `Future` que
    // nadie escucharía, y si la renovación falla ese quedaría con un error sin
    // atender.
    final enVuelo = _renovando;
    if (enVuelo != null) return enVuelo;

    final futuro = _renovar();
    _renovando = futuro;
    try {
      return await futuro;
    } finally {
      _renovando = null;
    }
  }

  Future<String> _renovar() async {
    final sesion = await _leerSesion();
    if (sesion == null) {
      throw const ErrorSincro.reconectar('No hay ninguna cuenta conectada.');
    }

    final respuesta = await _enviar(
      () => _http.post(
        _auth('/token', {'grant_type': 'refresh_token'}),
        headers: _cabecerasAuth,
        body: jsonEncode({'refresh_token': sesion.refresco}),
      ),
    );

    if (!_correcta(respuesta)) {
      final error = _errorAuth(respuesta);
      // Una sesión muerta de verdad —el token ya se canjeó, caducó por desuso o
      // la cuenta se borró desde otro sitio— se olvida aquí, para que Ajustes
      // deje de decir que hay cuenta. Un fallo temporal **no** borra nada.
      if (error.motivo != MotivoSincro.temporal) {
        await _olvidar();
        throw const ErrorSincro.reconectar(
          'La sesión ya no vale. Vuelve a entrar.',
        );
      }
      throw error;
    }

    final datos = _json(respuesta);
    final acceso = datos['access_token'] as String?;
    if (acceso == null) {
      throw const ErrorSincro.reconectar(
        'El servidor no devolvió un token de acceso.',
      );
    }

    // GoTrue rota el *refresh token*: el anterior ya no vale y hay que guardar
    // el nuevo o la próxima renovación fallará.
    final refresco = datos['refresh_token'] as String?;
    if (refresco != null && refresco != sesion.refresco) {
      await _guardarSesion(
        _Sesion(id: sesion.id, correo: sesion.correo, refresco: refresco),
      );
    }

    _fijarAcceso(acceso, datos['expires_in']);
    return acceso;
  }

  // ── Peticiones ─────────────────────────────────────────────────────────────

  /// Una llamada a una función del servidor, ya autenticada.
  Future<Map<String, dynamic>> _rpc(
    String funcion, [
    Map<String, Object?> argumentos = const {},
  ]) async {
    final url = Uri.parse('${this.url}/rest/v1/rpc/$funcion');
    final cuerpo = jsonEncode(argumentos);

    var respuesta = await _lanzar(url, await _accesoVivo(), cuerpo);
    // El 401 se da cuando el acceso caducó antes de lo previsto o el servidor lo
    // invalidó; renovar y repetir lo arregla sin molestar al usuario. Si vuelve
    // a fallar, el permiso no está.
    if (respuesta.statusCode == 401) {
      _acceso = null;
      _caduca = null;
      respuesta = await _lanzar(url, await _accesoVivo(), cuerpo);
    }

    if (!_correcta(respuesta)) throw _comoError(respuesta);
    final decodificado = jsonDecode(utf8.decode(respuesta.bodyBytes));
    // Las funciones que no devuelven nada contestan con `null`.
    return decodificado is Map<String, dynamic> ? decodificado : {};
  }

  Future<http.Response> _lanzar(Uri url, String acceso, String cuerpo) =>
      _enviar(
        () => _http.post(
          url,
          headers: {..._cabecerasAuth, 'Authorization': 'Bearer $acceso'},
          body: cuerpo,
        ),
      );

  /// Envuelve cualquier envío para convertir los fallos de red en [ErrorSincro]
  /// temporales. En el gimnasio no hay cobertura la mitad de las veces y eso no
  /// puede llegar a la interfaz como una excepción sin traducir.
  Future<http.Response> _enviar(Future<http.Response> Function() envio) async {
    try {
      return await envio().timeout(_plazo);
    } on SocketException catch (e) {
      throw ErrorSincro.temporal('Sin conexión: ${e.message}');
    } on http.ClientException catch (e) {
      throw ErrorSincro.temporal('La conexión se cortó: ${e.message}');
    } on TimeoutException {
      throw const ErrorSincro.temporal('La conexión tardó demasiado.');
    }
  }

  Map<String, String> get _cabecerasAuth => {
    'apikey': clavePublica,
    'Content-Type': 'application/json',
  };

  Uri _auth(String camino, [Map<String, String>? consulta]) =>
      Uri.parse('$url/auth/v1$camino').replace(queryParameters: consulta);

  bool _correcta(http.Response r) => r.statusCode >= 200 && r.statusCode < 300;

  FilaRemota _fila(Map<Object?, Object?> json) => FilaRemota(
    tabla: '${json['tabla']}',
    clave: '${json['clave']}',
    actualizado: (json['actualizado'] as num?)?.toInt() ?? 0,
    // `null` es la lápida, en las dos direcciones y sin caso especial.
    datos: (json['datos'] as Map?)?.cast<String, Object?>(),
  );

  // ── Los fallos ─────────────────────────────────────────────────────────────

  /// Los fallos de los datos.
  ///
  /// Van por separado de los de autenticación: **un 400 no significa lo mismo en
  /// los dos sitios**. Aquí es un rechazo del servidor; en `/verify` es «te has
  /// equivocado de código», que es una frase que el usuario tiene que leer.
  ErrorSincro _comoError(http.Response respuesta) {
    final cuerpo = _jsonBlando(respuesta);
    final mensaje =
        '${cuerpo['message'] ?? cuerpo['msg'] ?? respuesta.reasonPhrase}';

    return switch (respuesta.statusCode) {
      // Ya se reintentó una vez tras renovar; si vuelve, el permiso no está.
      401 => const ErrorSincro.reconectar(
        'La sesión ya no vale. Vuelve a entrar.',
      ),
      // La RLS o el `auth.uid() is null` de las funciones.
      403 => const ErrorSincro.reconectar(
        'La cuenta ya no tiene acceso. Vuelve a entrar.',
      ),
      // PGRST202: la función no existe. El esquema no está aplicado, y eso no se
      // arregla reintentando: hay que ejecutar `supabase/esquema.sql`.
      404 => ErrorSincro.rechazado(
        'El servidor no tiene el esquema de AppGym ($mensaje).',
      ),
      429 => const ErrorSincro.temporal('Demasiadas peticiones seguidas.'),
      >= 500 => ErrorSincro.temporal('El servidor no responde ($mensaje).'),
      _ => ErrorSincro.rechazado(
        'El servidor rechazó la sincronización: $mensaje.',
      ),
    };
  }

  /// Los fallos de la autenticación.
  ///
  /// El mensaje del servidor se pasa **tal cual**, porque es el que explica al
  /// usuario qué ha pasado con su código, igual que hace `copiaErrorImportar`.
  ErrorSincro _errorAuth(http.Response respuesta) {
    final cuerpo = _jsonBlando(respuesta);
    final mensaje =
        '${cuerpo['msg'] ?? cuerpo['error_description'] ?? cuerpo['message'] ?? respuesta.reasonPhrase}';

    return switch (respuesta.statusCode) {
      // Código mal escrito, caducado o ya usado. Se arregla tecleando otra vez,
      // así que no se reintenta solo.
      400 || 401 || 403 || 422 => ErrorSincro.rechazado(mensaje),
      429 => const ErrorSincro.temporal(
        'Demasiados intentos seguidos. Espera un momento.',
      ),
      >= 500 => ErrorSincro.temporal('El servidor no responde ($mensaje).'),
      _ => ErrorSincro.rechazado(mensaje),
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
