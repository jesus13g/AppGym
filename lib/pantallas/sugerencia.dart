/// La sugerencia de progresión, pintada.
///
/// No es una pantalla, sino la pieza que comparten las dos que la enseñan: la
/// tarjeta del ejercicio al entrenar, donde se decide y se puede aplicar, y la
/// de resultados, donde solo se analiza. Vive aparte para que la frase y el
/// icono se escriban una sola vez.
///
/// El módulo `datos/progresion.dart` devuelve el motivo **como dato**; el texto
/// se compone aquí, que es lo que hará posible traducirlo cuando entre el
/// bloque I sin tocar la lógica.
library;

import 'package:flutter/cupertino.dart';

import '../datos/bd.dart';
import '../datos/formato.dart' as formato;
import '../datos/progresion.dart' as progresion;
import '../tema/tokens.dart';
import '../tema/ui.dart' as ui;

/// Qué se propone: «4×8 · 62,5 kg», o «12/11/9 · 60,0 kg» si no son iguales.
///
/// En peso corporal el peso se omite: «3×10» ya lo dice todo, y «3×10 · 0 kg»
/// es ruido.
String textoSugerencia(progresion.Sugerencia sugerencia, Ajustes ajustes) {
  final series = sugerencia.series;
  if (series.isEmpty) return '';

  final repeticiones = series.map((s) => s.repeticiones).toSet();
  final cuenta = repeticiones.length == 1
      ? '${series.length}×${series.first.repeticiones}'
      : series.map((s) => s.repeticiones).join('/');

  if (series.every((s) => s.peso == 0)) return cuenta;
  return '$cuenta · ${formato.peso(sugerencia.peso, ajustes)}';
}

/// Por qué se propone, en una frase.
String motivoSugerencia(progresion.Sugerencia sugerencia) =>
    switch (sugerencia.motivo) {
      progresion.MotivoSugerencia.rangoCompletado =>
        sugerencia.tipo == progresion.TipoSugerencia.subirPeso
            ? 'Completaste el rango en todas las series'
            : 'Ya estás en el tope del rango',
      progresion.MotivoSugerencia.rangoIncompleto =>
        'Te falta llegar al tope del rango',
      progresion.MotivoSugerencia.esfuerzoAlto =>
        'El esfuerzo fue alto: mejor consolidar este peso',
      progresion.MotivoSugerencia.esfuerzoBajo =>
        'Completaste el rango y sobró margen',
      progresion.MotivoSugerencia.repeticionesCaidas =>
        'Las repeticiones cayeron por debajo del rango',
      progresion.MotivoSugerencia.estancado =>
        'Van varias sesiones sin mejorar',
      progresion.MotivoSugerencia.descargaSugerida =>
        'Tres sesiones sin mejorar: bajar y reconstruir suele desatascarlo',
    };

/// Lo que la descarga **no** sabe, dicho donde hay sitio para decirlo.
///
/// La app no sabe si el usuario está en déficit calórico, durmiendo cuatro horas
/// o volviendo de una lesión, y todas esas cosas explican un estancamiento mejor
/// que el peso de la barra.
const avisoDescarga =
    'Es una sugerencia a partir de tres sesiones de datos, no un consejo de '
    'entrenamiento: el descanso, la comida o una lesión explican un '
    'estancamiento mejor que el peso de la barra.';

IconData _icono(progresion.TipoSugerencia tipo) => switch (tipo) {
  progresion.TipoSugerencia.subirPeso => CupertinoIcons.arrow_up,
  progresion.TipoSugerencia.subirRepeticiones => CupertinoIcons.plus,
  progresion.TipoSugerencia.mantener => CupertinoIcons.equal,
  progresion.TipoSugerencia.bajarPeso => CupertinoIcons.arrow_down,
  progresion.TipoSugerencia.descarga => CupertinoIcons.arrow_counterclockwise,
};

Color _color(BuildContext context, progresion.TipoSugerencia tipo) =>
    switch (tipo) {
      progresion.TipoSugerencia.bajarPeso ||
      progresion.TipoSugerencia.descarga => context.destructivo,
      _ => context.acento,
    };

/// La línea de sugerencia, lista para meter en una tarjeta.
///
/// Sin [onAplicar] no hay botón, que es como se enseña en resultados: desde esa
/// pantalla no se está entrenando y aplicar no significaría nada.
class LineaSugerencia extends StatelessWidget {
  const LineaSugerencia({
    super.key,
    required this.sugerencia,
    this.ajustes = const Ajustes(),
    this.onAplicar,
    this.onDescartar,
  });

  final progresion.Sugerencia sugerencia;
  final Ajustes ajustes;
  final VoidCallback? onAplicar;
  final VoidCallback? onDescartar;

  @override
  Widget build(BuildContext context) => ui.Sugerencia(
    icono: _icono(sugerencia.tipo),
    titulo: 'Sugerido ${textoSugerencia(sugerencia, ajustes)}',
    motivo: motivoSugerencia(sugerencia),
    color: _color(context, sugerencia.tipo),
    fiable: sugerencia.fiable,
    onAccion: onAplicar,
    onDescartar: onDescartar,
  );
}
