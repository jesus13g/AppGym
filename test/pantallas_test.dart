/// Tests de widget: montan pantallas reales contra una base en memoria.
///
/// El `bdProvider` se sobrescribe con una `NativeDatabase.memory()`, así que las
/// pantallas se ejercitan de verdad —consultas incluidas— sin tocar disco.
library;

import 'package:appgym/datos/bd.dart';
import 'package:appgym/datos/semilla.dart';
import 'package:appgym/estado/providers.dart';
import 'package:appgym/pantallas/catalogo.dart';
import 'package:appgym/pantallas/rutinas.dart';
import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

Widget _app(AppBD bd, Widget pantalla) => ProviderScope(
  overrides: [bdProvider.overrideWithValue(bd)],
  child: CupertinoApp(
    locale: const Locale('es'),
    supportedLocales: const [Locale('es')],
    localizationsDelegates: const [
      GlobalCupertinoLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    home: pantalla,
  ),
);

void main() {
  late AppBD bd;

  setUp(() => bd = AppBD(NativeDatabase.memory()));
  tearDown(() => bd.close());

  group('pantalla de rutinas', () {
    testWidgets('sin rutinas invita a crear la primera', (tester) async {
      await tester.pumpWidget(_app(bd, const PantallaRutinas()));
      await tester.pumpAndSettle();

      expect(find.text('Aún no tienes rutinas'), findsOneWidget);
      expect(find.text('Crear rutina'), findsOneWidget);
    });

    testWidgets('lista las rutinas con su recuento de ejercicios', (
      tester,
    ) async {
      final id = (await bd.insertarRutina('Empuje'))!;
      await bd.insertarEjercicio(id, 'Press banca');
      await bd.insertarRutina('Pierna');

      await tester.pumpWidget(_app(bd, const PantallaRutinas()));
      await tester.pumpAndSettle();

      expect(find.text('Empuje'), findsOneWidget);
      expect(find.text('Pierna'), findsOneWidget);
      expect(find.textContaining('1 ejercicio · Sin entrenar'), findsOneWidget);
      expect(find.text('Aún no tienes rutinas'), findsNothing);
    });

    testWidgets('crear una rutina desde el diálogo la añade a la lista', (
      tester,
    ) async {
      await tester.pumpWidget(_app(bd, const PantallaRutinas()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Crear rutina'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(CupertinoTextField), 'Full body');
      await tester.tap(find.text('Crear'));
      await tester.pumpAndSettle();

      expect(await bd.todasLasRutinas(), hasLength(1));
      expect((await bd.todasLasRutinas()).single.nombre, 'Full body');
    });
  });

  group('buscador del catálogo', () {
    setUp(() => sembrarCatalogo(bd, datos: _catalogoFalso));

    testWidgets('pinta el catálogo completo al abrirse', (tester) async {
      await tester.pumpWidget(_app(bd, const PantallaCatalogo()));
      await tester.pumpAndSettle();

      expect(find.text('barbell bench press'), findsOneWidget);
      expect(find.text('dumbbell curl'), findsOneWidget);
      expect(find.text('2 ejercicios'), findsOneWidget);
    });

    testWidgets('filtra al escribir, en español y tras el debounce', (
      tester,
    ) async {
      await tester.pumpWidget(_app(bd, const PantallaCatalogo()));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(CupertinoSearchTextField),
        'mancuerna',
      );
      // El buscador espera 250 ms antes de consultar, para no hacerlo en cada
      // tecla: sin avanzar el reloj no habría pasado nada todavía.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('dumbbell curl'), findsOneWidget);
      expect(find.text('barbell bench press'), findsNothing);
    });

    testWidgets('la última búsqueda manda aunque encadene consultas', (
      tester,
    ) async {
      await tester.pumpWidget(_app(bd, const PantallaCatalogo()));
      await tester.pumpAndSettle();

      // Dos búsquedas seguidas: la segunda no puede perderse por tener la
      // primera en vuelo.
      await tester.enterText(find.byType(CupertinoSearchTextField), 'barbell');
      await tester.pump(const Duration(milliseconds: 260));
      await tester.enterText(
        find.byType(CupertinoSearchTextField),
        'mancuerna',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('dumbbell curl'), findsOneWidget);
      expect(find.text('barbell bench press'), findsNothing);
    });

    testWidgets('filtra por zona del cuerpo al tocar una píldora', (
      tester,
    ) async {
      await tester.pumpWidget(_app(bd, const PantallaCatalogo()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pecho'));
      await tester.pumpAndSettle();

      expect(find.text('barbell bench press'), findsOneWidget);
      expect(find.text('dumbbell curl'), findsNothing);
    });
  });
}
