/// Carga el catálogo de ejercicios desde el asset JSON a la tabla del catálogo.
///
/// `assets/ejercicios.es.json` es un recorte de
/// https://github.com/hasaneyldrm/exercises-dataset (datos bajo licencia MIT)
/// con los 1.324 ejercicios, sus metadatos y las instrucciones en español.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'ajustes.dart' show Claves;
import 'bd.dart';
import 'i18n.dart';

const rutaCatalogo = 'assets/ejercicios.es.json';

/// Los pasos en inglés, aparte del catálogo. Los genera
/// `tool/instrucciones_en.py` desde el dataset original; ver su cabecera.
const rutaInstruccionesEn = 'assets/instrucciones.en.json';

/// Versión del índice de búsqueda y del formato de las instrucciones.
///
/// `sembrarCatalogo` la compara **además** del recuento de filas, que por sí
/// solo no cambia cuando lo que cambia es lo que se escribe en cada fila. Al
/// tocar `i18n_es.dart`, `i18n_en.dart` o el formato de la columna
/// `instrucciones`, se sube este número y el catálogo se resiembra una vez en
/// el siguiente arranque.
const versionIndice = 2;

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
    this.pasosEn = const [],
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

  /// Devuelve una copia con los pasos en inglés puestos.
  EjercicioJson conPasosEn(List<String> valores) => EjercicioJson(
    id: id,
    nombre: nombre,
    bodyPart: bodyPart,
    equipment: equipment,
    target: target,
    muscleGroup: muscleGroup,
    secondaryMuscles: secondaryMuscles,
    pasos: pasos,
    image: image,
    gif: gif,
    pasosEn: valores,
  );

  final String id;
  final String nombre;
  final String bodyPart;
  final String equipment;
  final String target;
  final String muscleGroup;
  final List<String> secondaryMuscles;

  /// Los pasos en español, que es como vienen en el asset del catálogo.
  final List<String> pasos;

  /// Los pasos en inglés, que vienen del asset aparte. Vacío si no se cargó.
  final List<String> pasosEn;

  final String image;
  final String gif;

  static List<String> _listaTexto(Object? valor) => switch (valor) {
    final List<dynamic> l => [for (final v in l) '$v'],
    _ => const [],
  };

  /// Índice de búsqueda: el nombre más las traducciones de **todos** los
  /// idiomas.
  ///
  /// Así «mancuerna pecho» y «dumbbell chest» devuelven lo mismo sea cual sea
  /// el idioma activo, cambiar de idioma no toca la base y, de regalo, quien
  /// aprendió los nombres en el otro idioma los sigue encontrando. El coste es
  /// que la columna crece; con 1.324 filas y dos idiomas son unos 200 KB más en
  /// el fichero SQLite, irrelevante al lado del megabyte del asset.
  String get textoBusqueda {
    final partes = <String>[
      nombre,
      bodyPart,
      equipment,
      target,
      muscleGroup,
      ...secondaryMuscles,
      for (final idioma in idiomasCatalogo) ...[
        zonaCuerpo(bodyPart, idioma),
        equipamiento(equipment, idioma),
        musculo(target, idioma),
        musculo(muscleGroup, idioma),
        ...musculos(secondaryMuscles, idioma),
      ],
    ];
    return normalizar(partes.where((p) => p.isNotEmpty).join(' '));
  }

  /// Las instrucciones, por idioma, tal y como se guardan en la columna.
  ///
  /// Un mapa y no una lista: el idioma se elige al pintar, no al sembrar, así
  /// que cambiar de idioma no toca la base. El español está siempre, y es a
  /// donde cae [pasosDe] si falta el resto.
  Map<String, List<String>> get instruccionesPorIdioma => {
    'es': pasos,
    if (pasosEn.isNotEmpty) 'en': pasosEn,
  };

  CatalogoEjerciciosCompanion get fila => CatalogoEjerciciosCompanion.insert(
    id: id,
    nombre: nombre,
    bodyPart: bodyPart,
    equipment: equipment,
    target: target,
    muscleGroup: muscleGroup,
    secondaryMuscles: jsonEncode(secondaryMuscles),
    instrucciones: jsonEncode(instruccionesPorIdioma),
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
/// se deserializa el megabyte de JSON. Las instrucciones en inglés van por el
/// mismo camino: son otros 600 KB.
Future<List<EjercicioJson>> cargarCatalogo() async {
  final contenido = await rootBundle.loadString(rutaCatalogo);
  final catalogo = await compute(parsearCatalogo, contenido);

  // Si el asset en inglés faltara, la app sigue: las fichas enseñarían los
  // pasos en español, que es lo que hacían antes de este bloque.
  try {
    final crudo = await rootBundle.loadString(rutaInstruccionesEn);
    final enIngles = await compute(parsearInstrucciones, crudo);
    return [
      for (final e in catalogo)
        if (enIngles[e.id] case final pasos?) e.conPasosEn(pasos) else e,
    ];
  } on FlutterError {
    return catalogo;
  }
}

/// Parsea el mapa `{id: [pasos]}` de las instrucciones en inglés.
Map<String, List<String>> parsearInstrucciones(String contenido) {
  final crudo = jsonDecode(contenido) as Map<String, dynamic>;
  return {
    for (final entrada in crudo.entries)
      entrada.key: [for (final v in entrada.value as List<dynamic>) '$v'],
  };
}

/// Los pasos de una ficha en el idioma pedido, con caída al español.
///
/// La columna `instrucciones` guarda un mapa por idioma desde `versionIndice`
/// 2; antes guardaba una lista suelta, así que se admiten las dos formas para
/// que una base sin resembrar todavía no se quede sin instrucciones.
List<String> pasosDe(String? columna, String idioma) {
  if (columna == null || columna.isEmpty) return const [];
  final Object? cargado;
  try {
    cargado = jsonDecode(columna);
  } on FormatException {
    return const [];
  }
  return switch (cargado) {
    final List<dynamic> lista => [for (final v in lista) '$v'],
    final Map<String, dynamic> mapa => [
      for (final v in (mapa[idioma] ?? mapa['es'] ?? const []) as List<dynamic>)
        '$v',
    ],
    _ => const [],
  };
}

/// Siembra el catálogo si hace falta. Es idempotente y barato de llamar.
///
/// Resiembra cuando cambia el recuento de filas **o** cuando [versionIndice]
/// sube: el recuento no se entera de que lo que cambió es lo que se escribe en
/// cada fila —el índice de búsqueda o el formato de las instrucciones—, y sin
/// ese segundo disparador el índice viejo se quedaría para siempre.
///
/// Con [forzar] resiembra pase lo que pase.
/// Devuelve el número de ejercicios en el catálogo tras la operación.
Future<int> sembrarCatalogo(
  AppBD bd, {
  bool forzar = false,
  List<EjercicioJson>? datos,
}) async {
  final ejercicios = datos ?? await cargarCatalogo();
  if (ejercicios.isEmpty) return bd.contarCatalogo();

  final guardada = int.tryParse(
    (await bd.ajustesCrudos())[Claves.versionIndice] ?? '',
  );
  final alDia = guardada == versionIndice;

  if (!forzar && alDia && await bd.contarCatalogo() == ejercicios.length) {
    return ejercicios.length;
  }

  await bd.sembrarCatalogo([for (final e in ejercicios) e.fila]);
  if (!alDia) {
    await bd.fijarAjuste(Claves.versionIndice, '$versionIndice');
  }
  return bd.contarCatalogo();
}
