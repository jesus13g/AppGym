/// El reloj de la app, en un solo sitio.
///
/// El temporizador de descanso y el cronómetro de la sesión viva se calculan
/// contra la hora real —`fin - ahora`, nunca acumulando tics— para que
/// suspender la app no los desfase. Eso es lo correcto y es justo lo que impide
/// probarlos: `tester.pump(Duration(...))` adelanta el reloj *de los `Timer`*,
/// pero `DateTime.now()` sigue devolviendo la hora de verdad.
///
/// Esta es la costura que lo resuelve. Es la misma idea que
/// `media.fijarDirectorioMedia`: un punto único que los tests sustituyen y que
/// en la app siempre vale lo de siempre.
library;

DateTime Function() _fuente = DateTime.now;

/// La hora actual. Úsalo en vez de `DateTime.now()` en todo lo que cronometre.
DateTime ahora() => _fuente();

/// Sustituye el reloj. Solo lo usan los tests; con `null` vuelve al de verdad.
void fijarReloj(DateTime Function()? fuente) =>
    _fuente = fuente ?? DateTime.now;
