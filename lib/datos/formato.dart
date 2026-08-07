/// Formateo de textos que comparten varias pantallas.
library;

import 'dart:convert';

import 'package:flutter/widgets.dart' show ImageProvider;

import 'bd.dart';
import 'i18n.dart';
import 'media.dart' as media;

const meses = <String>[
  'Enero',
  'Febrero',
  'Marzo',
  'Abril',
  'Mayo',
  'Junio',
  'Julio',
  'Agosto',
  'Septiembre',
  'Octubre',
  'Noviembre',
  'Diciembre',
];

const diasSemana = <String>['L', 'M', 'X', 'J', 'V', 'S', 'D'];

/// Nombre del mes (1-12).
String mes(int numero) => meses[numero - 1];

/// '12 mar'.
String fechaCorta(DateTime? valor) {
  if (valor == null) return '';
  return '${valor.day} ${meses[valor.month - 1].substring(0, 3).toLowerCase()}';
}

/// '12 de marzo de 2026'.
String fechaLarga(DateTime? valor) {
  if (valor == null) return '';
  return '${valor.day} de ${meses[valor.month - 1].toLowerCase()} de ${valor.year}';
}

/// '19:30'. La hora del día, en 24 h, que es como se lee en español.
String hora(DateTime valor) =>
    '${valor.hour}:${valor.minute.toString().padLeft(2, '0')}';

/// Distancia en lenguaje natural hasta hoy: 'Hoy', 'Ayer', 'Hace 5 días'…
String hace(DateTime? valor) {
  if (valor == null) return 'Sin entrenar';
  final hoy = DateTime.now();
  final dias = DateTime(
    hoy.year,
    hoy.month,
    hoy.day,
  ).difference(DateTime(valor.year, valor.month, valor.day)).inDays;

  if (dias <= 0) return 'Hoy';
  if (dias == 1) return 'Ayer';
  if (dias < 7) return 'Hace $dias días';
  if (dias < 30) {
    final semanas = dias ~/ 7;
    return 'Hace $semanas ${semanas > 1 ? 'semanas' : 'semana'}';
  }
  final n = dias ~/ 30;
  return 'Hace $n ${n > 1 ? 'meses' : 'mes'}';
}

/// Cuánto hace, en lenguaje natural: 'hace 12 minutos', 'hace 2 horas'.
///
/// A diferencia de [hace], que cuenta días para el calendario, esto cuenta
/// minutos: la sesión que se ofrece retomar se dejó hace un rato, no hace días.
String desde(DateTime valor) {
  final minutos = DateTime.now().difference(valor).inMinutes;
  if (minutos < 1) return 'hace un momento';
  if (minutos < 60) return 'hace ${plural(minutos, 'minuto', 'minutos')}';

  final horas = minutos ~/ 60;
  if (horas < 24) return 'hace ${plural(horas, 'hora', 'horas')}';
  return 'hace ${plural(horas ~/ 24, 'día', 'días')}';
}

String plural(int cantidad, String singular, String plural) =>
    '$cantidad ${cantidad == 1 ? singular : plural}';

/// Formatea un número quitando el '.0' cuando es entero, como el '%g' de Python.
///
/// Con coma decimal: la interfaz está en español y `toString` siempre escribe
/// el punto, sea cual sea la localización.
String numero(num valor) {
  if (valor == valor.roundToDouble()) return valor.round().toString();
  return valor.toString().replaceAll('.', ',');
}

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

/// Un peso guardado (siempre en kilos) escrito en la unidad activa.
///
/// Es el único sitio por el que debe pasar un peso antes de pintarse: en cuanto
/// una pantalla escriba `'$valor kg'` a mano, cambiar a libras dejará de
/// funcionar justo ahí.
String peso(double kilos, Ajustes ajustes) {
  final valor = ajustes.desdeKilos(kilos);
  // Un decimal: en libras la conversión saca 132,2772 y ese resto no aporta
  // nada, ni siquiera precisión real.
  return '${numero((valor * 10).round() / 10)} ${ajustes.unidad.sufijo}';
}

/// Una duración en segundos como '1:05:12' o '34:12'.
///
/// Las horas solo aparecen si las hay: un entrenamiento de 40 minutos escrito
/// como «0:40:12» se lee peor.
String duracion(int segundos) {
  final horas = segundos ~/ 3600;
  final minutos = (segundos % 3600) ~/ 60;
  final resto = (segundos % 60).toString().padLeft(2, '0');
  if (horas == 0) return '$minutos:$resto';
  return '$horas:${minutos.toString().padLeft(2, '0')}:$resto';
}

/// Un descanso en segundos como '1 min 30 s'.
String descanso(int segundos) {
  if (segundos < 60) return '$segundos s';
  final minutos = segundos ~/ 60;
  final resto = segundos % 60;
  return resto == 0 ? '$minutos min' : '$minutos min $resto s';
}

/// El esfuerzo guardado (siempre RPE) escrito en la escala elegida.
///
/// `RIR = 10 − RPE`: son la misma información contada al revés, así que cambiar
/// de escala reinterpreta lo guardado y no hace falta migrar nada.
String esfuerzo(double valorRpe, EscalaEsfuerzo escala) => switch (escala) {
  EscalaEsfuerzo.rpe => 'RPE ${numero(valorRpe)}',
  EscalaEsfuerzo.rir => 'RIR ${numero(10 - valorRpe)}',
};

// ── Ejercicios ───────────────────────────────────────────────────────────────

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
      ? 'Ejercicio personalizado'
      : descripcion;
}

/// Miniatura de un ejercicio de rutina, o null si es personalizado.
ImageProvider? imagenEjercicio(EjercicioConFicha ejercicio) {
  final ficha = ejercicio.ficha;
  return ficha == null ? null : media.resolver(ficha.image);
}

/// GIF animado de una ficha del catálogo.
ImageProvider? animacionCatalogo(FichaCatalogo? ficha) =>
    ficha == null ? null : media.resolver(ficha.gif);
