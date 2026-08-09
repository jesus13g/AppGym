/// La costura de la copia automática: todo lo que necesita del mundo exterior.
///
/// Es la misma idea que `reloj.dart` y `media.fijarDirectorioMedia`, llevada a
/// un servicio entero. El motor (`estado/copia_automatica.dart`) **no importa
/// nada de Google**: habla con [DestinoNube] y punto. La implementación real
/// (`drive.dart`) es un adaptador fino y es el único fichero del proyecto que
/// sabe que Drive existe; la de test es un mapa en memoria.
///
/// Sin esta separación la funcionalidad no se podría probar sin red y sin
/// cuenta, y `CLAUDE.md` dice que en esta app se puede comprobar todo sin
/// interfaz. Este es el bloque que más cerca ha estado de romper esa frase.
library;

/// Una copia que ya está en la nube.
///
/// El [id] es opaco: lo pone el proveedor y solo se usa para volver a
/// escribirla o para borrarla al rotar.
class CopiaRemota {
  const CopiaRemota({
    required this.id,
    required this.nombre,
    required this.creada,
  });

  final String id;
  final String nombre;
  final DateTime creada;

  @override
  String toString() => 'CopiaRemota($nombre)';
}

/// Por qué falló una operación con la nube.
///
/// La distinción no es cosmética: es lo que decide si se reintenta. Reintentar
/// un permiso revocado no lo arregla nunca y gasta batería y datos; reintentar
/// un corte de cobertura sí funciona, y es el caso normal al salir del
/// gimnasio.
enum MotivoFallo {
  /// Sin cobertura, tiempo agotado o un 5xx del servidor. Se reintenta.
  temporal,

  /// El usuario revocó el permiso o la sesión caducó sin remedio
  /// (`invalid_grant`). No se reintenta: hay que volver a conectar.
  reconectar,

  /// La nube contestó que no, y no por falta de permiso: sin espacio, un
  /// nombre inválido, una cuota agotada. No se reintenta solo.
  rechazado,
}

/// Un fallo de la nube, con el motivo que decide si se reintenta.
class ErrorNube implements Exception {
  const ErrorNube(this.motivo, this.mensaje);

  const ErrorNube.temporal(String mensaje)
    : this(MotivoFallo.temporal, mensaje);

  const ErrorNube.reconectar(String mensaje)
    : this(MotivoFallo.reconectar, mensaje);

  const ErrorNube.rechazado(String mensaje)
    : this(MotivoFallo.rechazado, mensaje);

  final MotivoFallo motivo;

  /// Legible, y ya en el idioma del proveedor o en inglés: se enseña tal cual
  /// detrás de una frase traducida, igual que hace `copiaErrorImportar`.
  final String mensaje;

  bool get seReintenta => motivo == MotivoFallo.temporal;

  @override
  String toString() => mensaje;
}

/// Todo lo que la copia automática necesita del mundo exterior.
///
/// Doce líneas de interfaz. Cambiar de proveedor es escribir otro adaptador, no
/// reescribir la funcionalidad.
abstract interface class DestinoNube {
  /// Cómo se llama el destino en la interfaz («Google Drive»).
  String get nombre;

  /// Conecta una cuenta. Abre el navegador del sistema y espera.
  ///
  /// Devuelve el correo. Lanza [ErrorNube] si el usuario cancela o si el canje
  /// falla.
  ///
  /// **No hay un `cuenta()` que preguntar**: quién está conectado lo guarda el
  /// motor en la tabla `ajustes`, y tener dos sitios que lo supieran sería
  /// tener dos sitios que pueden discrepar.
  ///
  /// [mensajeVuelta] es lo que lee el usuario en el navegador cuando termina.
  /// Llega ya traducido porque este módulo no conoce el idioma activo, igual
  /// que no lo conocen `copia.dart` ni `tema/ui.dart`.
  Future<String> conectar([String mensajeVuelta]);

  /// Revoca el permiso y olvida las credenciales. **No borra nada de la nube**:
  /// las copias son del usuario y se quedan donde están.
  Future<void> desconectar();

  /// Las copias que hay ahora mismo, de la más reciente a la más antigua.
  Future<List<CopiaRemota>> listar();

  /// Escribe una copia. Si ya hay una con ese nombre, la reemplaza.
  Future<void> subir(String nombre, String contenido);

  /// Borra una copia por su [CopiaRemota.id]. Solo lo usa la rotación.
  Future<void> borrar(String id);
}
