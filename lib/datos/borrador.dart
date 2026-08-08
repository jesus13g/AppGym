/// Estado de la sesión que se está entrenando, serializado a JSON.
///
/// La pantalla de registro era un formulario: se rellenaba entero y se
/// guardaba al final. En el gimnasio se anota serie a serie durante una hora, y
/// hasta ahora cerrar la app a mitad se lo llevaba todo, porque el estado vivía
/// en campos del `State`.
///
/// Esto es lo que se escribe en la tabla `sesiones_activas` con *debounce*, y
/// lo que se vuelve a leer al recuperar. Va aparte de la pantalla para poder
/// probar la ida y vuelta sin montar ningún widget.
library;

import 'dart:convert';

import 'bd.dart';

/// Una serie mientras se entrena: sus valores y si ya está hecha.
///
/// El «hecha» no llega a la base de datos —una serie guardada es una serie
/// hecha— así que no está en [ValoresSerie]: solo vive mientras dura la sesión.
typedef SerieEnCurso = ({ValoresSerie valores, bool hecha});

/// Lo que hay que recordar de un entrenamiento a medias.
class Borrador {
  const Borrador({
    required this.series,
    this.nota = '',
    this.descartadas = const {},
  });

  /// Id de ejercicio -> sus series, en orden.
  final Map<int, List<SerieEnCurso>> series;

  final String nota;

  /// Ejercicios cuya sugerencia de progresión se ha descartado hoy.
  ///
  /// Vive aquí y no en una tabla a propósito: es un dato efímero de la sesión en
  /// curso, que es exactamente lo que esta tabla existe para guardar. Descartada
  /// no vuelve en esta sesión, y vuelve a aparecer en la siguiente.
  final Set<int> descartadas;

  /// Series ya marcadas y series totales.
  (int, int) get progreso {
    var hechas = 0;
    var total = 0;
    for (final lista in series.values) {
      total += lista.length;
      hechas += lista.where((s) => s.hecha).length;
    }
    return (hechas, total);
  }

  String aJson() => jsonEncode({
    'nota': nota,
    'descartadas': descartadas.toList(),
    'ejercicios': {
      for (final entrada in series.entries)
        '${entrada.key}': [
          for (final s in entrada.value)
            {
              'reps': s.valores.repeticiones,
              'peso': s.valores.peso,
              'cal': s.valores.calentamiento,
              'rpe': s.valores.rpe,
              'nota': s.valores.nota,
              'hecha': s.hecha,
            },
        ],
    },
  });

  /// Lee un borrador. Devuelve uno vacío si el JSON no se entiende.
  ///
  /// No lanza a propósito: un borrador ilegible es una molestia, no un motivo
  /// para que la app no arranque. Quien lo llame verá una sesión sin series y
  /// podrá descartarla.
  factory Borrador.desdeJson(String texto) {
    Object? cargado;
    try {
      cargado = jsonDecode(texto);
    } on FormatException {
      return const Borrador(series: {});
    }
    if (cargado is! Map) return const Borrador(series: {});

    final ejercicios = cargado['ejercicios'];
    if (ejercicios is! Map) return const Borrador(series: {});

    return Borrador(
      nota: cargado['nota'] as String? ?? '',
      // Un borrador escrito antes de que existieran las sugerencias no trae esta
      // clave, y sale vacía: no hay nada que versionar.
      descartadas: {
        for (final id in (cargado['descartadas'] as List<dynamic>? ?? const []))
          ?int.tryParse('$id'),
      },
      series: {
        for (final entrada in ejercicios.entries)
          ?int.tryParse('${entrada.key}'): [
            for (final s in (entrada.value as List<dynamic>? ?? const []))
              if (s is Map<String, dynamic>)
                (
                  valores: ValoresSerie(
                    repeticiones: (s['reps'] as num?)?.round() ?? 0,
                    peso: (s['peso'] as num?)?.toDouble() ?? 0,
                    calentamiento: s['cal'] == true,
                    rpe: (s['rpe'] as num?)?.toDouble(),
                    nota: s['nota'] as String?,
                  ),
                  hecha: s['hecha'] == true,
                ),
          ],
      },
    );
  }

  /// Las series tal y como las espera [AppBD.insertarEntrenamiento].
  ///
  /// En una sesión viva **solo se guardan las series marcadas**: las que
  /// quedaron sin hacer eran el plan, no el entrenamiento, y contarlas
  /// inflaría el volumen de un día que se cortó a la mitad.
  Map<int, List<ValoresSerie>> paraGuardar({required bool soloHechas}) => {
    for (final entrada in series.entries)
      entrada.key: [
        for (final s in entrada.value)
          if (!soloHechas || s.hecha) s.valores,
      ],
  };
}
