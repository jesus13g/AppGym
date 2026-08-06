/// Carga el catálogo de ejercicios desde el asset JSON a la tabla del catálogo.
///
/// `assets/ejercicios.es.json` es un recorte de
/// https://github.com/hasaneyldrm/exercises-dataset (datos bajo licencia MIT)
/// con los 1.324 ejercicios, sus metadatos y las instrucciones en español.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'bd.dart';
import 'i18n.dart';

const rutaCatalogo = 'assets/ejercicios.es.json';

/// Un ejercicio tal y como viene en el JSON, antes de entrar en la base de datos.
class EjercicioJson {
  const EjercicioJson({
    required this.id,
    required this.nombre,
    required this.bodyPart,
    required this.equipment,
    required this.target,
    required this.muscleGroup,
    required this.secondaryMuscles,
    required this.pasos,
    required this.image,
    required this.gif,
  });

  factory EjercicioJson.desdeMapa(Map<String, dynamic> m) => EjercicioJson(
    id: m['id'] as String,
    nombre: m['nombre'] as String? ?? '',
    bodyPart: m['body_part'] as String? ?? '',
    equipment: m['equipment'] as String? ?? '',
    target: m['target'] as String? ?? '',
    muscleGroup: m['muscle_group'] as String? ?? '',
    secondaryMuscles: _listaTexto(m['secondary_muscles']),
    pasos: _listaTexto(m['pasos']),
    image: m['image'] as String? ?? '',
    gif: m['gif'] as String? ?? '',
  );

  final String id;
  final String nombre;
  final String bodyPart;
  final String equipment;
  final String target;
  final String muscleGroup;
  final List<String> secondaryMuscles;
  final List<String> pasos;
  final String image;
  final String gif;

  static List<String> _listaTexto(Object? valor) => switch (valor) {
    final List<dynamic> l => [for (final v in l) '$v'],
    _ => const [],
  };

  /// Índice de búsqueda: nombre en inglés más todas las traducciones.
  ///
  /// Así «mancuerna», «pecho» o «bench press» encuentran el mismo ejercicio, y
  /// como se guarda normalizado «biceps» encuentra «bíceps».
  String get textoBusqueda {
    final partes = <String>[
      nombre,
      bodyPart,
      equipment,
      target,
      muscleGroup,
      zonaCuerpo(bodyPart),
      equipamiento(equipment),
      musculo(target),
      musculo(muscleGroup),
      ...secondaryMuscles,
      ...musculos(secondaryMuscles),
    ];
    return normalizar(partes.where((p) => p.isNotEmpty).join(' '));
  }

  CatalogoEjerciciosCompanion get fila => CatalogoEjerciciosCompanion.insert(
    id: id,
    nombre: nombre,
    bodyPart: bodyPart,
    equipment: equipment,
    target: target,
    muscleGroup: muscleGroup,
    secondaryMuscles: jsonEncode(secondaryMuscles),
    instrucciones: jsonEncode(pasos),
    image: image,
    gif: gif,
    busqueda: textoBusqueda,
  );
}

/// Parsea el JSON del catálogo. Pesa 1 MB, así que se llama desde un isolate.
List<EjercicioJson> parsearCatalogo(String contenido) {
  final crudo = jsonDecode(contenido) as List<dynamic>;
  return [
    for (final e in crudo) EjercicioJson.desdeMapa(e as Map<String, dynamic>),
  ];
}

/// Lee y parsea el catálogo fuera del hilo de interfaz.
///
/// El `compute` es lo que evita que el primer frame se quede congelado mientras
/// se deserializa el megabyte de JSON.
Future<List<EjercicioJson>> cargarCatalogo() async {
  final contenido = await rootBundle.loadString(rutaCatalogo);
  return compute(parsearCatalogo, contenido);
}

/// Siembra el catálogo si hace falta. Es idempotente y barato de llamar.
///
/// Con [forzar] vuelve a sembrar aunque el recuento ya coincida, que es lo que
/// hay que hacer tras tocar `i18n.dart`.
/// Devuelve el número de ejercicios en el catálogo tras la operación.
Future<int> sembrarCatalogo(
  AppBD bd, {
  bool forzar = false,
  List<EjercicioJson>? datos,
}) async {
  final ejercicios = datos ?? await cargarCatalogo();
  if (ejercicios.isEmpty) return bd.contarCatalogo();

  if (!forzar && await bd.contarCatalogo() == ejercicios.length) {
    return ejercicios.length;
  }

  await bd.sembrarCatalogo([for (final e in ejercicios) e.fila]);
  return bd.contarCatalogo();
}
