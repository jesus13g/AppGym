/// Temporizador de descanso entre series.
///
/// El reloj vive en un `Notifier` de Riverpod y **no** en el estado de un
/// widget: así el descanso sigue corriendo aunque se navegue a la ficha de un
/// ejercicio y se vuelva. Cerrar la pantalla de entrenamiento sí lo cancela,
/// que es lo que evita el clásico *«A Timer is still pending even after the
/// widget tree was disposed»*.
///
/// El tiempo restante se calcula siempre como `fin - ahora`, nunca acumulando
/// tics: si el sistema suspende la app treinta segundos, al volver la cuenta
/// está donde tiene que estar en vez de treinta segundos por detrás.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/reloj.dart';
import 'providers.dart';

/// Cada cuánto se repinta. El valor mostrado no depende de esto —sale de la
/// resta contra el reloj—, solo su frescura.
const _tic = Duration(milliseconds: 200);

/// Cuánto se sigue contando hacia arriba antes de dejarlo estar.
///
/// Sin tope, un descanso que nadie salta dejaría un `Timer` vivo el resto de la
/// sesión contando minutos que ya no interesan a nadie.
const _maxExceso = Duration(minutes: 5);

/// Lo que suman o restan los botones de la barra.
const ajusteDescanso = Duration(seconds: 15);

/// Un descanso en marcha.
class Descanso {
  const Descanso({
    required this.fin,
    required this.totalSeg,
    required this.ahora,
  });

  /// Instante en el que debería sonar.
  final DateTime fin;

  /// Duración con la que arrancó, para la barra de progreso.
  final int totalSeg;

  /// Instante del último tic. Es lo que hace que el estado cambie y se repinte.
  final DateTime ahora;

  /// Segundos que faltan, redondeados hacia arriba. Negativo si ya se pasó.
  ///
  /// Hacia arriba porque es una cuenta atrás: mientras quede algo de ese
  /// segundo, el número que toca ver es el segundo entero.
  int get restanteSeg => (fin.difference(ahora).inMilliseconds / 1000).ceil();

  bool get excedido => restanteSeg <= 0;

  /// Segundos de más, ya en positivo.
  int get excesoSeg => excedido ? -restanteSeg : 0;

  /// De 1 a 0 según se consume. Se queda en 0 al pasarse.
  double get progreso {
    if (totalSeg <= 0) return 0;
    return (restanteSeg / totalSeg).clamp(0.0, 1.0);
  }

  /// 'M:SS', contando en positivo tanto lo que falta como lo que sobra.
  String get reloj {
    final segundos = excedido ? excesoSeg : restanteSeg;
    final minutos = segundos ~/ 60;
    return '$minutos:${(segundos % 60).toString().padLeft(2, '0')}';
  }
}

class DescansoNotifier extends Notifier<Descanso?> {
  Timer? _reloj;

  /// Para que el pitido y la vibración salgan una sola vez por descanso.
  bool _avisado = false;

  @override
  Descanso? build() {
    ref.onDispose(pararReloj);
    return null;
  }

  /// Arranca (o reinicia) una cuenta atrás de [segundos].
  void arrancar(int segundos) {
    if (segundos <= 0) return;
    _avisado = false;
    final instante = ahora();
    state = Descanso(
      fin: instante.add(Duration(seconds: segundos)),
      totalSeg: segundos,
      ahora: instante,
    );
    pararReloj();
    _reloj = Timer.periodic(_tic, (_) => _latir());
  }

  /// Suma o resta tiempo sin reiniciar la cuenta.
  ///
  /// El total sube o baja con el final, de modo que la barra de progreso siga
  /// significando lo mismo después de tocarla.
  void ajustar(Duration delta) {
    final actual = state;
    if (actual == null) return;

    final instante = ahora();
    var fin = actual.fin.add(delta);
    // Restar por debajo del momento actual no debe dejar el descanso «en el
    // pasado»: se queda a cero, que es lo que el usuario quiere decir.
    if (fin.isBefore(instante)) fin = instante;

    final total = (actual.totalSeg + delta.inSeconds).clamp(1, 3600);
    state = Descanso(fin: fin, totalSeg: total, ahora: instante);
    if (!actual.excedido) _avisado = false;
  }

  /// Cancela el descanso. Es también lo que llama la pantalla al cerrarse.
  ///
  /// La pantalla lo aplaza un frame para no escribir el estado mientras se
  /// desmonta el árbol, y en ese hueco el `ProviderScope` entero puede haberse
  /// ido —cerrar la app, o terminar un test—. De ahí la guarda: el reloj ya
  /// está parado, que es lo que importaba.
  void saltar() {
    pararReloj();
    if (!ref.mounted) return;
    state = null;
  }

  /// Para el reloj sin tocar el estado.
  ///
  /// Es lo que necesita `dispose` de la pantalla: el `Timer` tiene que morir en
  /// ese mismo instante, pero escribir el estado del provider mientras se
  /// desmonta el árbol es lo que Riverpod no permite.
  void pararReloj() {
    _reloj?.cancel();
    _reloj = null;
  }

  void _latir() {
    final actual = state;
    if (actual == null) {
      pararReloj();
      return;
    }

    final instante = ahora();
    state = Descanso(
      fin: actual.fin,
      totalSeg: actual.totalSeg,
      ahora: instante,
    );

    if (!_avisado && !instante.isBefore(actual.fin)) {
      _avisado = true;
      avisar();
    }
    if (instante.difference(actual.fin) > _maxExceso) pararReloj();
  }

  /// Pitido y vibración al llegar a cero.
  ///
  /// Sin dependencias nuevas: `SystemSound` y `HapticFeedback` vienen en
  /// `services.dart`. Un sonido propio exigiría `audioplayers` y no compensa
  /// para un pitido. La vibración va siempre —es lo que se nota con el móvil en
  /// el bolsillo—; el sonido solo si está activado en Ajustes.
  void avisar() {
    final ajustes = ref.read(ajustesProvider).value;
    if (ajustes?.sonidoDescanso ?? true) {
      SystemSound.play(SystemSoundType.alert);
    }
    HapticFeedback.heavyImpact();
  }
}

final descansoProvider = NotifierProvider<DescansoNotifier, Descanso?>(
  DescansoNotifier.new,
);
