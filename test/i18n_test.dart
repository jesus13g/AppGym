/// El vocabulario del catálogo y el índice de búsqueda multilingüe.
///
/// Es el equivalente al test de cobertura de `musculos_test.dart`: recorre los
/// 1.324 ejercicios de verdad y exige que **todo** término de los cuatro
/// vocabularios tenga traducción en **los dos** idiomas. Sin él, un término
/// nuevo del dataset saldría en inglés dentro de la app en español (o al revés)
/// y nadie se enteraría hasta verlo en el móvil.
library;

import 'package:appgym/datos/ajustes.dart' show Claves;
import 'package:appgym/datos/bd.dart';
import 'package:appgym/datos/i18n.dart';
import 'package:appgym/datos/i18n_en.dart';
import 'package:appgym/datos/i18n_es.dart';
import 'package:appgym/datos/semilla.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Un ejercicio del catálogo con lo justo para probar el índice.
EjercicioJson _ficha(
  String id, {
  String nombre = 'barbell bench press',
  String bodyPart = 'chest',
  String equipment = 'barbell',
  String target = 'pectorals',
  String muscleGroup = 'chest',
  List<String> secundarios = const ['triceps'],
}) => EjercicioJson(
  id: id,
  nombre: nombre,
  bodyPart: bodyPart,
  equipment: equipment,
  target: target,
  muscleGroup: muscleGroup,
  secondaryMuscles: secundarios,
  pasos: const ['Empuja la barra.'],
  image: 'images/$id.jpg',
  gif: 'videos/$id.gif',
  pasosEn: const ['Push the bar.'],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('cobertura del vocabulario', () {
    test('las tres tablas tienen las mismas claves en los dos idiomas', () {
      expect(zonasCuerpoEn.keys.toSet(), zonasCuerpoEs.keys.toSet());
      expect(equipamientosEn.keys.toSet(), equipamientosEs.keys.toSet());
      expect(musculosEn.keys.toSet(), musculosEs.keys.toSet());
    });

    test('ninguna traducción se ha quedado en blanco', () {
      for (final tabla in [
        zonasCuerpoEs,
        zonasCuerpoEn,
        equipamientosEs,
        equipamientosEn,
        musculosEs,
        musculosEn,
      ]) {
        for (final entrada in tabla.entries) {
          expect(entrada.value.trim(), isNotEmpty, reason: entrada.key);
        }
      }
    });

    test(
      'todo término del catálogo real se traduce en los dos idiomas',
      () async {
        final catalogo = await cargarCatalogo();
        // Sin traducción, `_traducir` capitaliza el término en crudo; comparar
        // contra eso es lo que caza un valor nuevo del dataset.
        String crudo(String valor) =>
            valor.isEmpty ? '' : valor[0].toUpperCase() + valor.substring(1);

        final sinTraducir = <String>{};
        for (final e in catalogo) {
          for (final idioma in idiomasCatalogo) {
            for (final (valor, traducido) in <(String, String)>[
              (e.bodyPart, zonaCuerpo(e.bodyPart, idioma)),
              (e.equipment, equipamiento(e.equipment, idioma)),
              (e.target, musculo(e.target, idioma)),
              (e.muscleGroup, musculo(e.muscleGroup, idioma)),
              for (final m in e.secondaryMuscles) (m, musculo(m, idioma)),
            ]) {
              if (valor.isEmpty) continue;
              if (traducido == crudo(valor.toLowerCase().trim()) &&
                  !_esIdentidad(valor)) {
                sinTraducir.add('$idioma: $valor');
              }
            }
          }
        }
        expect(sinTraducir, isEmpty);
      },
    );
  });

  group('índice de búsqueda multilingüe', () {
    test('lleva los términos de los dos idiomas a la vez', () {
      final indice = _ficha('0001').textoBusqueda;
      // Español e inglés en la misma columna: por eso cambiar de idioma no
      // vuelve a sembrar.
      expect(indice, contains('pectorales'));
      expect(indice, contains('pectorals'));
      expect(indice, contains('barra'));
      expect(indice, contains('barbell'));
      expect(indice, contains('triceps'));
    });

    test('se guarda normalizado, sin acentos', () {
      final indice = _ficha(
        '0002',
        target: 'biceps',
        muscleGroup: 'upper arms',
        secundarios: const ['forearms'],
      ).textoBusqueda;
      expect(indice, contains('biceps'));
      expect(indice, isNot(contains('í')));
    });

    test('«mancuerna pecho» y «dumbbell chest» casan con lo mismo', () async {
      final bd = AppBD(DatabaseConnection(NativeDatabase.memory()));
      addTearDown(bd.close);
      await sembrarCatalogo(bd, datos: [_ficha('0003', equipment: 'dumbbell')]);

      for (final texto in ['mancuerna pecho', 'dumbbell chest']) {
        final resultados = await bd.buscarCatalogo(
          texto: normalizar(texto),
          limite: 10,
        );
        expect(resultados, hasLength(1), reason: texto);
      }
    });
  });

  group('resiembra', () {
    late AppBD bd;

    setUp(() {
      bd = AppBD(DatabaseConnection(NativeDatabase.memory()));
      addTearDown(bd.close);
    });

    test('la primera vez siembra y deja anotada la versión', () async {
      await sembrarCatalogo(bd, datos: [_ficha('0001')]);
      expect(await bd.contarCatalogo(), 1);
      expect(
        (await bd.ajustesCrudos())[Claves.versionIndice],
        '$versionIndice',
      );
    });

    test('con el índice al día no se vuelve a escribir', () async {
      await sembrarCatalogo(bd, datos: [_ficha('0001')]);
      // Se ensucia una fila: si resembrara, volvería a la del asset.
      await bd.sembrarCatalogo([_ficha('0001', nombre: 'tocado a mano').fila]);

      await sembrarCatalogo(bd, datos: [_ficha('0001')]);
      expect((await bd.ficha('0001'))!.nombre, 'tocado a mano');
    });

    test('subir la versión del índice resiembra exactamente una vez', () async {
      await sembrarCatalogo(bd, datos: [_ficha('0001')]);
      // Se simula una base sembrada por una versión anterior del vocabulario.
      await bd.fijarAjuste(Claves.versionIndice, '0');
      await bd.sembrarCatalogo([_ficha('0001', nombre: 'tocado a mano').fila]);

      await sembrarCatalogo(bd, datos: [_ficha('0001')]);
      expect((await bd.ficha('0001'))!.nombre, 'barbell bench press');

      // Y la segunda pasada ya no toca nada.
      await bd.sembrarCatalogo([_ficha('0001', nombre: 'otra vez').fila]);
      await sembrarCatalogo(bd, datos: [_ficha('0001')]);
      expect((await bd.ficha('0001'))!.nombre, 'otra vez');
    });
  });

  group('instrucciones por idioma', () {
    test('la columna guarda los dos idiomas y se elige al pintar', () {
      final columna = _ficha('0001').fila.instrucciones.value;
      expect(pasosDe(columna, 'es'), ['Empuja la barra.']);
      expect(pasosDe(columna, 'en'), ['Push the bar.']);
      // Un idioma sin pasos cae al español, que siempre está.
      expect(pasosDe(columna, 'fr'), ['Empuja la barra.']);
    });

    test(
      'una base sin resembrar, con la lista suelta de antes, sigue valiendo',
      () {
        expect(pasosDe('["Un paso"]', 'en'), ['Un paso']);
        expect(pasosDe(null, 'es'), isEmpty);
        expect(pasosDe('no es json', 'es'), isEmpty);
      },
    );

    test('el asset en inglés cubre el catálogo entero', () async {
      final catalogo = await cargarCatalogo();
      final sinIngles = catalogo
          .where((e) => e.pasosEn.isEmpty)
          .map((e) => e.id);
      expect(sinIngles, isEmpty);
    });
  });
}

/// Términos que en inglés se escriben igual que en crudo, y que por tanto no
/// distinguen «traducido» de «sin traducir». No son un agujero: están en la
/// tabla, solo que su traducción coincide con la capitalización automática.
bool _esIdentidad(String valor) {
  final clave = valor.toLowerCase().trim();
  return zonasCuerpoEn.containsKey(clave) ||
      equipamientosEn.containsKey(clave) ||
      musculosEn.containsKey(clave);
}
