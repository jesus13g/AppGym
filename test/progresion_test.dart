/// Tests de `datos/progresion.dart`.
///
/// Todo lo de ese módulo son funciones puras, así que aquí no se monta ninguna
/// base de datos ni ninguna pantalla: se le pasan historiales escritos a mano,
/// con fechas clavadas, y se comprueba qué propone.
library;

import 'package:appgym/datos/ajustes.dart';
import 'package:appgym/datos/bd.dart';
import 'package:appgym/datos/progresion.dart';
import 'package:flutter_test/flutter_test.dart';

/// Una sesión del historial, con las cifras que la consulta ya agrega.
///
/// [repeticiones] y [nSeries] son las que de verdad importan aquí: de su
/// cociente sale si la sesión completó el rango.
ResumenSesionEjercicio _sesion({
  required int id,
  required DateTime fecha,
  required double pesoMaximo,
  int nSeries = 4,
  int repeticiones = 40,
  double? volumen,
}) => ResumenSesionEjercicio(
  idEntrenamiento: id,
  fecha: fecha,
  nSeries: nSeries,
  repeticiones: repeticiones,
  volumen: volumen ?? pesoMaximo * repeticiones,
  pesoMaximo: pesoMaximo,
  mejor1RM: pesoMaximo * 1.3,
  mejor1RMFiable: pesoMaximo * 1.3,
);

/// N series iguales, que es como se entrena de verdad la mayoría de las veces.
List<ValoresSerie> _series(
  int cuantas, {
  required int repeticiones,
  required double peso,
  double? rpe,
}) => [
  for (var i = 0; i < cuantas; i++)
    ValoresSerie(repeticiones: repeticiones, peso: peso, rpe: rpe),
];

/// Un ejercicio de rutina con su configuración propia.
EjercicioConFicha _ejercicio({
  int id = 1,
  int? repMin,
  int? repMax,
  double? incrementoKg,
  int? estrategia,
  FichaCatalogo? ficha,
}) => EjercicioConFicha(
  Ejercicio(
    id: id,
    idRutina: 1,
    nombre: 'Barbell Bench Press',
    orden: 0,
    uuid: 'ejercicio-$id',
    actualizado: 0,
    repMin: repMin,
    repMax: repMax,
    incrementoKg: incrementoKg,
    estrategia: estrategia,
  ),
  ficha,
);

FichaCatalogo _ficha({
  String bodyPart = 'chest',
  String target = 'pectorals',
}) => FichaCatalogo(
  id: '0001',
  nombre: 'Barbell Bench Press',
  bodyPart: bodyPart,
  equipment: 'barbell',
  target: target,
  muscleGroup: 'chest',
  secondaryMuscles: '[]',
  instrucciones: '[]',
  image: 'a.png',
  gif: 'a.gif',
  busqueda: 'barbell bench press',
);

/// Dos sesiones sin nada raro: lo mínimo para que haya sugerencia.
List<ResumenSesionEjercicio> _dosSesiones({double peso = 60}) => [
  _sesion(
    id: 1,
    fecha: DateTime(2026, 3, 1),
    pesoMaximo: peso,
    repeticiones: 36,
  ),
  _sesion(
    id: 2,
    fecha: DateTime(2026, 3, 8),
    pesoMaximo: peso,
    repeticiones: 40,
  ),
];

void main() {
  group('doble progresión', () {
    test('con el rango completo sube el peso un escalón y vuelve al suelo', () {
      final sugerencia = sugerir(
        _dosSesiones(),
        _series(4, repeticiones: 12, peso: 60),
        const ConfiguracionProgresion(),
      )!;

      expect(sugerencia.tipo, TipoSugerencia.subirPeso);
      expect(sugerencia.motivo, MotivoSugerencia.rangoCompletado);
      expect(sugerencia.deltaPeso, closeTo(2.5, 1e-9));
      expect(sugerencia.series, hasLength(4));
      expect(sugerencia.series.every((s) => s.peso == 62.5), isTrue);
      expect(sugerencia.series.every((s) => s.repeticiones == 8), isTrue);
    });

    test('con el rango incompleto mantiene el peso y suma una repetición', () {
      final sugerencia = sugerir(_dosSesiones(), [
        const ValoresSerie(repeticiones: 12, peso: 60),
        const ValoresSerie(repeticiones: 10, peso: 60),
        const ValoresSerie(repeticiones: 9, peso: 60),
      ], const ConfiguracionProgresion())!;

      expect(sugerencia.tipo, TipoSugerencia.subirRepeticiones);
      expect(sugerencia.motivo, MotivoSugerencia.rangoIncompleto);
      expect(sugerencia.deltaPeso, 0);
      // La primera que no llegó al tope, no todas: subir una repetición en cada
      // serie a la vez es un salto que nadie da.
      expect(sugerencia.series.map((s) => s.repeticiones), [12, 11, 9]);
      expect(sugerencia.series.every((s) => s.peso == 60), isTrue);
    });

    test('con las repeticiones por debajo del suelo baja el peso', () {
      final sugerencia = sugerir(
        _dosSesiones(),
        _series(4, repeticiones: 6, peso: 60),
        const ConfiguracionProgresion(),
      )!;

      expect(sugerencia.tipo, TipoSugerencia.bajarPeso);
      expect(sugerencia.motivo, MotivoSugerencia.repeticionesCaidas);
      expect(sugerencia.deltaPeso, closeTo(-2.5, 1e-9));
      expect(sugerencia.series.every((s) => s.peso == 57.5), isTrue);
    });

    test('una sola serie floja no basta para bajar el peso', () {
      // Tres series buenas y una mala son un mal día, no una carga excesiva.
      final sugerencia = sugerir(_dosSesiones(), [
        const ValoresSerie(repeticiones: 11, peso: 60),
        const ValoresSerie(repeticiones: 10, peso: 60),
        const ValoresSerie(repeticiones: 9, peso: 60),
        const ValoresSerie(repeticiones: 5, peso: 60),
      ], const ConfiguracionProgresion())!;

      expect(sugerencia.tipo, TipoSugerencia.subirRepeticiones);
    });

    test('el calentamiento no cuenta para decidir', () {
      final sugerencia = sugerir(_dosSesiones(), [
        const ValoresSerie(repeticiones: 20, peso: 20, calentamiento: true),
        const ValoresSerie(repeticiones: 12, peso: 60),
        const ValoresSerie(repeticiones: 12, peso: 60),
      ], const ConfiguracionProgresion())!;

      // Si el calentamiento contara, sus 20 repeticiones a 20 kg habrían
      // arrastrado el peso base y el rango.
      expect(sugerencia.tipo, TipoSugerencia.subirPeso);
      expect(sugerencia.series, hasLength(2));
      expect(sugerencia.series.every((s) => s.peso == 62.5), isTrue);
    });
  });

  group('cuándo no hay nada que decir', () {
    test('con menos de dos sesiones no se sugiere nada', () {
      expect(
        sugerir(
          [_sesion(id: 1, fecha: DateTime(2026, 3, 1), pesoMaximo: 60)],
          _series(4, repeticiones: 12, peso: 60),
          const ConfiguracionProgresion(),
        ),
        isNull,
      );
      expect(
        sugerir(
          const [],
          _series(4, repeticiones: 12, peso: 60),
          const ConfiguracionProgresion(),
        ),
        isNull,
      );
    });

    test('el cardio no recibe sugerencia, ni por bodyPart ni por target', () {
      for (final ficha in [
        _ficha(bodyPart: 'cardio', target: 'quads'),
        _ficha(bodyPart: 'chest', target: 'cardiovascular system'),
      ]) {
        final config = ConfiguracionProgresion.resolver(
          _ejercicio(ficha: ficha),
          const Ajustes(),
        );
        expect(config.estrategia, Estrategia.desactivada);
        expect(
          sugerir(
            _dosSesiones(),
            _series(4, repeticiones: 12, peso: 60),
            config,
          ),
          isNull,
        );
      }
    });

    test('con la estrategia desactivada tampoco', () {
      final config = ConfiguracionProgresion.resolver(
        _ejercicio(estrategia: Estrategia.desactivada.index),
        const Ajustes(),
      );
      expect(
        sugerir(_dosSesiones(), _series(4, repeticiones: 12, peso: 60), config),
        isNull,
      );
    });

    test('con la progresión global apagada no hay sugerencia', () {
      final config = ConfiguracionProgresion.resolver(
        _ejercicio(),
        const Ajustes(progresionActiva: false),
      );
      expect(config.estrategia, Estrategia.desactivada);
    });

    test('un ejercicio con estrategia propia ignora el interruptor global', () {
      // Apagar la progresión en Ajustes no debe borrar lo que el usuario
      // configuró a mano en un ejercicio concreto; lo que hace la pantalla es no
      // pedir la sugerencia.
      final config = ConfiguracionProgresion.resolver(
        _ejercicio(estrategia: Estrategia.dobleProgresion.index),
        const Ajustes(progresionActiva: false),
      );
      expect(config.estrategia, Estrategia.dobleProgresion);
    });
  });

  group('esfuerzo', () {
    test('con RPE 9,5 se mantiene aunque el rango esté completo', () {
      final sugerencia = sugerir(
        _dosSesiones(),
        _series(4, repeticiones: 12, peso: 60, rpe: 9.5),
        const ConfiguracionProgresion(esfuerzoActivo: true),
      )!;

      expect(sugerencia.tipo, TipoSugerencia.mantener);
      expect(sugerencia.motivo, MotivoSugerencia.esfuerzoAlto);
      expect(sugerencia.deltaPeso, 0);
    });

    test('con el esfuerzo desactivado el mismo caso sí sube', () {
      // Es la garantía de que el modelo no depende de una preferencia que está
      // apagada de fábrica: sin RPE, funciona solo con repeticiones.
      final sugerencia = sugerir(
        _dosSesiones(),
        _series(4, repeticiones: 12, peso: 60, rpe: 9.5),
        const ConfiguracionProgresion(),
      )!;

      expect(sugerencia.tipo, TipoSugerencia.subirPeso);
    });

    test('el perfil agresivo sube dos escalones con el esfuerzo bajo', () {
      final sugerencia = sugerir(
        _dosSesiones(),
        _series(4, repeticiones: 12, peso: 60, rpe: 6.5),
        const ConfiguracionProgresion(
          esfuerzoActivo: true,
          perfil: Perfil.agresivo,
        ),
      )!;

      expect(sugerencia.tipo, TipoSugerencia.subirPeso);
      expect(sugerencia.motivo, MotivoSugerencia.esfuerzoBajo);
      expect(sugerencia.deltaPeso, closeTo(5, 1e-9));
    });

    test('el perfil estándar sube uno solo con ese mismo esfuerzo', () {
      final sugerencia = sugerir(
        _dosSesiones(),
        _series(4, repeticiones: 12, peso: 60, rpe: 6.5),
        const ConfiguracionProgresion(esfuerzoActivo: true),
      )!;

      expect(sugerencia.deltaPeso, closeTo(2.5, 1e-9));
    });

    test('el conservador espera a completar el rango dos veces', () {
      const config = ConfiguracionProgresion(perfil: Perfil.conservador);

      // La sesión anterior no llegó al tope: se mantiene.
      final espera = sugerir(
        _dosSesiones(),
        _series(4, repeticiones: 12, peso: 60),
        config,
      )!;
      expect(espera.tipo, TipoSugerencia.mantener);

      // Con la anterior también al tope (4 × 12 = 48), ya sube.
      final sube = sugerir(
        [
          _sesion(
            id: 1,
            fecha: DateTime(2026, 3, 1),
            pesoMaximo: 60,
            repeticiones: 48,
          ),
          _sesion(
            id: 2,
            fecha: DateTime(2026, 3, 8),
            pesoMaximo: 60,
            repeticiones: 48,
          ),
        ],
        _series(4, repeticiones: 12, peso: 60),
        config,
      )!;
      expect(sube.tipo, TipoSugerencia.subirPeso);
    });

    test('el esfuerzo activo y sin registrar marca la sugerencia', () {
      // Con tres sesiones el historial ya da, así que lo que la marca es que se
      // pida el esfuerzo y no esté anotado.
      final historial = [
        for (var i = 0; i < 3; i++)
          _sesion(
            id: i + 1,
            fecha: DateTime(2026, 3, 1 + i * 7),
            pesoMaximo: 60,
            repeticiones: 40 + i,
          ),
      ];

      expect(
        sugerir(
          historial,
          _series(4, repeticiones: 10, peso: 60),
          const ConfiguracionProgresion(esfuerzoActivo: true),
        )!.fiable,
        isFalse,
      );

      // Y no usar el RPE en absoluto no resta: el modelo va sin él.
      expect(
        sugerir(
          historial,
          _series(4, repeticiones: 10, peso: 60),
          const ConfiguracionProgresion(),
        )!.fiable,
        isTrue,
      );
    });

    test('con dos sesiones la sugerencia se da, pero marcada', () {
      expect(
        sugerir(
          _dosSesiones(),
          _series(4, repeticiones: 10, peso: 60),
          const ConfiguracionProgresion(),
        )!.fiable,
        isFalse,
      );
    });

    test('la sugerencia no arrastra el RPE de la sesión anterior', () {
      final sugerencia = sugerir(
        _dosSesiones(),
        _series(4, repeticiones: 10, peso: 60, rpe: 8),
        const ConfiguracionProgresion(esfuerzoActivo: true),
      )!;

      expect(sugerencia.series.every((s) => s.rpe == null), isTrue);
    });
  });

  group('peso corporal', () {
    test(
      'sin peso en todo el historial la progresión es solo repeticiones',
      () {
        final historial = [
          _sesion(id: 1, fecha: DateTime(2026, 3, 1), pesoMaximo: 0),
          _sesion(id: 2, fecha: DateTime(2026, 3, 8), pesoMaximo: 0),
        ];
        final ultimas = _series(3, repeticiones: 8, peso: 0);

        expect(esDePesoCorporal(historial, ultimas), isTrue);

        final config = ConfiguracionProgresion.resolver(
          _ejercicio(),
          const Ajustes(),
          pesoCorporal: true,
        );
        expect(config.estrategia, Estrategia.soloRepeticiones);
        // El rango se amplía: con 8-12 y sin escalón, la sugerencia se quedaría
        // sin salida a la tercera sesión.
        expect(config.repMin, 5);
        expect(config.repMax, 15);

        final sugerencia = sugerir(historial, ultimas, config)!;
        expect(sugerencia.tipo, TipoSugerencia.subirRepeticiones);
        expect(sugerencia.deltaPeso, 0);
        expect(sugerencia.series.every((s) => s.peso == 0), isTrue);
      },
    );

    test('unas dominadas lastradas ya no son peso corporal', () {
      final historial = [
        _sesion(id: 1, fecha: DateTime(2026, 3, 1), pesoMaximo: 0),
        _sesion(id: 2, fecha: DateTime(2026, 3, 8), pesoMaximo: 5),
      ];
      expect(
        esDePesoCorporal(historial, _series(3, repeticiones: 8, peso: 5)),
        isFalse,
      );
    });

    test('completar el rango sin peso que subir no propone un salto', () {
      final historial = [
        _sesion(id: 1, fecha: DateTime(2026, 3, 1), pesoMaximo: 0),
        _sesion(id: 2, fecha: DateTime(2026, 3, 8), pesoMaximo: 0),
      ];
      final sugerencia = sugerir(
        historial,
        _series(3, repeticiones: 15, peso: 0),
        const ConfiguracionProgresion(
          repMin: 5,
          repMax: 15,
          estrategia: Estrategia.soloRepeticiones,
        ),
      )!;

      expect(sugerencia.tipo, TipoSugerencia.mantener);
      expect(sugerencia.deltaPeso, 0);
    });

    test('«peso efectivo mínimo de 1 kg» no se aplica aquí', () {
      // Es un truco exclusivo del mapa muscular. Aplicado a una sugerencia
      // diría «sube de 1 a 3,5 kg» en unas dominadas, que es absurdo.
      final sugerencia = sugerir(
        [
          _sesion(id: 1, fecha: DateTime(2026, 3, 1), pesoMaximo: 0),
          _sesion(id: 2, fecha: DateTime(2026, 3, 8), pesoMaximo: 0),
        ],
        _series(3, repeticiones: 8, peso: 0),
        const ConfiguracionProgresion(estrategia: Estrategia.soloRepeticiones),
      )!;

      expect(sugerencia.series.every((s) => s.peso == 0), isTrue);
    });
  });

  group('el escalón de peso', () {
    test('el peso sugerido es múltiplo del escalón', () {
      for (final paso in pasosPeso) {
        final sugerencia = sugerir(
          _dosSesiones(peso: 61.3),
          _series(4, repeticiones: 12, peso: 61.3),
          ConfiguracionProgresion(incrementoKg: paso),
        )!;
        final pasos = sugerencia.peso / paso;
        expect(
          pasos,
          closeTo(pasos.roundToDouble(), 1e-9),
          reason: 'con escalón $paso el peso sugerido no cuadra',
        );
      }
    });

    test('en libras el peso sale redondo en libras, no en kilos', () {
      const ajustes = Ajustes(unidad: Unidad.lb, pasoPeso: 5);
      final config = ConfiguracionProgresion.resolver(_ejercicio(), ajustes);

      // El escalón guardado es kilos, pero sale de un paso en libras.
      expect(config.incrementoKg, closeTo(5 / factorLibras, 1e-9));

      final sugerencia = sugerir(
        _dosSesiones(peso: ajustes.aKilos(135)),
        _series(4, repeticiones: 12, peso: ajustes.aKilos(135)),
        config,
      )!;

      final enLibras = ajustes.desdeKilos(sugerencia.peso);
      expect(enLibras, closeTo(140, 1e-6));
      // Y el selector de peso lo puede enseñar tal cual.
      expect(ajustes.paraSelector(sugerencia.peso), closeTo(140, 1e-6));
    });

    test('el escalón propio del ejercicio gana al global', () {
      final config = ConfiguracionProgresion.resolver(
        _ejercicio(incrementoKg: 1.25),
        const Ajustes(pasoPeso: 5),
      );
      expect(config.incrementoKg, 1.25);
    });

    test('bajar nunca cruza el cero', () {
      expect(redondearAEscalon(-3, 2.5), 0);
      expect(redondearAEscalon(1, 2.5), 0);
    });
  });

  group('estancamiento y descarga', () {
    /// Tres sesiones idénticas: ni peso, ni repeticiones, ni volumen mejoran.
    List<ResumenSesionEjercicio> estancado() => [
      _sesion(
        id: 1,
        fecha: DateTime(2026, 3, 1),
        pesoMaximo: 60,
        repeticiones: 48,
      ),
      _sesion(
        id: 2,
        fecha: DateTime(2026, 3, 8),
        pesoMaximo: 70,
        repeticiones: 36,
      ),
      _sesion(
        id: 3,
        fecha: DateTime(2026, 3, 15),
        pesoMaximo: 70,
        repeticiones: 36,
      ),
      _sesion(
        id: 4,
        fecha: DateTime(2026, 3, 22),
        pesoMaximo: 70,
        repeticiones: 36,
      ),
      _sesion(
        id: 5,
        fecha: DateTime(2026, 3, 29),
        pesoMaximo: 70,
        repeticiones: 36,
      ),
    ];

    test('tres sesiones sin mejorar dan una descarga', () {
      final sugerencia = sugerir(
        estancado(),
        _series(4, repeticiones: 9, peso: 70),
        const ConfiguracionProgresion(),
      )!;

      expect(sugerencia.tipo, TipoSugerencia.descarga);
      expect(sugerencia.motivo, MotivoSugerencia.descargaSugerida);
      // La primera sesión completó el rango (48 = 4 × 12) a 60 kg: ahí se vuelve.
      expect(sugerencia.peso, 60);
      expect(sugerencia.deltaPeso, closeTo(-10, 1e-9));
      expect(sugerencia.series.every((s) => s.repeticiones == 8), isTrue);
    });

    test(
      'sin una sesión que completara el rango, la descarga baja un 10 %',
      () {
        final historial = [
          for (var i = 0; i < 4; i++)
            _sesion(
              id: i + 1,
              fecha: DateTime(2026, 3, 1 + i * 7),
              pesoMaximo: 100,
              repeticiones: 36,
            ),
        ];

        final sugerencia = sugerir(
          historial,
          _series(4, repeticiones: 9, peso: 100),
          const ConfiguracionProgresion(),
        )!;

        expect(sugerencia.tipo, TipoSugerencia.descarga);
        // 90 kg redondeado al escalón hacia abajo: 36 pasos de 2,5.
        expect(sugerencia.peso, closeTo(90, 1e-9));
      },
    );

    test(
      'la descarga se sugiere una vez; ignorarla vuelve a la regla normal',
      () {
        final sugerencia = sugerir(
          estancado(),
          _series(4, repeticiones: 9, peso: 70),
          const ConfiguracionProgresion(),
          descargaYaSugerida: true,
        )!;

        expect(sugerencia.tipo, TipoSugerencia.subirRepeticiones);
      },
    );

    test('mejorar el volumen rompe el estancamiento', () {
      final historial = estancado();
      // Misma carga y mismas repeticiones, pero más volumen en la última.
      historial[historial.length - 1] = _sesion(
        id: 5,
        fecha: DateTime(2026, 3, 29),
        pesoMaximo: 70,
        repeticiones: 36,
        volumen: 99999,
      );

      expect(sesionesSinMejorar(historial), 0);
      expect(
        sugerir(
          historial,
          _series(4, repeticiones: 9, peso: 70),
          const ConfiguracionProgresion(),
        )!.tipo,
        TipoSugerencia.subirRepeticiones,
      );
    });

    test(
      'estancados ordena por sesiones sin mejorar y descarta a los demás',
      () {
        final lista = estancados([
          SesionesDeEjercicio(
            idRutina: 1,
            idEjercicio: 10,
            nombre: 'Press banca',
            sesiones: estancado(),
          ),
          SesionesDeEjercicio(
            idRutina: 1,
            idEjercicio: 11,
            nombre: 'Sentadilla',
            sesiones: _dosSesiones(),
          ),
        ]);

        expect(lista, hasLength(1));
        expect(lista.single.nombre, 'Press banca');
        expect(lista.single.idEjercicio, 10);
        expect(lista.single.sesionesSinMejorar, 3);
        expect(lista.single.ultimaFecha, DateTime(2026, 3, 29));
      },
    );
  });

  group('el rango que se hace de verdad', () {
    test('tres sesiones de 5×5 proponen bajar el rango a 3–5', () {
      final historial = [
        for (var i = 0; i < 3; i++)
          _sesion(
            id: i + 1,
            fecha: DateTime(2026, 3, 1 + i * 7),
            pesoMaximo: 100,
            nSeries: 5,
            repeticiones: 25,
          ),
      ];

      expect(rangoObservado(historial, const ConfiguracionProgresion()), (
        3,
        5,
      ));
    });

    test('quien hace 8–12 de verdad no recibe ninguna propuesta', () {
      final historial = [
        for (var i = 0; i < 3; i++)
          _sesion(
            id: i + 1,
            fecha: DateTime(2026, 3, 1 + i * 7),
            pesoMaximo: 60,
            nSeries: 4,
            repeticiones: 40,
          ),
      ];

      expect(
        rangoObservado(historial, const ConfiguracionProgresion()),
        isNull,
      );
    });

    test('con menos de tres sesiones no se propone nada', () {
      expect(
        rangoObservado(_dosSesiones(), const ConfiguracionProgresion()),
        isNull,
      );
    });
  });

  group('la configuración se resuelve por capas', () {
    test('sin nada propio manda el global', () {
      final config = ConfiguracionProgresion.resolver(
        _ejercicio(),
        const Ajustes(repMinGlobal: 6, repMaxGlobal: 10, pasoPeso: 1.25),
      );

      expect(config.repMin, 6);
      expect(config.repMax, 10);
      expect(config.incrementoKg, 1.25);
      expect(config.estrategia, Estrategia.dobleProgresion);
    });

    test('lo propio del ejercicio gana al global', () {
      final config = ConfiguracionProgresion.resolver(
        _ejercicio(repMin: 3, repMax: 5),
        const Ajustes(repMinGlobal: 8, repMaxGlobal: 12),
      );

      expect(config.repMin, 3);
      expect(config.repMax, 5);
    });

    test('un rango invertido se endereza en vez de romper la sugerencia', () {
      final config = ConfiguracionProgresion.resolver(
        _ejercicio(repMin: 12, repMax: 8),
        const Ajustes(),
      );

      expect(config.repMin, 12);
      expect(config.repMax, 12);
    });

    test('el perfil sale de los ajustes', () {
      final config = ConfiguracionProgresion.resolver(
        _ejercicio(),
        const Ajustes(perfilProgresion: Perfil.agresivo),
      );

      expect(config.perfil, Perfil.agresivo);
    });
  });
}
