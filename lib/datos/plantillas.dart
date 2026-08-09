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
/// **Los nombres van por idioma y se resuelven al cargar.** Lo que se escribe
/// en la tabla `rutinas` es lo que el usuario veía al pulsar: si crea
/// «Push / Pull / Legs» con la app en inglés, sus rutinas se llaman `Push`,
/// `Pull` y `Legs`, y **no cambian** si luego cambia de idioma. Ya son sus
/// rutinas, con el nombre que él puede editar; traducirlas retroactivamente
/// sería sobrescribirle los datos.
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

  factory Plantilla.desdeMapa(Map<String, dynamic> m, String idioma) =>
      Plantilla(
        nombre: _texto(m['nombre'], idioma),
        descripcion: _texto(m['descripcion'], idioma),
        rutinas: [
          for (final r in (m['rutinas'] as List<dynamic>? ?? const []))
            if (r is Map<String, dynamic>)
              RutinaPlantilla(
                nombre: _texto(r['nombre'], idioma),
                ejercicios: [
                  for (final id
                      in (r['ejercicios'] as List<dynamic>? ?? const []))
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

/// Una cadena del JSON en el idioma pedido, con caída al español.
///
/// El español es obligatorio y es la referencia: un idioma que falte se ve
/// igual que antes en vez de quedarse en blanco. Hay un test que exige que
/// **toda** cadena traiga todos los idiomas, que es lo que impide que uno nuevo
/// entre a medias.
String _texto(Object? valor, String idioma) => switch (valor) {
  final Map<String, dynamic> m => '${m[idioma] ?? m['es'] ?? ''}',
  final String s => s,
  _ => '',
};

List<Plantilla> parsearPlantillas(String contenido, String idioma) {
  final crudo = jsonDecode(contenido) as List<dynamic>;
  return [
    for (final p in crudo)
      if (p is Map<String, dynamic>) Plantilla.desdeMapa(p, idioma),
  ];
}

/// Lee el asset. Es pequeño (unos pocos KB), así que no necesita isolate.
Future<List<Plantilla>> cargarPlantillas(String idioma) async =>
    parsearPlantillas(await rootBundle.loadString(rutaPlantillas), idioma);

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
