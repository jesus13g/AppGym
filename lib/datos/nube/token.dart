/// Dónde se guardan las credenciales que no pueden salir del móvil.
///
/// **No en la tabla `ajustes`.** Esa tabla se exporta entera en la copia de
/// seguridad (`copia.dart`), y un token dentro de un JSON que el usuario
/// comparte por correo o sube a su Drive es una fuga con todas las letras. Va
/// al almacén seguro de la plataforma —Keystore en Android—, que es lo único
/// que no depende de que nadie se acuerde de excluirlo el día que amplíe la
/// exportación.
///
/// La interfaz existe para poder probar los adaptadores sin plataforma:
/// `flutter_secure_storage` necesita un canal nativo que en `flutter test` no
/// hay.
///
/// Lo usan dos: la copia automática guarda aquí su *refresh token* de Drive
/// ([claveDrive]) y la sincronización guarda la sesión entera de la cuenta
/// ([claveSincro]). Son dos claves del mismo almacén, no dos almacenes: la
/// configuración que importa —`encryptedSharedPreferences`, que es lo que
/// respalda el valor con el Keystore en vez de dejarlo en unas preferencias
/// normales— tiene que estar escrita **una sola vez**, o sería un sitio de más
/// donde equivocarse.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// El *refresh token* de Google Drive, de la copia automática (fase 8a).
const claveDrive = 'copia_nube_refresh_token';

/// La sesión de la cuenta de sincronización (fase 8c).
///
/// Guarda un JSON con `id`, `correo` y `refresco`. El correo va aquí y no en la
/// tabla `ajustes` por dos motivos: esa tabla se exporta, y sobre todo porque
/// `sesionActual()` tiene que poder contestar **sin red** —si hiciera falta
/// renovar el token para saber si hay cuenta, un móvil sin cobertura diría «sin
/// cuenta» y el usuario volvería a entrar, cayendo otra vez por el primer
/// enlace—.
const claveSincro = 'sincro_sesion';

/// Dos métodos: leer y escribir. Nada más hace falta.
abstract interface class AlmacenToken {
  Future<String?> leer();

  /// Con `null` se borra.
  Future<void> escribir(String? token);
}

/// El almacén de verdad, sobre el Keystore de Android.
class AlmacenSeguro implements AlmacenToken {
  const AlmacenSeguro({this.clave = claveDrive});

  /// Bajo qué nombre se guarda. Ver [claveDrive] y [claveSincro].
  final String clave;

  static const _almacen = FlutterSecureStorage(
    // `EncryptedSharedPreferences` es lo que respalda el valor con el Keystore
    // en vez de dejarlo en unas preferencias normales.
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  @override
  Future<String?> leer() => _almacen.read(key: clave);

  @override
  Future<void> escribir(String? token) => token == null
      ? _almacen.delete(key: clave)
      : _almacen.write(key: clave, value: token);
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
