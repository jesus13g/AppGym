/// Tests de las métricas de progreso.
///
/// Todo lo de `metricas.dart` son funciones puras, así que aquí no se monta
/// ninguna base de datos ni ninguna pantalla: se les pasan los datos a mano y
/// se comprueba lo que devuelven. Es lo que permite fijar la racha con fechas
/// clavadas en vez de depender de cuándo se ejecute la suite.
library;

import 'package:appgym/datos/bd.dart';
import 'package:appgym/datos/metricas.dart';
import 'package:flutter_test/flutter_test.dart';

/// Una sesión del histórico de un ejercicio, con lo justo para las pruebas.
ResumenSesionEjercicio _sesion({
  required int id,
  required DateTime fecha,
  required double pesoMaximo,
  required double volumen,
  required double mejor1RM,
  double? mejor1RMFiable,
  int nSeries = 3,
}) => ResumenSesionEjercicio(
  idEntrenamiento: id,
  fecha: fecha,
  nSeries: nSeries,
  volumen: volumen,
  pesoMaximo: pesoMaximo,
  mejor1RM: mejor1RM,
  mejor1RMFiable: mejor1RMFiable,
);

SesionConVolumen _dia(DateTime fecha, {double volumen = 1000, int id = 1}) =>
    SesionConVolumen(id: id, idRutina: 1, fecha: fecha, volumen: volumen);

void main() {
  group('1RM estimado', () {
    test('una sola repetición es el peso, sin estimar nada', () {
      // La fórmula cruda de Epley daría 103,33 y eso sería absurdo: levantar
      // 100 kg una vez ya es un máximo de 100 kg.
      expect(unoRm(100, 1), 100);
      expect(unoRm(100, 1, formula: Formula.brzycki), 100);
      // Cero repeticiones no debería llegar aquí, pero tampoco puede reventar.
      expect(unoRm(100, 0), 100);
    });

    test('Epley: 10 × 60 kg estima 80', () {
      expect(unoRm(60, 10), closeTo(80, 1e-9));
      expect(unoRm(60, 12), closeTo(84, 1e-9));
    });

    test('Brzycki estima algo distinto en series largas', () {
      // 60 × 36 / (37 − 10) = 80: con diez repeticiones coinciden.
      expect(unoRm(60, 10, formula: Formula.brzycki), closeTo(80, 1e-9));
      // Con doce se separan: Epley 84, Brzycki 86,4.
      expect(unoRm(60, 12, formula: Formula.brzycki), closeTo(86.4, 1e-9));
    });

    test('Brzycki no divide por cero con series interminables', () {
      // Su denominador es 37 − repeticiones. Sin el tope, 37 reventaría y 40
      // devolvería un negativo.
      expect(unoRm(40, 37, formula: Formula.brzycki), isPositive);
      expect(unoRm(40, 40, formula: Formula.brzycki), isPositive);
      expect(
        unoRm(40, 40, formula: Formula.brzycki),
        unoRm(40, 36, formula: Formula.brzycki),
      );
    });

    test('doce repeticiones son de fiar; trece ya no', () {
      expect(esFiable(12), isTrue);
      expect(esFiable(13), isFalse);
      expect(maxRepeticionesFiables, 12);
    });
  });

  group('volumen y mejor serie', () {
    test('el calentamiento no suma volumen', () {
      const series = [
        ValoresSerie(repeticiones: 10, peso: 20, calentamiento: true),
        ValoresSerie(repeticiones: 10, peso: 60),
        ValoresSerie(repeticiones: 8, peso: 65),
      ];
      expect(volumen(series), 600 + 520);
    });

    test('la mejor serie no es siempre la más pesada', () {
      const series = [
        ValoresSerie(repeticiones: 1, peso: 80),
        ValoresSerie(repeticiones: 5, peso: 75),
      ];
      // 5 × 75 estima 87,5; 1 × 80 se queda en 80.
      expect(mejorSerie(series)!.peso, 75);
    });

    test('sin series efectivas no hay mejor serie', () {
      expect(
        mejorSerie(const [
          ValoresSerie(repeticiones: 10, peso: 20, calentamiento: true),
        ]),
        isNull,
      );
      expect(mejorSerie(const []), isNull);
    });
  });

  group('récords de un ejercicio', () {
    final historico = [
      _sesion(
        id: 1,
        fecha: DateTime(2026, 3, 1),
        pesoMaximo: 60,
        volumen: 600,
        mejor1RM: 80,
        mejor1RMFiable: 80,
      ),
      _sesion(
        id: 2,
        fecha: DateTime(2026, 3, 8),
        pesoMaximo: 65,
        volumen: 520,
        mejor1RM: 82.3,
        mejor1RMFiable: 82.3,
      ),
      _sesion(
        id: 3,
        fecha: DateTime(2026, 3, 15),
        pesoMaximo: 62.5,
        volumen: 750,
        mejor1RM: 81,
        mejor1RMFiable: 81,
      ),
    ];

    test('los tres récords salen de sesiones distintas', () {
      final records = recordsEjercicio(historico);
      expect(records.pesoMaximo, 65);
      expect(records.mejor1RM, closeTo(82.3, 1e-9));
      expect(records.volumenMaximo, 750);
      expect(records.volumenTotal, 600 + 520 + 750);
    });

    test('una serie larga no genera récord de 1RM', () {
      final conSerieLarga = [
        _sesion(
          id: 1,
          fecha: DateTime(2026, 3, 1),
          pesoMaximo: 40,
          volumen: 800,
          // Veinte repeticiones: se estima, pero no hay nada fiable.
          mejor1RM: 66.7,
          mejor1RMFiable: null,
        ),
      ];

      final records = recordsEjercicio(conSerieLarga);
      expect(records.pesoMaximo, 40);
      expect(records.volumenMaximo, 800);
      expect(records.mejor1RM, isNull);
      expect(sesionesConRecord(conSerieLarga), {1});
    });

    test('sin histórico no hay récords, pero tampoco excepciones', () {
      final records = recordsEjercicio(const []);
      expect(records.pesoMaximo, isNull);
      expect(records.mejor1RM, isNull);
      expect(records.volumenTotal, 0);
      expect(sesionesConRecord(const []), isEmpty);
    });

    test('se marca la sesión que fue récord el día que se hizo', () {
      // Las tres lo fueron de algo: la primera de todo, la segunda de peso y
      // 1RM, la tercera de volumen.
      expect(sesionesConRecord(historico), {1, 2, 3});

      // Una cuarta peor en todo no se marca.
      final conFloja = [
        ...historico,
        _sesion(
          id: 4,
          fecha: DateTime(2026, 3, 22),
          pesoMaximo: 55,
          volumen: 400,
          mejor1RM: 70,
          mejor1RMFiable: 70,
        ),
      ];
      expect(sesionesConRecord(conFloja), {1, 2, 3});
    });

    test('borrar la sesión del récord lo pasa a la siguiente mejor', () {
      final sinLaMejor = [
        for (final s in historico)
          if (s.idEntrenamiento != 2) s,
      ];
      final records = recordsEjercicio(sinLaMejor);
      expect(records.pesoMaximo, 62.5);
      expect(records.mejor1RM, closeTo(81, 1e-9));
    });
  });

  group('la semana', () {
    test('el lunes de una fecha es su lunes, y el del lunes es él mismo', () {
      // 8 de marzo de 2026 es domingo; 2 de marzo, lunes.
      expect(lunesDe(DateTime(2026, 3, 8)), DateTime(2026, 3, 2));
      expect(lunesDe(DateTime(2026, 3, 2)), DateTime(2026, 3, 2));
      // La hora se descarta: la semana empieza a medianoche.
      expect(lunesDe(DateTime(2026, 3, 4, 23, 30)), DateTime(2026, 3, 2));
    });

    test('el cambio de semana reparte bien domingo y lunes', () {
      final sesiones = [
        _dia(DateTime(2026, 3, 8, 20), id: 1), // domingo
        _dia(DateTime(2026, 3, 9, 8), id: 2), // lunes siguiente
      ];

      expect(resumenSemana(sesiones, DateTime(2026, 3, 2)).sesiones, 1);
      expect(resumenSemana(sesiones, DateTime(2026, 3, 9)).sesiones, 1);
    });

    test('el resumen suma sesiones y volumen de su semana', () {
      final sesiones = [
        _dia(DateTime(2026, 3, 2), volumen: 1000, id: 1),
        _dia(DateTime(2026, 3, 4), volumen: 1500, id: 2),
        _dia(DateTime(2026, 3, 10), volumen: 900, id: 3),
      ];

      final semana = resumenSemana(sesiones, DateTime(2026, 3, 5));
      expect(semana.lunes, DateTime(2026, 3, 2));
      expect(semana.sesiones, 2);
      expect(semana.volumen, 2500);
      expect(semana.vacia, isFalse);
    });

    test('una semana sin sesiones da un resumen a cero, no nulo', () {
      final semana = resumenSemana(const [], DateTime(2026, 3, 2));
      expect(semana.sesiones, 0);
      expect(semana.volumen, 0);
      expect(semana.vacia, isTrue);
    });

    test('la variación se omite cuando no hay con qué comparar', () {
      expect(variacion(12, 10), closeTo(0.2, 1e-9));
      expect(variacion(8, 10), closeTo(-0.2, 1e-9));
      expect(variacion(12, 0), isNull);
    });
  });

  group('racha de semanas', () {
    /// Tantas sesiones en la semana del [lunes] dado.
    List<SesionConVolumen> semanaCon(DateTime lunes, int cuantas) => [
      for (var i = 0; i < cuantas; i++)
        _dia(lunes.add(Duration(days: i)), id: lunes.day * 10 + i),
    ];

    test('cuenta semanas cerradas consecutivas que cumplen el objetivo', () {
      // Jueves 12 de marzo de 2026. Las dos semanas anteriores cumplen.
      final hoy = DateTime(2026, 3, 12);
      final sesiones = [
        ...semanaCon(DateTime(2026, 2, 23), 3),
        ...semanaCon(DateTime(2026, 3, 2), 3),
        ...semanaCon(DateTime(2026, 3, 9), 1),
      ];

      expect(rachaSemanas(sesiones, 3, hoy: hoy), 2);
    });

    test('la semana en curso no rompe la racha el lunes por la mañana', () {
      // Lunes 9 de marzo a las 7 de la mañana: aún no se ha entrenado nada esta
      // semana y la racha debe seguir viva.
      final hoy = DateTime(2026, 3, 9, 7);
      final sesiones = [
        ...semanaCon(DateTime(2026, 2, 23), 3),
        ...semanaCon(DateTime(2026, 3, 2), 4),
      ];

      expect(rachaSemanas(sesiones, 3, hoy: hoy), 2);
    });

    test('una semana en blanco ya terminada rompe la racha', () {
      final hoy = DateTime(2026, 3, 12);
      final sesiones = [
        ...semanaCon(DateTime(2026, 2, 16), 3),
        // La semana del 23 no se entrenó.
        ...semanaCon(DateTime(2026, 3, 2), 3),
      ];

      // Solo cuenta la del 2 de marzo: la anterior está vacía y ahí se corta.
      expect(rachaSemanas(sesiones, 3, hoy: hoy), 1);
    });

    test('sin sesiones o sin objetivo la racha es cero', () {
      expect(rachaSemanas(const [], 3, hoy: DateTime(2026, 3, 12)), 0);
      expect(
        rachaSemanas(
          semanaCon(DateTime(2026, 3, 2), 5),
          0,
          hoy: DateTime(2026, 3, 12),
        ),
        0,
      );
    });

    test('la racha no se cuela más atrás de la primera semana registrada', () {
      // Con objetivo 1 y una sola semana entrenada, la racha es 1: sin el suelo
      // de los datos, el bucle seguiría contando semanas vacías hacia atrás.
      final sesiones = semanaCon(DateTime(2026, 3, 2), 1);
      expect(rachaSemanas(sesiones, 1, hoy: DateTime(2026, 3, 12)), 1);
    });
  });
}
