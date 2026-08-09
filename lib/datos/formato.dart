/// Formateo de textos que comparten varias pantallas.
///
/// Todo lo que depende del idioma vive en [Formato], que se construye con el
/// locale activo, las preferencias y los textos traducidos. Antes esto era un
/// puñado de funciones globales con el español dentro —los nombres de los meses,
/// la coma decimal, «Hace 3 días»—, y ninguna de esas cosas se arregla cambiando
/// el literal: cambia el orden de la fecha, cambia el separador de miles y
/// cambia el número de formas del plural.
///
/// [Formato] **no conoce `BuildContext`**: recibe datos y devuelve texto, así
/// que `test/formato_test.dart` lo prueba en los dos idiomas con fechas fijas.
/// Quien lo construye es `formatoDe(context, ref)` (ver `estado/providers.dart`),
/// que toma el idioma del árbol de widgets para que no pueda divergir del que
/// `CupertinoApp` resolvió.
library;

import 'dart:convert';

import 'package:flutter/widgets.dart' show ImageProvider;
import 'package:intl/intl.dart';

import '../l10n/textos.dart';
import 'bd.dart';
import 'i18n.dart' as i18n;
import 'semilla.dart' show pasosDe;
import 'media.dart' as media;

/// Fechas, números y unidades del idioma activo.
class Formato {
  const Formato({
    required this.locale,
    required this.textos,
    this.ajustes = const Ajustes(),
  });

  /// Código del idioma activo ('es', 'en'), tal y como lo resolvió Flutter.
  final String locale;

  /// Los textos traducidos. Hacen falta aquí porque los relativos («Hace 3
  /// días») salen de una clave ICU con plural, no de un `if` por idioma.
  final Textos textos;

  final Ajustes ajustes;

  // ── Fechas ─────────────────────────────────────────────────────────────────

  /// '1 mar' · 'Mar 1'.
  String fechaCorta(DateTime? valor) =>
      valor == null ? '' : DateFormat.MMMd(locale).format(valor);

  /// '1 de marzo de 2026' · 'March 1, 2026'.
  String fechaLarga(DateTime? valor) =>
      valor == null ? '' : DateFormat.yMMMMd(locale).format(valor);

  /// 'Marzo de 2026' · 'March 2026', para la cabecera del calendario.
  String mesYAno(DateTime valor) =>
      _capitalizar(DateFormat.yMMMM(locale).format(valor));

  /// La hora del día, en el reloj que use el idioma: '19:05' · '7:05 PM'.
  String hora(DateTime valor) => DateFormat.jm(locale).format(valor);

  /// Las iniciales de los días, **de lunes a domingo**.
  ///
  /// La semana empieza en lunes en todos los idiomas y eso es deliberado, no un
  /// descuido: la racha semanal (C17) y el reparto de `metricas.porSemana` están
  /// definidos sobre semanas de lunes a domingo, y hacer que el primer día
  /// dependiera del idioma daría rachas distintas en dos móviles del mismo
  /// usuario. Ver la nota de `metricas.lunesDe`.
  List<String> get inicialesSemana {
    // `NARROWWEEKDAYS` empieza en domingo, que es la convención de CLDR.
    final estrechos = DateFormat(null, locale).dateSymbols.NARROWWEEKDAYS;
    return [for (var i = 1; i <= 7; i++) estrechos[i % 7]];
  }

  /// Distancia en lenguaje natural hasta hoy: 'Hoy', 'Ayer', 'Hace 5 días'…
  String hace(DateTime? valor) {
    if (valor == null) return textos.comunSinEntrenar;
    final hoy = DateTime.now();
    final dias = DateTime(
      hoy.year,
      hoy.month,
      hoy.day,
    ).difference(DateTime(valor.year, valor.month, valor.day)).inDays;

    if (dias < 7) return textos.haceDias(dias < 0 ? 0 : dias);
    if (dias < 30) return textos.haceSemanas(dias ~/ 7);
    return textos.haceMeses(dias ~/ 30);
  }

  /// Cuánto hace, en lenguaje natural: 'hace 12 minutos', 'hace 2 horas'.
  ///
  /// A diferencia de [hace], que cuenta días para el calendario, esto cuenta
  /// minutos: la sesión que se ofrece retomar se dejó hace un rato, no hace
  /// días. Va en minúscula porque se incrusta dentro de una frase.
  String desde(DateTime valor) {
    final minutos = DateTime.now().difference(valor).inMinutes;
    if (minutos < 1) return textos.desdeMomento;
    if (minutos < 60) return textos.desdeMinutos(minutos);

    final horas = minutos ~/ 60;
    if (horas < 24) return textos.desdeHoras(horas);
    return textos.desdeDias(horas ~/ 24);
  }

  // ── Números ────────────────────────────────────────────────────────────────

  /// Un número con los separadores del idioma, sin el '.0' cuando es entero.
  ///
  /// '8.750' y '62,5' en español; '8,750' y '62.5' en inglés. `toString`
  /// siempre escribe el punto y nunca agrupa, sea cual sea la localización.
  String numero(num valor) => NumberFormat.decimalPattern(locale).format(valor);

  /// Un peso guardado (siempre en kilos) escrito en la unidad activa.
  ///
  /// Es el único sitio por el que debe pasar un peso antes de pintarse: en
  /// cuanto una pantalla escriba `'$valor kg'` a mano, cambiar a libras dejará
  /// de funcionar justo ahí.
  String peso(double kilos) {
    final valor = ajustes.desdeKilos(kilos);
    // Un decimal: en libras la conversión saca 132,2772 y ese resto no aporta
    // nada, ni siquiera precisión real.
    return '${numero((valor * 10).round() / 10)} ${ajustes.unidad.sufijo}';
  }

  /// Una duración en segundos como '1:05:12' o '34:12'.
  ///
  /// Las horas solo aparecen si las hay: un entrenamiento de 40 minutos escrito
  /// como «0:40:12» se lee peor. Los dos puntos son universales, así que esto no
  /// depende del idioma.
  String duracion(int segundos) {
    final horas = segundos ~/ 3600;
    final minutos = (segundos % 3600) ~/ 60;
    final resto = (segundos % 60).toString().padLeft(2, '0');
    if (horas == 0) return '$minutos:$resto';
    return '$horas:${minutos.toString().padLeft(2, '0')}:$resto';
  }

  /// Un descanso en segundos como '1 min 30 s'.
  ///
  /// `s` y `min` son los símbolos del SI y no se traducen, igual que `kg`.
  String descanso(int segundos) {
    if (segundos < 60) return '$segundos s';
    final minutos = segundos ~/ 60;
    final resto = segundos % 60;
    return resto == 0 ? '$minutos min' : '$minutos min $resto s';
  }

  /// El esfuerzo guardado (siempre RPE) escrito en la escala elegida.
  ///
  /// `RIR = 10 − RPE`: son la misma información contada al revés, así que
  /// cambiar de escala reinterpreta lo guardado y no hace falta migrar nada.
  /// Las dos siglas son internacionales y no se traducen.
  String esfuerzo(double valorRpe, EscalaEsfuerzo escala) => switch (escala) {
    EscalaEsfuerzo.rpe => 'RPE ${numero(valorRpe)}',
    EscalaEsfuerzo.rir => 'RIR ${numero(10 - valorRpe)}',
  };

  // ── Ejercicios ─────────────────────────────────────────────────────────────

  // ── Vocabulario del catálogo ───────────────────────────────────────────────

  /// Traduce una zona del cuerpo ('chest' -> 'Pecho').
  String zonaCuerpo(String? valor) => i18n.zonaCuerpo(valor, locale);

  /// Traduce un equipamiento ('dumbbell' -> 'Mancuerna').
  String equipamiento(String? valor) => i18n.equipamiento(valor, locale);

  /// Traduce un músculo ('lats' -> 'Dorsales').
  String musculo(String? valor) => i18n.musculo(valor, locale);

  /// Traduce una lista de músculos, sin repetir traducciones.
  List<String> musculos(Iterable<String>? valores) =>
      i18n.musculos(valores, locale);

  /// Los pasos de una ficha, en el idioma activo con caída al español.
  List<String> instrucciones(String? columna) => pasosDe(columna, locale);

  /// 'Pectorales · Mancuerna' para una ficha del catálogo.
  String subtituloCatalogo(FichaCatalogo? ficha) {
    if (ficha == null) return '';
    return [
      musculo(ficha.target),
      equipamiento(ficha.equipment),
    ].where((p) => p.isNotEmpty).join(' · ');
  }

  /// Subtítulo de un ejercicio de rutina: el del catálogo, o su descripción.
  String subtituloEjercicio(EjercicioConFicha ejercicio) {
    if (ejercicio.ficha != null) return subtituloCatalogo(ejercicio.ficha);
    final descripcion = ejercicio.ejercicio.descripcion?.trim();
    return (descripcion == null || descripcion.isEmpty)
        ? textos.comunEjercicioPersonalizado
        : descripcion;
  }

  static String _capitalizar(String texto) =>
      texto.isEmpty ? texto : texto[0].toUpperCase() + texto.substring(1);
}

// ── Lo que no depende del idioma ─────────────────────────────────────────────

/// Deserializa una columna de texto que guarda una lista JSON.
List<String> listaJson(String? valor) {
  if (valor == null || valor.isEmpty) return const [];
  try {
    final cargado = jsonDecode(valor);
    if (cargado is! List) return const [];
    return [for (final v in cargado) '$v'];
  } on FormatException {
    return const [];
  }
}

/// Miniatura de un ejercicio de rutina, o null si es personalizado.
ImageProvider? imagenEjercicio(EjercicioConFicha ejercicio) {
  final ficha = ejercicio.ficha;
  return ficha == null ? null : media.resolver(ficha.image);
}

/// GIF animado de una ficha del catálogo.
ImageProvider? animacionCatalogo(FichaCatalogo? ficha) =>
    ficha == null ? null : media.resolver(ficha.gif);
