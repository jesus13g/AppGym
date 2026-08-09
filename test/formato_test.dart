/// Fechas, números y relativos en los dos idiomas.
///
/// Es el test que fija lo que I3 cambió: el orden de la fecha, el separador de
/// miles y los plurales, que no son el mismo texto con otras palabras. Todo con
/// fechas fijas, porque un formato que solo se comprueba con `DateTime.now()`
/// no se comprueba.
library;

import 'package:appgym/datos/ajustes.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ayuda.dart';

void main() {
  final es = formatoDePrueba();
  final en = formatoDePrueba(idioma: 'en');

  group('fechas', () {
    final fecha = DateTime(2026, 3, 1, 19, 5);

    test('la larga cambia de orden, no solo de palabras', () {
      expect(es.fechaLarga(fecha), '1 de marzo de 2026');
      expect(en.fechaLarga(fecha), 'March 1, 2026');
    });

    test('la corta también', () {
      expect(es.fechaCorta(fecha), '1 mar');
      expect(en.fechaCorta(fecha), 'Mar 1');
    });

    test('sin fecha no se escribe nada', () {
      expect(es.fechaCorta(null), '');
      expect(es.fechaLarga(null), '');
    });

    test('la cabecera del calendario va capitalizada', () {
      expect(es.mesYAno(fecha), 'Marzo de 2026');
      expect(en.mesYAno(fecha), 'March 2026');
    });

    test('la hora usa el reloj del idioma', () {
      expect(es.hora(fecha), '19:05');
      // CLDR separa el «PM» con un espacio fino de no separación (U+202F), no
      // con un espacio normal; se normaliza para que la aserción se lea.
      expect(en.hora(fecha).replaceAll('\u202f', ' '), '7:05 PM');
    });

    test('la semana empieza en lunes en los dos idiomas', () {
      // Deliberado: la racha (C17) y `metricas.porSemana` están definidas sobre
      // semanas de lunes a domingo, y hacer que dependiera del idioma daría
      // rachas distintas en dos móviles del mismo usuario.
      expect(es.inicialesSemana, ['L', 'M', 'X', 'J', 'V', 'S', 'D']);
      expect(en.inicialesSemana, ['M', 'T', 'W', 'T', 'F', 'S', 'S']);
    });
  });

  group('números y pesos', () {
    test('los separadores son los del idioma', () {
      expect(es.numero(1234.5), '1.234,5');
      expect(en.numero(1234.5), '1,234.5');
      expect(es.numero(8750), '8.750');
      expect(en.numero(8750), '8,750');
    });

    test('un entero no arrastra decimales', () {
      expect(es.numero(60), '60');
      expect(en.numero(60), '60');
    });

    test('el peso lleva el separador del idioma y la unidad activa', () {
      expect(es.peso(1234.5), '1.234,5 kg');
      expect(en.peso(1234.5), '1,234.5 kg');

      final libras = formatoDePrueba(
        idioma: 'en',
        ajustes: const Ajustes(unidad: Unidad.lb),
      );
      expect(libras.peso(60), '132.3 lb');
    });

    test(
      'la duración no depende del idioma: los dos puntos son universales',
      () {
        for (final f in [es, en]) {
          expect(f.duracion(0), '0:00');
          expect(f.duracion(72), '1:12');
          expect(f.duracion(2052), '34:12');
          expect(f.duracion(3912), '1:05:12');
        }
      },
    );

    test('el descanso usa los símbolos del SI, que tampoco se traducen', () {
      for (final f in [es, en]) {
        expect(f.descanso(45), '45 s');
        expect(f.descanso(60), '1 min');
        expect(f.descanso(90), '1 min 30 s');
        expect(f.descanso(300), '5 min');
      }
    });

    test('RPE y RIR son siglas internacionales', () {
      expect(es.esfuerzo(8, EscalaEsfuerzo.rpe), 'RPE 8');
      expect(en.esfuerzo(8, EscalaEsfuerzo.rir), 'RIR 2');
    });
  });

  group('relativos', () {
    /// Se cuenta contra hoy, así que las fechas se construyen restando.
    DateTime haceDias(int dias) =>
        DateTime.now().subtract(Duration(days: dias));

    test('«Hoy» y «Ayer» salen de la clave ICU, no de un if', () {
      expect(es.hace(haceDias(0)), 'Hoy');
      expect(en.hace(haceDias(0)), 'Today');
      expect(es.hace(haceDias(1)), 'Ayer');
      expect(en.hace(haceDias(1)), 'Yesterday');
    });

    test('días, semanas y meses', () {
      expect(es.hace(haceDias(3)), 'Hace 3 días');
      expect(en.hace(haceDias(3)), '3 days ago');
      expect(es.hace(haceDias(8)), 'Hace 1 semana');
      expect(en.hace(haceDias(8)), '1 week ago');
      expect(es.hace(haceDias(40)), 'Hace 1 mes');
      expect(en.hace(haceDias(40)), '1 month ago');
    });

    test('sin fecha, la rutina está sin entrenar', () {
      expect(es.hace(null), 'Sin entrenar');
      expect(en.hace(null), 'Not trained yet');
    });

    test('«desde» cuenta minutos, no días', () {
      final ahora = DateTime.now();
      expect(es.desde(ahora), 'hace un momento');
      expect(en.desde(ahora), 'a moment ago');
      expect(
        es.desde(ahora.subtract(const Duration(minutes: 12))),
        'hace 12 minutos',
      );
      expect(
        en.desde(ahora.subtract(const Duration(minutes: 12))),
        '12 minutes ago',
      );
      expect(
        es.desde(ahora.subtract(const Duration(minutes: 1))),
        'hace 1 minuto',
      );
      expect(
        es.desde(ahora.subtract(const Duration(hours: 3))),
        'hace 3 horas',
      );
      expect(en.desde(ahora.subtract(const Duration(hours: 3))), '3 hours ago');
      expect(es.desde(ahora.subtract(const Duration(days: 2))), 'hace 2 días');
      expect(en.desde(ahora.subtract(const Duration(days: 2))), '2 days ago');
    });
  });
}
