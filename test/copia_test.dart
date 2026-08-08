/// Tests de la copia de seguridad: exportar, validar e importar.
///
/// La prueba que de verdad importa es la de ida y vuelta: una base con datos se
/// exporta, se importa en otra vacía y las dos tienen que decir lo mismo. Es lo
/// único que responde a «¿me sirve esta copia si pierdo el móvil?».
library;

import 'package:appgym/datos/ajustes.dart';
import 'package:appgym/datos/bd.dart';
import 'package:appgym/datos/copia.dart';
import 'package:appgym/datos/semilla.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

final _catalogoFalso = [
  const EjercicioJson(
    id: '0001',
    nombre: 'barbell bench press',
    bodyPart: 'chest',
    equipment: 'barbell',
    target: 'pectorals',
    muscleGroup: 'chest',
    secondaryMuscles: ['triceps'],
    pasos: ['Empuja la barra.'],
    image: 'images/0001.jpg',
    gif: 'videos/0001.gif',
  ),
];

/// Deja una base con algo de todo: rutina, ejercicios, sesiones con sus series,
/// notas, RPE, calentamiento, medidas y una preferencia.
Future<void> _poblar(AppBD bd) async {
  await sembrarCatalogo(bd, datos: _catalogoFalso);

  final idRutina = (await bd.insertarRutina('Empuje'))!;
  await bd.insertarEjercicio(
    idRutina,
    'barbell bench press',
    idCatalogo: '0001',
  );
  await bd.insertarEjercicio(
    idRutina,
    'Fondos en anillas',
    descripcion: 'Con lastre',
  );

  final ejercicios = await bd.ejerciciosDeRutina(idRutina);
  await bd.fijarDescansoEjercicio(ejercicios.first.id, 180);
  await bd.fijarProgresionEjercicio(
    ejercicios.first.id,
    repMin: const Value(3),
    repMax: const Value(5),
    incrementoKg: const Value(1.25),
    estrategia: const Value(1),
  );

  await bd.insertarEntrenamiento(
    idRutina,
    DateTime(2026, 8, 1, 12),
    {
      ejercicios[0].id: const [
        ValoresSerie(repeticiones: 12, peso: 40, calentamiento: true),
        ValoresSerie(repeticiones: 10, peso: 60, rpe: 8, nota: 'Buena'),
        ValoresSerie(repeticiones: 8, peso: 65),
      ],
      ejercicios[1].id: const [ValoresSerie(repeticiones: 10, peso: 0)],
    },
    nota: 'Me dolía el hombro',
    duracionSeg: 3600,
  );
  await bd.insertarEntrenamiento(idRutina, DateTime(2026, 8, 8, 12), {
    ejercicios[0].id: const [ValoresSerie(repeticiones: 10, peso: 62.5)],
  });

  await bd.registrarMedida(DateTime(2026, 8, 1), 'peso', 78.4);
  await bd.registrarMedida(DateTime(2026, 8, 8), 'cintura', 82);
  await bd.fijarAjuste(Claves.unidad, 'lb');
}

void main() {
  late AppBD bd;

  setUp(() => bd = AppBD(NativeDatabase.memory()));
  tearDown(() => bd.close());

  group('exportar', () {
    test('vuelca rutinas, sesiones, series y medidas', () async {
      await _poblar(bd);
      final datos = await exportar(bd);

      expect(datos['formato'], formatoCopia);
      expect(datos['version'], versionCopia);
      expect((datos['ajustes'] as Map)[Claves.unidad], 'lb');

      final rutina = (datos['rutinas'] as List).single as Map;
      expect(rutina['nombre'], 'Empuje');

      final ejercicios = rutina['ejercicios'] as List;
      expect(ejercicios, hasLength(2));
      expect((ejercicios.first as Map)['idCatalogo'], '0001');
      expect((ejercicios.first as Map)['descansoSeg'], 180);
      // El personalizado no lleva id de catálogo, y su descripción viaja.
      expect((ejercicios[1] as Map)['idCatalogo'], isNull);
      expect((ejercicios[1] as Map)['descripcion'], 'Con lastre');

      final sesiones = rutina['entrenamientos'] as List;
      expect(sesiones, hasLength(2));
      final primera = sesiones.first as Map;
      expect(primera['nota'], 'Me dolía el hombro');
      expect(primera['duracionSeg'], 3600);
      expect(primera['series'], hasLength(4));

      // Las series apuntan a su ejercicio por nombre, no por id interno: es lo
      // que permite reimportar la copia en cualquier instalación.
      final serie = (primera['series'] as List)[1] as Map;
      expect(serie['ejercicio'], 'barbell bench press');
      expect(serie['peso'], 60);
      expect(serie['rpe'], 8);
      expect(serie['calentamiento'], isFalse);

      expect(datos['medidas'], hasLength(2));
    });

    test('el CSV lleva una fila por serie y su cabecera', () async {
      await _poblar(bd);
      final csv = await exportarCsv(bd);
      final lineas = csv.split('\n');

      expect(
        lineas.first,
        'fecha,rutina,ejercicio,serie,repeticiones,peso_kg,rpe,calentamiento',
      );
      // Cuatro series de la primera sesión más una de la segunda.
      expect(lineas, hasLength(6));
      expect(lineas[1], contains('Empuje'));
      expect(lineas[1], endsWith(',1'));
    });

    test('un nombre con coma va entrecomillado', () async {
      await bd.insertarRutina('Empuje, pierna');
      final id = (await bd.todasLasRutinas()).single.id;
      await bd.insertarEjercicio(id, 'Press');
      final idEjercicio = (await bd.ejerciciosDeRutina(id)).single.id;
      await bd.insertarEntrenamiento(id, DateTime(2026, 8, 1), {
        idEjercicio: const [ValoresSerie(repeticiones: 10, peso: 60)],
      });

      expect(await exportarCsv(bd), contains('"Empuje, pierna"'));
    });
  });

  group('validar', () {
    test('acepta una copia recién exportada', () async {
      await _poblar(bd);
      expect(validar(await exportar(bd)), isEmpty);
    });

    test('rechaza el JSON de otra aplicación', () {
      expect(validar({'algo': 1}), hasLength(1));
      expect(validar({'algo': 1}).single, contains('no es una copia'));
    });

    test('rechaza una copia de una versión futura', () {
      final errores = validar({
        'formato': formatoCopia,
        'version': versionCopia + 1,
        'rutinas': <dynamic>[],
      });
      expect(errores.single, contains('más nueva'));
    });

    test('señala una rutina sin nombre', () {
      final errores = validar({
        'formato': formatoCopia,
        'version': versionCopia,
        'rutinas': [
          {'nombre': ''},
        ],
      });
      expect(errores.single, contains('no tiene nombre'));
    });

    test('leer devuelve null con un texto que no es JSON', () {
      expect(leer('esto no es json'), isNull);
      expect(leer('[]'), isNull);
      expect(leer('{"formato":"x"}'), isNotNull);
    });

    test('leer se traga un BOM al principio', () {
      // Un fichero que haya pasado por un editor de Windows o por una hoja de
      // cálculo puede traerlo, y `jsonDecode` no lo admite.
      expect(leer('\u{FEFF}{"formato":"x"}'), isNotNull);
    });
  });

  group('importar', () {
    test('ida y vuelta: exportar y restaurar en una base vacía', () async {
      await _poblar(bd);
      final datos = await exportar(bd);

      final vacia = AppBD(NativeDatabase.memory());
      addTearDown(vacia.close);
      await sembrarCatalogo(vacia, datos: _catalogoFalso);

      final informe = await importar(
        vacia,
        datos,
        modo: ModoImportacion.reemplazar,
      );
      expect(informe.rutinas, 1);
      expect(informe.ejercicios, 2);
      expect(informe.entrenamientos, 2);
      expect(informe.series, 4 + 1);
      expect(informe.medidas, 2);
      expect(informe.avisos, isEmpty);

      // Y lo importado dice lo mismo que el original.
      expect(
        _sinFechaDeExportacion(await exportar(vacia)),
        _sinFechaDeExportacion(datos),
      );

      // Incluida la configuración de progresión, que es lo que estrena la v3.
      final restaurado = (await vacia.ejerciciosDeRutina(
        (await vacia.todasLasRutinas()).single.id,
      )).first.ejercicio;
      expect(restaurado.repMin, 3);
      expect(restaurado.repMax, 5);
      expect(restaurado.incrementoKg, 1.25);
      expect(restaurado.estrategia, 1);
    });

    test(
      'una copia de la versión 2 se importa y deja la progresión vacía',
      () async {
        // La v2 no conocía las cuatro columnas. Lo que falta entra como null,
        // que en ellas significa «como el global», así que una copia vieja
        // restaura un ejercicio que se comporta exactamente como antes.
        final datos = {
          'formato': formatoCopia,
          'version': 2,
          'exportado': '2026-08-01T12:00:00.000',
          'ajustes': <String, String>{},
          'rutinas': [
            {
              'nombre': 'Empuje',
              'color': null,
              'ejercicios': [
                {
                  'nombre': 'barbell bench press',
                  'idCatalogo': '0001',
                  'descripcion': null,
                  'orden': 0,
                  'descansoSeg': 120,
                },
              ],
              'entrenamientos': <Map<String, dynamic>>[],
            },
          ],
          'medidas': <Map<String, dynamic>>[],
        };

        expect(validar(datos), isEmpty);

        await sembrarCatalogo(bd, datos: _catalogoFalso);
        final informe = await importar(
          bd,
          datos,
          modo: ModoImportacion.reemplazar,
        );
        expect(informe.avisos, isEmpty);
        expect(informe.ejercicios, 1);

        final ejercicio = (await bd.ejerciciosDeRutina(
          (await bd.todasLasRutinas()).single.id,
        )).single.ejercicio;
        expect(ejercicio.descansoSeg, 120);
        expect(ejercicio.repMin, isNull);
        expect(ejercicio.repMax, isNull);
        expect(ejercicio.incrementoKg, isNull);
        expect(ejercicio.estrategia, isNull);
      },
    );

    test('conserva el vínculo con el catálogo y la ficha', () async {
      await _poblar(bd);
      final datos = await exportar(bd);

      final vacia = AppBD(NativeDatabase.memory());
      addTearDown(vacia.close);
      await sembrarCatalogo(vacia, datos: _catalogoFalso);
      await importar(vacia, datos, modo: ModoImportacion.reemplazar);

      final idRutina = (await vacia.todasLasRutinas()).single.id;
      final ejercicios = await vacia.ejerciciosDeRutina(idRutina);
      expect(ejercicios.first.ficha, isNotNull);
      expect(ejercicios.first.ficha!.target, 'pectorals');
      expect(ejercicios[1].ficha, isNull);
    });

    test(
      'un ejercicio que ya no está en el catálogo entra como propio',
      () async {
        await _poblar(bd);
        final datos = await exportar(bd);

        // La base de destino no tiene ese catálogo: la copia es de otra versión
        // del dataset.
        final vacia = AppBD(NativeDatabase.memory());
        addTearDown(vacia.close);

        final informe = await importar(
          vacia,
          datos,
          modo: ModoImportacion.reemplazar,
        );
        expect(informe.ejercicios, 2);
        expect(informe.avisos.single, contains('ya no está en el catálogo'));

        final idRutina = (await vacia.todasLasRutinas()).single.id;
        final ejercicios = await vacia.ejerciciosDeRutina(idRutina);
        // Se conserva el nombre, que es lo que hace reconocible el histórico.
        expect(ejercicios.first.nombre, 'barbell bench press');
        expect(ejercicios.first.ejercicio.idCatalogo, isNull);
      },
    );

    test('reemplazar borra lo que hubiera antes', () async {
      await _poblar(bd);
      final datos = await exportar(bd);

      final otra = AppBD(NativeDatabase.memory());
      addTearDown(otra.close);
      await otra.insertarRutina('Pierna');

      await importar(otra, datos, modo: ModoImportacion.reemplazar);
      expect((await otra.todasLasRutinas()).map((r) => r.nombre), ['Empuje']);
      expect((await otra.ajustes()).unidad, Unidad.lb);
    });

    test('fusionar dos veces la misma copia no duplica en silencio', () async {
      await _poblar(bd);
      final datos = await exportar(bd);

      final otra = AppBD(NativeDatabase.memory());
      addTearDown(otra.close);
      await sembrarCatalogo(otra, datos: _catalogoFalso);
      await otra.insertarRutina('Empuje');

      final primera = await importar(
        otra,
        datos,
        modo: ModoImportacion.fusionar,
      );
      expect(primera.avisos.single, contains('(importada)'));

      final segunda = await importar(
        otra,
        datos,
        modo: ModoImportacion.fusionar,
      );
      expect(segunda.avisos.first, contains('(importada 2)'));

      expect((await otra.todasLasRutinas()).map((r) => r.nombre), [
        'Empuje',
        'Empuje (importada)',
        'Empuje (importada 2)',
      ]);
    });

    test('fusionar no pisa las preferencias', () async {
      await _poblar(bd);
      final datos = await exportar(bd);

      final otra = AppBD(NativeDatabase.memory());
      addTearDown(otra.close);
      await importar(otra, datos, modo: ModoImportacion.fusionar);

      // La copia venía en libras; fusionar añade rutinas, no cambia la unidad
      // con la que estabas trabajando.
      expect((await otra.ajustes()).unidad, Unidad.kg);
    });

    test('un archivo corrupto no modifica nada', () async {
      final idRutina = (await bd.insertarRutina('Empuje'))!;
      await bd.insertarEjercicio(idRutina, 'Press');

      await expectLater(
        importar(bd, {'algo': 1}, modo: ModoImportacion.reemplazar),
        throwsA(isA<FormatException>()),
      );

      expect(await bd.todasLasRutinas(), hasLength(1));
      expect(await bd.ejerciciosDeRutina(idRutina), hasLength(1));
    });

    test('una sesión con la fecha ilegible se salta y se avisa', () async {
      final informe = await importar(bd, {
        'formato': formatoCopia,
        'version': versionCopia,
        'rutinas': [
          {
            'nombre': 'Empuje',
            'ejercicios': [
              {'nombre': 'Press', 'orden': 0},
            ],
            'entrenamientos': [
              {
                'fecha': 'ayer por la tarde',
                'series': [
                  {'ejercicio': 'Press', 'repeticiones': 10, 'peso': 60},
                ],
              },
            ],
          },
        ],
      }, modo: ModoImportacion.reemplazar);

      expect(informe.rutinas, 1);
      expect(informe.entrenamientos, 0);
      expect(informe.avisos.single, contains('fecha ilegible'));
    });
  });

  test('el nombre del fichero lleva la fecha', () {
    expect(nombreFichero(DateTime(2026, 8, 6)), 'appgym-copia-2026-08-06.json');
    expect(
      nombreFichero(DateTime(2026, 12, 25), extension: 'csv'),
      'appgym-copia-2026-12-25.csv',
    );
  });
}

/// La marca de tiempo del volcado cambia en cada llamada, así que se quita
/// antes de comparar dos exportaciones.
Map<String, dynamic> _sinFechaDeExportacion(Map<String, dynamic> datos) =>
    {...datos}..remove('exportado');
