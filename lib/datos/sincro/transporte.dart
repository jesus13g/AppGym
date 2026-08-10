/// La costura de la sincronización: todo lo que el motor necesita del mundo
/// exterior.
///
/// **Este apartado es la condición de entrega del bloque, no un detalle de
/// implementación.** `CLAUDE.md` dice que en esta app se puede comprobar todo
/// sin interfaz; la sincronización es lo primero capaz de romper esa frase,
/// porque su lógica vive entre dos dispositivos y un servidor. Se resuelve
/// igual que se resolvieron `reloj.dart`, `media.fijarDirectorioMedia` y
/// `nube.dart`: con una interfaz pequeña que los tests sustituyen.
///
/// El motor **no importa ningún SDK**: habla con [SincroTransporte]. El
/// adaptador real (`servidor.dart`) es el único fichero del proyecto que sabe
/// cómo se habla con el servidor; el de test es un mapa en memoria
/// (`test/sincro_falso.dart`).
///
/// Son **nueve** métodos, no los seis que proponía K10. Los dos primeros de más
/// son de la fase 8b y están razonados en cada uno: `resumen()`, para enseñar
/// las cifras de los dos lados antes de preguntar en el primer enlace, y
/// `vaciar()`, para «este dispositivo manda». El noveno es de la 8c:
/// `registrar()`, porque crear una cuenta y entrar en ella dejaron de ser la
/// misma operación en cuanto hubo contraseña.
///
/// Nada de aquí importa Flutter ni drift: son datos y una interfaz.
library;

/// Lo que mide de largo una contraseña aceptable.
///
/// Diez, y sin reglas de «una mayúscula y un símbolo»: obligan a contraseñas
/// peores y más difíciles de recordar, y lo que de verdad importa es la longitud.
/// **El servidor comprueba lo mismo**; esto está aquí para poder decírselo al
/// usuario antes de enviar nada.
const largoMinimoContrasena = 10;

/// La cuenta con la que se está sincronizando.
class SesionRemota {
  const SesionRemota({required this.id, required this.correo});

  /// El identificador del usuario en el servidor. No se enseña.
  final String id;

  final String correo;

  @override
  String toString() => 'SesionRemota($correo)';
}

/// Una fila tal y como viaja: identidad, versión y datos.
///
/// Las claves primarias enteras **no viajan**. El id 7 es una rutina distinta en
/// cada móvil; lo que identifica a una fila entre dispositivos es [clave]: el
/// `uuid` en las tablas que lo llevan y la clave natural en las que ya tenían
/// una estable (`medidas`, `favoritos`, `ajustes`). Las relaciones viajan igual:
/// una sesión dice de qué rutina es por el `uuid` de la rutina, nunca por su id.
class FilaRemota {
  const FilaRemota({
    required this.tabla,
    required this.clave,
    required this.actualizado,
    this.datos,
  });

  /// Una lápida: la fila ya no está.
  const FilaRemota.borrada({
    required this.tabla,
    required this.clave,
    required this.actualizado,
  }) : datos = null;

  /// El nombre del valor de `TablaSincro`, no el tipo: este fichero no importa
  /// `bd.dart` y el protocolo se define con cadenas, que es lo que acaba en el
  /// servidor.
  final String tabla;

  final String clave;

  /// La versión. La pone el servidor al aceptar la fila; mientras está
  /// pendiente de subir lleva el sello local que puso `identidad.selloLocal`.
  final int actualizado;

  /// Los campos de la fila, ya en tipos que `jsonEncode` admite. `null` es una
  /// lápida: la fila se borró.
  final Map<String, Object?>? datos;

  bool get borrada => datos == null;

  /// Identifica la fila dentro de un paquete, para casar la respuesta de una
  /// subida con lo que se envió.
  String get id => '$tabla/$clave';

  FilaRemota conSello(int sello) =>
      FilaRemota(tabla: tabla, clave: clave, actualizado: sello, datos: datos);

  @override
  String toString() => '$id@$actualizado${borrada ? ' †' : ''}';
}

/// Un conjunto de filas y hasta dónde llega.
class Paquete {
  const Paquete(this.filas, {this.cursor = 0});

  final List<FilaRemota> filas;

  /// El sello más alto que el servidor tenía al responder. Es lo que se guarda
  /// como cursor de bajada, y no el mayor de [filas]: si el paquete viene
  /// vacío, el cursor tiene que avanzar igual.
  final int cursor;

  bool get vacio => filas.isEmpty;
}

/// Lo que el servidor contesta a una subida.
class RespuestaSubida {
  const RespuestaSubida(
    this.sellos, {
    required this.cursor,
    required this.cursorPrevio,
  });

  /// [FilaRemota.id] → el sello que el servidor le puso.
  ///
  /// **El reloj lo pone el servidor**, no el móvil: un usuario con la hora mal
  /// puesta enviaría filas del año 2000 que perderían todos los conflictos, o
  /// del 2030 que los ganarían todos para siempre.
  final Map<String, int> sellos;

  /// El sello más alto que el servidor ha repartido en esta subida.
  final int cursor;

  /// Dónde estaba el servidor **antes** de escribir esta subida.
  ///
  /// Con esto el cliente sabe si lo que hay entre [cursorPrevio] y [cursor] es
  /// solo suyo. Si lo es, puede adelantar también su cursor de bajada y
  /// ahorrarse volver a bajar lo que él mismo acaba de subir; y si no lo es
  /// —otro dispositivo escribió en medio—, no lo adelanta y se baja todo, que
  /// es lo único seguro.
  final int cursorPrevio;
}

/// Cuántas rutinas y cuántas sesiones hay al otro lado.
///
/// Solo lo necesita el primer enlace (K7), y solo para poder enseñar las cifras
/// antes de preguntar: sin números, la pregunta no se puede responder.
class Cifras {
  const Cifras({required this.rutinas, required this.sesiones});

  final int rutinas;
  final int sesiones;

  bool get vacio => rutinas == 0 && sesiones == 0;
}

/// Por qué falló una operación de sincronización.
///
/// La distinción no es cosmética: es lo que decide si se reintenta. Es la misma
/// que hace `nube.MotivoFallo` para la copia automática, y va repetida a
/// propósito —son dos costuras independientes y ninguna debe depender de la
/// otra—.
enum MotivoSincro {
  /// Sin cobertura, tiempo agotado o un 5xx. Se reintenta con espera creciente.
  temporal,

  /// La sesión caducó o se revocó. No se reintenta: hay que volver a entrar.
  reconectar,

  /// El servidor contestó que no, y no por falta de permiso: cuota, un dato
  /// que rechaza, una versión de protocolo que no entiende.
  rechazado,
}

/// Un fallo de la sincronización, con el motivo que decide si se reintenta.
class ErrorSincro implements Exception {
  const ErrorSincro(this.motivo, this.mensaje);

  const ErrorSincro.temporal(String mensaje)
    : this(MotivoSincro.temporal, mensaje);

  const ErrorSincro.reconectar(String mensaje)
    : this(MotivoSincro.reconectar, mensaje);

  const ErrorSincro.rechazado(String mensaje)
    : this(MotivoSincro.rechazado, mensaje);

  final MotivoSincro motivo;

  /// Legible, y ya en el idioma del proveedor o en inglés: se enseña tal cual
  /// detrás de una frase traducida, igual que hace `copiaErrorImportar`.
  final String mensaje;

  bool get seReintenta => motivo == MotivoSincro.temporal;

  @override
  String toString() => mensaje;
}

/// Todo lo que la sincronización necesita del mundo exterior.
///
/// Nueve métodos. Cambiar de proveedor es escribir otro adaptador, no reescribir
/// el bloque; y el motor, que es donde está la dificultad, se prueba entero sin
/// red, sin cuenta y sin proveedor.
abstract interface class SincroTransporte {
  /// La cuenta con la que se está sincronizando, o `null` si no hay ninguna.
  ///
  /// **Se contesta sin red.** Si hiciera falta cobertura para saber si hay
  /// cuenta, un móvil sin línea diría «sin cuenta» y el usuario volvería a
  /// entrar, cayendo otra vez por el primer enlace, que es el riesgo número uno
  /// de todo el bloque.
  Future<SesionRemota?> sesionActual();

  /// Crea una cuenta y entra en ella.
  ///
  /// **Va aparte de [entrar], y no es un capricho.** Con el código por correo de
  /// la primera versión eran la misma operación —el código creaba la cuenta si no
  /// existía—, pero con contraseña eso sería un desastre: quien se equivoca al
  /// teclear su correo se crearía una cuenta nueva y vacía en vez de leer
  /// «contraseña incorrecta», y no entendería nada de lo que pasa después.
  ///
  /// Lanza [ErrorSincro] con motivo `rechazado` si el correo ya tiene cuenta o si
  /// el servidor no admite cuentas nuevas.
  Future<SesionRemota> registrar(String correo, String contrasena);

  /// Entra con el correo y la contraseña.
  ///
  /// **Contraseña y no enlace mágico ni código**, aunque K3 dijera lo primero. Un
  /// enlace que vuelve a la app exige deep links, un *intent-filter* en el
  /// manifiesto y un dominio de redirección; y un código de un solo uso exige
  /// correo saliente, que en un servidor propio es infraestructura que hay que
  /// montar, pagar y vigilar **antes** de que nadie pueda entrar. Con contraseña,
  /// el día que el servidor esté en pie ya se puede usar. Es la misma clase de
  /// decisión que renunciar a `google_sign_in` en la fase 8a.
  ///
  /// Lanza [ErrorSincro] con motivo `rechazado` si las credenciales no valen: el
  /// usuario puede arreglarlo tecleando otra vez, así que no se reintenta solo y
  /// el mensaje se enseña tal cual.
  Future<SesionRemota> entrar(String correo, String contrasena);

  /// Cierra la sesión. **No borra nada**, ni aquí ni en el servidor.
  Future<void> salir();

  /// Lo que el servidor tenga con `actualizado` posterior a [cursor].
  ///
  /// El paquete se aplica entero o no se aplica, así que puede venir en
  /// cualquier orden: el motor lo ordena solo.
  Future<Paquete> bajar(int cursor);

  /// Envía filas y devuelve el sello que el servidor les puso.
  ///
  /// El servidor acepta siempre y sella con su reloj: gana quien llega el
  /// último, que es lo único que un cliente con la hora mal puesta no puede
  /// falsear.
  Future<RespuestaSubida> subir(Paquete paquete);

  /// Cuántas rutinas y sesiones hay en la cuenta, para el primer enlace.
  Future<Cifras> resumen();

  /// Borra los datos de la cuenta y **conserva la cuenta**.
  ///
  /// Lo usa «este dispositivo manda» del primer enlace. No está en la lista de
  /// seis métodos que proponía K10 y hace falta: sin él, esa salida tendría que
  /// enterrar una por una las filas del otro lado, que es la misma operación
  /// hecha cara y a trozos.
  Future<void> vaciar();

  /// Borra la cuenta y sus datos. Los locales no se tocan.
  Future<void> borrarCuenta();
}
