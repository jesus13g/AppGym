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
