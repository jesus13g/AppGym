/// La nube de mentira que usan los tests.
///
/// Es la mitad que hace posible la costura de `DestinoNube`: con esto, todo el
/// motor de la copia automática se prueba **sin red, sin cuenta y sin
/// proveedor**, que es la condición de entrega del bloque.
library;

import 'package:appgym/datos/nube/nube.dart';

class NubeFalsa implements DestinoNube {
  NubeFalsa({this.correo = 'yo@ejemplo.com'});

  final String correo;

  /// Lo subido, por nombre de fichero. Es la nube entera.
  final Map<String, String> ficheros = {};

  /// Cuándo se creó cada fichero, para poder probar la rotación con fechas
  /// escritas a mano en vez de depender del orden de inserción.
  final Map<String, DateTime> creados = {};

  /// Lo que se lanzará en la próxima operación de ficheros, si se pone algo.
  ErrorNube? fallo;

  /// Lo que lanzará [conectar].
  ErrorNube? falloAlConectar;

  int subidas = 0;
  int borrados = 0;
  int conexiones = 0;
  bool desconectado = false;

  /// Un contador propio para que dos copias seguidas no empaten en fecha.
  int _reloj = 0;

  @override
  String get nombre => 'Nube de prueba';

  @override
  Future<String> conectar([String mensajeVuelta = '']) async {
    conexiones++;
    if (falloAlConectar case final e?) throw e;
    return correo;
  }

  @override
  Future<void> desconectar() async {
    desconectado = true;
    ficheros.clear();
    creados.clear();
  }

  @override
  Future<List<CopiaRemota>> listar() async {
    if (fallo case final e?) throw e;
    return [
      for (final nombre in ficheros.keys)
        CopiaRemota(
          id: nombre,
          nombre: nombre,
          creada: creados[nombre] ?? DateTime(2000),
        ),
    ];
  }

  @override
  Future<void> subir(String nombre, String contenido) async {
    if (fallo case final e?) throw e;
    subidas++;
    ficheros[nombre] = contenido;
    creados[nombre] ??= DateTime(2020).add(Duration(days: _reloj++));
  }

  @override
  Future<void> borrar(String id) async {
    if (fallo case final e?) throw e;
    borrados++;
    ficheros.remove(id);
    creados.remove(id);
  }

  /// Rellena la nube con copias ya existentes, la más antigua primero.
  void sembrar(int cuantas) {
    for (var i = 0; i < cuantas; i++) {
      final nombre = 'appgym-copia-vieja-$i.json';
      ficheros[nombre] = '{}';
      creados[nombre] = DateTime(2020).add(Duration(days: i));
    }
    _reloj = cuantas;
  }
}
