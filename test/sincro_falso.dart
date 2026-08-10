/// El servidor de mentira que usan los tests de sincronización.
///
/// Es la mitad que hace posible la costura de `SincroTransporte`: con esto, el
/// motor entero se prueba **sin red, sin cuenta y sin proveedor**, que es la
/// condición de entrega del bloque (K10). Dos `AppBD` en memoria y uno de estos
/// en medio son dos móviles y una cuenta.
///
/// Hace de servidor de verdad en lo único en lo que importa que lo sea: **el
/// reloj es suyo**. Sella cada fila que acepta con su propio contador, en orden
/// de llegada, así que un cliente con la hora mal puesta no puede ganar ni
/// perder todos los conflictos.
library;

import 'package:appgym/datos/sincro/transporte.dart';

class SincroFalso implements SincroTransporte {
  SincroFalso({this.correo = 'yo@ejemplo.com'});

  final String correo;

  /// Lo que hay en la cuenta, por [FilaRemota.id]. Es el servidor entero.
  final Map<String, FilaRemota> filas = {};

  SesionRemota? _sesion;

  /// Lo que se lanzará en la próxima bajada, si se pone algo.
  ErrorSincro? falloAlBajar;

  /// Lo que se lanzará en la próxima subida, si se pone algo.
  ErrorSincro? falloAlSubir;

  /// Con esto puesto, [subir] escribe las filas y **luego** falla, que es el
  /// «se cae a mitad de subida»: el servidor se quedó con parte y el cliente no
  /// se enteró de nada.
  bool caerTrasEscribir = false;

  /// El código que [entrar] da por bueno. Cualquier otro se rechaza, como haría
  /// el servidor de verdad.
  final String codigo = '123456';

  /// A qué correos se ha pedido un código, en orden.
  final List<String> codigosPedidos = [];

  /// Lo que lanzará [pedirCodigo], si se pone algo.
  ErrorSincro? falloAlPedirCodigo;

  int bajadas = 0;
  int subidas = 0;
  int vaciados = 0;

  /// El reloj del servidor. Empieza alto a propósito, para que ningún test pase
  /// por casualidad al coincidir con un sello local.
  int _reloj = 1000000;

  int get cursor => _reloj;

  @override
  Future<SesionRemota?> sesionActual() async => _sesion;

  @override
  Future<void> pedirCodigo(String correo) async {
    if (falloAlPedirCodigo case final e?) throw e;
    codigosPedidos.add(correo);
  }

  @override
  Future<SesionRemota> entrar(String correo, String codigo) async {
    // El código se comprueba de verdad: la pantalla tiene que poder enseñar el
    // mensaje de «no vale», y un falso que aceptara cualquier cosa dejaría ese
    // camino sin probar.
    if (codigo != this.codigo) {
      throw const ErrorSincro.rechazado('El código no vale o ha caducado.');
    }
    return _sesion = SesionRemota(id: 'usuario-1', correo: correo);
  }

  @override
  Future<void> salir() async => _sesion = null;

  @override
  Future<Paquete> bajar(int cursor) async {
    bajadas++;
    if (falloAlBajar case final e?) throw e;
    return Paquete(
      [
        for (final fila in filas.values)
          if (fila.actualizado > cursor) fila,
        // Se devuelven barajadas —del más nuevo al más viejo— para que ningún
        // test dependa de que el paquete venga ordenado. El motor lo ordena solo.
      ]..sort((a, b) => b.actualizado.compareTo(a.actualizado)),
      cursor: _reloj,
    );
  }

  @override
  Future<RespuestaSubida> subir(Paquete paquete) async {
    subidas++;
    if (falloAlSubir case final e?) throw e;

    final previo = _reloj;
    final sellos = <String, int>{};
    for (final fila in paquete.filas) {
      final sello = ++_reloj;
      filas[fila.id] = fila.conSello(sello);
      sellos[fila.id] = sello;
    }
    if (caerTrasEscribir) {
      caerTrasEscribir = false;
      throw const ErrorSincro.temporal('se cortó al confirmar');
    }
    return RespuestaSubida(sellos, cursor: _reloj, cursorPrevio: previo);
  }

  @override
  Future<Cifras> resumen() async => Cifras(
    rutinas: _cuantas('rutinas'),
    sesiones: _cuantas('entrenamientos'),
  );

  @override
  Future<void> vaciar() async {
    vaciados++;
    filas.clear();
  }

  @override
  Future<void> borrarCuenta() async {
    filas.clear();
    _sesion = null;
  }

  int _cuantas(String tabla) =>
      filas.values.where((f) => f.tabla == tabla && !f.borrada).length;

  /// Lo que hay en la cuenta de una tabla, sin las lápidas.
  Iterable<FilaRemota> deTabla(String tabla) =>
      filas.values.where((f) => f.tabla == tabla && !f.borrada);
}
