/// El primer enlace: qué pasa cuando una base local se junta con una cuenta.
///
/// **Es el momento más peligroso de todo el bloque.** Un usuario con dos años
/// de histórico entra por primera vez en una cuenta que puede tener datos o no
/// tenerlos, y si eso se resuelve mal se le borra el histórico. Es el único
/// punto de K donde una decisión automática es inaceptable, así que aquí lo que
/// se decide es **cuándo hay que preguntar**, no qué contestar.
///
/// Tres de los cuatro casos no preguntan nada porque no hay nada que decidir; el
/// cuarto —datos a los dos lados— pregunta siempre, y la salida que puede
/// destruir dos años de datos no se ofrece sin exportar antes una copia.
///
/// No importa Flutter: la copia previa entra como una función que la pantalla
/// proporciona, igual que `copia.dart` recibe los textos en vez de conocer el
/// idioma.
library;

import '../bd.dart';
import 'motor.dart';
import 'transporte.dart';

/// Qué hacer cuando hay datos a los dos lados.
///
/// Mismo vocabulario que la importación de copias (`ModoImportacion`), que el
/// usuario puede haber visto ya.
enum EstrategiaEnlace {
  /// Todo lo local sube y todo lo remoto baja; los choques se resuelven con las
  /// reglas de K5. Es la recomendada y la única que no pierde nada.
  fusionar,

  /// Lo remoto se sustituye por lo local.
  esteDispositivo,

  /// Lo local se sustituye por lo remoto. **Exporta una copia antes.**
  laCuenta,
}

/// Lo que hay a cada lado, para poder enseñarlo antes de preguntar.
///
/// Sin números la pregunta no se puede responder: «aquí 3 rutinas y 214
/// sesiones, en la cuenta 2 y 180» es una pregunta contestable; «¿fusionar o
/// reemplazar?» no lo es.
class ResumenLados {
  const ResumenLados({required this.local, required this.remoto});

  final Cifras local;
  final Cifras remoto;

  /// Si hay que preguntar. Es el cuarto caso de K7 y el único.
  bool get hayQueDecidir => !local.vacio && !remoto.vacio;
}

/// Cómo acabó el enlace.
class ResultadoEnlace {
  const ResultadoEnlace(this.estrategia, this.sincro);

  /// La que se aplicó de verdad, incluida la que se dedujo sola.
  final EstrategiaEnlace estrategia;

  final ResultadoSincro sincro;
}

/// Se pidió enlazar con datos a los dos lados y sin decir cuál manda.
///
/// Es un error de programación, no un fallo de red: la pantalla tiene que
/// preguntar antes. Existe para que ese olvido salte en un test en vez de
/// resolverse solo por el camino equivocado.
class DecisionPendiente implements Exception {
  const DecisionPendiente(this.lados);

  final ResumenLados lados;

  @override
  String toString() =>
      'Hay datos en los dos lados: hay que elegir qué manda antes de enlazar.';
}

/// Enlaza una base local con una cuenta.
class Enlace {
  Enlace(this.bd, this.transporte) : _motor = MotorSincro(bd, transporte);

  final AppBD bd;
  final SincroTransporte transporte;
  final MotorSincro _motor;

  /// Qué hay a cada lado. Es lo que la pantalla enseña antes de preguntar.
  Future<ResumenLados> examinar() async => ResumenLados(
    local: Cifras(
      rutinas: (await bd.todasLasRutinas()).length,
      sesiones: await bd.contarEntrenamientos(),
    ),
    remoto: await transporte.resumen(),
  );

  /// Enlaza, aplicando [estrategia] solo si hace falta elegir.
  ///
  /// [respaldoPrevio] se llama, sin preguntar, justo antes de la única salida
  /// que puede destruir el histórico local. Es la red de seguridad de K7 y por
  /// eso no es opcional en ese camino: si no se proporciona, no se sigue.
  Future<ResultadoEnlace> enlazar({
    EstrategiaEnlace? estrategia,
    Future<void> Function()? respaldoPrevio,
  }) async {
    final lados = await examinar();

    // Los tres casos automáticos. Ninguno pregunta nada porque en ninguno hay
    // nada que decidir: o no hay datos, o solo los hay en un lado.
    if (!lados.hayQueDecidir) {
      return ResultadoEnlace(
        EstrategiaEnlace.fusionar,
        await _motor.sincronizar(),
      );
    }

    if (estrategia == null) throw DecisionPendiente(lados);

    switch (estrategia) {
      case EstrategiaEnlace.fusionar:
        break;

      case EstrategiaEnlace.esteDispositivo:
        // Se vacía la cuenta y se vuelve a empezar desde cero: sin reiniciar los
        // cursores, lo local seguiría pareciendo ya subido y la cuenta se
        // quedaría vacía de verdad.
        await transporte.vaciar();
        await _reiniciarCursores();

      case EstrategiaEnlace.laCuenta:
        if (respaldoPrevio == null) {
          throw StateError(
            'La salida «la cuenta manda» exige exportar una copia antes.',
          );
        }
        await respaldoPrevio();
        // Sin lápidas: enterrar lo que se va se llevaría por delante la cuenta,
        // que es justo el lado que el usuario ha dicho que manda.
        await bd.borrarTodosLosDatos(conLapidas: false);
        await _reiniciarCursores();
    }

    return ResultadoEnlace(estrategia, await _motor.sincronizar());
  }

  /// Vuelve a poner los dos cursores a cero.
  ///
  /// Después de vaciar un lado, lo que queda en el otro tiene que volver a
  /// contarse entero: con los cursores donde estaban, lo ya sincronizado se
  /// daría por sabido y no se movería.
  Future<void> _reiniciarCursores() => bd.fijarEstadoSincro(
    cursorSubida: const Value(0),
    cursorBajada: const Value(0),
  );
}
