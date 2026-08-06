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
      await bd.fijarAjuste(AppBD.claveEsfuerzoActivo, '1');
      await bd.fijarAjuste(AppBD.claveEsfuerzoEscala, 'rir');
      expect((await bd.ajustes()).esfuerzoActivo, isTrue);
      expect((await bd.ajustes()).escala, EscalaEsfuerzo.rir);

      await bd.fijarAjuste(AppBD.claveEsfuerzoEscala, 'rpe');
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
        isFalse,
      );
      // Un ejercicio con la lista vacía tampoco: es lo que sustituye al
      // interruptor de «incluir ejercicio».
      expect(
        await bd.insertarEntrenamiento(idRutina, DateTime.now(), {
          idEjercicio: const [],
        }),
        isFalse,
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
      expect(resumen.last.fecha, DateTime(2026, 3, 8));
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
}
