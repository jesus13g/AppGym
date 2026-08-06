/// Tests de la capa de datos.
///
/// Cada caso abre una base en memoria, así que son instantáneos y no comparten
/// estado. Esto es lo que en el proyecto Flet no se podía hacer.
library;

import 'package:appgym/datos/bd.dart';
import 'package:appgym/datos/formato.dart';
import 'package:appgym/datos/i18n.dart';
import 'package:appgym/datos/semilla.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Un par de fichas sintéticas, para no depender del asset de 1 MB.
final _catalogoFalso = [
  const EjercicioJson(
    id: '0001',
    nombre: 'barbell bench press',
    bodyPart: 'chest',
    equipment: 'barbell',
    target: 'pectorals',
    muscleGroup: 'chest',
    secondaryMuscles: ['triceps'],
    pasos: ['Túmbate en el banco.', 'Empuja la barra.'],
    image: 'images/0001.jpg',
    gif: 'videos/0001.gif',
  ),
  const EjercicioJson(
    id: '0002',
    nombre: 'dumbbell curl',
    bodyPart: 'upper arms',
    equipment: 'dumbbell',
    target: 'biceps',
    muscleGroup: 'upper arms',
    secondaryMuscles: ['forearms'],
    pasos: ['Flexiona el codo.'],
    image: 'images/0002.jpg',
    gif: 'videos/0002.gif',
  ),
];

void main() {
  late AppBD bd;

  setUp(() => bd = AppBD(NativeDatabase.memory()));
  tearDown(() => bd.close());

  group('rutinas', () {
    test('se crean con un color de la paleta y sin duplicar nombre', () async {
      final id = await bd.insertarRutina('Empuje');
      expect(id, isNotNull);

      final rutina = await bd.rutina(id!);
      expect(rutina!.nombre, 'Empuje');
      expect(rutina.color, coloresRutina.first);

      // El nombre es único.
      expect(await bd.insertarRutina('Empuje'), isNull);
    });

    test('el color rota por la paleta en vez de desbordarla', () async {
      // El bug que arrastraba la versión antigua: con más rutinas que colores,
      // indexar la lista petaba. Aquí la novena debe reutilizar el primero.
      for (var i = 0; i < coloresRutina.length + 1; i++) {
        await bd.insertarRutina('Rutina $i');
      }
      final todas = await bd.todasLasRutinas();
      expect(todas.length, coloresRutina.length + 1);
      expect(todas[coloresRutina.length - 1].color, coloresRutina.last);
      expect(todas.last.color, coloresRutina.first);
    });

    test('renombrar respeta la unicidad', () async {
      final a = (await bd.insertarRutina('Empuje'))!;
      await bd.insertarRutina('Tirón');

      expect(await bd.renombrarRutina(a, 'Tirón'), isFalse);
      expect(await bd.renombrarRutina(a, 'Empuje pesado'), isTrue);
      expect((await bd.rutina(a))!.nombre, 'Empuje pesado');
    });

    test('borrar una rutina arrastra ejercicios y entrenamientos', () async {
      final id = (await bd.insertarRutina('Pierna'))!;
      await bd.insertarEjercicio(id, 'Sentadilla');
      final ejercicio = (await bd.ejerciciosDeRutina(id)).single;
      await bd.insertarEntrenamiento(id, DateTime(2026, 3, 1), {
        ejercicio.id: const UltimaSerie(series: 4, repeticiones: 8, peso: 80),
      });

      await bd.borrarRutina(id);

      expect(await bd.ejerciciosDeRutina(id), isEmpty);
      expect(await bd.contarEntrenamientosRutina(id), 0);
      expect(await bd.seriesConFecha(id, ejercicio.id), isEmpty);
    });
  });

  group('ejercicios de una rutina', () {
    test('el mismo ejercicio del catálogo puede estar en dos rutinas', () async {
      await sembrarCatalogo(bd, datos: _catalogoFalso);
      final a = (await bd.insertarRutina('Empuje'))!;
      final b = (await bd.insertarRutina('Full body'))!;

      expect(
        await bd.insertarEjercicio(a, 'barbell bench press', idCatalogo: '0001'),
        isTrue,
      );
      // La regresión que importa: el duplicado se mira dentro de la rutina.
      expect(
        await bd.insertarEjercicio(b, 'barbell bench press', idCatalogo: '0001'),
        isTrue,
      );
      // Pero repetirlo en la misma rutina sí se rechaza.
      expect(
        await bd.insertarEjercicio(a, 'barbell bench press', idCatalogo: '0001'),
        isFalse,
      );
    });

    test('los personalizados se deduplican por nombre dentro de la rutina', () async {
      final a = (await bd.insertarRutina('Empuje'))!;
      final b = (await bd.insertarRutina('Tirón'))!;

      expect(await bd.insertarEjercicio(a, 'Press militar'), isTrue);
      expect(await bd.insertarEjercicio(a, 'Press militar'), isFalse);
      expect(await bd.insertarEjercicio(b, 'Press militar'), isTrue);
    });

    test('trae la ficha de catálogo resuelta, y null si es personalizado', () async {
      await sembrarCatalogo(bd, datos: _catalogoFalso);
      final id = (await bd.insertarRutina('Mixta'))!;
      await bd.insertarEjercicio(id, 'dumbbell curl', idCatalogo: '0002');
      await bd.insertarEjercicio(id, 'Plancha', descripcion: 'Un minuto');

      final lista = await bd.ejerciciosDeRutina(id);
      expect(lista.length, 2);
      expect(lista[0].ficha!.target, 'biceps');
      expect(subtituloEjercicio(lista[0]), 'Bíceps · Mancuerna');
      expect(lista[1].ficha, isNull);
      expect(subtituloEjercicio(lista[1]), 'Un minuto');
    });

    test('idsCatalogoEnRutina ignora los personalizados', () async {
      await sembrarCatalogo(bd, datos: _catalogoFalso);
      final id = (await bd.insertarRutina('Mixta'))!;
      await bd.insertarEjercicio(id, 'dumbbell curl', idCatalogo: '0002');
      await bd.insertarEjercicio(id, 'Plancha');

      expect(await bd.idsCatalogoEnRutina(id), {'0002'});
    });
  });

  group('catálogo', () {
    setUp(() => sembrarCatalogo(bd, datos: _catalogoFalso));

    test('la semilla es idempotente', () async {
      expect(await bd.contarCatalogo(), 2);
      await sembrarCatalogo(bd, datos: _catalogoFalso);
      expect(await bd.contarCatalogo(), 2);
    });

    test('busca por nombre en inglés y por traducción al español', () async {
      final porIngles = await bd.buscarCatalogo(texto: 'bench press');
      expect(porIngles.single.id, '0001');

      final porEspanol = await bd.buscarCatalogo(texto: 'mancuerna');
      expect(porEspanol.single.id, '0002');
    });

    test('la búsqueda es insensible a los acentos', () async {
      // «biceps» sin tilde debe encontrar el ejercicio indexado como «Bíceps».
      final sinTilde = await bd.buscarCatalogo(texto: normalizar('biceps'));
      expect(sinTilde.single.id, '0002');

      final conTilde = await bd.buscarCatalogo(texto: normalizar('bíceps'));
      expect(conTilde.single.id, '0002');
    });

    test('los filtros se combinan con AND', () async {
      expect(
        (await bd.buscarCatalogo(bodyPart: 'chest')).single.id,
        '0001',
      );
      expect(
        await bd.buscarCatalogo(bodyPart: 'chest', equipment: 'dumbbell'),
        isEmpty,
      );
    });

    test('pagina con límite y desplazamiento', () async {
      final primera = await bd.buscarCatalogo(limite: 1);
      final segunda = await bd.buscarCatalogo(limite: 1, desplazamiento: 1);
      expect(primera.single.id, isNot(segunda.single.id));
    });

    test('lista los equipamientos disponibles ordenados', () async {
      expect(await bd.equipamientosDisponibles(), ['barbell', 'dumbbell']);
    });
  });

  group('entrenamientos y progreso', () {
    late int idRutina;
    late int idEjercicio;

    setUp(() async {
      idRutina = (await bd.insertarRutina('Empuje'))!;
      await bd.insertarEjercicio(idRutina, 'Press banca');
      idEjercicio = (await bd.ejerciciosDeRutina(idRutina)).single.id;
    });

    test('guarda las series y las devuelve con su fecha, en orden', () async {
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 10), {
        idEjercicio: const UltimaSerie(series: 4, repeticiones: 8, peso: 60),
      });
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 1), {
        idEjercicio: const UltimaSerie(series: 3, repeticiones: 10, peso: 50),
      });

      final registros = await bd.seriesConFecha(idRutina, idEjercicio);
      expect(registros.map((r) => r.peso), [50, 60]);
      expect(registros.first.fecha, DateTime(2026, 3, 1));
      expect(registros.last.repeticiones, 8);
    });

    test('un entrenamiento sin series no se guarda', () async {
      expect(await bd.insertarEntrenamiento(idRutina, DateTime.now(), {}), isFalse);
      expect(await bd.contarEntrenamientosRutina(idRutina), 0);
    });

    test('ultimaSerieEjercicio devuelve la del entrenamiento más reciente', () async {
      expect(await bd.ultimaSerieEjercicio(idEjercicio), isNull);

      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 1), {
        idEjercicio: const UltimaSerie(series: 3, repeticiones: 10, peso: 50),
      });
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 10), {
        idEjercicio: const UltimaSerie(series: 4, repeticiones: 8, peso: 62.5),
      });

      final ultima = await bd.ultimaSerieEjercicio(idEjercicio);
      expect(ultima!.peso, 62.5);
      expect(ultima.series, 4);
    });

    test('resumenRutinas agrega conteo y última fecha de una vez', () async {
      final otra = (await bd.insertarRutina('Pierna'))!;
      await bd.insertarEjercicio(otra, 'Sentadilla');
      await bd.insertarEjercicio(otra, 'Peso muerto');
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 5), {
        idEjercicio: const UltimaSerie(series: 4, repeticiones: 8, peso: 60),
      });

      final resumen = await bd.resumenRutinas();
      expect(resumen.map((r) => r.nombre), ['Empuje', 'Pierna']);
      expect(resumen[0].nEjercicios, 1);
      expect(resumen[0].ultimaFecha, DateTime(2026, 3, 5));
      expect(resumen[1].nEjercicios, 2);
      expect(resumen[1].ultimaFecha, isNull);
    });

    test('entrenamientosPorDia se queda con el más reciente de cada día', () async {
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 5, 9), {
        idEjercicio: const UltimaSerie(series: 1, repeticiones: 1, peso: 10),
      });
      final otra = (await bd.insertarRutina('Pierna'))!;
      await bd.insertarEjercicio(otra, 'Sentadilla');
      final otroEjercicio = (await bd.ejerciciosDeRutina(otra)).single.id;
      await bd.insertarEntrenamiento(otra, DateTime(2026, 3, 5, 19), {
        otroEjercicio: const UltimaSerie(series: 1, repeticiones: 1, peso: 10),
      });

      final porDia = await bd.entrenamientosPorDia();
      expect(porDia[DateTime(2026, 3, 5)], otra);
    });

    test('borrar un ejercicio se lleva sus series', () async {
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 5), {
        idEjercicio: const UltimaSerie(series: 4, repeticiones: 8, peso: 60),
      });
      await bd.borrarEjercicio(idRutina, idEjercicio);

      expect(await bd.seriesConFecha(idRutina, idEjercicio), isEmpty);
      // El entrenamiento sigue existiendo; lo que desaparece son sus series.
      expect(await bd.contarEntrenamientosRutina(idRutina), 1);
    });
  });
}
