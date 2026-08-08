/// Tests de las preferencias, del formateo y del borrador de sesión.
///
/// Son las tres piezas que no tocan la base de datos y de las que cuelga media
/// interfaz: la unidad con la que se escribe cada peso, cómo se lee un valor
/// guardado y qué sobrevive a cerrar la app a mitad de entrenamiento.
library;

import 'package:appgym/datos/ajustes.dart';
import 'package:appgym/datos/bd.dart';
import 'package:appgym/datos/borrador.dart';
import 'package:appgym/datos/formato.dart' as formato;
import 'package:appgym/pantallas/medidas.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('preferencias', () {
    test('sin ninguna fila valen los valores por defecto', () {
      final ajustes = Ajustes.desdeMapa(const {});

      expect(ajustes.unidad, Unidad.kg);
      expect(ajustes.pasoPeso, 2.5);
      expect(ajustes.descansoSeg, 90);
      expect(ajustes.sonidoDescanso, isTrue);
      expect(ajustes.seriesPorDefecto, 4);
      expect(ajustes.repeticionesPorDefecto, 10);
      // El esfuerzo arranca apagado: quien no lo use no debe verlo estorbando.
      expect(ajustes.esfuerzoActivo, isFalse);
      expect(ajustes.escala, EscalaEsfuerzo.rpe);
      expect(ajustes.sesionesPorSemana, 3);
      expect(ajustes.formula, Formula.epley);
      expect(ajustes.tema, Tema.sistema);
      // La progresión, en cambio, arranca encendida: no estorba a nadie hasta
      // que hay dos sesiones de un ejercicio, y entonces es lo útil.
      expect(ajustes.progresionActiva, isTrue);
      expect(ajustes.repMinGlobal, 8);
      expect(ajustes.repMaxGlobal, 12);
      expect(ajustes.perfilProgresion, Perfil.estandar);
    });

    test('lee lo guardado', () {
      final ajustes = Ajustes.desdeMapa(const {
        Claves.unidad: 'lb',
        Claves.pasoPeso: '1.25',
        Claves.descanso: '180',
        Claves.sonidoDescanso: '0',
        Claves.series: '5',
        Claves.repeticiones: '8',
        Claves.esfuerzoActivo: '1',
        Claves.esfuerzoEscala: 'rir',
        Claves.sesionesPorSemana: '5',
        Claves.formula1RM: 'brzycki',
        Claves.tema: 'oscuro',
        Claves.progresionActiva: '0',
        Claves.repMin: '3',
        Claves.repMax: '5',
        Claves.perfilProgresion: 'agresivo',
      });

      expect(ajustes.unidad, Unidad.lb);
      expect(ajustes.pasoPeso, 1.25);
      expect(ajustes.descansoSeg, 180);
      expect(ajustes.sonidoDescanso, isFalse);
      expect(ajustes.seriesPorDefecto, 5);
      expect(ajustes.repeticionesPorDefecto, 8);
      expect(ajustes.esfuerzoActivo, isTrue);
      expect(ajustes.escala, EscalaEsfuerzo.rir);
      expect(ajustes.sesionesPorSemana, 5);
      expect(ajustes.formula, Formula.brzycki);
      expect(ajustes.tema, Tema.oscuro);
      expect(ajustes.progresionActiva, isFalse);
      expect(ajustes.repMinGlobal, 3);
      expect(ajustes.repMaxGlobal, 5);
      expect(ajustes.perfilProgresion, Perfil.agresivo);
    });

    test('un valor con basura o fuera de rango se queda con el de fábrica', () {
      final ajustes = Ajustes.desdeMapa(const {
        Claves.descanso: 'mucho rato',
        Claves.series: '99',
        Claves.repeticiones: '0',
        Claves.pasoPeso: '3',
        Claves.tema: 'fucsia',
        Claves.unidad: 'piedras',
        Claves.formula1RM: 'lombardi',
      });

      expect(ajustes.descansoSeg, 90);
      expect(ajustes.seriesPorDefecto, 4);
      expect(ajustes.repeticionesPorDefecto, 10);
      // 3 no está entre los pasos admitidos.
      expect(ajustes.pasoPeso, 2.5);
      expect(ajustes.tema, Tema.sistema);
      expect(ajustes.unidad, Unidad.kg);
      expect(ajustes.formula, Formula.epley);
    });

    test('lo que escribe `texto` es lo que lee `desdeMapa`', () {
      final original = Ajustes.desdeMapa(const {
        Claves.unidad: 'lb',
        Claves.tema: 'claro',
        Claves.sonidoDescanso: '0',
        Claves.perfilProgresion: 'conservador',
        Claves.repMin: '6',
      });
      final ida = {
        Claves.unidad: Ajustes.texto(original.unidad),
        Claves.tema: Ajustes.texto(original.tema),
        Claves.sonidoDescanso: Ajustes.texto(original.sonidoDescanso),
        Claves.perfilProgresion: Ajustes.texto(original.perfilProgresion),
        Claves.repMin: Ajustes.texto(original.repMinGlobal),
      };
      final vuelta = Ajustes.desdeMapa(ida);

      expect(vuelta.unidad, original.unidad);
      expect(vuelta.tema, original.tema);
      expect(vuelta.sonidoDescanso, original.sonidoDescanso);
      expect(vuelta.perfilProgresion, Perfil.conservador);
      expect(vuelta.repMinGlobal, 6);
    });
  });

  group('conversión de unidades', () {
    test('en kilos no se convierte nada', () {
      const ajustes = Ajustes();
      expect(ajustes.desdeKilos(60), 60);
      expect(ajustes.aKilos(60), 60);
      expect(formato.peso(62.5, ajustes), '62,5 kg');
    });

    test('en libras se convierte solo al mostrar', () {
      const ajustes = Ajustes(unidad: Unidad.lb);

      expect(ajustes.desdeKilos(100), closeTo(220.462, 0.001));
      expect(ajustes.aKilos(220.462), closeTo(100, 0.001));
      // Un decimal al escribir: el resto de 132,2772 no aporta ni precisión.
      expect(formato.peso(60, ajustes), '132,3 lb');
    });

    test('ida y vuelta devuelve el mismo peso', () {
      const ajustes = Ajustes(unidad: Unidad.lb);
      expect(ajustes.aKilos(ajustes.desdeKilos(77.5)), closeTo(77.5, 1e-9));
    });

    test('el selector cuadra el valor al paso', () {
      const kilos = Ajustes();
      // 61 kg con paso 2,5 cae en 60.
      expect(kilos.paraSelector(61), 60);
      expect(kilos.paraSelector(64), 65);

      const libras = Ajustes(unidad: Unidad.lb);
      // 60 kg son 132,28 lb, que con paso 2,5 se queda en 132,5.
      expect(libras.paraSelector(60), closeTo(132.5, 1e-9));
    });

    test('el paso de 1,25 es el único que pide dos decimales', () {
      expect(const Ajustes(pasoPeso: 1.25).decimalesPaso, 2);
      expect(const Ajustes(pasoPeso: 2.5).decimalesPaso, 1);
      expect(const Ajustes(pasoPeso: 0.5).decimalesPaso, 1);
    });

    test('el tope del selector sigue a la unidad', () {
      expect(const Ajustes().pesoMaximo, 400);
      expect(const Ajustes(unidad: Unidad.lb).pesoMaximo, 882);
    });
  });

  group('formato', () {
    test('duración con y sin horas', () {
      expect(formato.duracion(0), '0:00');
      expect(formato.duracion(72), '1:12');
      expect(formato.duracion(2052), '34:12');
      expect(formato.duracion(3912), '1:05:12');
    });

    test('descanso en lenguaje corriente', () {
      expect(formato.descanso(45), '45 s');
      expect(formato.descanso(60), '1 min');
      expect(formato.descanso(90), '1 min 30 s');
      expect(formato.descanso(300), '5 min');
    });

    test('«desde» cuenta minutos, no días', () {
      final ahora = DateTime.now();
      expect(formato.desde(ahora), 'hace un momento');
      expect(
        formato.desde(ahora.subtract(const Duration(minutes: 12))),
        'hace 12 minutos',
      );
      expect(
        formato.desde(ahora.subtract(const Duration(minutes: 1))),
        'hace 1 minuto',
      );
      expect(
        formato.desde(ahora.subtract(const Duration(hours: 3))),
        'hace 3 horas',
      );
      expect(
        formato.desde(ahora.subtract(const Duration(days: 2))),
        'hace 2 días',
      );
    });
  });

  group('borrador de la sesión viva', () {
    final borrador = Borrador(
      nota: 'Me dolía el hombro',
      series: {
        7: const [
          (
            valores: ValoresSerie(
              repeticiones: 12,
              peso: 40,
              calentamiento: true,
            ),
            hecha: true,
          ),
          (
            valores: ValoresSerie(
              repeticiones: 10,
              peso: 62.5,
              rpe: 8,
              nota: 'Justa',
            ),
            hecha: true,
          ),
          (valores: ValoresSerie(repeticiones: 8, peso: 65), hecha: false),
        ],
        9: const [],
      },
    );

    test('ida y vuelta por JSON conserva todo', () {
      final vuelta = Borrador.desdeJson(borrador.aJson());

      expect(vuelta.nota, 'Me dolía el hombro');
      expect(vuelta.series[7], hasLength(3));
      expect(vuelta.series[9], isEmpty);

      final segunda = vuelta.series[7]![1];
      expect(segunda.valores.repeticiones, 10);
      expect(segunda.valores.peso, 62.5);
      expect(segunda.valores.rpe, 8);
      expect(segunda.valores.nota, 'Justa');
      expect(segunda.hecha, isTrue);

      expect(vuelta.series[7]![0].valores.calentamiento, isTrue);
      expect(vuelta.series[7]![2].hecha, isFalse);
    });

    test('las sugerencias descartadas viajan en el borrador', () {
      final descartado = Borrador(
        series: borrador.series,
        descartadas: const {7},
      );
      expect(Borrador.desdeJson(descartado.aJson()).descartadas, {7});

      // Y un borrador escrito antes de que existieran no trae la clave: sale
      // vacío en vez de reventar, que es como se tolera todo aquí.
      expect(
        Borrador.desdeJson('{"nota":"","ejercicios":{}}').descartadas,
        isEmpty,
      );
    });

    test('el progreso cuenta las marcadas sobre el total', () {
      expect(borrador.progreso, (2, 3));
      expect(const Borrador(series: {}).progreso, (0, 0));
    });

    test('en sesión viva solo se guardan las series marcadas', () {
      final vivo = borrador.paraGuardar(soloHechas: true);
      expect(vivo[7], hasLength(2));
      expect(vivo[7]!.last.peso, 62.5);

      // En formulario se guardan todas: ahí no hay checks que marcar.
      expect(borrador.paraGuardar(soloHechas: false)[7], hasLength(3));
    });

    test('un JSON ilegible da un borrador vacío en vez de reventar', () {
      // Un borrador que no se entiende es una molestia, no un motivo para que
      // la app no arranque.
      expect(Borrador.desdeJson('no soy json').series, isEmpty);
      expect(Borrador.desdeJson('[]').series, isEmpty);
      expect(Borrador.desdeJson('{"nota":"a"}').series, isEmpty);
      expect(Borrador.desdeJson('{"ejercicios":{"x":[]}}').series, isEmpty);
    });
  });

  group('media móvil del peso corporal', () {
    test('los primeros puntos promedian lo que hay', () {
      // Sin esto la línea empezaría el séptimo día y el gráfico se vería medio
      // vacío justo la primera semana, que es cuando más se mira.
      expect(mediaMovil([10, 20], ventana: 7), [10, 15]);
    });

    test('con la ventana llena, promedia los últimos', () {
      expect(mediaMovil([1, 2, 3, 4, 5], ventana: 3), [1, 1.5, 2, 3, 4]);
    });

    test('una serie plana no se mueve', () {
      expect(mediaMovil([80, 80, 80]), [80, 80, 80]);
    });
  });
}
