/// Dónde se guarda el *refresh token*.
///
/// **No en la tabla `ajustes`.** Esa tabla se exporta entera en la copia de
/// seguridad (`copia.dart`), y un token dentro de un JSON que el usuario
/// comparte por correo o sube a su Drive es una fuga con todas las letras. Va
/// al almacén seguro de la plataforma —Keystore en Android—, que es lo único
/// que no depende de que nadie se acuerde de excluirlo el día que amplíe la
/// exportación.
///
/// La interfaz existe para poder probar el adaptador de Drive sin plataforma:
/// `flutter_secure_storage` necesita un canal nativo que en `flutter test` no
/// hay.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Dos métodos: leer y escribir el token. Nada más hace falta.
abstract interface class AlmacenToken {
  Future<String?> leer();

  /// Con `null` se borra.
  Future<void> escribir(String? token);
}

/// El almacén de verdad, sobre el Keystore de Android.
class AlmacenSeguro implements AlmacenToken {
  const AlmacenSeguro();

  static const _clave = 'copia_nube_refresh_token';
  static const _almacen = FlutterSecureStorage(
    // `EncryptedSharedPreferences` es lo que respalda el valor con el Keystore
    // en vez de dejarlo en unas preferencias normales.
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  @override
  Future<String?> leer() => _almacen.read(key: _clave);

  @override
  Future<void> escribir(String? token) => token == null
      ? _almacen.delete(key: _clave)
      : _almacen.write(key: _clave, value: token);
}

/// Un almacén en memoria, para los tests.
class AlmacenEnMemoria implements AlmacenToken {
  AlmacenEnMemoria([this._token]);

  String? _token;

  @override
  Future<String?> leer() async => _token;

  @override
  Future<void> escribir(String? token) async => _token = token;
}
