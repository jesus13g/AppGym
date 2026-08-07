/// Tests de la capa de datos.
///
/// Cada caso abre una base en memoria, así que son instantáneos y no comparten
/// estado. Esto es lo que en el proyecto Flet no se podía hacer.
library;

import 'package:appgym/datos/ajustes.dart';
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
        ejercicio.id: const [ValoresSerie(repeticiones: 8, peso: 80)],
      });

      await bd.borrarRutina(id);

      expect(await bd.ejerciciosDeRutina(id), isEmpty);
      expect(await bd.contarEntrenamientosRutina(id), 0);
      expect(await bd.seriesConFecha(id, ejercicio.id), isEmpty);
    });
  });

  group('ejercicios de una rutina', () {
    test(
      'el mismo ejercicio del catálogo puede estar en dos rutinas',
      () async {
        await sembrarCatalogo(bd, datos: _catalogoFalso);
        final a = (await bd.insertarRutina('Empuje'))!;
        final b = (await bd.insertarRutina('Full body'))!;

        expect(
          await bd.insertarEjercicio(
            a,
            'barbell bench press',
            idCatalogo: '0001',
          ),
          isTrue,
        );
        // La regresión que importa: el duplicado se mira dentro de la rutina.
        expect(
          await bd.insertarEjercicio(
            b,
            'barbell bench press',
            idCatalogo: '0001',
          ),
          isTrue,
        );
        // Pero repetirlo en la misma rutina sí se rechaza.
        expect(
          await bd.insertarEjercicio(
            a,
            'barbell bench press',
            idCatalogo: '0001',
          ),
          isFalse,
        );
      },
    );

    test(
      'los personalizados se deduplican por nombre dentro de la rutina',
      () async {
        final a = (await bd.insertarRutina('Empuje'))!;
        final b = (await bd.insertarRutina('Tirón'))!;

        expect(await bd.insertarEjercicio(a, 'Press militar'), isTrue);
        expect(await bd.insertarEjercicio(a, 'Press militar'), isFalse);
        expect(await bd.insertarEjercicio(b, 'Press militar'), isTrue);
      },
    );

    test(
      'trae la ficha de catálogo resuelta, y null si es personalizado',
      () async {
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
      },
    );

    test('se listan en el orden en que se añadieron', () async {
      final id = (await bd.insertarRutina('Empuje'))!;
      for (final nombre in ['Press banca', 'Aperturas', 'Fondos']) {
        await bd.insertarEjercicio(id, nombre);
      }

      expect((await bd.ejerciciosDeRutina(id)).map((e) => e.nombre), [
        'Press banca',
        'Aperturas',
        'Fondos',
      ]);
      expect((await bd.ejerciciosDeRutina(id)).map((e) => e.ejercicio.orden), [
        0,
        1,
        2,
      ]);
    });

    test('reordenar cambia el orden y persiste', () async {
      final id = (await bd.insertarRutina('Empuje'))!;
      for (final nombre in ['Press banca', 'Aperturas', 'Fondos']) {
        await bd.insertarEjercicio(id, nombre);
      }
      final ids = [for (final e in await bd.ejerciciosDeRutina(id)) e.id];

      // Las aperturas primero, el press al final.
      await bd.reordenarEjercicios(id, [ids[1], ids[2], ids[0]]);

      expect((await bd.ejerciciosDeRutina(id)).map((e) => e.nombre), [
        'Aperturas',
        'Fondos',
        'Press banca',
      ]);
      // Y un ejercicio nuevo entra al final, no en medio.
      await bd.insertarEjercicio(id, 'Press militar');
      expect((await bd.ejerciciosDeRutina(id)).last.nombre, 'Press militar');
    });

    test('mover un ejercicio a otra rutina conserva sus series', () async {
      final origen = (await bd.insertarRutina('Empuje'))!;
      final destino = (await bd.insertarRutina('Full body'))!;
      await bd.insertarEjercicio(origen, 'Press banca');
      final ejercicio = (await bd.ejerciciosDeRutina(origen)).single.id;
      await bd.insertarEntrenamiento(origen, DateTime(2026, 3, 1), {
        ejercicio: const [ValoresSerie(repeticiones: 10, peso: 60)],
      });

      expect(await bd.moverEjercicio(ejercicio, destino), isTrue);

      expect(await bd.ejerciciosDeRutina(origen), isEmpty);
      expect((await bd.ejerciciosDeRutina(destino)).single.id, ejercicio);
      // Las series siguen colgando de la sesión en la que se hicieron, que es
      // de la rutina de origen, y la precarga del registro las encuentra.
      expect(await bd.ultimasSeriesEjercicio(ejercicio), const [
        ValoresSerie(repeticiones: 10, peso: 60),
      ]);
      expect(await bd.seriesConFecha(origen, ejercicio), hasLength(1));
    });

    test('mover a una rutina que ya lo tiene se rechaza', () async {
      await sembrarCatalogo(bd, datos: _catalogoFalso);
      final origen = (await bd.insertarRutina('Empuje'))!;
      final destino = (await bd.insertarRutina('Full body'))!;
      await bd.insertarEjercicio(
        origen,
        'barbell bench press',
        idCatalogo: '0001',
      );
      await bd.insertarEjercicio(
        destino,
        'barbell bench press',
        idCatalogo: '0001',
      );
      final ejercicio = (await bd.ejerciciosDeRutina(origen)).single.id;

      expect(await bd.moverEjercicio(ejercicio, destino), isFalse);
      expect(await bd.ejerciciosDeRutina(origen), hasLength(1));
    });

    test('idsCatalogoEnRutina ignora los personalizados', () async {
      await sembrarCatalogo(bd, datos: _catalogoFalso);
      final id = (await bd.insertarRutina('Mixta'))!;
      await bd.insertarEjercicio(id, 'dumbbell curl', idCatalogo: '0002');
      await bd.insertarEjercicio(id, 'Plancha');

      expect(await bd.idsCatalogoEnRutina(id), {'0002'});
    });
  });

  group('ajustes', () {
    test(
      'por defecto el esfuerzo está desactivado y la escala es RPE',
      () async {
        final ajustes = await bd.ajustes();
        expect(ajustes.esfuerzoActivo, isFalse);
        expect(ajustes.escala, EscalaEsfuerzo.rpe);
      },
    );

    test('se guardan y se sobrescriben por clave', () async {
      await bd.fijarAjuste(Claves.esfuerzoActivo, '1');
      await bd.fijarAjuste(Claves.esfuerzoEscala, 'rir');
      expect((await bd.ajustes()).esfuerzoActivo, isTrue);
      expect((await bd.ajustes()).escala, EscalaEsfuerzo.rir);

      await bd.fijarAjuste(Claves.esfuerzoEscala, 'rpe');
      expect((await bd.ajustes()).escala, EscalaEsfuerzo.rpe);
    });

    test('cambiar de escala reinterpreta lo guardado, no lo migra', () async {
      // El valor vive en la base siempre como RPE; RIR = 10 − RPE.
      expect(esfuerzo(8, EscalaEsfuerzo.rpe), 'RPE 8');
      expect(esfuerzo(8, EscalaEsfuerzo.rir), 'RIR 2');
      expect(esfuerzo(9.5, EscalaEsfuerzo.rpe), 'RPE 9,5');
      expect(esfuerzo(9.5, EscalaEsfuerzo.rir), 'RIR 0,5');
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
      expect((await bd.buscarCatalogo(bodyPart: 'chest')).single.id, '0001');
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

    test('guarda una fila por serie, con su fecha y en orden', () async {
      // La pirámide que el esquema v1 no podía anotar: cada serie con su peso.
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 10), {
        idEjercicio: const [
          ValoresSerie(repeticiones: 10, peso: 60),
          ValoresSerie(repeticiones: 8, peso: 65),
          ValoresSerie(repeticiones: 6, peso: 70),
        ],
      });
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 1), {
        idEjercicio: const [ValoresSerie(repeticiones: 10, peso: 50)],
      });

      final registros = await bd.seriesConFecha(idRutina, idEjercicio);
      expect(registros.map((r) => r.peso), [50, 60, 65, 70]);
      expect(registros.map((r) => r.nSerie), [1, 1, 2, 3]);
      expect(registros.first.fecha, DateTime(2026, 3, 1));
      expect(registros.last.repeticiones, 6);
    });

    test('un entrenamiento sin series no se guarda', () async {
      expect(
        await bd.insertarEntrenamiento(idRutina, DateTime.now(), {}),
        isNull,
      );
      // Un ejercicio con la lista vacía tampoco: es lo que sustituye al
      // interruptor de «incluir ejercicio».
      expect(
        await bd.insertarEntrenamiento(idRutina, DateTime.now(), {
          idEjercicio: const [],
        }),
        isNull,
      );
      expect(await bd.contarEntrenamientosRutina(idRutina), 0);
    });

    test(
      'ultimasSeriesEjercicio devuelve todas las de la última sesión',
      () async {
        expect(await bd.ultimasSeriesEjercicio(idEjercicio), isEmpty);

        await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 1), {
          idEjercicio: const [
            ValoresSerie(repeticiones: 10, peso: 50),
            ValoresSerie(repeticiones: 10, peso: 50),
          ],
        });
        await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 10), {
          idEjercicio: const [
            ValoresSerie(repeticiones: 12, peso: 40, calentamiento: true),
            ValoresSerie(repeticiones: 8, peso: 62.5),
            ValoresSerie(repeticiones: 8, peso: 62.5),
            ValoresSerie(repeticiones: 6, peso: 65),
          ],
        });

        // Cuatro series, no un valor agregado: es lo que precarga el registro.
        expect(await bd.ultimasSeriesEjercicio(idEjercicio), const [
          ValoresSerie(repeticiones: 12, peso: 40, calentamiento: true),
          ValoresSerie(repeticiones: 8, peso: 62.5),
          ValoresSerie(repeticiones: 8, peso: 62.5),
          ValoresSerie(repeticiones: 6, peso: 65),
        ]);
      },
    );

    test('resumenSesionesEjercicio agrega por sesión, no por serie', () async {
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 1), {
        idEjercicio: const [
          ValoresSerie(repeticiones: 10, peso: 60),
          ValoresSerie(repeticiones: 8, peso: 70),
        ],
      });
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 8), {
        idEjercicio: const [ValoresSerie(repeticiones: 5, peso: 80)],
      });

      final resumen = await bd.resumenSesionesEjercicio(idRutina, idEjercicio);
      expect(resumen.length, 2);
      expect(resumen.first.nSeries, 2);
      expect(resumen.first.volumen, 10 * 60 + 8 * 70);
      expect(resumen.first.pesoMaximo, 70);
      // Epley: 70 × (1 + 8/30) = 88,67, mejor que 60 × (1 + 10/30) = 80.
      expect(resumen.first.mejor1RM, closeTo(88.67, 0.01));
      // Ocho repeticiones son de fiar, así que las dos estimaciones coinciden.
      expect(resumen.first.mejor1RMFiable, closeTo(88.67, 0.01));
      expect(resumen.first.fiable, isTrue);
      expect(resumen.last.fecha, DateTime(2026, 3, 8));
    });

    test('una sesión de series largas no deja estimación fiable', () async {
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 1), {
        idEjercicio: const [
          ValoresSerie(repeticiones: 20, peso: 40),
          ValoresSerie(repeticiones: 15, peso: 45),
        ],
      });

      final resumen = await bd.resumenSesionesEjercicio(idRutina, idEjercicio);
      // Se estima igual —hay que enseñar algo—, pero marcado: nada de esto
      // puede convertirse en un récord de 1RM.
      expect(resumen.single.mejor1RM, isPositive);
      expect(resumen.single.mejor1RMFiable, isNull);
      expect(resumen.single.fiable, isFalse);
    });

    test('las dos estimaciones conviven en la misma sesión', () async {
      // La serie larga estima más alto que la corta, así que `mejor1RM` sale de
      // ella y la sesión queda marcada; `mejor1RMFiable` conserva la buena, que
      // es la que puede llegar a ser récord.
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 1), {
        idEjercicio: const [
          ValoresSerie(repeticiones: 5, peso: 60), // Epley: 70
          ValoresSerie(repeticiones: 20, peso: 60), // Epley: 100
        ],
      });

      final resumen = await bd.resumenSesionesEjercicio(idRutina, idEjercicio);
      expect(resumen.single.mejor1RM, closeTo(100, 0.01));
      expect(resumen.single.mejor1RMFiable, closeTo(70, 0.01));
      expect(resumen.single.fiable, isFalse);
    });

    test('la fórmula elegida cambia la estimación', () async {
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 1), {
        idEjercicio: const [ValoresSerie(repeticiones: 12, peso: 60)],
      });

      final epley = await bd.resumenSesionesEjercicio(idRutina, idEjercicio);
      expect(epley.single.mejor1RM, closeTo(84, 0.01));

      // Brzycki: 60 × 36 / 25 = 86,4.
      final brzycki = await bd.resumenSesionesEjercicio(
        idRutina,
        idEjercicio,
        formula: Formula.brzycki,
      );
      expect(brzycki.single.mejor1RM, closeTo(86.4, 0.01));
    });

    test('una repetición se estima como el peso, no como Epley cruda', () async {
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 1), {
        idEjercicio: const [ValoresSerie(repeticiones: 1, peso: 100)],
      });

      final resumen = await bd.resumenSesionesEjercicio(idRutina, idEjercicio);
      // La fórmula cruda daría 103,33; el SQL lleva el mismo caso especial que
      // `metricas.unoRm`, y que no se separen es justo lo que fija este test.
      expect(resumen.single.mejor1RM, 100);
    });

    test('el calentamiento no cuenta en volumen, máximo ni 1RM', () async {
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 1), {
        idEjercicio: const [
          ValoresSerie(repeticiones: 20, peso: 100, calentamiento: true),
          ValoresSerie(repeticiones: 10, peso: 60),
        ],
      });

      final resumen = await bd.resumenSesionesEjercicio(idRutina, idEjercicio);
      expect(resumen.single.nSeries, 1);
      expect(resumen.single.volumen, 600);
      expect(resumen.single.pesoMaximo, 60);
      expect(resumen.single.mejor1RM, closeTo(80, 0.01));

      // Pero la serie sigue guardada: se registra, no se descarta.
      final series = await bd.seriesConFecha(idRutina, idEjercicio);
      expect(series.length, 2);
      expect(series.first.calentamiento, isTrue);
    });

    test('sesionesConVolumen suma sin contar el calentamiento', () async {
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 1), {
        idEjercicio: const [
          ValoresSerie(repeticiones: 20, peso: 100, calentamiento: true),
          ValoresSerie(repeticiones: 10, peso: 60),
        ],
      });
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 8), {
        idEjercicio: const [ValoresSerie(repeticiones: 8, peso: 65)],
      });

      final sesiones = await bd.sesionesConVolumen();
      // De la más reciente a la más antigua, que es lo que espera el resumen
      // semanal para dar con la última sesión sin ordenar nada.
      expect(sesiones.first.fecha, DateTime(2026, 3, 8));
      expect(sesiones.first.volumen, 520);
      expect(sesiones.last.volumen, 600);
    });

    test('sesionesConVolumen respeta el «desde»', () async {
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 1, 5), {
        idEjercicio: const [ValoresSerie(repeticiones: 10, peso: 60)],
      });
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 8), {
        idEjercicio: const [ValoresSerie(repeticiones: 10, peso: 60)],
      });

      final recientes = await bd.sesionesConVolumen(
        desde: DateTime(2026, 3, 1),
      );
      expect(recientes, hasLength(1));
      expect(await bd.sesionesConVolumen(), hasLength(2));
    });

    test('una sesión sin series aparece con volumen cero', () async {
      // No deberían existir, pero si una se cuela no puede desaparecer del
      // resumen ni reventar la suma.
      await bd
          .into(bd.entrenamientos)
          .insert(
            EntrenamientosCompanion.insert(
              idRutina: idRutina,
              fecha: DateTime(2026, 3, 1),
            ),
          );

      final sesiones = await bd.sesionesConVolumen();
      expect(sesiones.single.volumen, 0);
    });

    test('resumenRutinas agrega conteo y última fecha de una vez', () async {
      final otra = (await bd.insertarRutina('Pierna'))!;
      await bd.insertarEjercicio(otra, 'Sentadilla');
      await bd.insertarEjercicio(otra, 'Peso muerto');
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 5), {
        idEjercicio: const [ValoresSerie(repeticiones: 8, peso: 60)],
      });

      final resumen = await bd.resumenRutinas();
      expect(resumen.map((r) => r.nombre), ['Empuje', 'Pierna']);
      expect(resumen[0].nEjercicios, 1);
      expect(resumen[0].ultimaFecha, DateTime(2026, 3, 5));
      expect(resumen[1].nEjercicios, 2);
      expect(resumen[1].ultimaFecha, isNull);
    });

    group('entrenamientosPorDia', () {
      /// Un entrenamiento cualquiera, que aquí solo importa por su fecha.
      Future<void> entrenar(int rutina, int ejercicio, DateTime fecha) =>
          bd.insertarEntrenamiento(rutina, fecha, {
            ejercicio: const [ValoresSerie(repeticiones: 1, peso: 10)],
          });

      Future<int> otraRutina(String nombre) async {
        final id = (await bd.insertarRutina(nombre))!;
        await bd.insertarEjercicio(id, 'Sentadilla');
        return id;
      }

      test('un día con dos rutinas distintas devuelve las dos', () async {
        final otra = await otraRutina('Pierna');
        final otroEjercicio = (await bd.ejerciciosDeRutina(otra)).single.id;

        await entrenar(idRutina, idEjercicio, DateTime(2026, 3, 5, 9));
        await entrenar(otra, otroEjercicio, DateTime(2026, 3, 5, 19));

        final porDia = await bd.entrenamientosPorDia(
          desde: DateTime(2026, 3),
          hasta: DateTime(2026, 4),
        );
        final dia = porDia[DateTime(2026, 3, 5)]!;
        // La segunda ya no pisa a la primera, que es lo que hacía que el
        // calendario pintara una sola.
        expect(dia.map((s) => s.idRutina), [idRutina, otra]);
      });

      test('dos sesiones de la misma rutina son una sola rutina', () async {
        await entrenar(idRutina, idEjercicio, DateTime(2026, 3, 5, 9));
        await entrenar(idRutina, idEjercicio, DateTime(2026, 3, 5, 19));

        final porDia = await bd.entrenamientosPorDia(
          desde: DateTime(2026, 3),
          hasta: DateTime(2026, 4),
        );
        final dia = porDia[DateTime(2026, 3, 5)]!;
        expect(dia, hasLength(2));
        expect({for (final s in dia) s.idRutina}, {idRutina});
      });

      test('el rango acota: pintar un mes no trae los demás', () async {
        await entrenar(idRutina, idEjercicio, DateTime(2026, 2, 27));
        await entrenar(idRutina, idEjercicio, DateTime(2026, 3, 5));
        await entrenar(idRutina, idEjercicio, DateTime(2026, 4, 1));

        final marzo = await bd.entrenamientosPorDia(
          desde: DateTime(2026, 3),
          hasta: DateTime(2026, 4),
        );
        expect(marzo.keys, [DateTime(2026, 3, 5)]);
      });
    });

    test('actualizar una sesión reemplaza sus series en bloque', () async {
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 1), {
        idEjercicio: const [
          ValoresSerie(repeticiones: 10, peso: 60),
          ValoresSerie(repeticiones: 10, peso: 60),
        ],
      });
      final sesion = (await bd.historialRutina(idRutina)).single;

      // Se corrige el peso de la segunda serie y se añade una tercera.
      final bien = await bd.actualizarEntrenamiento(sesion.id, sesion.fecha, {
        idEjercicio: const [
          ValoresSerie(repeticiones: 10, peso: 60),
          ValoresSerie(repeticiones: 10, peso: 55),
          ValoresSerie(repeticiones: 8, peso: 55),
        ],
      });

      expect(bien, isTrue);
      final series = await bd.seriesConFecha(idRutina, idEjercicio);
      expect(series.map((s) => s.peso), [60, 55, 55]);
      expect(series.map((s) => s.nSerie), [1, 2, 3]);
      // La fecha no cambia si no se cambia, y no aparece una sesión de más.
      expect(await bd.contarEntrenamientosRutina(idRutina), 1);
      expect((await bd.sesion(sesion.id))!.fecha, DateTime(2026, 3, 1));
    });

    test(
      'actualizar sin series o sobre una sesión que no existe no hace nada',
      () async {
        await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 1), {
          idEjercicio: const [ValoresSerie(repeticiones: 10, peso: 60)],
        });
        final sesion = (await bd.historialRutina(idRutina)).single;

        expect(
          await bd.actualizarEntrenamiento(sesion.id, sesion.fecha, {
            idEjercicio: const [],
          }),
          isFalse,
        );
        expect(
          await bd.actualizarEntrenamiento(9999, DateTime.now(), {
            idEjercicio: const [ValoresSerie(repeticiones: 1, peso: 1)],
          }),
          isFalse,
        );
        expect(await bd.seriesConFecha(idRutina, idEjercicio), hasLength(1));
      },
    );

    test(
      'borrar una sesión se lleva sus series y la saca del historial',
      () async {
        await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 1), {
          idEjercicio: const [
            ValoresSerie(repeticiones: 10, peso: 60),
            ValoresSerie(repeticiones: 10, peso: 60),
          ],
        });
        await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 8), {
          idEjercicio: const [ValoresSerie(repeticiones: 8, peso: 65)],
        });

        final historial = await bd.historialRutina(idRutina);
        expect(historial.map((s) => s.fecha), [
          DateTime(2026, 3, 8),
          DateTime(2026, 3, 1),
        ]);

        await bd.borrarEntrenamiento(historial.first.id);

        expect(await bd.historialRutina(idRutina), hasLength(1));
        expect(await bd.contarEntrenamientosRutina(idRutina), 1);
        // El cascade se lleva las series de esa sesión y solo esas.
        final series = await bd.seriesConFecha(idRutina, idEjercicio);
        expect(series, hasLength(2));
        expect(series.map((s) => s.peso), [60, 60]);
        expect(await bd.sesion(historial.first.id), isNull);
      },
    );

    test('el historial trae las cifras de cada sesión ya agregadas', () async {
      await bd.insertarEjercicio(idRutina, 'Fondos');
      final otro = (await bd.ejerciciosDeRutina(idRutina)).last.id;
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 1), {
        idEjercicio: const [
          ValoresSerie(repeticiones: 20, peso: 20, calentamiento: true),
          ValoresSerie(repeticiones: 10, peso: 60),
        ],
        otro: const [ValoresSerie(repeticiones: 12, peso: 10)],
      });

      final sesion = (await bd.historialRutina(idRutina)).single;
      expect(sesion.nEjercicios, 2);
      expect(sesion.nSeries, 3);
      // El calentamiento cuenta como serie, pero no suma volumen.
      expect(sesion.volumen, 10 * 60 + 12 * 10);
    });

    test(
      'la sesión trae sus ejercicios con la ficha y las series en orden',
      () async {
        await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 1), {
          idEjercicio: const [
            ValoresSerie(repeticiones: 12, peso: 40, calentamiento: true),
            ValoresSerie(repeticiones: 10, peso: 60),
            ValoresSerie(repeticiones: 8, peso: 65),
          ],
        });
        final id = (await bd.historialRutina(idRutina)).single.id;

        final sesion = (await bd.sesion(id))!;
        expect(sesion.idRutina, idRutina);
        expect(sesion.ejercicios.single.ejercicio.nombre, 'Press banca');
        expect(sesion.ejercicios.single.series, const [
          ValoresSerie(repeticiones: 12, peso: 40, calentamiento: true),
          ValoresSerie(repeticiones: 10, peso: 60),
          ValoresSerie(repeticiones: 8, peso: 65),
        ]);
        expect(sesion.volumen, 10 * 60 + 8 * 65);
        // Y sale en el formato que espera actualizarEntrenamiento.
        expect(sesion.series[idEjercicio], hasLength(3));
      },
    );

    test('guarda la nota de la sesión y la de cada serie', () async {
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 1), {
        idEjercicio: const [
          ValoresSerie(repeticiones: 10, peso: 60, rpe: 8),
          ValoresSerie(
            repeticiones: 8,
            peso: 65,
            rpe: 9.5,
            nota: 'Fallo en la última',
          ),
        ],
      }, nota: 'Me dolía el hombro');

      final sesion = (await bd.sesion(1))!;
      expect(sesion.nota, 'Me dolía el hombro');
      expect(sesion.ejercicios.single.series, const [
        ValoresSerie(repeticiones: 10, peso: 60, rpe: 8),
        ValoresSerie(
          repeticiones: 8,
          peso: 65,
          rpe: 9.5,
          nota: 'Fallo en la última',
        ),
      ]);
      // Y el historial marca que esa sesión tiene algo escrito.
      expect((await bd.historialRutina(idRutina)).single.tieneNota, isTrue);
    });

    test('una nota en blanco es no tener nota', () async {
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 1), {
        idEjercicio: const [
          ValoresSerie(repeticiones: 10, peso: 60, nota: '   '),
        ],
      }, nota: '  ');

      final sesion = (await bd.sesion(1))!;
      expect(sesion.nota, isNull);
      expect(sesion.ejercicios.single.series.single.nota, isNull);
      expect((await bd.historialRutina(idRutina)).single.tieneNota, isFalse);
    });

    test('borrar un ejercicio se lleva sus series', () async {
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 5), {
        idEjercicio: const [ValoresSerie(repeticiones: 8, peso: 60)],
      });
      await bd.borrarEjercicio(idRutina, idEjercicio);

      expect(await bd.seriesConFecha(idRutina, idEjercicio), isEmpty);
      // El entrenamiento sigue existiendo; lo que desaparece son sus series.
      expect(await bd.contarEntrenamientosRutina(idRutina), 1);
    });
  });
  // ── B7 y B8: descanso, sesión viva y récords ───────────────────────────────

  group('descanso por ejercicio', () {
    test('se fija por ejercicio y se vuelve al global con null', () async {
      final idRutina = (await bd.insertarRutina('Empuje'))!;
      await bd.insertarEjercicio(idRutina, 'Sentadilla');
      final id = (await bd.ejerciciosDeRutina(idRutina)).single.id;

      // Sin fijar nada, el ejercicio no manda: decide el ajuste global.
      expect(
        (await bd.ejerciciosDeRutina(idRutina)).single.ejercicio.descansoSeg,
        isNull,
      );

      await bd.fijarDescansoEjercicio(id, 180);
      expect(
        (await bd.ejerciciosDeRutina(idRutina)).single.ejercicio.descansoSeg,
        180,
      );

      await bd.fijarDescansoEjercicio(id, null);
      expect(
        (await bd.ejerciciosDeRutina(idRutina)).single.ejercicio.descansoSeg,
        isNull,
      );
    });
  });

  group('sesión en curso', () {
    late int idRutina;
    late int idEjercicio;

    setUp(() async {
      idRutina = (await bd.insertarRutina('Empuje'))!;
      await bd.insertarEjercicio(idRutina, 'Press banca');
      idEjercicio = (await bd.ejerciciosDeRutina(idRutina)).single.id;
    });

    test('se guarda, se lee y se descarta', () async {
      expect(await bd.sesionActiva(), isNull);

      final inicio = DateTime(2026, 8, 1, 18, 30);
      await bd.guardarSesionActiva(idRutina, inicio, '{"a":1}');

      final borrador = (await bd.sesionActiva())!;
      expect(borrador.idRutina, idRutina);
      expect(borrador.inicio, inicio);
      expect(borrador.estado, '{"a":1}');

      await bd.descartarSesionActiva();
      expect(await bd.sesionActiva(), isNull);
    });

    test('como mucho hay un borrador: el nuevo pisa al anterior', () async {
      final otra = (await bd.insertarRutina('Pierna'))!;
      await bd.guardarSesionActiva(idRutina, DateTime(2026, 8, 1), '{}');
      await bd.guardarSesionActiva(otra, DateTime(2026, 8, 2), '{"b":2}');

      final borrador = (await bd.sesionActiva())!;
      expect(borrador.idRutina, otra);
      expect(borrador.estado, '{"b":2}');
    });

    test('confirmar guarda la duración y borra el borrador a la vez', () async {
      await bd.guardarSesionActiva(idRutina, DateTime(2026, 8, 1), '{}');

      final id = await bd.insertarEntrenamiento(
        idRutina,
        DateTime(2026, 8, 1, 19),
        {
          idEjercicio: const [ValoresSerie(repeticiones: 10, peso: 60)],
        },
        duracionSeg: 3600,
        descartarBorrador: true,
      );

      expect(id, isNotNull);
      expect((await bd.sesion(id!))!.entrenamiento.duracionSeg, 3600);
      // Si esto quedara vivo, al reabrir la app aparecería un falso «tienes una
      // sesión en curso» sobre un entrenamiento ya guardado.
      expect(await bd.sesionActiva(), isNull);
    });

    test('editar una sesión no le cambia la duración', () async {
      final id = (await bd.insertarEntrenamiento(
        idRutina,
        DateTime(2026, 8, 1),
        {
          idEjercicio: const [ValoresSerie(repeticiones: 10, peso: 60)],
        },
        duracionSeg: 2400,
      ))!;

      await bd.actualizarEntrenamiento(id, DateTime(2026, 8, 1), {
        idEjercicio: const [ValoresSerie(repeticiones: 10, peso: 65)],
      });

      expect((await bd.sesion(id))!.entrenamiento.duracionSeg, 2400);
    });

    test('borrar la rutina se lleva su borrador', () async {
      await bd.guardarSesionActiva(idRutina, DateTime(2026, 8, 1), '{}');
      await bd.borrarRutina(idRutina);
      expect(await bd.sesionActiva(), isNull);
    });
  });

  group('récords de una sesión', () {
    late int idRutina;
    late int idEjercicio;

    setUp(() async {
      idRutina = (await bd.insertarRutina('Empuje'))!;
      await bd.insertarEjercicio(idRutina, 'Press banca');
      idEjercicio = (await bd.ejerciciosDeRutina(idRutina)).single.id;
    });

    test('la primera vez cuenta como récord, sin peso anterior', () async {
      final id = (await bd.insertarEntrenamiento(
        idRutina,
        DateTime(2026, 3, 1),
        {
          idEjercicio: const [ValoresSerie(repeticiones: 10, peso: 60)],
        },
      ))!;

      final records = await bd.recordsDeSesion(id);
      expect(records.single.nombre, 'Press banca');
      expect(records.single.pesoMaximo, 60);
      expect(records.single.pesoAnterior, isNull);
      // Epley: 60 × (1 + 10/30) = 80.
      expect(records.single.mejor1RM, closeTo(80, 0.001));
    });

    test('solo hay récord si se supera lo anterior', () async {
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 1), {
        idEjercicio: const [ValoresSerie(repeticiones: 10, peso: 60)],
      });
      // Más repeticiones con el mismo peso: no bate el peso máximo, pero sí el
      // 1RM estimado (60 × 1,4 = 84 contra 80) y el volumen (720 contra 600).
      // Antes de C16 esto no era récord de nada, porque solo se miraba el peso.
      final masReps = (await bd.insertarEntrenamiento(
        idRutina,
        DateTime(2026, 3, 8),
        {
          idEjercicio: const [ValoresSerie(repeticiones: 12, peso: 60)],
        },
      ))!;
      expect((await bd.recordsDeSesion(masReps)).single.batidos, {
        TipoRecord.unoRm,
        TipoRecord.volumen,
      });

      // Menos peso y menos repeticiones: no bate absolutamente nada.
      final peor = (await bd.insertarEntrenamiento(
        idRutina,
        DateTime(2026, 3, 12),
        {
          idEjercicio: const [ValoresSerie(repeticiones: 6, peso: 55)],
        },
      ))!;
      expect(await bd.recordsDeSesion(peor), isEmpty);

      final mejor = (await bd.insertarEntrenamiento(
        idRutina,
        DateTime(2026, 3, 15),
        {
          idEjercicio: const [ValoresSerie(repeticiones: 8, peso: 65)],
        },
      ))!;
      final records = await bd.recordsDeSesion(mejor);
      expect(records.single.pesoMaximo, 65);
      expect(records.single.pesoAnterior, 60);
      expect(records.single.batidos, contains(TipoRecord.peso));

      // Y no depende de cuándo se pregunte: la sesión floja sigue sin ser
      // récord ahora que existe una posterior mejor.
      expect(await bd.recordsDeSesion(peor), isEmpty);
    });

    test('una serie larga no da récord de 1RM', () async {
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 1), {
        idEjercicio: const [ValoresSerie(repeticiones: 10, peso: 60)],
      });
      // Epley daría 40 × (1 + 20/30) = 66,7, por debajo de 80; pero aunque
      // saliera más alto, veinte repeticiones no estiman un máximo.
      final larga = (await bd.insertarEntrenamiento(
        idRutina,
        DateTime(2026, 3, 8),
        {
          idEjercicio: const [ValoresSerie(repeticiones: 20, peso: 45)],
        },
      ))!;

      final records = await bd.recordsDeSesion(larga);
      // Sí bate el volumen (900 contra 600), pero el 1RM ni se calcula.
      expect(records.single.mejor1RM, isNull);
      expect(records.single.batidos, {TipoRecord.volumen});
    });

    test('con Brzycki la estimación cambia', () async {
      final id = (await bd.insertarEntrenamiento(
        idRutina,
        DateTime(2026, 3, 1),
        {
          idEjercicio: const [ValoresSerie(repeticiones: 10, peso: 60)],
        },
      ))!;

      final epley = await bd.recordsDeSesion(id);
      expect(epley.single.mejor1RM, closeTo(80, 0.001));

      // Brzycki: 60 × 36 / 27 = 80.
      final brzycki = await bd.recordsDeSesion(id, formula: Formula.brzycki);
      expect(brzycki.single.mejor1RM, closeTo(80, 0.001));

      // Con doce repeticiones sí se separan: Epley 84, Brzycki 86,4.
      final doce = (await bd.insertarEntrenamiento(
        idRutina,
        DateTime(2026, 3, 8),
        {
          idEjercicio: const [ValoresSerie(repeticiones: 12, peso: 60)],
        },
      ))!;
      expect(
        (await bd.recordsDeSesion(doce)).single.mejor1RM,
        closeTo(84, 0.001),
      );
      expect(
        (await bd.recordsDeSesion(
          doce,
          formula: Formula.brzycki,
        )).single.mejor1RM,
        closeTo(86.4, 0.001),
      );
    });

    test('el calentamiento no bate récords', () async {
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 1), {
        idEjercicio: const [ValoresSerie(repeticiones: 10, peso: 60)],
      });
      final id = (await bd.insertarEntrenamiento(
        idRutina,
        DateTime(2026, 3, 8),
        {
          idEjercicio: const [
            ValoresSerie(repeticiones: 3, peso: 100, calentamiento: true),
            ValoresSerie(repeticiones: 10, peso: 55),
          ],
        },
      ))!;

      expect(await bd.recordsDeSesion(id), isEmpty);
    });
  });

  // ── B11: duplicar rutina ───────────────────────────────────────────────────

  group('duplicar rutina', () {
    test('copia ejercicios y orden, y no el histórico', () async {
      final idRutina = (await bd.insertarRutina('Empuje'))!;
      for (final nombre in ['Press banca', 'Aperturas', 'Fondos']) {
        await bd.insertarEjercicio(idRutina, nombre);
      }
      final ejercicios = await bd.ejerciciosDeRutina(idRutina);
      await bd.fijarDescansoEjercicio(ejercicios.first.id, 180);
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 1), {
        ejercicios.first.id: const [ValoresSerie(repeticiones: 10, peso: 60)],
      });

      final copia = (await bd.duplicarRutina(idRutina))!;
      expect((await bd.rutina(copia))!.nombre, 'Empuje (copia)');

      final copiados = await bd.ejerciciosDeRutina(copia);
      expect(copiados.map((e) => e.nombre), [
        'Press banca',
        'Aperturas',
        'Fondos',
      ]);
      expect(copiados.map((e) => e.ejercicio.orden), [0, 1, 2]);
      // El descanso propio viaja con el ejercicio; el histórico no.
      expect(copiados.first.ejercicio.descansoSeg, 180);
      expect(await bd.contarEntrenamientosRutina(copia), 0);
      // Y la original se queda como estaba.
      expect(await bd.contarEntrenamientosRutina(idRutina), 1);
    });

    test('no duplica si el nombre propuesto ya existe', () async {
      final idRutina = (await bd.insertarRutina('Empuje'))!;
      await bd.insertarRutina('Empuje B');

      expect(
        await bd.duplicarRutina(idRutina, nuevoNombre: 'Empuje B'),
        isNull,
      );
      expect(await bd.todasLasRutinas(), hasLength(2));
    });
  });

  // ── B12: favoritos, vistos y filtro por músculo ────────────────────────────

  group('favoritos y vistos', () {
    setUp(() => sembrarCatalogo(bd, datos: _catalogoFalso));

    test('marcar y desmarcar un favorito', () async {
      await bd.marcarFavorito('0001', true);
      expect(await bd.idsFavoritos(), {'0001'});
      expect((await bd.fichasFavoritas()).single.nombre, 'barbell bench press');

      // Marcar dos veces no duplica ni falla.
      await bd.marcarFavorito('0001', true);
      expect(await bd.fichasFavoritas(), hasLength(1));

      await bd.marcarFavorito('0001', false);
      expect(await bd.fichasFavoritas(), isEmpty);
    });

    test('resembrar el catálogo no se lleva los favoritos', () async {
      await bd.marcarFavorito('0002', true);
      // Es lo que pasa cuando cambia el dataset: sin la clave foránea puesta,
      // el borrado y la reinserción del catálogo no tocan los favoritos.
      await sembrarCatalogo(bd, datos: _catalogoFalso, forzar: true);
      expect(await bd.idsFavoritos(), {'0002'});
    });

    test('un favorito que ya no está en el catálogo no se pinta', () async {
      await bd.marcarFavorito('9999', true);
      expect(await bd.idsFavoritos(), {'9999'});
      expect(await bd.fichasFavoritas(), isEmpty);
    });

    test('los vistos se quedan en los más recientes', () async {
      await bd.registrarVisto('0001', conservar: 1);
      await bd.registrarVisto('0002', conservar: 1);

      final vistos = await bd.vistosRecientes();
      expect(vistos.single.id, '0002');
    });

    test('volver a ver una ficha la sube, sin duplicarla', () async {
      await bd.registrarVisto('0001');
      await bd.registrarVisto('0002');
      await bd.registrarVisto('0001');

      final vistos = await bd.vistosRecientes();
      expect(vistos.map((v) => v.id), ['0001', '0002']);
    });

    test('buscarCatalogo filtra por músculo objetivo', () async {
      expect(
        (await bd.buscarCatalogo(target: 'biceps')).single.nombre,
        'dumbbell curl',
      );
      expect(await bd.buscarCatalogo(target: 'glutes'), isEmpty);
      // Y se combina con el resto de filtros.
      expect(
        await bd.buscarCatalogo(target: 'biceps', equipment: 'barbell'),
        isEmpty,
      );
    });

    test('la paginación sigue funcionando con el filtro por músculo', () async {
      // 45 fichas del mismo objetivo: más de una página de 40.
      await sembrarCatalogo(
        bd,
        datos: [
          for (final numero in [
            for (var i = 0; i < 45; i++) i.toString().padLeft(4, '0'),
          ])
            EjercicioJson(
              id: 'x$numero',
              nombre: 'curl $numero',
              bodyPart: 'upper arms',
              equipment: 'dumbbell',
              target: 'biceps',
              muscleGroup: 'upper arms',
              secondaryMuscles: const [],
              pasos: const [],
              image: '',
              gif: '',
            ),
        ],
        forzar: true,
      );

      final primera = await bd.buscarCatalogo(target: 'biceps');
      expect(primera, hasLength(40));

      final segunda = await bd.buscarCatalogo(
        target: 'biceps',
        desplazamiento: 40,
      );
      expect(segunda, hasLength(5));
      // Sin solaparse con la primera tanda.
      expect({
        for (final f in [...primera, ...segunda]) f.id,
      }, hasLength(45));
    });

    test('los objetivos vienen con su recuento y ordenados', () async {
      expect(await bd.objetivosDisponibles(), [
        ('biceps', 1),
        ('pectorals', 1),
      ]);
    });

    test('rutinasQueContienen dice dónde está ya un ejercicio', () async {
      final empuje = (await bd.insertarRutina('Empuje'))!;
      final full = (await bd.insertarRutina('Full body'))!;
      await bd.insertarEjercicio(empuje, 'Press', idCatalogo: '0001');
      await bd.insertarEjercicio(full, 'Press', idCatalogo: '0001');
      await bd.insertarEjercicio(full, 'Curl', idCatalogo: '0002');

      expect((await bd.rutinasQueContienen('0001')).map((r) => r.nombre), [
        'Empuje',
        'Full body',
      ]);
      expect((await bd.rutinasQueContienen('0002')).map((r) => r.nombre), [
        'Full body',
      ]);
    });
  });

  // ── B13: medidas del cuerpo ────────────────────────────────────────────────

  group('medidas', () {
    test('un valor por día y tipo: el último manda', () async {
      await bd.registrarMedida(DateTime(2026, 8, 1, 8), 'peso', 78.4);
      await bd.registrarMedida(DateTime(2026, 8, 1, 21), 'peso', 78.9);

      final serie = await bd.serieMedida('peso');
      expect(serie, hasLength(1));
      expect(serie.single.valor, 78.9);
      // La hora se descarta: la fecha guardada es el día a medianoche.
      expect(serie.single.fecha, DateTime(2026, 8, 1));
    });

    test('tipos distintos el mismo día conviven', () async {
      await bd.registrarMedida(DateTime(2026, 8, 1), 'peso', 78.4);
      await bd.registrarMedida(DateTime(2026, 8, 1), 'cintura', 82);

      expect(await bd.serieMedida('peso'), hasLength(1));
      expect(await bd.serieMedida('cintura'), hasLength(1));
      expect(await bd.todasLasMedidas(), hasLength(2));
    });

    test('la serie sale en orden y la última es la más reciente', () async {
      await bd.registrarMedida(DateTime(2026, 8, 3), 'peso', 78);
      await bd.registrarMedida(DateTime(2026, 8, 1), 'peso', 79);
      await bd.registrarMedida(DateTime(2026, 8, 2), 'peso', 78.5);

      expect((await bd.serieMedida('peso')).map((m) => m.valor), [
        79,
        78.5,
        78,
      ]);
      expect((await bd.ultimaMedida('peso'))!.valor, 78);
      expect(await bd.ultimaMedida('brazo'), isNull);
    });

    test('el rango acota la serie', () async {
      for (var dia = 1; dia <= 5; dia++) {
        await bd.registrarMedida(
          DateTime(2026, 8, dia),
          'peso',
          78 + dia.toDouble(),
        );
      }
      final acotada = await bd.serieMedida(
        'peso',
        desde: DateTime(2026, 8, 2),
        hasta: DateTime(2026, 8, 4),
      );
      expect(acotada.map((m) => m.fecha.day), [2, 3]);
    });

    test('borrar quita solo ese día y tipo', () async {
      await bd.registrarMedida(DateTime(2026, 8, 1), 'peso', 78);
      await bd.registrarMedida(DateTime(2026, 8, 1), 'cintura', 82);
      await bd.registrarMedida(DateTime(2026, 8, 2), 'peso', 79);

      await bd.borrarMedida(DateTime(2026, 8, 1, 15), 'peso');

      expect((await bd.serieMedida('peso')).map((m) => m.fecha.day), [2]);
      expect(await bd.serieMedida('cintura'), hasLength(1));
    });
  });

  // ── B10: borrar todos los datos ────────────────────────────────────────────

  group('borrar todos los datos', () {
    test('se lleva lo del usuario y conserva el catálogo', () async {
      await sembrarCatalogo(bd, datos: _catalogoFalso);
      final idRutina = (await bd.insertarRutina('Empuje'))!;
      await bd.insertarEjercicio(idRutina, 'Press', idCatalogo: '0001');
      final idEjercicio = (await bd.ejerciciosDeRutina(idRutina)).single.id;
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 8, 1), {
        idEjercicio: const [ValoresSerie(repeticiones: 10, peso: 60)],
      });
      await bd.registrarMedida(DateTime(2026, 8, 1), 'peso', 78);
      await bd.marcarFavorito('0001', true);
      await bd.registrarVisto('0002');
      await bd.guardarSesionActiva(idRutina, DateTime(2026, 8, 1), '{}');
      await bd.fijarAjuste(Claves.unidad, 'lb');

      await bd.borrarTodosLosDatos();

      expect(await bd.todasLasRutinas(), isEmpty);
      expect(await bd.todasLasMedidas(), isEmpty);
      expect(await bd.idsFavoritos(), isEmpty);
      expect(await bd.vistosRecientes(), isEmpty);
      expect(await bd.sesionActiva(), isNull);
      expect((await bd.ajustes()).unidad, Unidad.kg);
      // El catálogo es regenerable pero no hay motivo para tirarlo.
      expect(await bd.contarCatalogo(), 2);
    });
  });
}
