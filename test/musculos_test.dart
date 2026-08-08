/// Tests del vocabulario muscular y del reparto del trabajo.
///
/// El importante es el que recorre los 1.324 ejercicios de verdad: si mañana se
/// actualiza el dataset y aparece un músculo que la tabla no conoce, tiene que
/// fallar aquí y no desaparecer en silencio del mapa. Es el mismo patrón que ya
/// usan las plantillas contra el catálogo.
///
/// El resto son funciones puras, así que se les pasan filas escritas a mano con
/// fechas clavadas, como en `metricas_test.dart`.
library;

import 'dart:convert';

import 'package:appgym/datos/bd.dart';
import 'package:appgym/datos/musculos.dart';
import 'package:appgym/datos/semilla.dart';
import 'package:flutter_test/flutter_test.dart';

TrabajoMuscular _fila({
  required DateTime fecha,
  String target = '',
  String muscleGroup = '',
  List<String> secundarios = const [],
  int nSeries = 3,
  double volumen = 300,
  int idEntrenamiento = 1,
  int idEjercicio = 1,
  String? idCatalogo = '0001',
  String ejercicio = 'barbell bench press',
  int idRutina = 1,
}) => TrabajoMuscular(
  idEntrenamiento: idEntrenamiento,
  idRutina: idRutina,
  fecha: fecha,
  idEjercicio: idEjercicio,
  ejercicio: ejercicio,
  idCatalogo: idCatalogo,
  target: target,
  muscleGroup: muscleGroup,
  secondaryMuscles: jsonEncode(secundarios),
  nSeries: nSeries,
  volumen: volumen,
);

final _hoy = DateTime(2026, 8, 8);

void main() {
  // Cargar el asset del catálogo necesita el binding montado.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('cobertura del catálogo real', () {
    late List<EjercicioJson> catalogo;

    setUpAll(() async => catalogo = await cargarCatalogo());

    test('el dataset trae los 1.324 ejercicios de siempre', () {
      expect(catalogo, hasLength(1324));
    });

    test('todo músculo del dataset cae en una región o está excluido', () {
      // Los tres vocabularios, no solo `target`: las cuatro regiones que no
      // tienen ningún `target` propio —deltoides posterior, oblicuos, flexores
      // de cadera y tibial— viven enteras de `muscleGroup` y los secundarios.
      final huerfanos = <String>{};
      for (final ejercicio in catalogo) {
        for (final termino in [
          ejercicio.target,
          ejercicio.muscleGroup,
          ...ejercicio.secondaryMuscles,
        ]) {
          if (termino.isEmpty) continue;
          if (terminosSinRegion.contains(termino)) continue;
          if (regionDe(termino) == null) huerfanos.add(termino);
        }
      }
      expect(huerfanos, isEmpty, reason: 'músculos sin región: $huerfanos');
    });

    test('las 21 regiones son alcanzables desde el dataset', () {
      // Sin esto, un término mal escrito en la tabla («rear deltoid» en vez de
      // «rear deltoids») pasaría la cobertura y dejaría la región muerta.
      final vistas = <Region>{};
      for (final ejercicio in catalogo) {
        vistas.addAll(
          regionesDeTerminos(
            target: ejercicio.target,
            muscleGroup: ejercicio.muscleGroup,
            secundarios: ejercicio.secondaryMuscles,
          ).keys,
        );
      }
      expect(
        Region.values.toSet().difference(vistas),
        isEmpty,
        reason: 'regiones que ningún ejercicio alcanza',
      );
    });

    test('los ejercicios de cardio reparten por sus otros músculos', () {
      // `cardiovascular system` no es un músculo y no se pinta, pero los 29
      // ejercicios sí traen grupo y secundarios reales: un burpee trabaja las
      // piernas y decir que no sería peor dato que no decir nada.
      final cardio = catalogo
          .where((e) => e.target == 'cardiovascular system')
          .toList();
      expect(cardio, hasLength(29));
      expect(regionDe('cardiovascular system'), isNull);
      for (final e in cardio) {
        expect(
          regionesDeTerminos(
            target: e.target,
            muscleGroup: e.muscleGroup,
            secundarios: e.secondaryMuscles,
          ),
          isNotEmpty,
          reason: '${e.nombre} no reparte a ninguna región',
        );
      }
    });

    test('ningún término está en dos regiones', () {
      // La construcción del índice lanza si los hay; basta con provocarla.
      expect(() => regionDe('biceps'), returnsNormally);
      final todos = <String>[];
      for (final datos in regiones.values) {
        todos.addAll(datos.terminos);
      }
      expect(todos.toSet(), hasLength(todos.length));
    });
  });

  group('atribución', () {
    test('el objetivo, el grupo y los secundarios pesan 1 · 0,5 · 0,3', () {
      final pesos = regionesDeTerminos(
        target: 'pectorals',
        muscleGroup: 'triceps',
        secundarios: ['shoulders'],
      );
      expect(pesos[Region.pectoral], pesoTarget);
      expect(pesos[Region.triceps], pesoGrupo);
      expect(pesos[Region.deltoides], pesoSecundario);
    });

    test(
      'una región por varias vías se queda con el mayor, no con la suma',
      () {
        // Un curl que además declara el bíceps como grupo vale 1,0 y no 1,5, o
        // los ejercicios bien etiquetados pesarían más solo por estarlo.
        final pesos = regionesDeTerminos(
          target: 'biceps',
          muscleGroup: 'biceps',
          secundarios: ['brachialis'],
        );
        expect(pesos[Region.biceps], pesoTarget);
        expect(pesos, hasLength(1));
      },
    );

    test('la zona del cuerpo no se consulta nunca', () {
      // `bodyPart` se solapa con los otros vocabularios (`back` son 203
      // ejercicios) y atribuiría en bloque y mal.
      final pesos = regionesDeTerminos(
        target: 'biceps',
        muscleGroup: '',
        secundarios: const [],
      );
      expect(pesos.keys, [Region.biceps]);
    });

    test('un ejercicio personalizado no aporta a ninguna región', () {
      expect(
        regionesDeTerminos(target: '', muscleGroup: '', secundarios: const []),
        isEmpty,
      );
    });

    test('los términos se normalizan en mayúsculas y espacios', () {
      expect(regionDe('  Biceps '), Region.biceps);
      expect(regionDe(''), isNull);
      expect(regionDe(null), isNull);
    });
  });

  group('reparto por periodo', () {
    final filas = [
      _fila(
        fecha: _hoy.subtract(const Duration(days: 2)),
        target: 'pectorals',
        secundarios: ['triceps'],
        nSeries: 4,
        volumen: 400,
        idEntrenamiento: 1,
      ),
      _fila(
        fecha: _hoy.subtract(const Duration(days: 40)),
        target: 'quads',
        nSeries: 5,
        volumen: 5000,
        idEntrenamiento: 2,
      ),
    ];

    test('el corte por fecha incluye el propio día', () {
      final desde = _hoy.subtract(const Duration(days: 2));
      expect(
        trabajoPorRegion(filas, desde: desde).keys,
        contains(Region.pectoral),
      );
      expect(
        trabajoPorRegion(filas, desde: desde).keys,
        isNot(contains(Region.cuadriceps)),
      );
    });

    test('el mismo histórico da mapas distintos según el periodo', () {
      final semana = trabajoPorRegion(
        filas,
        desde: _hoy.subtract(const Duration(days: 7)),
      );
      final trimestre = trabajoPorRegion(
        filas,
        desde: _hoy.subtract(const Duration(days: 90)),
      );
      expect(semana.keys, isNot(contains(Region.cuadriceps)));
      expect(trimestre.keys, contains(Region.cuadriceps));
    });

    test('las series y el volumen se ponderan; las sesiones se cuentan', () {
      final t = trabajoPorRegion(
        filas,
        desde: _hoy.subtract(const Duration(days: 90)),
      );
      // El tríceps entra como secundario del press: 4 series × 0,3.
      expect(t[Region.triceps]!.puntos, closeTo(1.2, 1e-9));
      expect(t[Region.triceps]!.volumen, closeTo(120, 1e-9));
      // Las series sin ponderar son las que se hicieron.
      expect(t[Region.triceps]!.nSeries, 4);
      expect(t[Region.pectoral]!.nSesiones, 1);
      expect(
        t[Region.pectoral]!.ultima,
        _hoy.subtract(const Duration(days: 2)),
      );
    });

    test('colorea por series ponderadas y no por kilos', () {
      // Es la razón de ser de `puntos`: en volumen, cuatro series de sentadilla
      // aplastan a cuatro de curl y el mapa saldría siempre igual. En series,
      // cuatro y cuatro son cuatro y cuatro.
      final iguales = [
        _fila(fecha: _hoy, target: 'quads', nSeries: 4, volumen: 5000),
        _fila(
          fecha: _hoy,
          target: 'biceps',
          nSeries: 4,
          volumen: 320,
          idEntrenamiento: 2,
        ),
      ];
      final niveles = nivelesPorRegion(
        trabajoPorRegion(
          iguales,
          desde: _hoy.subtract(const Duration(days: 7)),
        ),
      );
      expect(niveles[Region.cuadriceps], niveles[Region.biceps]);
      expect(niveles[Region.cuadriceps], 4);
    });
  });

  group('niveles de color', () {
    test('las fronteras caen donde dicen', () {
      expect(nivelDe(0, 100), 0);
      expect(nivelDe(0.001, 100), 1);
      expect(nivelDe(25, 100), 1);
      expect(nivelDe(25.1, 100), 2);
      expect(nivelDe(50, 100), 2);
      expect(nivelDe(75, 100), 3);
      expect(nivelDe(75.1, 100), 4);
      expect(nivelDe(100, 100), 4);
    });

    test('sin máximo todo se queda en cero', () {
      expect(nivelDe(0, 0), 0);
      expect(nivelesPorRegion(const {}).values, everyElement(0));
    });

    test('siempre devuelve las 21 regiones', () {
      final niveles = nivelesPorRegion(
        trabajoPorRegion([
          _fila(fecha: _hoy, target: 'biceps'),
        ], desde: _hoy.subtract(const Duration(days: 7))),
      );
      expect(niveles, hasLength(Region.values.length));
      expect(niveles[Region.gemelo], 0);
      expect(niveles[Region.biceps], 4);
    });

    test('hay una opacidad por nivel', () {
      expect(opacidadesNivel, hasLength(nivelesColor));
    });
  });

  group('menos trabajados', () {
    test('primero lo que no se ha tocado nunca, luego por abandono', () {
      final filas = [
        _fila(fecha: _hoy.subtract(const Duration(days: 3)), target: 'biceps'),
        _fila(fecha: _hoy.subtract(const Duration(days: 60)), target: 'calves'),
      ];
      final lista = menosTrabajados(filas, hoy: _hoy, limite: 21);
      expect(
        lista.first.$2,
        isNull,
        reason: 'las nunca entrenadas van delante',
      );
      // Entre las entrenadas, la más abandonada va antes.
      final entrenadas = lista.where((e) => e.$2 != null).toList();
      expect(entrenadas.first.$1, Region.gemelo);
      expect(entrenadas.first.$2, 60);
      expect(entrenadas.last.$1, Region.biceps);
    });

    test('mira todo el histórico y no solo el periodo elegido', () {
      // Es lo que permite decir «sin entrenar 84 días» con el mapa en 7 días.
      final filas = [
        _fila(fecha: _hoy.subtract(const Duration(days: 84)), target: 'calves'),
      ];
      final dias = {
        for (final (region, d) in menosTrabajados(filas, hoy: _hoy, limite: 21))
          region: d,
      };
      expect(dias[Region.gemelo], 84);
    });

    test('respeta el límite', () {
      expect(menosTrabajados(const [], hoy: _hoy), hasLength(5));
    });
  });

  group('sesiones de una región', () {
    test('una entrada por sesión, con el ejercicio que más aportó', () {
      final filas = [
        _fila(
          fecha: _hoy,
          target: 'pectorals',
          nSeries: 4,
          volumen: 4000,
          idEntrenamiento: 7,
          idEjercicio: 1,
          ejercicio: 'barbell bench press',
        ),
        _fila(
          fecha: _hoy,
          target: 'pectorals',
          nSeries: 3,
          volumen: 300,
          idEntrenamiento: 7,
          idEjercicio: 2,
          ejercicio: 'cable fly',
        ),
      ];
      final sesiones = sesionesDeRegion(filas, Region.pectoral);
      expect(sesiones, hasLength(1));
      expect(sesiones.single.ejercicio, 'barbell bench press');
      expect(sesiones.single.nSeries, 7);
      expect(sesiones.single.volumen, 4300);
    });

    test('de la más reciente hacia atrás y con límite', () {
      final filas = [
        for (var i = 0; i < 8; i++)
          _fila(
            fecha: _hoy.subtract(Duration(days: i)),
            target: 'biceps',
            idEntrenamiento: i,
          ),
      ];
      final sesiones = sesionesDeRegion(filas, Region.biceps);
      expect(sesiones, hasLength(5));
      expect(sesiones.first.fecha, _hoy);
      expect(sesiones.last.fecha, _hoy.subtract(const Duration(days: 4)));
    });

    test('una región que no se ha tocado no devuelve nada', () {
      expect(
        sesionesDeRegion([_fila(fecha: _hoy, target: 'biceps')], Region.gemelo),
        isEmpty,
      );
    });
  });

  group('lo que se queda fuera del modelo', () {
    test('cuenta ejercicios distintos, no filas', () {
      final filas = [
        _fila(
          fecha: _hoy,
          idCatalogo: null,
          idEjercicio: 5,
          idEntrenamiento: 1,
        ),
        _fila(
          fecha: _hoy,
          idCatalogo: null,
          idEjercicio: 5,
          idEntrenamiento: 2,
        ),
        _fila(
          fecha: _hoy,
          idCatalogo: '1234',
          idEjercicio: 6,
          target: 'cardiovascular system',
        ),
      ];
      final fuera = sinRepresentar(
        filas,
        desde: _hoy.subtract(const Duration(days: 7)),
      );
      expect(fuera.personalizados, 1);
      expect(fuera.cardio, 1);
      expect(fuera.hayAlgo, isTrue);
    });

    test('sin nada fuera, no hay aviso', () {
      final fuera = sinRepresentar([
        _fila(fecha: _hoy, target: 'biceps'),
      ], desde: _hoy.subtract(const Duration(days: 7)));
      expect(fuera.hayAlgo, isFalse);
    });
  });
}
