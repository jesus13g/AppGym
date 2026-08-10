/// El adaptador del servidor de AppGym. **El único fichero del proyecto que sabe
/// cómo se habla con él.**
///
/// ── Un servidor propio, y por qué ─────────────────────────────────────────────
///
/// La especificación evaluó tres caminos en K2 y recomendó un BaaS gestionado
/// —opción B, Supabase— «con el protocolo diseñado para no depender de B». La
/// decisión se ha reabierto y cerrado en la **C: servidor propio** (`servidor/`,
/// FastAPI y PostgreSQL). Lo que hace que ese cambio sea un fichero y no una
/// reescritura es justamente la promesa que K2 dejó por escrito: el motor de
/// reconciliación no importa el SDK de nadie, habla con `SincroTransporte`.
///
/// Cambiar otra vez de proveedor sigue siendo escribir otro fichero como este.
///
/// ── Sigue sin haber ningún SDK ────────────────────────────────────────────────
///
/// Se habla REST con el `http` que ya estaba, exactamente igual que
/// `datos/nube/drive.dart` habla con Drive. Con servidor propio la tentación del
/// SDK ni siquiera existe: la API son nueve rutas escritas para este cliente.
///
/// ── Lo que este adaptador hace y `drive.dart` no ──────────────────────────────
///
/// Dos cosas, y las dos costarían la sesión del usuario si se copiara
/// `drive.dart` sin pensar:
///
///   1. **El servidor rota el refresco**: cada renovación devuelve uno nuevo e
///      **invalida el anterior**, y además, si el viejo vuelve a aparecer, revoca
///      la cadena entera por si lo ha robado alguien. Google no rota, así que
///      `drive.dart` guarda el suyo una vez y no vuelve a tocarlo. Aquí hay que
///      reescribir el almacén en cada renovación o la sesión muere a la segunda.
///   2. **Solo puede haber una renovación en vuelo.** Dos peticiones que caduquen
///      a la vez canjearían el mismo refresco dos veces, y la segunda llegaría con
///      uno ya gastado: el servidor lo tomaría por un robo y cerraría la sesión.
///      Por eso [_renovando] comparte el `Future`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../nube/token.dart';
import 'anclaje.dart';
import 'transporte.dart';

/// El servidor al que se sincroniza, con esquema y sin barra final:
/// `https://appgym.tudominio.com`. Entra por `--dart-define` desde un secreto de
/// CI, igual que entran `VERSION` y las credenciales de Drive.
const _url = String.fromEnvironment('API_URL');

/// Si esta compilación lleva servidor configurado.
///
/// Cuando es `false` la sincronización **no existe**: `sincroProvider` da `null`,
/// el grupo de Ajustes no se pinta y no hay disparador que haga nada. Un *fork* o
/// una compilación local funcionan sin tocar nada, igual que hoy ponen `local` en
/// la versión.
bool get sincroDisponible => _url.isNotEmpty;

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

class SincroServidor implements SincroTransporte {
  SincroServidor({
    http.Client? cliente,
    AlmacenToken? almacen,
    this.url = _url,
    this.filasPorLote = 200,
  }) : _almacen = almacen ?? const AlmacenSeguro(clave: claveSincro) {
    _cliente = cliente;
  }

  final AlmacenToken _almacen;
  final String url;

  /// Cuántas filas van en cada envío de [subir].
  ///
  /// El primer enlace de un histórico de dos años son miles de filas, y mandarlas
  /// en un solo cuerpo de varios megas por la wifi del gimnasio es pedir un
  /// tiempo agotado. Cada lote es atómico en el servidor por su cuenta.
  final int filasPorLote;

  /// El cliente HTTP. Se construye **la primera vez que hace falta** y no en el
  /// constructor: si el anclaje de esta compilación estuviera mal puesto, montarlo
  /// al arrancar tiraría la app entera en vez de dejarla sin sincronizar.
  http.Client? _cliente;

  /// La sesión, cacheada tras la primera lectura del almacén.
  _Sesion? _sesion;
  bool _leida = false;

  /// El token de acceso vivo y cuándo caduca. **Solo en memoria**: lo único que
  /// se persiste es lo que permite renovarlo.
  String? _acceso;
  DateTime? _caduca;

  /// La renovación en vuelo, si la hay. Ver la nota de la cabecera.
  Future<String>? _renovando;

  http.Client get _http {
    final ya = _cliente;
    if (ya != null) return ya;
    try {
      return _cliente = IOClient(clienteAnclado());
    } on Object catch (e) {
      throw ErrorSincro.rechazado(
        'El anclaje de certificado de esta compilación no vale ($e).',
      );
    }
  }

  // ── La cuenta ──────────────────────────────────────────────────────────────

  @override
  Future<SesionRemota?> sesionActual() async => (await _leerSesion())?.remota;

  @override
  Future<SesionRemota> registrar(String correo, String contrasena) =>
      _abrirSesion('/auth/registro', correo, contrasena);

  @override
  Future<SesionRemota> entrar(String correo, String contrasena) =>
      _abrirSesion('/auth/entrar', correo, contrasena);

  Future<SesionRemota> _abrirSesion(
    String camino,
    String correo,
    String contrasena,
  ) async {
    final respuesta = await _enviar(
      () => _http.post(
        _ruta(camino),
        headers: _cabeceras,
        body: jsonEncode({'correo': correo.trim(), 'contrasena': contrasena}),
      ),
    );
    if (!_correcta(respuesta)) throw _errorAuth(respuesta);

    final datos = _json(respuesta);
    final refresco = datos['refresco'] as String?;
    final acceso = datos['acceso'] as String?;
    if (refresco == null || acceso == null) {
      throw const ErrorSincro.rechazado(
        'El servidor no devolvió una sesión utilizable.',
      );
    }

    final usuario = datos['usuario'];
    final sesion = _Sesion(
      id: usuario is Map ? '${usuario['id']}' : '',
      correo: usuario is Map && usuario['correo'] is String
          ? usuario['correo'] as String
          : correo.trim(),
      refresco: refresco,
    );
    await _guardarSesion(sesion);
    _fijarAcceso(acceso, datos['expira_en']);
    return sesion.remota;
  }

  @override
  Future<void> salir() async {
    final sesion = await _leerSesion();
    if (sesion != null) {
      try {
        // Revoca **este** refresco y solo este: cerrar sesión en el móvil no
        // puede cerrar la de la tableta. K3 dice «un usuario, N dispositivos».
        await _enviar(
          () => _http.post(
            _ruta('/auth/salir'),
            headers: _cabeceras,
            body: jsonEncode({'refresco': sesion.refresco}),
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
    await _pedir('DELETE', '/auth/cuenta');
    // La cuenta ya no existe: quedarse con su sesión solo daría errores raros.
    await _olvidar();
  }

  // ── Los datos ──────────────────────────────────────────────────────────────

  @override
  Future<Paquete> bajar(int cursor) async {
    final datos = await _pedir(
      'GET',
      '/sincro/bajar',
      consulta: {'cursor': '$cursor'},
    );
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
      final datos = await _pedir(
        'POST',
        '/sincro/subir',
        cuerpo: {
          'filas': [
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
        },
      );

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
  Future<void> vaciar() async {
    await _pedir('POST', '/sincro/vaciar');
  }

  @override
  Future<Cifras> resumen() async {
    final datos = await _pedir('GET', '/sincro/resumen');
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
      Duration(seconds: (caducaEn as num?)?.toInt() ?? 900),
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
        _ruta('/auth/refrescar'),
        headers: _cabeceras,
        body: jsonEncode({'refresco': sesion.refresco}),
      ),
    );

    if (!_correcta(respuesta)) {
      final error = _comoError(respuesta);
      // Una sesión muerta de verdad —el refresco ya se canjeó, caducó por desuso
      // o la cuenta se borró desde otro sitio— se olvida aquí, para que Ajustes
      // deje de decir que hay cuenta. Un fallo temporal **no** borra nada.
      if (error.motivo != MotivoSincro.temporal) {
        await _olvidar();
        throw ErrorSincro.reconectar(error.mensaje);
      }
      throw error;
    }

    final datos = _json(respuesta);
    final acceso = datos['acceso'] as String?;
    if (acceso == null) {
      throw const ErrorSincro.reconectar(
        'El servidor no devolvió un token de acceso.',
      );
    }

    // El servidor **rota** el refresco: el anterior ya no vale y hay que guardar
    // el nuevo, o la próxima renovación llegaría con uno gastado y el servidor la
    // tomaría por un robo.
    final refresco = datos['refresco'] as String?;
    if (refresco != null && refresco != sesion.refresco) {
      await _guardarSesion(
        _Sesion(id: sesion.id, correo: sesion.correo, refresco: refresco),
      );
    }

    _fijarAcceso(acceso, datos['expira_en']);
    return acceso;
  }

  // ── Peticiones ─────────────────────────────────────────────────────────────

  /// Una llamada a la API, ya autenticada.
  Future<Map<String, dynamic>> _pedir(
    String metodo,
    String camino, {
    Map<String, Object?>? cuerpo,
    Map<String, String>? consulta,
  }) async {
    final ruta = _ruta(camino, consulta);
    final texto = cuerpo == null ? null : jsonEncode(cuerpo);

    var respuesta = await _lanzar(metodo, ruta, await _accesoVivo(), texto);
    // El 401 se da cuando el acceso caducó antes de lo previsto o el servidor lo
    // invalidó; renovar y repetir lo arregla sin molestar al usuario. Si vuelve
    // a fallar, el permiso no está.
    if (respuesta.statusCode == 401) {
      _acceso = null;
      _caduca = null;
      respuesta = await _lanzar(metodo, ruta, await _accesoVivo(), texto);
    }

    if (!_correcta(respuesta)) throw _comoError(respuesta);
    return _json(respuesta);
  }

  Future<http.Response> _lanzar(
    String metodo,
    Uri ruta,
    String acceso,
    String? cuerpo,
  ) {
    final cabeceras = {..._cabeceras, 'Authorization': 'Bearer $acceso'};
    return _enviar(() {
      switch (metodo) {
        case 'GET':
          return _http.get(ruta, headers: cabeceras);
        case 'DELETE':
          return _http.delete(ruta, headers: cabeceras);
        default:
          return _http.post(ruta, headers: cabeceras, body: cuerpo);
      }
    });
  }

  /// Envuelve cualquier envío para convertir los fallos de red en [ErrorSincro].
  /// En el gimnasio no hay cobertura la mitad de las veces y eso no puede llegar
  /// a la interfaz como una excepción sin traducir.
  Future<http.Response> _enviar(Future<http.Response> Function() envio) async {
    try {
      return await envio().timeout(_plazo);
    } on TlsException catch (e) {
      // El anclaje no cuadra: o el certificado del servidor no es el que esta
      // compilación acepta, o hay algo por el medio leyendo el tráfico.
      // Reintentar no lo arregla, así que no es un fallo temporal.
      throw ErrorSincro.rechazado(
        'No se ha podido verificar el servidor: ${e.message}',
      );
    } on SocketException catch (e) {
      throw ErrorSincro.temporal('Sin conexión: ${e.message}');
    } on http.ClientException catch (e) {
      throw ErrorSincro.temporal('La conexión se cortó: ${e.message}');
    } on TimeoutException {
      throw const ErrorSincro.temporal('La conexión tardó demasiado.');
    }
  }

  Map<String, String> get _cabeceras => const {
    'Content-Type': 'application/json',
  };

  Uri _ruta(String camino, [Map<String, String>? consulta]) =>
      Uri.parse('$url$camino').replace(queryParameters: consulta);

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
  /// Van por separado de los de la cuenta: **un 400 no significa lo mismo en los
  /// dos sitios**. Aquí es un rechazo del servidor; al entrar es «esa contraseña
  /// no es», que es una frase que el usuario tiene que leer.
  ErrorSincro _comoError(http.Response respuesta) {
    final mensaje = _mensaje(respuesta);

    return switch (respuesta.statusCode) {
      // Ya se reintentó una vez tras renovar; si vuelve, la sesión no vale.
      401 => ErrorSincro.reconectar(mensaje),
      403 => ErrorSincro.reconectar(mensaje),
      // La ruta no existe: el servidor de esa URL no es el de AppGym, o es de una
      // versión anterior. No se arregla reintentando.
      404 => ErrorSincro.rechazado(
        'El servidor no tiene la API de AppGym ($mensaje).',
      ),
      429 => ErrorSincro.temporal(mensaje),
      >= 500 => ErrorSincro.temporal('El servidor no responde ($mensaje).'),
      _ => ErrorSincro.rechazado(
        'El servidor rechazó la sincronización: $mensaje.',
      ),
    };
  }

  /// Los fallos de la cuenta. El mensaje del servidor se pasa **tal cual**,
  /// porque es el que le explica al usuario qué ha pasado.
  ErrorSincro _errorAuth(http.Response respuesta) {
    final mensaje = _mensaje(respuesta);

    return switch (respuesta.statusCode) {
      // Credenciales que no valen, contraseña corta, correo ya registrado o
      // registro cerrado. Se arregla tecleando otra cosa, así que no se reintenta.
      400 || 401 || 403 || 409 || 422 => ErrorSincro.rechazado(mensaje),
      429 => ErrorSincro.temporal(mensaje),
      >= 500 => ErrorSincro.temporal('El servidor no responde ($mensaje).'),
      _ => ErrorSincro.rechazado(mensaje),
    };
  }

  /// La frase del servidor, o algo razonable si el cuerpo no es lo esperado.
  String _mensaje(http.Response respuesta) {
    try {
      final cuerpo = _json(respuesta);
      final mensaje = cuerpo['mensaje'] ?? cuerpo['detail'];
      if (mensaje != null) return '$mensaje';
    } on Object {
      // Un cuerpo que no sea JSON no puede provocar un segundo fallo.
    }
    return respuesta.reasonPhrase ?? 'error ${respuesta.statusCode}';
  }

  /// El cuerpo, o un mapa vacío. Las rutas que no devuelven nada contestan 204.
  Map<String, dynamic> _json(http.Response respuesta) {
    if (respuesta.bodyBytes.isEmpty) return {};
    final decodificado = jsonDecode(utf8.decode(respuesta.bodyBytes));
    return decodificado is Map<String, dynamic> ? decodificado : {};
  }
}
