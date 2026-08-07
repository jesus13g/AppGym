/// Rutinas predefinidas para no empezar cada vez desde una lista vacía.
///
/// Crear una rutina hoy es entrar al catálogo y buscar los ejercicios uno a
/// uno: para una de ocho, ocho búsquedas. Las plantillas resuelven el arranque
/// y siguen siendo editables después, que es lo importante — no son un carril,
/// son un punto de partida.
///
/// Viven en `assets/plantillas.json` y referencian el catálogo por su
/// `idCatalogo`, de modo que los ejercicios entran vinculados a su ficha (con
/// imagen, músculos e instrucciones) y no como personalizados.
///
/// **Hay un test que comprueba que todos esos ids existen en el catálogo.** Si
/// mañana se actualiza el dataset y uno desaparece, falla el test en vez de
/// crearse una rutina con un hueco silencioso.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'bd.dart';

const rutaPlantillas = 'assets/plantillas.json';

/// Una rutina dentro de una plantilla, con sus ejercicios en orden.
class RutinaPlantilla {
  const RutinaPlantilla({required this.nombre, required this.ejercicios});

  final String nombre;

  /// Ids del catálogo, en el orden en el que deben quedar.
  final List<String> ejercicios;
}

/// Un programa completo: una o varias rutinas que se entrenan juntas.
class Plantilla {
  const Plantilla({
    required this.nombre,
    required this.descripcion,
    required this.rutinas,
  });

  factory Plantilla.desdeMapa(Map<String, dynamic> m) => Plantilla(
    nombre: m['nombre'] as String? ?? '',
    descripcion: m['descripcion'] as String? ?? '',
    rutinas: [
      for (final r in (m['rutinas'] as List<dynamic>? ?? const []))
        if (r is Map<String, dynamic>)
          RutinaPlantilla(
            nombre: r['nombre'] as String? ?? '',
            ejercicios: [
              for (final id in (r['ejercicios'] as List<dynamic>? ?? const []))
                '$id',
            ],
          ),
    ],
  );

  final String nombre;
  final String descripcion;
  final List<RutinaPlantilla> rutinas;

  /// Todos los ids que usa, sin repetir.
  Set<String> get idsCatalogo => {for (final r in rutinas) ...r.ejercicios};

  int get nEjercicios =>
      rutinas.fold(0, (suma, r) => suma + r.ejercicios.length);

  /// 'Empuje · Tirón · Pierna', para el subtítulo de la lista.
  String get resumen => rutinas.map((r) => r.nombre).join(' · ');
}

List<Plantilla> parsearPlantillas(String contenido) {
  final crudo = jsonDecode(contenido) as List<dynamic>;
  return [
    for (final p in crudo)
      if (p is Map<String, dynamic>) Plantilla.desdeMapa(p),
  ];
}

/// Lee el asset. Es pequeño (unos pocos KB), así que no necesita isolate.
Future<List<Plantilla>> cargarPlantillas() async =>
    parsearPlantillas(await rootBundle.loadString(rutaPlantillas));

/// Crea las rutinas de una plantilla y devuelve los ids creados.
///
/// Los nombres de los ejercicios salen del catálogo, no del JSON: así una
/// plantilla no puede desincronizarse del dataset por el lado del texto, solo
/// por el del id — y eso lo caza el test.
///
/// Una rutina cuyo nombre ya exista se salta: [AppBD.insertarRutina] devuelve
/// `null` y aquí no se insiste. Quien la llama avisa con lo que sí ha entrado.
Future<List<int>> crearRutinasDesdePlantilla(
  AppBD bd,
  Plantilla plantilla,
) async {
  final fichas = <String, FichaCatalogo>{};
  for (final id in plantilla.idsCatalogo) {
    if (await bd.ficha(id) case final ficha?) fichas[id] = ficha;
  }

  final creadas = <int>[];
  for (final rutina in plantilla.rutinas) {
    final id = await bd.crearRutinaConEjercicios(rutina.nombre, [
      for (final idCatalogo in rutina.ejercicios)
        if (fichas[idCatalogo] case final ficha?) (idCatalogo, ficha.nombre),
    ]);
    if (id != null) creadas.add(id);
  }
  return creadas;
}
