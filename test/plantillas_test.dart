/// Tests de las plantillas de rutina.
///
/// El importante es el que recorre `assets/plantillas.json` contra el catálogo
/// de verdad: si mañana se actualiza el dataset y desaparece un id, tiene que
/// fallar aquí y no crearse una rutina con un hueco silencioso.
library;

import 'dart:convert';

import 'package:appgym/datos/bd.dart';
import 'package:appgym/datos/plantillas.dart';
import 'package:appgym/datos/semilla.dart';
import 'package:appgym/l10n/textos.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Cargar un asset necesita el binding montado.
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppBD bd;

  setUp(() => bd = AppBD(NativeDatabase.memory()));
  tearDown(() => bd.close());

  test('el asset se parsea y trae plantillas con rutinas', () async {
    final plantillas = await cargarPlantillas('es');

    expect(plantillas, isNotEmpty);
    for (final p in plantillas) {
      expect(p.nombre, isNotEmpty, reason: 'una plantilla sin nombre');
      expect(p.descripcion, isNotEmpty, reason: '${p.nombre} sin descripción');
      expect(p.rutinas, isNotEmpty, reason: '${p.nombre} sin rutinas');
      for (final r in p.rutinas) {
        expect(r.nombre, isNotEmpty);
        expect(r.ejercicios, isNotEmpty, reason: '${r.nombre} sin ejercicios');
      }
    }
  });

  test('todos los ids de las plantillas existen en el catálogo', () async {
    // Contra el catálogo real, no contra fichas de mentira: es exactamente la
    // comprobación que se quiere.
    await sembrarCatalogo(bd);
    final plantillas = await cargarPlantillas('es');

    for (final plantilla in plantillas) {
      for (final id in plantilla.idsCatalogo) {
        expect(
          await bd.ficha(id),
          isNotNull,
          reason:
              'La plantilla «${plantilla.nombre}» usa el id $id, que ya no '
              'está en el catálogo',
        );
      }
    }
  });

  test('crear desde plantilla vincula los ejercicios al catálogo', () async {
    await sembrarCatalogo(bd);
    final plantilla = (await cargarPlantillas(
      'es',
    )).firstWhere((p) => p.rutinas.length > 1);

    final creadas = await crearRutinasDesdePlantilla(bd, plantilla);
    expect(creadas, hasLength(plantilla.rutinas.length));

    for (final (indice, idRutina) in creadas.indexed) {
      final esperada = plantilla.rutinas[indice];
      final ejercicios = await bd.ejerciciosDeRutina(idRutina);

      expect((await bd.rutina(idRutina))!.nombre, esperada.nombre);
      expect(ejercicios, hasLength(esperada.ejercicios.length));
      // Vinculados al catálogo, con su ficha: no personalizados.
      expect(
        ejercicios.map((e) => e.ejercicio.idCatalogo),
        esperada.ejercicios,
      );
      expect(ejercicios.map((e) => e.ficha), everyElement(isNotNull));
      // Y en el orden de la plantilla.
      expect(
        ejercicios.map((e) => e.ejercicio.orden),
        List.generate(ejercicios.length, (i) => i),
      );
      // Sin histórico: la rutina se acaba de crear.
      expect(await bd.contarEntrenamientosRutina(idRutina), 0);
    }
  });

  test('una rutina cuyo nombre ya existe no se crea, y las demás sí', () async {
    await sembrarCatalogo(bd);
    final plantilla = (await cargarPlantillas(
      'es',
    )).firstWhere((p) => p.rutinas.length > 1);
    await bd.insertarRutina(plantilla.rutinas.first.nombre);

    final creadas = await crearRutinasDesdePlantilla(bd, plantilla);
    expect(creadas, hasLength(plantilla.rutinas.length - 1));
  });

  test('un id que no está en el catálogo se salta sin romper nada', () async {
    await sembrarCatalogo(bd);
    const plantilla = Plantilla(
      nombre: 'Inventada',
      descripcion: 'Con un id que no existe',
      rutinas: [
        RutinaPlantilla(nombre: 'Rara', ejercicios: ['0025', '9999']),
      ],
    );

    final creadas = await crearRutinasDesdePlantilla(bd, plantilla);
    expect(await bd.ejerciciosDeRutina(creadas.single), hasLength(1));
  });

  test('toda cadena trae los idiomas soportados', () async {
    // Es el equivalente al test de cobertura del catálogo, y lo que impide que
    // un idioma nuevo entre a medias: sin esto, una plantilla sin traducir
    // saldría en español dentro de la app en inglés y nadie se enteraría.
    final crudo =
        jsonDecode(await rootBundle.loadString(rutaPlantillas))
            as List<dynamic>;

    void comprobar(Object? valor, String donde) {
      expect(valor, isA<Map<String, dynamic>>(), reason: donde);
      for (final idioma in idiomasSoportados.map((l) => l.languageCode)) {
        final texto = (valor as Map<String, dynamic>)[idioma];
        expect(texto, isA<String>(), reason: '$donde no tiene «$idioma»');
        expect(
          (texto as String).trim(),
          isNotEmpty,
          reason: '$donde en $idioma',
        );
      }
    }

    for (final (indice, p) in crudo.indexed) {
      final plantilla = p as Map<String, dynamic>;
      comprobar(plantilla['nombre'], 'plantilla $indice: nombre');
      comprobar(plantilla['descripcion'], 'plantilla $indice: descripción');
      for (final r in plantilla['rutinas'] as List<dynamic>) {
        comprobar(
          (r as Map<String, dynamic>)['nombre'],
          'plantilla $indice: rutina',
        );
      }
    }
  });

  test('cada idioma resuelve sus nombres, con caída al español', () async {
    final es = await cargarPlantillas('es');
    final en = await cargarPlantillas('en');
    final klingon = await cargarPlantillas('tlh');

    expect(es.map((p) => p.nombre), contains('Torso / Pierna'));
    expect(en.map((p) => p.nombre), contains('Upper / Lower'));
    // Un idioma que no está cae al español, que es la referencia obligatoria.
    expect(klingon.map((p) => p.nombre), es.map((p) => p.nombre));
  });

  test('la rutina se crea con el nombre que el usuario veía', () async {
    await sembrarCatalogo(bd);
    final ppl = (await cargarPlantillas(
      'en',
    )).firstWhere((p) => p.nombre == 'Push / Pull / Legs');

    await crearRutinasDesdePlantilla(bd, ppl);
    final nombres = (await bd.todasLasRutinas()).map((r) => r.nombre);

    // En inglés se llaman Push, Pull y Legs, y ya son datos del usuario:
    // cambiar luego el idioma no las renombra.
    expect(nombres, containsAll(['Push', 'Pull', 'Legs']));
  });
}
