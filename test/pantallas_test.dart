/// Tests de widget: montan pantallas reales contra una base en memoria.
///
/// El `bdProvider` se sobrescribe con una `NativeDatabase.memory()`, así que las
/// pantallas se ejercitan de verdad —consultas incluidas— sin tocar disco.
library;

import 'package:appgym/datos/ajustes.dart';
import 'package:appgym/datos/bd.dart';
import 'package:appgym/datos/geometria.dart';
import 'package:appgym/datos/musculos.dart';
import 'package:appgym/datos/nube/nube.dart';
import 'package:appgym/datos/reloj.dart' as reloj;
import 'package:appgym/datos/sincro/motor.dart';
import 'package:appgym/datos/sincro/transporte.dart';
import 'package:appgym/estado/descanso.dart';
import 'package:appgym/l10n/textos.dart';
import 'package:appgym/main.dart';
import 'package:appgym/datos/semilla.dart';
import 'package:appgym/estado/providers.dart';
import 'package:appgym/pantallas/ajustes.dart';
import 'package:appgym/pantallas/catalogo.dart';
import 'package:appgym/pantallas/entrenar.dart';
import 'package:appgym/pantallas/ficha.dart';
import 'package:appgym/pantallas/historial.dart';
import 'package:appgym/pantallas/medidas.dart';
import 'package:appgym/pantallas/musculatura.dart';
import 'package:appgym/pantallas/progreso.dart';
import 'package:appgym/pantallas/resultado_ejercicio.dart';
import 'package:appgym/pantallas/resumen_sesion.dart';
import 'package:appgym/pantallas/rutina.dart';
import 'package:appgym/pantallas/rutinas.dart';
import 'package:appgym/pantallas/sesion.dart';
import 'package:appgym/pantallas/sincro_detalle.dart';
import 'package:appgym/tema/ui.dart' as ui;
import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ayuda.dart';
import 'nube_falsa.dart';
import 'sincro_falso.dart';

/// Los formatos en español, para las aserciones que comparan una fecha ya
/// escrita. Es el mismo idioma que fija `_app`.
final _es = formatoDePrueba();

/// Y los ingleses, para el grupo que monta la app en inglés.
final _en = formatoDePrueba(idioma: 'en');

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

Widget _app(
  AppBD bd,
  Widget pantalla, {
  Brightness? brillo,
  Locale idioma = const Locale('es'),
  MapaCuerpo<Region>? modelo,
  // `Override` no lo exporta `flutter_riverpod`, así que no se puede nombrar
  // aquí; el `cast` lo resuelve la lista de destino, que sí está tipada.
  Iterable<Object> overrides = const [],
}) => ProviderScope(
  overrides: [
    bdProvider.overrideWithValue(bd),
    if (modelo != null) modeloCuerpoProvider.overrideWith((ref) => modelo),
    ...overrides.cast(),
  ],
  child: CupertinoApp(
    // El idioma se fija a español a propósito: así las aserciones de texto de
    // toda la suite siguen siendo válidas tal cual, y lo que de verdad depende
    // del idioma se prueba aparte, en el grupo que monta en inglés.
    locale: idioma,
    supportedLocales: idiomasSoportados,
    localizationsDelegates: Textos.localizationsDelegates,
    theme: CupertinoThemeData(brightness: brillo),
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

/// Asienta la pantalla a base de fotogramas sueltos.
///
/// En la sesión viva no se puede usar `pumpAndSettle`: el cronómetro y el
/// descanso son `Timer.periodic` que repintan para siempre, así que «esperar a
/// que no queden fotogramas» no termina nunca.
Future<void> _asentar(WidgetTester tester, {int veces = 8}) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Un reloj que solo avanza cuando se le dice.
///
/// El descanso y el cronómetro se calculan contra la hora real —para que
/// suspender la app no los desfase—, así que `tester.pump` por sí solo no los
/// mueve: adelanta los `Timer`, no el calendario. Con esto se adelantan los
/// dos a la vez.
class _RelojFalso {
  DateTime _ahora = DateTime(2026, 8, 1, 18);

  /// Lo instala y programa su retirada al acabar el test.
  void instalar() {
    reloj.fijarReloj(() => _ahora);
    addTearDown(() => reloj.fijarReloj(null));
  }

  /// Adelanta el reloj y deja que los `Timer` se pongan al día.
  Future<void> avanzar(WidgetTester tester, Duration cuanto) async {
    _ahora = _ahora.add(cuanto);
    await tester.pump(cuanto);
  }
}

/// Deja que se cierre el aviso flotante, que se retira con un `Timer`.
Future<void> _cerrarAviso(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 2));

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

      // El «+» ofrece antes las plantillas; «En blanco» es el camino de siempre.
      await tester.tap(find.text('En blanco'));
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

  group('notas y esfuerzo', () {
    late int idRutina;
    late int idEjercicio;

    setUp(() async {
      idRutina = (await bd.insertarRutina('Empuje'))!;
      await bd.insertarEjercicio(idRutina, 'Press banca');
      idEjercicio = (await bd.ejerciciosDeRutina(idRutina)).single.id;
    });

    testWidgets('con el esfuerzo desactivado el registro no lo enseña', (
      tester,
    ) async {
      _comoUnMovil(tester);
      await tester.pumpWidget(_app(bd, PantallaEntrenar(idRutina: idRutina)));
      await tester.pumpAndSettle();

      expect(find.text('RPE'), findsNothing);
      expect(find.text('RIR'), findsNothing);
      // La nota de sesión sí está siempre.
      expect(find.text('Nota de la sesión'), findsOneWidget);
    });

    testWidgets('activado en Ajustes, se elige y se guarda como RPE', (
      tester,
    ) async {
      await bd.fijarAjuste(Claves.esfuerzoActivo, '1');
      await bd.fijarAjuste(Claves.esfuerzoEscala, 'rir');

      _comoUnMovil(tester);
      await tester.pumpWidget(_app(bd, PantallaEntrenar(idRutina: idRutina)));
      await tester.pumpAndSettle();

      // Con la escala en RIR se rotulan las repeticiones en recámara.
      expect(find.text('RIR'), findsNWidgets(4));

      // RIR 2 en la primera serie, que se guarda como RPE 8.
      await tester.tap(find.text('2').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar entrenamiento'));
      await tester.pumpAndSettle();

      final sesion = (await bd.sesion(1))!;
      expect(sesion.ejercicios.single.series.first.rpe, 8);
      expect(sesion.ejercicios.single.series[1].rpe, isNull);
      expect(await bd.seriesConFecha(idRutina, idEjercicio), hasLength(4));
    });

    testWidgets('la nota de la sesión se guarda y se ve al abrirla', (
      tester,
    ) async {
      _comoUnMovil(tester);
      await tester.pumpWidget(_app(bd, PantallaEntrenar(idRutina: idRutina)));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(CupertinoTextField),
        'Me dolía el hombro',
      );
      await tester.tap(find.text('Guardar entrenamiento'));
      await tester.pumpAndSettle();

      expect((await bd.sesion(1))!.nota, 'Me dolía el hombro');
    });

    testWidgets('el detalle enseña la nota y el esfuerzo de cada serie', (
      tester,
    ) async {
      await bd.fijarAjuste(Claves.esfuerzoActivo, '1');
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 1), {
        idEjercicio: const [
          ValoresSerie(
            repeticiones: 8,
            peso: 65,
            rpe: 9,
            nota: 'Fallo en la última',
          ),
        ],
      }, nota: 'Me dolía el hombro');

      _comoUnMovil(tester);
      await tester.pumpWidget(
        _app(bd, const PantallaSesion(idEntrenamiento: 1)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Me dolía el hombro'), findsOneWidget);
      expect(find.text('RPE 9 · Fallo en la última'), findsOneWidget);
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
      expect(find.text(_es.fechaLarga(hoy)), findsOneWidget);

      await tester.tap(find.text(_es.fechaLarga(hoy)));
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

      expect(find.text(_es.fechaLarga(ayer)), findsOneWidget);

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

      await tester.tap(find.text(_es.fechaLarga(DateTime.now())));
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
      expect(find.text('1 ejercicio · 2 series · 1.120 kg'), findsOneWidget);
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
      expect(find.text('1 ejercicio · 3 series · 1.640 kg'), findsOneWidget);
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
  // ── B7 y B8: descanso y sesión viva ────────────────────────────────────────

  group('sesión viva', () {
    late int idRutina;
    late int idEjercicio;
    late _RelojFalso cronometro;

    setUp(() async {
      cronometro = _RelojFalso()..instalar();
      idRutina = (await bd.insertarRutina('Empuje'))!;
      await bd.insertarEjercicio(idRutina, 'Press banca');
      idEjercicio = (await bd.ejerciciosDeRutina(idRutina)).single.id;
    });

    testWidgets('arranca con cronómetro y las series por marcar', (
      tester,
    ) async {
      _comoUnMovil(tester);
      await tester.pumpWidget(
        _app(bd, PantallaEntrenar(idRutina: idRutina, modo: Modo.vivo)),
      );
      await _asentar(tester);

      expect(find.text('Entrenando'), findsOneWidget);
      expect(find.textContaining('0 / 4 series · 0:0'), findsOneWidget);
      // Un check por serie, ninguno marcado.
      expect(find.byType(ui.CheckSerie), findsNWidgets(4));
      expect(find.byIcon(CupertinoIcons.checkmark_circle_fill), findsNothing);
      // Y todavía no hay descanso que mostrar.
      expect(find.byType(ui.BarraDescanso), findsNothing);
    });

    testWidgets('seis series marcables caben en un móvil', (tester) async {
      // Seis series con su check: es la fila más apretada de la app, y donde
      // los desbordes se ven antes.
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 1), {
        idEjercicio: const [
          ValoresSerie(repeticiones: 12, peso: 40, calentamiento: true),
          ValoresSerie(repeticiones: 10, peso: 60),
          ValoresSerie(repeticiones: 10, peso: 60),
          ValoresSerie(repeticiones: 8, peso: 65),
          ValoresSerie(repeticiones: 6, peso: 70),
          ValoresSerie(repeticiones: 6, peso: 72.5),
        ],
      });

      _comoUnMovil(tester);
      await tester.pumpWidget(
        _app(bd, PantallaEntrenar(idRutina: idRutina, modo: Modo.vivo)),
      );
      await _asentar(tester);

      expect(find.byType(ui.CheckSerie), findsNWidgets(6));
      expect(find.byType(ui.SelectorEnLinea), findsNWidgets(12));
      expect(find.text('72,5 kg'), findsOneWidget);
    });

    testWidgets('marcar una serie arranca el descanso', (tester) async {
      _comoUnMovil(tester);
      await tester.pumpWidget(
        _app(bd, PantallaEntrenar(idRutina: idRutina, modo: Modo.vivo)),
      );
      await _asentar(tester);

      await tester.tap(find.byType(ui.CheckSerie).first);
      await _asentar(tester);

      expect(find.text('1 / 4 series · 0:00'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.checkmark_circle_fill), findsOneWidget);

      // Y con la serie hecha aparece la barra con los 90 s por defecto.
      expect(find.byType(ui.BarraDescanso), findsOneWidget);
      expect(find.text('1:30'), findsOneWidget);
      expect(find.text('Saltar'), findsOneWidget);
    });

    testWidgets('+15 s y −15 s ajustan sin reiniciar la cuenta', (
      tester,
    ) async {
      _comoUnMovil(tester);
      await tester.pumpWidget(
        _app(bd, PantallaEntrenar(idRutina: idRutina, modo: Modo.vivo)),
      );
      await _asentar(tester);

      await tester.tap(find.byType(ui.CheckSerie).first);
      await _asentar(tester);

      // Diez segundos consumidos: quedan 80.
      await cronometro.avanzar(tester, const Duration(seconds: 10));
      expect(find.text('1:20'), findsOneWidget);

      await tester.tap(find.text('+15 s'));
      await tester.pump();
      // 80 + 15, no 90 + 15: ajustar no reinicia.
      expect(find.text('1:35'), findsOneWidget);

      await tester.tap(find.text('−15 s'));
      await tester.pump();
      expect(find.text('1:20'), findsOneWidget);
    });

    testWidgets('al pasarse, el contador sube en vez de bajar', (tester) async {
      _comoUnMovil(tester);
      await tester.pumpWidget(
        _app(bd, PantallaEntrenar(idRutina: idRutina, modo: Modo.vivo)),
      );
      await _asentar(tester);

      await tester.tap(find.byType(ui.CheckSerie).first);
      await _asentar(tester);

      await cronometro.avanzar(tester, const Duration(seconds: 95));
      // El signo delante es lo que distingue «faltan 5» de «te has pasado 5».
      expect(find.text('+0:05'), findsOneWidget);
    });

    testWidgets('saltar retira la barra', (tester) async {
      _comoUnMovil(tester);
      await tester.pumpWidget(
        _app(bd, PantallaEntrenar(idRutina: idRutina, modo: Modo.vivo)),
      );
      await _asentar(tester);

      await tester.tap(find.byType(ui.CheckSerie).first);
      await _asentar(tester);
      expect(find.byType(ui.BarraDescanso), findsOneWidget);

      await tester.tap(find.text('Saltar'));
      await _asentar(tester);
      expect(find.byType(ui.BarraDescanso), findsNothing);
    });

    testWidgets('cerrar la pantalla cancela el reloj del descanso', (
      tester,
    ) async {
      // Si el `Timer` quedara vivo, este test fallaría solo con «A Timer is
      // still pending even after the widget tree was disposed»: es el motivo de
      // que exista.
      _comoUnMovil(tester);
      await tester.pumpWidget(
        _app(bd, PantallaEntrenar(idRutina: idRutina, modo: Modo.vivo)),
      );
      await _asentar(tester);

      await tester.tap(find.byType(ui.CheckSerie).first);
      await _asentar(tester);
      expect(find.byType(ui.BarraDescanso), findsOneWidget);

      await tester.pumpWidget(_app(bd, const PantallaRutinas()));
      await tester.pumpAndSettle();
    });

    testWidgets('terminar guarda solo lo marcado, con su duración', (
      tester,
    ) async {
      _comoUnMovil(tester);
      await tester.pumpWidget(
        _app(bd, PantallaEntrenar(idRutina: idRutina, modo: Modo.vivo)),
      );
      await _asentar(tester);

      await tester.tap(find.byType(ui.CheckSerie).at(0));
      await _asentar(tester);
      await tester.tap(find.byType(ui.CheckSerie).at(1));
      await _asentar(tester);

      // Media hora de sesión.
      await cronometro.avanzar(tester, const Duration(minutes: 30));
      await tester.tap(find.text('Terminar'));
      await _asentar(tester, veces: 12);

      final sesion = (await bd.sesion(1))!;
      // Dos de las cuatro: las que quedaron sin marcar eran el plan, no el
      // entrenamiento.
      expect(sesion.ejercicios.single.series, hasLength(2));
      expect(sesion.entrenamiento.duracionSeg, closeTo(1800, 5));
      // Y el borrador no sobrevive a confirmar.
      expect(await bd.sesionActiva(), isNull);
    });

    testWidgets('sin ninguna serie marcada no se guarda nada', (tester) async {
      _comoUnMovil(tester);
      await tester.pumpWidget(
        _app(bd, PantallaEntrenar(idRutina: idRutina, modo: Modo.vivo)),
      );
      await _asentar(tester);

      await tester.tap(find.text('Terminar'));
      await _asentar(tester);

      expect(await bd.contarEntrenamientosRutina(idRutina), 0);
      expect(find.text('Marca al menos una serie'), findsOneWidget);
      await _cerrarAviso(tester);
    });

    testWidgets('el borrador se escribe y se recupera con lo ya marcado', (
      tester,
    ) async {
      _comoUnMovil(tester);
      await tester.pumpWidget(
        _app(bd, PantallaEntrenar(idRutina: idRutina, modo: Modo.vivo)),
      );
      await _asentar(tester);

      await tester.tap(find.byType(ui.CheckSerie).first);
      // El borrador se escribe con dos segundos de retraso, para no tocar disco
      // en cada toque de un selector.
      await cronometro.avanzar(tester, const Duration(seconds: 3));
      await _asentar(tester);

      final borrador = await bd.sesionActiva();
      expect(borrador, isNotNull);
      expect(borrador!.idRutina, idRutina);

      // Y al reabrir con ese borrador, la serie sigue marcada.
      await tester.pumpWidget(
        _app(
          bd,
          PantallaEntrenar(
            idRutina: idRutina,
            modo: Modo.vivo,
            borrador: borrador,
          ),
        ),
      );
      await _asentar(tester);

      expect(find.byIcon(CupertinoIcons.checkmark_circle_fill), findsOneWidget);
      expect(find.textContaining('1 / 4 series'), findsOneWidget);
    });

    testWidgets('el formulario sigue sin cronómetro ni checks', (tester) async {
      _comoUnMovil(tester);
      await tester.pumpWidget(
        _app(bd, PantallaEntrenar(idRutina: idRutina, modo: Modo.formulario)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Registrar sesión'), findsOneWidget);
      expect(find.byType(ui.CheckSerie), findsNothing);
      expect(find.text('Guardar entrenamiento'), findsOneWidget);
      // La fecha se elige, que es de lo que va el formulario.
      expect(find.text(_es.fechaLarga(DateTime.now())), findsOneWidget);
    });

    testWidgets('el descanso propio de un ejercicio manda sobre el global', (
      tester,
    ) async {
      await bd.fijarDescansoEjercicio(idEjercicio, 45);

      _comoUnMovil(tester);
      await tester.pumpWidget(
        _app(bd, PantallaEntrenar(idRutina: idRutina, modo: Modo.vivo)),
      );
      await _asentar(tester);

      expect(find.text('45 s'), findsOneWidget);

      await tester.tap(find.byType(ui.CheckSerie).first);
      await _asentar(tester);
      expect(find.text('0:45'), findsOneWidget);
    });
  });

  // ── J3: la sugerencia de progresión ────────────────────────────────────────

  group('sugerencia de progresión', () {
    late int idRutina;
    late int idEjercicio;

    setUp(() async {
      idRutina = (await bd.insertarRutina('Empuje'))!;
      await bd.insertarEjercicio(idRutina, 'Press banca');
      idEjercicio = (await bd.ejerciciosDeRutina(idRutina)).single.id;
    });

    /// Tres sesiones completando el rango a 60 kg: toca subir de peso.
    ///
    /// Con dos bastaría para que hubiera sugerencia, pero se enseñaría marcada;
    /// con tres el historial ya da y el texto sale limpio.
    Future<void> historialAlTope() async {
      for (final fecha in [
        DateTime(2026, 3, 1),
        DateTime(2026, 3, 8),
        DateTime(2026, 3, 15),
      ]) {
        await bd.insertarEntrenamiento(idRutina, fecha, {
          idEjercicio: const [
            ValoresSerie(repeticiones: 12, peso: 60),
            ValoresSerie(repeticiones: 12, peso: 60),
            ValoresSerie(repeticiones: 12, peso: 60),
            ValoresSerie(repeticiones: 12, peso: 60),
          ],
        });
      }
    }

    testWidgets('propone subir el peso, y la línea cabe en un móvil', (
      tester,
    ) async {
      _comoUnMovil(tester);
      await historialAlTope();

      await tester.pumpWidget(_app(bd, PantallaEntrenar(idRutina: idRutina)));
      await tester.pumpAndSettle();

      expect(find.text('Sugerido 4×8 · 62,5 kg'), findsOneWidget);
      expect(find.text('Completaste el rango en todas las series'), findsOne);
      expect(find.byType(ui.Sugerencia), findsOneWidget);
    });

    testWidgets('sin dos sesiones previas no se enseña nada', (tester) async {
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 1), {
        idEjercicio: const [ValoresSerie(repeticiones: 12, peso: 60)],
      });

      await tester.pumpWidget(_app(bd, PantallaEntrenar(idRutina: idRutina)));
      await tester.pumpAndSettle();

      expect(find.byType(ui.Sugerencia), findsNothing);
    });

    testWidgets('aplicar reescribe las series y no guarda nada', (
      tester,
    ) async {
      _comoUnMovil(tester);
      await historialAlTope();

      await tester.pumpWidget(_app(bd, PantallaEntrenar(idRutina: idRutina)));
      await tester.pumpAndSettle();

      // Antes de aplicar, el registro viene precargado con la última sesión.
      expect(find.text('12'), findsNWidgets(4));

      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();

      expect(find.text('8'), findsNWidgets(4));
      expect(find.text('62,5 kg'), findsNWidgets(4));
      // Aplicar no confirma: siguen siendo las sesiones del historial.
      expect(await bd.contarEntrenamientosRutina(idRutina), 3);
      // Y la línea se retira: ya se ha hecho caso.
      expect(find.byType(ui.Sugerencia), findsNothing);
    });

    testWidgets('descartarla la quita sin tocar las series', (tester) async {
      _comoUnMovil(tester);
      await historialAlTope();

      await tester.pumpWidget(_app(bd, PantallaEntrenar(idRutina: idRutina)));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(CupertinoIcons.xmark));
      await tester.pumpAndSettle();

      expect(find.byType(ui.Sugerencia), findsNothing);
      expect(find.text('12'), findsNWidgets(4));
    });

    testWidgets('el descarte sobrevive a recuperar la sesión viva', (
      tester,
    ) async {
      _RelojFalso().instalar();
      await historialAlTope();

      await tester.pumpWidget(
        _app(bd, PantallaEntrenar(idRutina: idRutina, modo: Modo.vivo)),
      );
      await _asentar(tester);

      await tester.tap(find.byIcon(CupertinoIcons.xmark));
      await _asentar(tester, veces: 12);
      // El borrador se escribe con dos segundos de retraso.
      await tester.pump(const Duration(seconds: 3));

      final borrador = await bd.sesionActiva();
      expect(borrador, isNotNull);

      // Se recupera la sesión: la sugerencia sigue descartada, que es lo que
      // significa «no vuelve en esta sesión».
      await tester.pumpWidget(
        _app(
          bd,
          PantallaEntrenar(
            idRutina: idRutina,
            modo: Modo.vivo,
            borrador: borrador,
          ),
        ),
      );
      await _asentar(tester);

      expect(find.byType(ui.Sugerencia), findsNothing);
    });

    testWidgets('marcar la primera serie retira la línea en sesión viva', (
      tester,
    ) async {
      _comoUnMovil(tester);
      _RelojFalso().instalar();
      await historialAlTope();

      await tester.pumpWidget(
        _app(bd, PantallaEntrenar(idRutina: idRutina, modo: Modo.vivo)),
      );
      await _asentar(tester);
      expect(find.byType(ui.Sugerencia), findsOneWidget);

      await tester.tap(find.byType(ui.CheckSerie).first);
      await _asentar(tester);

      expect(find.byType(ui.Sugerencia), findsNothing);
    });

    testWidgets('con la progresión apagada ni siquiera se calcula', (
      tester,
    ) async {
      await historialAlTope();
      await bd.fijarAjuste(Claves.progresionActiva, '0');

      // El provider se sobrescribe con un espía: si la pantalla lo pidiera, se
      // notaría aquí. No basta con comprobar que no se pinta nada.
      var pedido = false;
      await tester.pumpWidget(
        _app(
          bd,
          PantallaEntrenar(idRutina: idRutina),
          overrides: [
            sugerenciaProvider.overrideWith((ref, clave) {
              pedido = true;
              return null;
            }),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(pedido, isFalse);
      expect(find.byType(ui.Sugerencia), findsNothing);
    });

    testWidgets('el rango propio del ejercicio manda sobre el global', (
      tester,
    ) async {
      await historialAlTope();
      // Con 3-5, cuatro series de doce ya no son «rango incompleto» sino
      // repeticiones muy por encima: toca subir peso igual, pero desde otro
      // rango, así que la propuesta baja a cinco repeticiones.
      await bd.fijarProgresionEjercicio(
        idEjercicio,
        repMin: const Value(3),
        repMax: const Value(5),
      );

      await tester.pumpWidget(_app(bd, PantallaEntrenar(idRutina: idRutina)));
      await tester.pumpAndSettle();

      expect(find.text('Sugerido 4×3 · 62,5 kg'), findsOneWidget);
    });

    testWidgets('la hoja de opciones escribe el rango del ejercicio', (
      tester,
    ) async {
      _comoUnMovil(tester);
      await historialAlTope();

      await tester.pumpWidget(_app(bd, PantallaRutina(idRutina: idRutina)));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Press banca'));
      await tester.pumpAndSettle();

      expect(find.text('Progresión'.toUpperCase()), findsOneWidget);
      expect(find.text('Rango de repeticiones'), findsOneWidget);

      await tester.tap(find.text('Rango de repeticiones'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3 – 5').last);
      await tester.pumpAndSettle();

      final ejercicio = (await bd.ejerciciosDeRutina(idRutina)).single;
      expect(ejercicio.ejercicio.repMin, 3);
      expect(ejercicio.ejercicio.repMax, 5);
    });

    testWidgets('un ejercicio estancado se anuncia en el resumen', (
      tester,
    ) async {
      // Cuatro sesiones idénticas: ni peso, ni repeticiones, ni volumen.
      for (var i = 0; i < 4; i++) {
        await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 1 + i * 7), {
          idEjercicio: const [ValoresSerie(repeticiones: 10, peso: 60)],
        });
      }

      await tester.pumpWidget(_app(bd, const PantallaProgreso()));
      await tester.pumpAndSettle();

      expect(find.text('1 ejercicio estancado'), findsOneWidget);

      await tester.tap(find.text('1 ejercicio estancado'));
      await tester.pumpAndSettle();

      expect(find.text('Press banca'), findsOneWidget);
      expect(find.textContaining('no un consejo de entrenamiento'), findsOne);
    });

    testWidgets('en la evolución del ejercicio se enseña sin aplicar', (
      tester,
    ) async {
      await historialAlTope();

      await tester.pumpWidget(
        _app(
          bd,
          PantallaResultadoEjercicio(
            idRutina: idRutina,
            idEjercicio: idEjercicio,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ui.Sugerencia), findsOneWidget);
      expect(find.text('Aplicar'), findsNothing);
    });
  });

  // ── B8: resumen de cierre ──────────────────────────────────────────────────

  group('resumen de cierre', () {
    testWidgets('enseña las cifras y los récords batidos', (tester) async {
      final idRutina = (await bd.insertarRutina('Empuje'))!;
      await bd.insertarEjercicio(idRutina, 'Press banca');
      final idEjercicio = (await bd.ejerciciosDeRutina(idRutina)).single.id;

      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 1), {
        idEjercicio: const [ValoresSerie(repeticiones: 10, peso: 60)],
      });
      final id = (await bd.insertarEntrenamiento(
        idRutina,
        DateTime(2026, 3, 8),
        {
          idEjercicio: const [
            ValoresSerie(repeticiones: 8, peso: 65),
            ValoresSerie(repeticiones: 8, peso: 65),
          ],
        },
        duracionSeg: 2052,
      ))!;

      _comoUnMovil(tester);
      await tester.pumpWidget(
        _app(bd, PantallaResumenSesion(idEntrenamiento: id)),
      );
      await tester.pumpAndSettle();

      expect(find.text('¡Sesión guardada!'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('1.040 kg'), findsOneWidget); // volumen de la sesión
      expect(find.text('34:12'), findsOneWidget);
      // Récord: 65 kg contra los 60 de la semana anterior. Se baten los tres,
      // porque subir el peso sube también la estimación y el volumen.
      expect(find.text('Récords'.toUpperCase()), findsOneWidget);
      expect(
        find.text(
          'Peso (antes 60 kg) · 1RM (antes 80 kg) · Volumen (antes 600 kg)',
        ),
        findsOneWidget,
      );
    });
  });

  // ── B9: unidades, paso y tema ──────────────────────────────────────────────

  group('ajustes en el registro', () {
    late int idRutina;
    late int idEjercicio;

    setUp(() async {
      idRutina = (await bd.insertarRutina('Empuje'))!;
      await bd.insertarEjercicio(idRutina, 'Press banca');
      idEjercicio = (await bd.ejerciciosDeRutina(idRutina)).single.id;
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 1), {
        idEjercicio: const [ValoresSerie(repeticiones: 10, peso: 60)],
      });
    });

    testWidgets('en libras el registro enseña los pesos convertidos', (
      tester,
    ) async {
      await bd.fijarAjuste(Claves.unidad, 'lb');

      _comoUnMovil(tester);
      await tester.pumpWidget(_app(bd, PantallaEntrenar(idRutina: idRutina)));
      await tester.pumpAndSettle();

      // 60 kg son 132,28 lb, que con el paso de 2,5 se cuadran en 132,5.
      expect(find.text('132,5 lb'), findsOneWidget);
      expect(find.textContaining('kg'), findsNothing);
    });

    testWidgets('cambiar a libras no toca lo guardado', (tester) async {
      await bd.fijarAjuste(Claves.unidad, 'lb');

      _comoUnMovil(tester);
      await tester.pumpWidget(_app(bd, PantallaEntrenar(idRutina: idRutina)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar entrenamiento'));
      await tester.pumpAndSettle();

      // Se ve en libras y se guarda en kilos. Y como nadie ha tocado el
      // selector, el valor no pasa siquiera por la conversión: sale intacto.
      final series = await bd.seriesConFecha(idRutina, idEjercicio);
      expect(series.last.peso, 60);
    });

    testWidgets('el paso del peso se respeta al pulsar +', (tester) async {
      await bd.fijarAjuste(Claves.pasoPeso, '1.25');

      _comoUnMovil(tester);
      await tester.pumpWidget(_app(bd, PantallaEntrenar(idRutina: idRutina)));
      await tester.pumpAndSettle();

      expect(find.text('60,00 kg'), findsOneWidget);
      // El «+» del peso es el segundo de la fila.
      await tester.tap(find.byIcon(CupertinoIcons.plus).at(1));
      await tester.pumpAndSettle();

      expect(find.text('61,25 kg'), findsOneWidget);
    });

    testWidgets('las series y repeticiones por defecto salen de Ajustes', (
      tester,
    ) async {
      await bd.fijarAjustes({Claves.series: '2', Claves.repeticiones: '15'});
      // Una rutina sin histórico, que es cuando se usan los valores de fábrica.
      final otra = (await bd.insertarRutina('Pierna'))!;
      await bd.insertarEjercicio(otra, 'Sentadilla');

      _comoUnMovil(tester);
      await tester.pumpWidget(_app(bd, PantallaEntrenar(idRutina: otra)));
      await tester.pumpAndSettle();

      expect(find.byType(ui.SelectorEnLinea), findsNWidgets(4));
      expect(find.text('15'), findsNWidgets(2));
    });

    testWidgets('el histórico también se lee en la unidad activa', (
      tester,
    ) async {
      await bd.fijarAjuste(Claves.unidad, 'lb');

      _comoUnMovil(tester);
      await tester.pumpWidget(
        _app(bd, const PantallaSesion(idEntrenamiento: 1)),
      );
      await tester.pumpAndSettle();

      expect(find.text('132,3 lb'), findsOneWidget);
      expect(find.textContaining('kg'), findsNothing);
    });
  });

  // ── B12: favoritos y añadir a rutina desde el catálogo ─────────────────────

  group('catálogo del usuario', () {
    setUp(() => sembrarCatalogo(bd, datos: _catalogoFalso));

    testWidgets('los favoritos salen arriba cuando no hay búsqueda', (
      tester,
    ) async {
      await bd.marcarFavorito('0002', true);

      await tester.pumpWidget(_app(bd, const PantallaCatalogo()));
      await tester.pumpAndSettle();

      expect(find.text('Favoritos'.toUpperCase()), findsOneWidget);
      expect(find.text('TODOS LOS EJERCICIOS'), findsOneWidget);
      // Una vez en favoritos y otra en la lista completa.
      expect(find.text('dumbbell curl'), findsNWidgets(2));
    });

    testWidgets('sin favoritos ni vistos, la cabecera no estorba', (
      tester,
    ) async {
      await tester.pumpWidget(_app(bd, const PantallaCatalogo()));
      await tester.pumpAndSettle();

      expect(find.text('Favoritos'.toUpperCase()), findsNothing);
      expect(find.text('TODOS LOS EJERCICIOS'), findsNothing);
      expect(find.text('dumbbell curl'), findsOneWidget);
    });

    testWidgets('con búsqueda activa desaparecen los destacados', (
      tester,
    ) async {
      await bd.marcarFavorito('0002', true);

      await tester.pumpWidget(_app(bd, const PantallaCatalogo()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CupertinoSearchTextField), 'barbell');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('Favoritos'.toUpperCase()), findsNothing);
      expect(find.text('barbell bench press'), findsOneWidget);
    });

    testWidgets('la estrella marca y desmarca desde la lista', (tester) async {
      await tester.pumpWidget(_app(bd, const PantallaCatalogo()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(CupertinoIcons.star).first);
      await tester.pumpAndSettle();

      expect(await bd.idsFavoritos(), hasLength(1));
      expect(find.byIcon(CupertinoIcons.star_fill), findsOneWidget);
    });

    testWidgets('con una sola rutina, el «+» añade sin preguntar', (
      tester,
    ) async {
      final idRutina = (await bd.insertarRutina('Empuje'))!;

      await tester.pumpWidget(_app(bd, const PantallaCatalogo()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(CupertinoIcons.plus_circle).first);
      await tester.pumpAndSettle();

      final ejercicios = await bd.ejerciciosDeRutina(idRutina);
      expect(ejercicios.single.nombre, 'barbell bench press');
      expect(ejercicios.single.ejercicio.idCatalogo, '0001');
      await _cerrarAviso(tester);
    });

    testWidgets('con varias rutinas pregunta a cuál', (tester) async {
      await bd.insertarRutina('Empuje');
      final pierna = (await bd.insertarRutina('Pierna'))!;

      await tester.pumpWidget(_app(bd, const PantallaCatalogo()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(CupertinoIcons.plus_circle).first);
      await tester.pumpAndSettle();

      expect(find.text('Añadir «barbell bench press»'), findsOneWidget);
      await tester.tap(find.text('Pierna'));
      await tester.pumpAndSettle();

      expect(await bd.ejerciciosDeRutina(pierna), hasLength(1));
      await _cerrarAviso(tester);
    });

    testWidgets('sin ninguna rutina, avisa en vez de no hacer nada', (
      tester,
    ) async {
      await tester.pumpWidget(_app(bd, const PantallaCatalogo()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(CupertinoIcons.plus_circle).first);
      await tester.pumpAndSettle();

      expect(find.text('Crea antes una rutina'), findsOneWidget);
      await _cerrarAviso(tester);
    });

    testWidgets('el filtro por músculo trae solo los de ese objetivo', (
      tester,
    ) async {
      await tester.pumpWidget(_app(bd, const PantallaCatalogo()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Músculo'));
      await tester.pumpAndSettle();
      // Con su recuento, que es lo que dice si merece la pena entrar.
      await tester.tap(find.text('Bíceps · 1'));
      await tester.pumpAndSettle();

      expect(find.text('dumbbell curl'), findsOneWidget);
      expect(find.text('barbell bench press'), findsNothing);
    });

    testWidgets('abrir una ficha la deja en vistos recientemente', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(bd, const PantallaFicha(idCatalogo: '0001')),
      );
      await tester.pumpAndSettle();

      expect((await bd.vistosRecientes()).single.id, '0001');
      // Y la ficha ofrece añadirlo sin salir de ahí.
      expect(find.text('Añadir a una rutina'), findsOneWidget);
    });

    testWidgets('la ficha dice en qué rutinas ya está', (tester) async {
      final idRutina = (await bd.insertarRutina('Empuje'))!;
      await bd.insertarEjercicio(idRutina, 'Press', idCatalogo: '0001');

      await tester.pumpWidget(
        _app(bd, const PantallaFicha(idCatalogo: '0001')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ya está en: Empuje'), findsOneWidget);
    });
  });

  // ── B13: peso corporal y medidas ───────────────────────────────────────────

  group('medidas del cuerpo', () {
    testWidgets('la pestaña Cuerpo ofrece registrar el peso', (tester) async {
      _comoUnMovil(tester);
      await tester.pumpWidget(_app(bd, const PantallaProgreso()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cuerpo'));
      await tester.pumpAndSettle();

      expect(find.text('Registrar tu peso'), findsOneWidget);
      expect(find.text('Peso corporal'), findsOneWidget);
      expect(find.text('Sin registros'), findsNWidgets(tiposMedida.length));
    });

    testWidgets('con el peso reciente no insiste', (tester) async {
      await bd.registrarMedida(DateTime.now(), 'peso', 78.4);

      _comoUnMovil(tester);
      await tester.pumpWidget(_app(bd, const PantallaProgreso()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cuerpo'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Registrar tu peso'), findsNothing);
      expect(find.text('78,4 kg'), findsOneWidget);
    });

    testWidgets('registrar dos veces el mismo día deja un solo valor', (
      tester,
    ) async {
      _comoUnMovil(tester);
      await tester.pumpWidget(_app(bd, const PantallaMedidas()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Registrar'));
      await tester.pumpAndSettle();
      // Con coma decimal, que es lo que escribe un teclado español.
      await tester.enterText(find.byType(CupertinoTextField), '78,4');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect((await bd.serieMedida('peso')).single.valor, closeTo(78.4, 1e-9));

      await tester.tap(find.byIcon(CupertinoIcons.add));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CupertinoTextField), '78,9');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      final serie = await bd.serieMedida('peso');
      expect(serie, hasLength(1));
      expect(serie.single.valor, closeTo(78.9, 1e-9));
    });

    testWidgets('un texto que no es un número no guarda nada', (tester) async {
      _comoUnMovil(tester);
      await tester.pumpWidget(_app(bd, const PantallaMedidas()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Registrar'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CupertinoTextField), 'bastante');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(await bd.serieMedida('peso'), isEmpty);
      expect(find.textContaining('Escribe un número'), findsOneWidget);
      await _cerrarAviso(tester);
    });

    testWidgets('en libras el peso corporal también se convierte', (
      tester,
    ) async {
      await bd.fijarAjuste(Claves.unidad, 'lb');
      await bd.registrarMedida(DateTime(2026, 8, 1), 'peso', 78.4);

      _comoUnMovil(tester);
      await tester.pumpWidget(_app(bd, const PantallaMedidas()));
      await tester.pumpAndSettle();

      expect(find.text('172,8 lb'), findsOneWidget);
    });

    testWidgets('la cintura se mide en centímetros, no en la unidad activa', (
      tester,
    ) async {
      await bd.fijarAjuste(Claves.unidad, 'lb');
      await bd.registrarMedida(DateTime(2026, 8, 1), 'cintura', 82);

      _comoUnMovil(tester);
      await tester.pumpWidget(_app(bd, const PantallaMedidas(tipo: 'cintura')));
      await tester.pumpAndSettle();

      expect(find.text('82 cm'), findsOneWidget);
    });
  });

  // ── B11: duplicar rutina ───────────────────────────────────────────────────

  group('duplicar rutina', () {
    testWidgets('desde el menú, copia los ejercicios y abre la copia', (
      tester,
    ) async {
      final idRutina = (await bd.insertarRutina('Empuje'))!;
      await bd.insertarEjercicio(idRutina, 'Press banca');
      await bd.insertarEjercicio(idRutina, 'Aperturas');

      _comoUnMovil(tester);
      await tester.pumpWidget(_app(bd, PantallaRutina(idRutina: idRutina)));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(CupertinoIcons.ellipsis));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Duplicar rutina'));
      await tester.pumpAndSettle();

      expect(find.text('Empuje (copia)'), findsOneWidget);
      await tester.tap(find.text('Duplicar'));
      await tester.pumpAndSettle();

      final rutinas = await bd.todasLasRutinas();
      expect(rutinas.map((r) => r.nombre), ['Empuje', 'Empuje (copia)']);
      expect(await bd.ejerciciosDeRutina(rutinas.last.id), hasLength(2));
    });
  });
  // ── B7: el aviso al terminar el descanso ───────────────────────────────────

  group('aviso del descanso', () {
    /// Anota lo que la app le pide al sistema: el pitido y la vibración van por
    /// el mismo canal de plataforma.
    List<String> espiarPlataforma(WidgetTester tester) {
      final llamadas = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (llamada) async {
          llamadas.add('${llamada.method}:${llamada.arguments}');
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      return llamadas;
    }

    testWidgets('con el sonido activado suena y vibra', (tester) async {
      final llamadas = espiarPlataforma(tester);
      final contenedor = ProviderContainer(
        overrides: [bdProvider.overrideWithValue(bd)],
      );
      addTearDown(contenedor.dispose);
      await contenedor.read(ajustesProvider.future);

      contenedor.read(descansoProvider.notifier).avisar();
      await tester.pump();

      expect(llamadas, contains('SystemSound.play:SystemSoundType.alert'));
      expect(
        llamadas,
        contains('HapticFeedback.vibrate:HapticFeedbackType.heavyImpact'),
      );
    });

    testWidgets('con el sonido desactivado no suena, pero sí vibra', (
      tester,
    ) async {
      await bd.fijarAjuste(Claves.sonidoDescanso, '0');

      final llamadas = espiarPlataforma(tester);
      final contenedor = ProviderContainer(
        overrides: [bdProvider.overrideWithValue(bd)],
      );
      addTearDown(contenedor.dispose);
      await contenedor.read(ajustesProvider.future);

      contenedor.read(descansoProvider.notifier).avisar();
      await tester.pump();

      expect(
        llamadas,
        isNot(contains('SystemSound.play:SystemSoundType.alert')),
      );
      // La vibración va siempre: es lo que se nota con el móvil en el bolsillo.
      expect(
        llamadas,
        contains('HapticFeedback.vibrate:HapticFeedbackType.heavyImpact'),
      );
    });
  });

  // ── B9: el tema forzado ────────────────────────────────────────────────────

  group('tema de la app', () {
    /// El brillo con el que la app pinta, leído desde dentro del árbol.
    Future<Brightness> brilloDe(WidgetTester tester, AppBD bd) async {
      late Brightness visto;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [bdProvider.overrideWithValue(bd)],
          child: const AppGym(),
        ),
      );
      await tester.pump();
      await tester.pump();

      // Cualquier punto del árbol vale: lo que se comprueba es que el ajuste
      // llega a la raíz y de ahí a todo lo que resuelve la extensión `Paleta`.
      final contexto = tester.element(find.byType(CupertinoPageScaffold).first);
      visto = CupertinoTheme.brightnessOf(contexto);
      return visto;
    }

    testWidgets('con «Sistema» sigue al móvil', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      expect(await brilloDe(tester, bd), Brightness.light);
    });

    testWidgets('forzar oscuro tiñe la app con el sistema en claro', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await bd.fijarAjuste(Claves.tema, 'oscuro');

      expect(await brilloDe(tester, bd), Brightness.dark);
    });

    testWidgets('forzar claro tiñe la app con el sistema en oscuro', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await bd.fijarAjuste(Claves.tema, 'claro');

      expect(await brilloDe(tester, bd), Brightness.light);
    });
  });

  // ── C16: 1RM estimado y récords ────────────────────────────────────────────

  group('evolución de un ejercicio', () {
    late int idRutina;
    late int idEjercicio;

    setUp(() async {
      idRutina = (await bd.insertarRutina('Empuje'))!;
      await bd.insertarEjercicio(idRutina, 'Press banca');
      idEjercicio = (await bd.ejerciciosDeRutina(idRutina)).single.id;
    });

    Future<void> abrir(WidgetTester tester) async {
      _comoUnMovil(tester);
      await tester.pumpWidget(
        _app(
          bd,
          PantallaResultadoEjercicio(
            idRutina: idRutina,
            idEjercicio: idEjercicio,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('la tarjeta enseña las cuatro cifras', (tester) async {
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 1), {
        idEjercicio: const [ValoresSerie(repeticiones: 10, peso: 60)],
      });
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 8), {
        idEjercicio: const [ValoresSerie(repeticiones: 8, peso: 65)],
      });

      await abrir(tester);

      expect(find.text('1RM estimado'), findsOneWidget);
      expect(find.text('Peso máximo'), findsOneWidget);
      expect(find.text('Volumen total'), findsOneWidget);
      expect(find.text('Sesiones'), findsOneWidget);

      expect(find.text('65 kg'), findsWidgets); // peso máximo
      // Con el idioma en español el separador de miles es el punto (I3).
      expect(find.text('1.120 kg'), findsOneWidget); // volumen total
      expect(find.text('2'), findsOneWidget); // sesiones
      // Epley sobre 8 × 65 = 82,3, mejor que los 80 de la primera sesión.
      expect(find.text('82,3 kg'), findsOneWidget);
    });

    testWidgets('cambiar el eje a Volumen repinta sin volver a consultar', (
      tester,
    ) async {
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 1), {
        idEjercicio: const [ValoresSerie(repeticiones: 10, peso: 60)],
      });

      await abrir(tester);
      await tester.tap(find.text('Volumen').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('1RM'));
      await tester.pumpAndSettle();

      // Si el gráfico reventara al cambiar de métrica, el árbol no llegaría
      // aquí entero.
      expect(find.text('Histórico'.toUpperCase()), findsOneWidget);
    });

    testWidgets('el rango recorta el gráfico sin perder el histórico', (
      tester,
    ) async {
      // Una sesión de hace dos años y otra de ayer: con «1M» solo entra la
      // reciente en el gráfico, pero la lista de abajo las enseña las dos.
      final ahora = DateTime.now();
      await bd.insertarEntrenamiento(
        idRutina,
        ahora.subtract(const Duration(days: 730)),
        {
          idEjercicio: const [ValoresSerie(repeticiones: 10, peso: 50)],
        },
      );
      await bd.insertarEntrenamiento(
        idRutina,
        ahora.subtract(const Duration(days: 1)),
        {
          idEjercicio: const [ValoresSerie(repeticiones: 10, peso: 60)],
        },
      );

      await abrir(tester);
      await tester.tap(find.text('1M'));
      await tester.pumpAndSettle();

      expect(find.text('2'), findsOneWidget); // siguen siendo dos sesiones
      expect(find.byIcon(CupertinoIcons.rosette), findsNWidgets(2));
    });

    testWidgets('una serie larga se marca como estimación poco fiable', (
      tester,
    ) async {
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 3, 1), {
        idEjercicio: const [ValoresSerie(repeticiones: 20, peso: 40)],
      });

      await abrir(tester);

      expect(find.textContaining('*'), findsWidgets);
      expect(
        find.textContaining('no cuenta como récord', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('sin registros no se pinta ni tarjeta ni gráfico', (
      tester,
    ) async {
      await abrir(tester);

      expect(find.text('Sin registros todavía'), findsOneWidget);
      expect(find.text('1RM estimado'), findsNothing);
    });
  });

  // ── C17: resumen semanal y racha ───────────────────────────────────────────

  group('resumen de la semana', () {
    /// Miércoles 11 de marzo de 2026; su semana va del lunes 9 al domingo 15.
    ///
    /// La fecha se fija para que la racha y el «esta semana» no dependan de
    /// cuándo se ejecute la suite, que es justo el fallo que tendría un test
    /// escrito contra `DateTime.now()`.
    final hoy = DateTime(2026, 3, 11, 19);

    late int idRutina;
    late int idEjercicio;

    setUp(() async {
      reloj.fijarReloj(() => hoy);
      addTearDown(() => reloj.fijarReloj(null));

      idRutina = (await bd.insertarRutina('Empuje'))!;
      await bd.insertarEjercicio(idRutina, 'Press banca');
      idEjercicio = (await bd.ejerciciosDeRutina(idRutina)).single.id;
    });

    Future<void> entrenar(DateTime fecha, {double peso = 60}) =>
        bd.insertarEntrenamiento(idRutina, fecha, {
          idEjercicio: [ValoresSerie(repeticiones: 10, peso: peso)],
        });

    Future<void> abrir(WidgetTester tester) async {
      _comoUnMovil(tester);
      await tester.pumpWidget(_app(bd, const PantallaProgreso()));
      await tester.pumpAndSettle();
    }

    testWidgets('cuenta las sesiones de la semana contra el objetivo', (
      tester,
    ) async {
      await entrenar(DateTime(2026, 3, 9));
      await entrenar(DateTime(2026, 3, 11));
      // La del domingo anterior es de la semana pasada y no cuenta aquí.
      await entrenar(DateTime(2026, 3, 8));

      await abrir(tester);

      expect(find.text('Esta semana'.toUpperCase()), findsOneWidget);
      expect(find.text('2 de 3'), findsOneWidget);
    });

    testWidgets('la comparativa se omite sin datos de la semana anterior', (
      tester,
    ) async {
      await entrenar(DateTime(2026, 3, 9));

      await abrir(tester);

      expect(find.text('1 de 3'), findsOneWidget);
      expect(find.textContaining('de volumen'), findsNothing);
    });

    testWidgets('con semana previa enseña la variación con signo', (
      tester,
    ) async {
      // La semana pasada: una sesión de 600 kg. Esta: dos de 600 y 720.
      await entrenar(DateTime(2026, 3, 4));
      await entrenar(DateTime(2026, 3, 9));
      await entrenar(DateTime(2026, 3, 10), peso: 72);

      await abrir(tester);

      expect(find.text('+1 sesión'), findsOneWidget);
      // (1320 − 600) / 600 = +120 %.
      expect(find.text('+120 % de volumen'), findsOneWidget);
    });

    testWidgets('la racha cuenta semanas cerradas, no la que está en curso', (
      tester,
    ) async {
      // Objetivo 2, cumplido las dos semanas anteriores. La actual va por una,
      // y aun así la racha sigue viva porque la semana no ha terminado.
      await bd.fijarAjuste(Claves.sesionesPorSemana, '2');
      for (final dia in [23, 25]) {
        await entrenar(DateTime(2026, 2, dia));
      }
      for (final dia in [2, 4]) {
        await entrenar(DateTime(2026, 3, dia));
      }
      await entrenar(DateTime(2026, 3, 9));

      await abrir(tester);

      expect(find.text('1 de 2'), findsOneWidget);
      expect(
        find.textContaining('2 semanas seguidas', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('avisa cuando hace más de una semana del último entreno', (
      tester,
    ) async {
      await entrenar(DateTime(2026, 3, 1));

      await abrir(tester);

      expect(find.text('0 de 3'), findsOneWidget);
      expect(
        find.text('Hace 10 días de tu último entrenamiento'),
        findsOneWidget,
      );
    });

    testWidgets('sin ninguna sesión no hay tarjeta, sino el estado vacío', (
      tester,
    ) async {
      await abrir(tester);

      expect(find.text('Todavía no hay datos'), findsOneWidget);
      expect(find.text('Esta semana'.toUpperCase()), findsNothing);
    });
  });

  // ── C19: días del calendario pulsables ─────────────────────────────────────

  group('días del calendario', () {
    late int idRutina;
    late int idEjercicio;

    setUp(() async {
      idRutina = (await bd.insertarRutina('Empuje'))!;
      await bd.insertarEjercicio(idRutina, 'Press banca');
      idEjercicio = (await bd.ejerciciosDeRutina(idRutina)).single.id;
    });

    /// Abre el calendario del mes en curso, que es el que monta la pantalla.
    Future<void> abrirCalendario(WidgetTester tester) async {
      _comoUnMovil(tester);
      await tester.pumpWidget(_app(bd, const PantallaProgreso()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Calendario'));
      await tester.pumpAndSettle();
    }

    /// Pulsa la celda de un día del mes visible.
    ///
    /// El número del día aparece también en otros sitios de la pantalla, así
    /// que se busca dentro del `GridView` del calendario.
    Future<void> pulsarDia(WidgetTester tester, int dia) async {
      await tester.tap(
        find.descendant(of: find.byType(GridView), matching: find.text('$dia')),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('pulsar un día entrenado enseña sus sesiones', (tester) async {
      // Se entrena **hoy**, y no un día fijo del mes: un 4 clavado convertiría
      // el test en futuro —y por tanto no pulsable— los tres primeros días de
      // cada mes.
      final ahora = DateTime.now();
      // Dos sesiones el mismo día: la hoja debe traerlas las dos.
      await bd.insertarEntrenamiento(
        idRutina,
        DateTime(ahora.year, ahora.month, ahora.day, 9),
        {
          idEjercicio: const [ValoresSerie(repeticiones: 10, peso: 60)],
        },
      );
      await bd.insertarEntrenamiento(
        idRutina,
        DateTime(ahora.year, ahora.month, ahora.day, 19),
        {
          idEjercicio: const [ValoresSerie(repeticiones: 8, peso: 65)],
        },
      );

      await abrirCalendario(tester);
      await pulsarDia(tester, ahora.day);

      expect(find.text('2 sesiones'), findsOneWidget);
      // El nombre de la rutina sale también en la leyenda del mes, así que se
      // cuenta solo dentro de la hoja.
      expect(
        find.descendant(
          of: find.byType(CupertinoActionSheet),
          matching: find.text('Empuje'),
        ),
        findsNWidgets(2),
      );
      expect(
        find.textContaining('9:00 · 1 ejercicio · 600 kg'),
        findsOneWidget,
      );
      expect(
        find.textContaining('19:00 · 1 ejercicio · 520 kg'),
        findsOneWidget,
      );
    });

    testWidgets('desde la hoja se llega al detalle de la sesión', (
      tester,
    ) async {
      final ahora = DateTime.now();
      await bd.insertarEntrenamiento(
        idRutina,
        DateTime(ahora.year, ahora.month, ahora.day, 9),
        {
          idEjercicio: const [ValoresSerie(repeticiones: 10, peso: 60)],
        },
      );

      await abrirCalendario(tester);
      await pulsarDia(tester, ahora.day);
      await tester.tap(
        find.descendant(
          of: find.byType(CupertinoActionSheet),
          matching: find.text('Empuje'),
        ),
      );
      await tester.pumpAndSettle();

      // La pantalla de sesión de A2, con su botón de eliminar.
      expect(find.text('Sesión'), findsWidgets);
      expect(find.text('Eliminar sesión'), findsOneWidget);
    });

    testWidgets('un día pasado y vacío ofrece registrar en él', (tester) async {
      await abrirCalendario(tester);
      await pulsarDia(tester, 1);

      expect(
        find.text('Registrar un entrenamiento en este día'),
        findsOneWidget,
      );
      await tester.tap(find.text('Empuje'));
      await tester.pumpAndSettle();

      // Se abre el formulario de siempre, con el día elegido puesto.
      expect(find.text('Registrar sesión'), findsOneWidget);
      final ahora = DateTime.now();
      expect(
        find.text(_es.fechaLarga(DateTime(ahora.year, ahora.month, 1))),
        findsOneWidget,
      );
    });

    testWidgets('sin ninguna rutina avisa en vez de abrir una hoja vacía', (
      tester,
    ) async {
      await bd.borrarRutina(idRutina);

      await abrirCalendario(tester);
      await pulsarDia(tester, 1);

      expect(find.text('Crea antes una rutina'), findsOneWidget);
      await _cerrarAviso(tester);
    });

    testWidgets('los días futuros no responden al toque', (tester) async {
      final ahora = DateTime.now();
      // El último día del mes; si hoy es ese mismo día no hay futuro que
      // probar dentro del mes visible y el caso no aplica.
      final ultimo = DateTime(ahora.year, ahora.month + 1, 0).day;
      if (ahora.day >= ultimo) return;

      await abrirCalendario(tester);
      await pulsarDia(tester, ultimo);

      expect(find.text('Registrar un entrenamiento en este día'), findsNothing);
      expect(find.text('Cancelar'), findsNothing);
    });
  });

  // ── D: el mapa muscular ────────────────────────────────────────────────────

  group('mapa muscular', () {
    late _RelojFalso hoy;
    late int idRutina;
    late MapaCuerpo<Region> modelo;

    // El dibujo se lee del asset una sola vez y se inyecta ya construido: leer
    // un fichero compite con el reloj falso de `pumpAndSettle` y hace los tests
    // dependientes de lo rápido que vaya el disco. Que el asset se parsea bien
    // lo prueba `geometria_test.dart`, que es su sitio.
    setUpAll(() {
      // Se lee del disco y no con `rootBundle`: `setUpAll` corre antes de que
      // exista el binding de Flutter, y ahí el bundle se queda esperando.
      modelo = cargarMapa(
        jsonDecode(File('assets/musculatura.json').readAsStringSync())
            as Map<String, dynamic>,
        (nombre) => Region.values.asNameMap()[nombre],
      );
    });

    setUp(() async {
      hoy = _RelojFalso()..instalar();
      await sembrarCatalogo(bd, datos: _catalogoFalso);
      idRutina = (await bd.insertarRutina('Empuje'))!;
    });

    /// Registra un press de banca, que en el catálogo falso es de pectorales.
    Future<void> entrenarPecho() async {
      await bd.insertarEjercicio(idRutina, 'Press banca', idCatalogo: '0001');
      final id = (await bd.ejerciciosDeRutina(idRutina)).first.id;
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 7, 30), {
        id: const [
          ValoresSerie(repeticiones: 10, peso: 60),
          ValoresSerie(repeticiones: 8, peso: 70),
        ],
      });
    }

    /// Monta Progreso y abre la pestaña «Cuerpo».
    Future<void> abrirCuerpo(WidgetTester tester, {Brightness? brillo}) async {
      _comoUnMovil(tester);
      await tester.pumpWidget(
        _app(bd, const PantallaProgreso(), brillo: brillo, modelo: modelo),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cuerpo'));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
    }

    testWidgets('se pinta con su conmutador, su periodo y su leyenda', (
      tester,
    ) async {
      await entrenarPecho();
      await abrirCuerpo(tester);

      expect(find.byType(MapaMuscular), findsOneWidget);
      expect(find.text('Frente'), findsOneWidget);
      expect(find.text('Espalda'), findsOneWidget);
      expect(find.text('30 días'), findsOneWidget);
      expect(find.text('Sin trabajar'), findsOneWidget);
      expect(find.text('MENOS TRABAJADOS'), findsOneWidget);
      // Y las medidas siguen debajo, en la misma sección.
      expect(find.text('MEDIDAS'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('el conmutador alterna de cara sin recargar', (tester) async {
      await entrenarPecho();
      await abrirCuerpo(tester);

      await tester.tap(find.text('Espalda'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(MapaMuscular), findsOneWidget);
    });

    testWidgets('cambiar de periodo recolorea sin excepciones', (tester) async {
      await entrenarPecho();
      await abrirCuerpo(tester);

      for (final periodo in ['7 días', '90 días', '30 días']) {
        await tester.tap(find.text(periodo));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: periodo);
      }
    });

    testWidgets('sin entrenamientos explica el modelo en gris', (tester) async {
      await abrirCuerpo(tester);

      expect(find.text('Aún no hay nada que colorear'), findsOneWidget);
      // El modelo se sigue pintando: la vista es útil sin histórico, porque el
      // catálogo por músculo se navega igual.
      expect(find.byType(CustomPaint), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('la lista de abandonados abre la hoja del músculo', (
      tester,
    ) async {
      await entrenarPecho();
      await abrirCuerpo(tester);

      // Un músculo que no se ha tocado nunca: la lista de abandonados es
      // justamente el camino fiable para las regiones pequeñas. Hay que
      // acercarla antes, que con el modelo delante cae bajo el pliegue.
      await tester.ensureVisible(find.text('Bíceps'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bíceps'));
      await tester.pumpAndSettle();

      expect(find.text('ÚLTIMOS 30 DÍAS'), findsOneWidget);
      expect(find.text('EJERCICIOS'), findsOneWidget);
      expect(find.text('Listo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('la hoja de un músculo entrenado trae sus sesiones', (
      tester,
    ) async {
      await entrenarPecho();
      hoy.instalar();
      await abrirCuerpo(tester);

      // Este va tocando el dibujo, que es el camino que la lista no cubre: un
      // músculo entrenado nunca sale entre los abandonados. El punto se calcula
      // con el mismo encaje que usa la pantalla, así que no depende del tamaño.
      await tester.ensureVisible(find.byKey(claveLienzo));
      await tester.pumpAndSettle();
      final caja = tester.getRect(find.byKey(claveLienzo));
      final encaje = Encaje.contener(
        destino: caja.size,
        lienzo: const Size(1000, 2000),
      );
      await tester.tapAt(
        caja.topLeft +
            encaje.desplazamiento +
            const Offset(590, 480) * encaje.escala,
      );
      await tester.pumpAndSettle();

      expect(find.text('Pecho'), findsWidgets);
      expect(find.text('TUS ENTRENAMIENTOS'), findsOneWidget);
      expect(find.text('Press banca'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('avisa de los ejercicios que no salen en el modelo', (
      tester,
    ) async {
      await bd.insertarEjercicio(idRutina, 'Remo con goma');
      final id = (await bd.ejerciciosDeRutina(idRutina)).first.id;
      await bd.insertarEntrenamiento(idRutina, DateTime(2026, 7, 30), {
        id: const [ValoresSerie(repeticiones: 12, peso: 10)],
      });
      await abrirCuerpo(tester);

      expect(find.textContaining('ejercicio personalizado'), findsOneWidget);
    });

    testWidgets('se pinta en claro y en oscuro', (tester) async {
      await entrenarPecho();
      for (final brillo in [Brightness.light, Brightness.dark]) {
        await abrirCuerpo(tester, brillo: brillo);
        expect(tester.takeException(), isNull, reason: '$brillo');
        expect(find.byType(MapaMuscular), findsOneWidget);
      }
    });

    testWidgets('los colores del mapa se resuelven contra el tema', (
      tester,
    ) async {
      // Montar en oscuro sin más solo demuestra que no revienta. Lo que hay que
      // fijar es que los colores salen del contexto: si alguien usara
      // `CupertinoColors` en crudo, el mapa se vería igual en los dos temas.
      Future<List<Color>> colores(Brightness brillo) async {
        late List<Color> vistos;
        await tester.pumpWidget(
          CupertinoApp(
            theme: CupertinoThemeData(brightness: brillo),
            home: Builder(
              builder: (context) {
                vistos = [
                  for (var n = 0; n < nivelesColor; n++) colorNivel(context, n),
                ];
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        return vistos;
      }

      final claro = await colores(Brightness.light);
      final oscuro = await colores(Brightness.dark);

      // El nivel 0 tiene que distinguirse del 4: es lo que responde a «¿qué no
      // estoy tocando?».
      expect(claro.first, isNot(claro.last));
      // Y el mismo nivel cambia con el tema.
      expect(claro.first, isNot(oscuro.first));
      expect(claro.last, isNot(oscuro.last));
    });

    testWidgets('el catálogo se abre filtrado por la región', (tester) async {
      _comoUnMovil(tester);
      await tester.pumpWidget(
        _app(bd, const PantallaCatalogo(region: Region.pectoral)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pecho'), findsWidgets);
      expect(find.text('barbell bench press'), findsOneWidget);
      // El curl de bíceps no es de pecho y no debe salir.
      expect(find.text('dumbbell curl'), findsNothing);
    });
  });

  // ── I7: la app en inglés ───────────────────────────────────────────────────

  /// El único grupo que monta en otro idioma.
  ///
  /// No se duplican las 300 aserciones en inglés: eso probaría a Flutter, no a
  /// la app. Se prueba lo que **de verdad** depende del idioma —una pantalla de
  /// cada tipo, los formatos, el vocabulario del catálogo y las plantillas—, que
  /// es donde puede quedarse una cadena sin traducir.
  group('la app en inglés', () {
    late int idRutina;

    Widget enIngles(Widget pantalla) =>
        _app(bd, pantalla, idioma: const Locale('en'));

    setUp(() async {
      await sembrarCatalogo(bd, datos: _catalogoFalso);
      idRutina = (await bd.insertarRutina('Push'))!;
      await bd.insertarEjercicio(idRutina, 'Bench press', idCatalogo: '0001');
    });

    testWidgets('la lista de rutinas', (tester) async {
      await tester.pumpWidget(enIngles(const PantallaRutinas()));
      await tester.pumpAndSettle();

      expect(find.text('Routines'), findsWidgets);
      // Sin entrenar, y con la frase inglesa: si la clave se hubiera quedado
      // sin traducir, aquí saldría «1 ejercicio · Sin entrenar».
      expect(find.text('1 exercise · Not trained yet'), findsOneWidget);
    });

    testWidgets('el registro de una sesión', (tester) async {
      _comoUnMovil(tester);
      await tester.pumpWidget(enIngles(PantallaEntrenar(idRutina: idRutina)));
      await tester.pumpAndSettle();

      expect(find.text('Log session'), findsOneWidget);
      expect(find.text('Add set'), findsOneWidget);
      expect(find.text('Save workout'), findsOneWidget);
      // La fecha, con el orden inglés y no con el español.
      expect(find.text(_en.fechaLarga(DateTime.now())), findsOneWidget);
    });

    testWidgets('el catálogo traduce las categorías, no los nombres', (
      tester,
    ) async {
      await tester.pumpWidget(enIngles(const PantallaCatalogo()));
      await tester.pumpAndSettle();

      expect(find.text('Exercises'), findsWidgets);
      // El nombre del ejercicio se queda en inglés siempre, que es como se
      // llama en el gimnasio.
      expect(find.text('barbell bench press'), findsOneWidget);
      // Y su categoría sí cambia: en español sería «Pectorales · Barra».
      expect(find.text('Pectorals · Barbell'), findsOneWidget);
    });

    testWidgets('el progreso y su resumen semanal', (tester) async {
      _comoUnMovil(tester);
      await tester.pumpWidget(enIngles(const PantallaProgreso()));
      await tester.pumpAndSettle();

      expect(find.text('Progress'), findsWidgets);
      expect(find.text('Summary'), findsOneWidget);
      expect(find.text('Calendar'), findsOneWidget);
      expect(find.text('Body'), findsOneWidget);
    });

    testWidgets('los ajustes, con el idioma en su propio idioma', (
      tester,
    ) async {
      _comoUnMovil(tester);
      await tester.pumpWidget(enIngles(const PantallaAjustes()));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsWidgets);
      expect(find.text('Weight unit'), findsOneWidget);

      // La fila del idioma está más abajo: en un móvil hay que bajar hasta ella.
      await tester.scrollUntilVisible(find.text('Language'), 300);
      await tester.pumpAndSettle();
      expect(find.text('Language'), findsOneWidget);
      // Los nombres de idioma no se traducen: cada uno va en el suyo.
      expect(find.text('Automatic'), findsOneWidget);
    });

    testWidgets('las medidas se llaman en inglés', (tester) async {
      _comoUnMovil(tester);
      await tester.pumpWidget(enIngles(const PantallaMedidas()));
      await tester.pumpAndSettle();

      expect(find.text('Bodyweight'), findsWidgets);
      expect(find.text('Waist'), findsOneWidget);
      expect(find.text('No Bodyweight records'), findsOneWidget);
    });

    testWidgets('el plural sale de la clave ICU', (tester) async {
      await bd.insertarEjercicio(idRutina, 'Row', idCatalogo: '0002');
      await tester.pumpWidget(enIngles(const PantallaRutinas()));
      await tester.pumpAndSettle();

      expect(find.textContaining('2 exercises'), findsOneWidget);
      expect(find.textContaining('1 exercise ·'), findsNothing);
    });

    testWidgets('cambiar de idioma con una sesión viva no la rompe', (
      tester,
    ) async {
      _comoUnMovil(tester);
      _RelojFalso().instalar();

      // Se monta la sesión viva en español y se repinta en inglés con el mismo
      // estado: el borrador es JSON con ids y números, así que el idioma no lo
      // toca.
      final vivo = PantallaEntrenar(idRutina: idRutina, modo: Modo.vivo);
      await tester.pumpWidget(_app(bd, vivo));
      await _asentar(tester);
      expect(find.text('Entrenando'), findsOneWidget);

      await tester.pumpWidget(_app(bd, vivo, idioma: const Locale('en')));
      await _asentar(tester);
      expect(find.text('Working out'), findsOneWidget);
      expect(find.text('Finish'), findsOneWidget);
    });
  });

  // ── Copia automática ───────────────────────────────────────────────────────

  group('copia automática', () {
    late AppBD bd;
    late NubeFalsa nube;

    /// La pantalla con una nube de mentira enchufada. Sin este `override` el
    /// grupo no se pinta, que es justamente lo que hace una compilación sin
    /// credenciales.
    Widget conNube(Widget pantalla, {Locale idioma = const Locale('es')}) =>
        _app(
          bd,
          pantalla,
          idioma: idioma,
          overrides: [nubeProvider.overrideWithValue(nube)],
        );

    setUp(() async {
      bd = AppBD(NativeDatabase.memory());
      nube = NubeFalsa();
      await bd.insertarRutina('Empuje');
    });

    tearDown(() async => bd.close());

    testWidgets('sin credenciales el grupo no aparece siquiera', (
      tester,
    ) async {
      _comoUnMovil(tester);
      // `_app` no sobrescribe `nubeProvider`, así que vale el de verdad, que
      // sin `--dart-define` es null.
      await tester.pumpWidget(_app(bd, const PantallaAjustes()));
      await tester.pumpAndSettle();

      // Y el grupo «Datos», que es su vecino, sigue estando: si el de la copia
      // se pintara, se toparía con él al bajar.
      await tester.scrollUntilVisible(find.text('DATOS'), 300);
      await tester.pumpAndSettle();
      expect(find.text('DATOS'), findsOneWidget);
      expect(find.text('COPIA AUTOMÁTICA'), findsNothing);
    });

    testWidgets('sin conectar ofrece conectar, y conectar copia', (
      tester,
    ) async {
      _comoUnMovil(tester);
      await tester.pumpWidget(conNube(const PantallaAjustes()));
      await tester.pumpAndSettle();

      final conectar = find.text('Conectar con Nube de prueba');
      await tester.scrollUntilVisible(conectar, 300);
      await tester.pumpAndSettle();

      await tester.tap(conectar);
      // Con `pumpAndSettle` no: mientras la copia sube hay un
      // `CupertinoActivityIndicator` girando, y esperar a que no queden
      // fotogramas no terminaría nunca. Es el mismo motivo que en la sesión
      // viva.
      await _asentar(tester, veces: 20);

      expect(nube.conexiones, 1);
      expect(nube.subidas, 1, reason: 'quien lo enciende quiere ver que va');
      expect(find.text('yo@ejemplo.com'), findsOneWidget);
      // Conectar sin frecuencia dejaría una cuenta que no copia nada.
      expect(find.text('Semanal'), findsOneWidget);
    });

    testWidgets('el grupo se llama «copia automática», nunca sincronizar', (
      tester,
    ) async {
      _comoUnMovil(tester);
      await tester.pumpWidget(conNube(const PantallaAjustes()));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('COPIA AUTOMÁTICA'), 300);
      await tester.pumpAndSettle();

      expect(find.text('COPIA AUTOMÁTICA'), findsOneWidget);
      expect(find.textContaining('incroniz'), findsNothing);
    });

    testWidgets('en inglés también', (tester) async {
      _comoUnMovil(tester);
      await tester.pumpWidget(
        conNube(const PantallaAjustes(), idioma: const Locale('en')),
      );
      await tester.pumpAndSettle();

      final cabecera = find.text('AUTOMATIC BACKUP');
      await tester.scrollUntilVisible(cabecera, 300);
      await tester.pumpAndSettle();
      expect(cabecera, findsOneWidget);
      expect(find.text('Connect to Nube de prueba'), findsOneWidget);
    });

    testWidgets('un fallo se cuenta al pie y no rompe la pantalla', (
      tester,
    ) async {
      _comoUnMovil(tester);
      nube.falloAlConectar = const ErrorNube.temporal('sin cobertura');
      await tester.pumpWidget(conNube(const PantallaAjustes()));
      await tester.pumpAndSettle();

      final conectar = find.text('Conectar con Nube de prueba');
      await tester.scrollUntilVisible(conectar, 300);
      await tester.pumpAndSettle();
      await tester.tap(conectar);
      await _asentar(tester, veces: 20);

      expect(find.text('sin cobertura'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('con la copia al día no hay aviso en Rutinas', (tester) async {
      _comoUnMovil(tester);
      await bd.fijarAjustes({
        Claves.copiaNubeCuenta: 'yo@ejemplo.com',
        Claves.copiaNubeFrecuencia: 'semanal',
        Claves.copiaNubeUltima: DateTime.now().toIso8601String(),
      });

      await tester.pumpWidget(conNube(const PantallaRutinas()));
      await tester.pumpAndSettle();

      expect(find.text('La copia automática no está al día'), findsNothing);
    });

    testWidgets('un fallo guardado sí saca el aviso', (tester) async {
      _comoUnMovil(tester);
      await bd.fijarAjustes({
        Claves.copiaNubeCuenta: 'yo@ejemplo.com',
        Claves.copiaNubeFrecuencia: 'semanal',
        Claves.copiaNubeError: 'sin cobertura',
      });

      await tester.pumpWidget(conNube(const PantallaRutinas()));
      await tester.pumpAndSettle();

      expect(find.text('La copia automática no está al día'), findsOneWidget);
    });

    testWidgets('el aviso lleva a Ajustes', (tester) async {
      _comoUnMovil(tester);
      await bd.fijarAjustes({
        Claves.copiaNubeCuenta: 'yo@ejemplo.com',
        Claves.copiaNubeFrecuencia: 'semanal',
        Claves.copiaNubeError: 'sin cobertura',
      });

      await tester.pumpWidget(conNube(const PantallaRutinas()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('La copia automática no está al día'));
      await tester.pumpAndSettle();
      expect(find.text('Ajustes'), findsWidgets);
    });
  });
  // ── La cuenta ──────────────────────────────────────────────────────────────

  group('cuenta', () {
    late AppBD bd;
    late SincroFalso servidor;

    /// La pantalla con un servidor de mentira enchufado. Sin este `override` el
    /// grupo no se pinta, que es justamente lo que hace una compilación sin
    /// credenciales.
    Widget conCuenta(Widget pantalla, {Locale idioma = const Locale('es')}) =>
        _app(
          bd,
          pantalla,
          idioma: idioma,
          overrides: [sincroProvider.overrideWithValue(servidor)],
        );

    /// El campo del diálogo que esté abierto.
    ///
    /// Acotado al diálogo a propósito: la pantalla de Ajustes tiene campos
    /// propios y `enterText` exige que el buscador encuentre **uno**.
    final campo = find.descendant(
      of: find.byType(CupertinoAlertDialog),
      matching: find.byType(CupertinoTextField),
    );

    /// Entra tecleando el correo y luego el código, que es el flujo entero.
    Future<void> entrar(WidgetTester tester, {String codigo = '123456'}) async {
      await tester.tap(find.text('Crear cuenta o entrar'));
      await tester.pumpAndSettle();
      await tester.enterText(campo, 'yo@ejemplo.com');
      await tester.tap(find.text('Continuar'));
      // `pumpAndSettle` y no fotogramas sueltos: mientras el primer diálogo se
      // va y el segundo llega, los dos están en el árbol y `campo` encontraría
      // dos. Aquí no hay nada girando, así que asienta.
      await tester.pumpAndSettle();

      await tester.enterText(campo, codigo);
      await tester.tap(find.text('Continuar'));
      // Al final sí van fotogramas sueltos: si algo falló, `ui.aviso` deja un
      // mensaje en pantalla que se retira solo a los 1,8 s, y asentar aquí lo
      // borraría antes de que ningún test pudiera comprobarlo.
      await _asentar(tester, veces: 20);
    }

    setUp(() async {
      bd = AppBD(NativeDatabase.memory());
      servidor = SincroFalso();
    });

    tearDown(() async => bd.close());

    testWidgets('sin credenciales el grupo no aparece siquiera', (
      tester,
    ) async {
      _comoUnMovil(tester);
      // `_app` no sobrescribe `sincroProvider`, así que vale el de verdad, que
      // sin `--dart-define` es null. Es el criterio de K12.
      await tester.pumpWidget(_app(bd, const PantallaAjustes()));
      await tester.pumpAndSettle();

      // Y el grupo «Datos», que es su vecino de más abajo, sigue estando: si el
      // de la cuenta se pintara, se toparía con él al bajar.
      await tester.scrollUntilVisible(find.text('DATOS'), 300);
      await tester.pumpAndSettle();
      expect(find.text('DATOS'), findsOneWidget);
      expect(find.text('CUENTA'), findsNothing);
    });

    testWidgets('sin cuenta ofrece entrar, y entrar la conecta', (
      tester,
    ) async {
      _comoUnMovil(tester);
      await tester.pumpWidget(conCuenta(const PantallaAjustes()));
      await tester.pumpAndSettle();

      final entrarFila = find.text('Crear cuenta o entrar');
      await tester.scrollUntilVisible(entrarFila, 300);
      await tester.pumpAndSettle();

      await entrar(tester);

      expect(servidor.codigosPedidos, ['yo@ejemplo.com']);
      expect(find.text('yo@ejemplo.com'), findsOneWidget);
      expect(find.text('Sincronizar ahora'), findsOneWidget);
    });

    testWidgets('un código que no vale se dice y no conecta', (tester) async {
      _comoUnMovil(tester);
      await tester.pumpWidget(conCuenta(const PantallaAjustes()));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Crear cuenta o entrar'), 300);
      await tester.pumpAndSettle();

      await entrar(tester, codigo: '000000');

      // El mensaje del servidor se enseña tal cual.
      expect(find.text('El código no vale o ha caducado.'), findsOneWidget);
      expect(find.text('Crear cuenta o entrar'), findsOneWidget);

      // `ui.aviso` se retira solo con un `Future.delayed`, y el test no puede
      // acabar con ese `Timer` vivo. No es un fallo de la app: es la contra de
      // haber comprobado el mensaje mientras estaba en pantalla.
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('con datos a los dos lados se pregunta, con las cifras', (
      tester,
    ) async {
      _comoUnMovil(tester);
      // Aquí una rutina; en la cuenta, otra.
      await bd.insertarRutina('Empuje');
      servidor.filas['rutinas/otra'] = const FilaRemota(
        tabla: 'rutinas',
        clave: 'otra',
        actualizado: 1000001,
        datos: {'nombre': 'Tirón'},
      );

      await tester.pumpWidget(conCuenta(const PantallaAjustes()));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Crear cuenta o entrar'), 300);
      await tester.pumpAndSettle();

      await entrar(tester);

      // Sin los números delante, la pregunta no se puede responder.
      expect(find.textContaining('1 rutina'), findsWidgets);
      expect(find.text('Juntarlo todo (recomendado)'), findsOneWidget);
    });

    testWidgets('borrar la cuenta pide escribir el correo', (tester) async {
      _comoUnMovil(tester);
      await tester.pumpWidget(conCuenta(const PantallaAjustes()));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Crear cuenta o entrar'), 300);
      await tester.pumpAndSettle();
      await entrar(tester);
      // Que el diálogo del código termine de irse: si no, al abrir el de borrar
      // habría dos en el árbol y `campo` encontraría dos.
      await tester.pumpAndSettle();

      final borrar = find.text('Borrar la cuenta');
      await tester.scrollUntilVisible(borrar, 300);
      await tester.pumpAndSettle();
      await tester.tap(borrar);
      await tester.pumpAndSettle();

      // Escrito mal, no se borra nada.
      await tester.enterText(campo, 'otro@sitio.com');
      await tester.tap(find.text('Borrar la cuenta').last);
      await _asentar(tester, veces: 20);

      expect(
        find.text('El correo no coincide. No se ha borrado nada.'),
        findsOneWidget,
      );
      expect(find.text('yo@ejemplo.com'), findsWidgets);

      // El aviso se retira solo con un `Future.delayed`, y el test no puede
      // acabar con ese `Timer` vivo.
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('el detalle lista los avisos con su frase', (tester) async {
      _comoUnMovil(tester);
      await bd.fijarEstadoSincro(
        subidas: const Value(3),
        bajadas: const Value(1),
        avisos: Value(
          jsonEncode([
            AvisoSincro(
              MotivoAviso.rutinaRenombrada,
              'Empuje (2)',
              DateTime(2026, 8, 10),
            ).aJson(),
          ]),
        ),
      );

      await tester.pumpWidget(conCuenta(const PantallaSincroDetalle()));
      await tester.pumpAndSettle();

      expect(find.text('3 cambios'), findsOneWidget);
      expect(find.text('1 cambio'), findsOneWidget);
      expect(
        find.textContaining('Empuje (2)'),
        findsOneWidget,
        reason: 'el motivo viaja como enumerado y la frase se compone aquí',
      );
    });

    testWidgets('en inglés el grupo se llama ACCOUNT', (tester) async {
      _comoUnMovil(tester);
      await tester.pumpWidget(
        conCuenta(const PantallaAjustes(), idioma: const Locale('en')),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('ACCOUNT'), 300);
      await tester.pumpAndSettle();
      expect(find.text('Create account or sign in'), findsOneWidget);
    });

    testWidgets('el aviso de la cabecera lleva a Ajustes', (tester) async {
      await bd.fijarAjustes({Claves.sincroActiva: '1'});
      await bd.fijarEstadoSincro(ultimoError: const Value('sin cobertura'));
      await servidor.entrar('yo@ejemplo.com', servidor.codigo);

      await tester.pumpWidget(conCuenta(const PantallaRutinas()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('La sincronización no está al día'));
      await tester.pumpAndSettle();
      expect(find.text('Ajustes'), findsWidgets);
    });
  });
}
