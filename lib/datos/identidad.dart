/// Las dos marcas que la sincronización necesita en cada fila que viaja: una
/// identidad estable entre dispositivos y una versión que diga cuál es la
/// última.
///
/// Vive aquí, al lado de `reloj.dart`, y no dentro de `sincro/`, porque **quien
/// las escribe es `bd.dart`**: son parte de cómo se guarda una fila, no de cómo
/// se sincroniza. El motor las lee; no las pone.
///
///   - [uuidV4] da la identidad. El `id` autoincremental sigue siendo la clave
///     primaria y lo que usan todas las consultas, los providers y las rutas:
///     el `uuid` es una identidad **añadida**, solo para traducir de identidad
///     global a identidad local al entrar y al salir.
///   - [selloLocal] da la versión: milisegundos desde época, pero **monótonos**.
///
/// El sello es monótono a propósito y no es una hora de verdad. Lo que decide
/// un conflicto no es el reloj del móvil —que puede estar mal puesto— sino si
/// la fila está pendiente de subir; el sello solo tiene que crecer para que
/// «pendiente» signifique «con sello mayor que el cursor de subida». Que además
/// se parezca a la hora es comodidad al depurar.
library;

import 'dart:math';

import 'reloj.dart';

/// De dónde salen los 122 bits aleatorios del uuid.
///
/// `Random.secure()` y no `Random()`: dos móviles que instalen la app el mismo
/// segundo no pueden generar la misma secuencia, y aquí una colisión de `uuid`
/// significa que dos rutinas distintas se creen la misma.
final _azar = Random.secure();

const _hex = '0123456789abcdef';

/// Un identificador único, versión 4, en las 36 letras de siempre.
///
/// Escrito a mano en quince líneas en vez de traerse el paquete `uuid`: aquí
/// las dependencias se cuentan, y de ese paquete se usaría exactamente esta
/// función. El formato es el del RFC 9562: la versión en el dígito 13 y la
/// variante en el 17.
String uuidV4() {
  final salida = StringBuffer();
  for (var i = 0; i < 32; i++) {
    if (i == 8 || i == 12 || i == 16 || i == 20) salida.write('-');
    salida.write(switch (i) {
      12 => '4',
      16 => _hex[8 + _azar.nextInt(4)],
      _ => _hex[_azar.nextInt(16)],
    });
  }
  return salida.toString();
}

int _ultimo = 0;

/// La versión que le toca a una fila que se acaba de escribir en este móvil.
///
/// Estrictamente creciente dentro de una ejecución: dos escrituras en el mismo
/// milisegundo no se pueden confundir, y un reloj que se retrase —o un test que
/// lo mueva— no hace que una fila nueva parezca vieja. Que un sello local sea
/// mayor que el cursor de subida es justo lo que significa «esta fila todavía
/// no está en el servidor».
int selloLocal() {
  final ahora_ = ahora().millisecondsSinceEpoch;
  return _ultimo = ahora_ > _ultimo ? ahora_ : _ultimo + 1;
}

/// Sube el suelo del contador hasta [sello] si estaba por debajo.
///
/// Lo llama `AppBD` al abrir con el mayor sello que haya en la base y con los
/// cursores: sin eso, reabrir la app con el reloj atrasado —o con sellos que
/// puso el servidor y van por delante de la hora local— generaría sellos que ya
/// se usaron, y una fila cambiada aquí podría parecer ya subida.
void sembrarSello(int sello) {
  if (sello > _ultimo) _ultimo = sello;
}

/// Vuelve a empezar. **Solo para los tests**, que abren muchas bases en la
/// misma ejecución y necesitan que la de ahora no herede el suelo de la
/// anterior.
void reiniciarSellos() => _ultimo = 0;
