/// Tests de las plantillas de rutina.
///
/// El importante es el que recorre `assets/plantillas.json` contra el catálogo
/// de verdad: si mañana se actualiza el dataset y desaparece un id, tiene que
/// fallar aquí y no crearse una rutina con un hueco silencioso.
library;

import 'package:appgym/datos/bd.dart';
import 'package:appgym/datos/plantillas.dart';
import 'package:appgym/datos/semilla.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Cargar un asset necesita el binding montado.
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppBD bd;

  setUp(() => bd = AppBD(NativeDatabase.memory()));
  tearDown(() => bd.close());

  test('el asset se parsea y trae plantillas con rutinas', () async {
    final plantillas = await cargarPlantillas();

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
    final plantillas = await cargarPlantillas();

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
    final plantilla = (await cargarPlantillas()).firstWhere(
      (p) => p.rutinas.length > 1,
    );

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
    final plantilla = (await cargarPlantillas()).firstWhere(
      (p) => p.rutinas.length > 1,
    );
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
}
