/// Tests de widget: montan pantallas reales contra una base en memoria.
///
/// El `bdProvider` se sobrescribe con una `NativeDatabase.memory()`, así que las
/// pantallas se ejercitan de verdad —consultas incluidas— sin tocar disco.
library;

import 'package:appgym/datos/bd.dart';
import 'package:appgym/datos/formato.dart' as formato;
import 'package:appgym/datos/semilla.dart';
import 'package:appgym/estado/providers.dart';
import 'package:appgym/pantallas/catalogo.dart';
import 'package:appgym/pantallas/entrenar.dart';
import 'package:appgym/pantallas/historial.dart';
import 'package:appgym/pantallas/rutina.dart';
import 'package:appgym/pantallas/rutinas.dart';
import 'package:appgym/tema/ui.dart' as ui;
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

/// Pone la ventana del tamaño de un móvil.
///
/// Por defecto los tests miden 800×600, donde casi nada desborda; el ancho que
/// importa es el del teléfono, que es donde caben —o no— los cuatro controles
/// de una fila de serie.
void _comoUnMovil(WidgetTester tester) {
  tester.view.physicalSize = const Size(375 * 3, 812 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

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

  group('registro de entrenamiento', () {
    late int idRutina;
    late int idEjercicio;

    setUp(() async {
      idRutina = (await bd.insertarRutina('Empuje'))!;
      await bd.insertarEjercicio(idRutina, 'Press banca');
      idEjercicio = (await bd.ejerciciosDeRutina(idRutina)).single.id;
    });

    testWidgets('sin histórico propone cuatro series editables', (
      tester,
    ) async {
      _comoUnMovil(tester);
      await tester.pumpWidget(_app(bd, PantallaEntrenar(idRutina: idRutina)));
      await tester.pumpAndSettle();

      // Dos selectores por serie: repeticiones y peso.
      expect(find.byType(ui.SelectorEnLinea), findsNWidgets(8));
      expect(find.text('Primera vez con este ejercicio'), findsOneWidget);
    });

    testWidgets('precarga tantas filas como series tuvo la última sesión', (
      tester,
    ) async {
      // Seis series, que es el caso que el ancho de un móvil aprieta.
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 1), {
        idEjercicio: const [
          ValoresSerie(repeticiones: 12, peso: 40, calentamiento: true),
          ValoresSerie(repeticiones: 10, peso: 60),
          ValoresSerie(repeticiones: 10, peso: 60),
          ValoresSerie(repeticiones: 8, peso: 65),
          ValoresSerie(repeticiones: 6, peso: 70),
          ValoresSerie(repeticiones: 6, peso: 70),
        ],
      });

      _comoUnMovil(tester);
      await tester.pumpWidget(_app(bd, PantallaEntrenar(idRutina: idRutina)));
      await tester.pumpAndSettle();

      // Seis filas pintadas y ni un RenderFlex desbordado: el test falla solo
      // si alguna fila no cabe.
      expect(find.byType(ui.SelectorEnLinea), findsNWidgets(12));
      expect(find.text('65,0 kg'), findsOneWidget);
      expect(find.text('70,0 kg'), findsNWidgets(2));
      expect(find.textContaining('Último: 6 series'), findsOneWidget);
    });

    testWidgets('añadir serie copia la última y se guarda una fila por serie', (
      tester,
    ) async {
      _comoUnMovil(tester);
      await tester.pumpWidget(_app(bd, PantallaEntrenar(idRutina: idRutina)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Añadir serie'));
      await tester.pumpAndSettle();
      expect(find.byType(ui.SelectorEnLinea), findsNWidgets(10));

      // Subir las repeticiones de la primera serie no toca a las demás: es lo
      // que el esquema agregado no permitía.
      await tester.tap(find.byIcon(CupertinoIcons.plus).first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar entrenamiento'));
      await tester.pumpAndSettle();

      final series = await bd.seriesConFecha(idRutina, idEjercicio);
      expect(series.length, 5);
      expect(series.map((s) => s.nSerie), [1, 2, 3, 4, 5]);
      expect(series.first.repeticiones, 11);
      expect(series.skip(1).map((s) => s.repeticiones), everyElement(10));
      expect(series.map((s) => s.peso), everyElement(20));
    });
  });

  group('orden de los ejercicios', () {
    late int idRutina;

    setUp(() async {
      idRutina = (await bd.insertarRutina('Empuje'))!;
      for (final nombre in ['Press banca', 'Aperturas', 'Fondos']) {
        await bd.insertarEjercicio(idRutina, nombre);
      }
    });

    testWidgets('arrastrar en modo edición cambia el orden guardado', (
      tester,
    ) async {
      _comoUnMovil(tester);
      await tester.pumpWidget(_app(bd, PantallaRutina(idRutina: idRutina)));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(CupertinoIcons.arrow_up_arrow_down));
      await tester.pumpAndSettle();

      final asas = find.byIcon(CupertinoIcons.line_horizontal_3);
      expect(asas, findsNWidgets(3));

      // Se agarra el press de banca y se baja una fila.
      final gesto = await tester.startGesture(tester.getCenter(asas.first));
      await tester.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 7; i++) {
        await gesto.moveBy(const Offset(0, 10));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesto.up();
      await tester.pumpAndSettle();

      expect((await bd.ejerciciosDeRutina(idRutina)).map((e) => e.nombre), [
        'Aperturas',
        'Press banca',
        'Fondos',
      ]);
    });

    testWidgets('mover un ejercicio a otra rutina lo saca de esta', (
      tester,
    ) async {
      final destino = (await bd.insertarRutina('Full body'))!;

      _comoUnMovil(tester);
      await tester.pumpWidget(_app(bd, PantallaRutina(idRutina: idRutina)));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(CupertinoIcons.arrow_up_arrow_down));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byIcon(CupertinoIcons.arrow_right_arrow_left).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Full body'));
      await tester.pumpAndSettle();

      expect((await bd.ejerciciosDeRutina(idRutina)).map((e) => e.nombre), [
        'Aperturas',
        'Fondos',
      ]);
      expect(
        (await bd.ejerciciosDeRutina(destino)).single.nombre,
        'Press banca',
      );
    });
  });

  group('fecha del entrenamiento', () {
    late int idRutina;

    setUp(() async {
      idRutina = (await bd.insertarRutina('Empuje'))!;
      await bd.insertarEjercicio(idRutina, 'Press banca');
    });

    testWidgets('por defecto es hoy y se puede cambiar a un día pasado', (
      tester,
    ) async {
      _comoUnMovil(tester);
      await tester.pumpWidget(_app(bd, PantallaEntrenar(idRutina: idRutina)));
      await tester.pumpAndSettle();

      final hoy = DateTime.now();
      expect(find.text(formato.fechaLarga(hoy)), findsOneWidget);

      await tester.tap(find.text(formato.fechaLarga(hoy)));
      await tester.pumpAndSettle();

      // Se mueve la rueda por su callback en vez de arrastrando: la física del
      // scroll haría el test dependiente de píxeles y de la altura de la fila.
      final ayer = hoy.subtract(const Duration(days: 1));
      tester
          .widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker))
          .onDateTimeChanged(ayer);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Listo'));
      await tester.pumpAndSettle();

      expect(find.text(formato.fechaLarga(ayer)), findsOneWidget);

      await tester.tap(find.text('Guardar entrenamiento'));
      await tester.pumpAndSettle();

      // Un día pasado se guarda a las 12:00, para que el orden dentro del día
      // no dependa de la hora a la que se anotó.
      final sesion = (await bd.historialRutina(idRutina)).single;
      expect(sesion.fecha, DateTime(ayer.year, ayer.month, ayer.day, 12));
    });

    testWidgets('no deja elegir una fecha futura', (tester) async {
      _comoUnMovil(tester);
      await tester.pumpWidget(_app(bd, PantallaEntrenar(idRutina: idRutina)));
      await tester.pumpAndSettle();

      await tester.tap(find.text(formato.fechaLarga(DateTime.now())));
      await tester.pumpAndSettle();

      final selector = tester.widget<CupertinoDatePicker>(
        find.byType(CupertinoDatePicker),
      );
      expect(selector.maximumDate, isNotNull);
      expect(
        selector.maximumDate!.isAfter(
          DateTime.now().add(const Duration(minutes: 1)),
        ),
        isFalse,
      );
    });
  });

  group('historial de sesiones', () {
    late int idRutina;
    late int idEjercicio;

    setUp(() async {
      idRutina = (await bd.insertarRutina('Empuje'))!;
      await bd.insertarEjercicio(idRutina, 'Press banca');
      idEjercicio = (await bd.ejerciciosDeRutina(idRutina)).single.id;
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 1), {
        idEjercicio: const [
          ValoresSerie(repeticiones: 10, peso: 60),
          ValoresSerie(repeticiones: 8, peso: 65),
        ],
      });
    });

    testWidgets('lista las sesiones con sus cifras', (tester) async {
      _comoUnMovil(tester);
      await tester.pumpWidget(_app(bd, PantallaHistorial(idRutina: idRutina)));
      await tester.pumpAndSettle();

      expect(find.text('1 de marzo de 2026'), findsOneWidget);
      expect(find.text('1 ejercicio · 2 series · 1120 kg'), findsOneWidget);
    });

    testWidgets('editar una sesión desde el historial repinta la lista', (
      tester,
    ) async {
      _comoUnMovil(tester);
      await tester.pumpWidget(_app(bd, PantallaHistorial(idRutina: idRutina)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('1 de marzo de 2026'));
      await tester.pumpAndSettle();
      expect(find.text('10 repeticiones'), findsOneWidget);

      await tester.tap(find.text('Editar'));
      await tester.pumpAndSettle();
      expect(find.text('Editar entrenamiento'), findsOneWidget);

      // Una serie más y a guardar: la lista de detrás tiene que enterarse.
      await tester.tap(find.text('Añadir serie'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar entrenamiento'));
      await tester.pumpAndSettle();

      expect(await bd.seriesConFecha(idRutina, idEjercicio), hasLength(3));
      // Se edita, no se duplica.
      expect(await bd.contarEntrenamientosRutina(idRutina), 1);

      // Al volver, la lista de detrás está al día sin reiniciar la app.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('1 ejercicio · 3 series · 1640 kg'), findsOneWidget);
    });

    testWidgets('eliminar una sesión la saca de la lista', (tester) async {
      _comoUnMovil(tester);
      await tester.pumpWidget(_app(bd, PantallaHistorial(idRutina: idRutina)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('1 de marzo de 2026'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Eliminar sesión'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar').last);
      await tester.pumpAndSettle();

      expect(await bd.contarEntrenamientosRutina(idRutina), 0);
      expect(find.text('Todavía no hay sesiones'), findsOneWidget);
    });
  });
}
