/// Tests de los trazados del modelo anatómico y de la resolución del toque.
///
/// Dos grupos: figuras sintéticas para fijar las reglas (el desempate por área,
/// la tolerancia, el reflejo) y el asset de verdad, para que un dibujo con una
/// región descolocada o fuera del lienzo falle aquí.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:appgym/datos/geometria.dart';
import 'package:appgym/datos/musculos.dart';
import 'package:flutter_test/flutter_test.dart';

/// Un cuadrado como trazado, con los cuatro lados rectos.
///
/// Una recta es una cúbica con los tiradores sobre ella, así que no hace falta
/// nada especial para escribirla.
Trazado _cuadrado(double x, double y, double lado) {
  Curva hasta(Offset desde, Offset fin) => Curva(
    Offset.lerp(desde, fin, 1 / 3)!,
    Offset.lerp(desde, fin, 2 / 3)!,
    fin,
  );
  final a = Offset(x, y);
  final b = Offset(x + lado, y);
  final c = Offset(x + lado, y + lado);
  final d = Offset(x, y + lado);
  return Trazado(
    inicio: a,
    curvas: [hasta(a, b), hasta(b, c), hasta(c, d), hasta(d, a)],
  );
}

Figura _figuraCuadrado(double x, double y, double lado) =>
    construirFigura([_cuadrado(x, y, lado)], anchoEspejo: 1000);

void main() {
  group('áreas y trazados', () {
    test('el área de un cuadrado es su lado al cuadrado', () {
      expect(areaTrazado(_cuadrado(0, 0, 100)), closeTo(10000, 1e-6));
    });

    test('el sentido de giro no cambia el área', () {
      final derecho = _cuadrado(0, 0, 100);
      final invertido = Trazado(
        inicio: derecho.curvas.last.fin,
        curvas: [
          for (final c in derecho.curvas.reversed) Curva(c.c2, c.c1, c.fin),
        ],
      );
      expect(areaTrazado(invertido), closeTo(areaTrazado(derecho), 1e-6));
    });

    test('un trazado con espejo produce dos partes y las dos responden', () {
      final figura = construirFigura([
        Trazado(
          inicio: _cuadrado(100, 100, 80).inicio,
          curvas: _cuadrado(100, 100, 80).curvas,
          espejo: true,
        ),
      ], anchoEspejo: 1000);

      expect(figura.partes, hasLength(2));
      expect(figura.area, closeTo(2 * 6400, 1e-6));
      expect(figura.contiene(const Offset(140, 140)), isTrue);
      // El reflejo de x=140 es x=860.
      expect(figura.contiene(const Offset(860, 140)), isTrue);
    });
  });

  group('resolución del toque', () {
    test('gana la figura de menor área cuando dos se solapan', () {
      final figuras = {
        'grande': _figuraCuadrado(0, 0, 400),
        'pequena': _figuraCuadrado(100, 100, 60),
      };
      expect(figuraEn(figuras, const Offset(130, 130)), 'pequena');
      expect(figuraEn(figuras, const Offset(300, 300)), 'grande');
    });

    test('tocar fuera de todo no devuelve nada', () {
      final figuras = {'a': _figuraCuadrado(0, 0, 100)};
      expect(figuraEn(figuras, const Offset(500, 500)), isNull);
    });

    test('la tolerancia perdona el dedo, pero no de más', () {
      final figuras = {'a': _figuraCuadrado(100, 100, 100)};
      // A 6 unidades del borde, con 12 de tolerancia: acierta.
      expect(figuraEn(figuras, const Offset(94, 150), tolerancia: 12), 'a');
      // A 30, no.
      expect(figuraEn(figuras, const Offset(70, 150), tolerancia: 12), isNull);
      // Sin tolerancia, nada de lo de fuera cuenta.
      expect(figuraEn(figuras, const Offset(94, 150)), isNull);
    });

    test('una región bilateral no pierde el desempate por su rectángulo', () {
      // La regresión que justifica desempatar por área y no por `getBounds`:
      // el rectángulo que envuelve las dos mitades del pectoral abarca el torso
      // entero, así que con él ganaría siempre la región equivocada.
      final bilateral = construirFigura([
        Trazado(
          inicio: _cuadrado(100, 100, 60).inicio,
          curvas: _cuadrado(100, 100, 60).curvas,
          espejo: true,
        ),
      ], anchoEspejo: 1000);
      final enmedio = _figuraCuadrado(300, 100, 200);

      expect(bilateral.limites.width, greaterThan(enmedio.limites.width));
      expect(bilateral.area, lessThan(enmedio.area));
      expect(
        figuraEn({
          'bilateral': bilateral,
          'enmedio': enmedio,
        }, const Offset(130, 130)),
        'bilateral',
      );
    });
  });

  group('encaje', () {
    test('centra el lienzo dentro de un destino más ancho', () {
      final encaje = Encaje.contener(
        destino: const Size(400, 400),
        lienzo: const Size(1000, 2000),
      );
      expect(encaje.escala, closeTo(0.2, 1e-9));
      expect(encaje.desplazamiento.dx, closeTo(100, 1e-9));
      expect(encaje.desplazamiento.dy, closeTo(0, 1e-9));
    });

    test('centra el lienzo dentro de un destino más alto', () {
      final encaje = Encaje.contener(
        destino: const Size(500, 2000),
        lienzo: const Size(1000, 2000),
      );
      expect(encaje.escala, closeTo(0.5, 1e-9));
      expect(encaje.desplazamiento.dy, closeTo(500, 1e-9));
    });

    test('la ida y la vuelta de un punto coinciden', () {
      final encaje = Encaje.contener(
        destino: const Size(300, 600),
        lienzo: const Size(1000, 2000),
      );
      expect(encaje.aLienzo(encaje.desplazamiento), Offset.zero);
      final punto = encaje.aLienzo(const Offset(150, 300));
      expect(punto.dx, closeTo(500, 1e-9));
      expect(punto.dy, closeTo(1000, 1e-9));
    });

    test('la tolerancia se traduce a unidades del lienzo', () {
      // 12 px de pantalla no son 12 del lienzo: el factor ronda el 5, y pasar
      // los 12 tal cual dejaría la tolerancia en nada.
      final encaje = Encaje.contener(
        destino: const Size(230, 460),
        lienzo: const Size(1000, 2000),
      );
      expect(encaje.aLienzoDistancia(12), closeTo(12 / 0.23, 1e-9));
      expect(encaje.aLienzoDistancia(12), greaterThan(50));
    });
  });

  group('el dibujo de verdad', () {
    late MapaCuerpo<Region> mapa;

    setUpAll(() {
      final json =
          jsonDecode(File('assets/musculatura.json').readAsStringSync())
              as Map<String, dynamic>;
      mapa = cargarMapa(json, (nombre) => Region.values.asNameMap()[nombre]);
    });

    test('el lienzo es el declarado y hay dos caras', () {
      expect(mapa.lienzo, const Size(1000, 2000));
      expect(mapa.caras.keys, containsAll(['frente', 'espalda']));
    });

    test('cada región se dibuja en la cara que declara', () {
      for (final MapEntry(key: region, value: datos) in regiones.entries) {
        final enFrente = mapa.caras['frente']!.regiones.containsKey(region);
        final enEspalda = mapa.caras['espalda']!.regiones.containsKey(region);
        expect(
          enFrente,
          datos.vista.seVeEn(Vista.frente),
          reason: '${region.name} y la vista frontal no concuerdan',
        );
        expect(
          enEspalda,
          datos.vista.seVeEn(Vista.espalda),
          reason: '${region.name} y la vista dorsal no concuerdan',
        );
      }
    });

    test('las 21 regiones están dibujadas en alguna cara', () {
      final dibujadas = {
        ...mapa.caras['frente']!.regiones.keys,
        ...mapa.caras['espalda']!.regiones.keys,
      };
      expect(dibujadas, hasLength(Region.values.length));
    });

    test('nada se sale del lienzo', () {
      for (final cara in mapa.caras.values) {
        for (final figura in [cara.silueta, ...cara.regiones.values]) {
          expect(figura.limites.left, greaterThanOrEqualTo(-1));
          expect(figura.limites.top, greaterThanOrEqualTo(-1));
          expect(figura.limites.right, lessThanOrEqualTo(1001));
          expect(figura.limites.bottom, lessThanOrEqualTo(2001));
        }
      }
    });

    test('toda región cae dentro de la silueta', () {
      // Un músculo flotando fuera del cuerpo es el error más visible que puede
      // tener el dibujo y el único que no se ve en una lista de números.
      //
      // Se comprueba con un punto del interior y no con el centro del
      // rectángulo: en una región bilateral ese centro cae en la línea media,
      // que para los gemelos es el aire de entre las dos piernas.
      for (final MapEntry(key: nombre, value: cara) in mapa.caras.entries) {
        for (final MapEntry(key: region, value: figura)
            in cara.regiones.entries) {
          final punto = _puntoDentro(figura);
          expect(punto, isNotNull, reason: '${region.name} no tiene interior');
          // `contiene` prueba parte a parte a propósito: sobre el `Path`
          // combinado, el brazo y el torso se solapan con sentidos de giro
          // opuestos y el relleno `nonZero` los anularía.
          expect(
            cara.silueta.contiene(punto!),
            isTrue,
            reason: '${region.name} se sale del cuerpo en $nombre',
          );
        }
      }
    });

    test('ninguna región queda tapada por otra', () {
      // Lo que de verdad hay que garantizar: que cada región tenga **algún**
      // punto donde gane el toque. Las regiones se solapan a propósito —el
      // deltoides posterior va encima del deltoides—, y en el solape gana la
      // menor; lo que no puede pasar es que una quede cubierta del todo y sea
      // imposible de tocar en el mapa.
      for (final MapEntry(key: nombre, value: cara) in mapa.caras.entries) {
        for (final region in cara.regiones.keys) {
          expect(
            _puntoQueGana(cara.regiones, region),
            isNotNull,
            reason: '${region.name} en $nombre no se puede tocar',
          );
        }
      }
    });

    test('los puntos de referencia caen en el músculo que se espera', () {
      // Estos sí van a mano: son los que cazarían un asset con dos regiones
      // intercambiadas de nombre, que el test anterior no puede ver.
      final frente = mapa.caras['frente']!.regiones;
      final espalda = mapa.caras['espalda']!.regiones;
      final referencias = <(Map<Region, Figura>, Offset, Region, String)>[
        (frente, const Offset(590, 480), Region.pectoral, 'mitad del pecho'),
        (frente, const Offset(500, 700), Region.abdomen, 'ombligo'),
        (frente, const Offset(600, 700), Region.oblicuo, 'flanco'),
        (frente, const Offset(600, 1150), Region.cuadriceps, 'muslo delantero'),
        (frente, const Offset(530, 1080), Region.aductor, 'cara interna'),
        (frente, const Offset(720, 600), Region.biceps, 'brazo delantero'),
        (frente, const Offset(760, 950), Region.antebrazo, 'antebrazo'),
        (frente, const Offset(730, 470), Region.deltoides, 'hombro'),
        (frente, const Offset(610, 1520), Region.gemelo, 'pantorrilla'),
        (frente, const Offset(545, 1600), Region.tibial, 'espinilla'),
        (frente, const Offset(560, 880), Region.flexorCadera, 'ingle'),
        (frente, const Offset(648, 930), Region.abductor, 'cadera externa'),
        (frente, const Offset(548, 320), Region.cuello, 'cuello'),
        (espalda, const Offset(500, 380), Region.trapecio, 'nuca'),
        (espalda, const Offset(620, 620), Region.dorsal, 'dorsal'),
        (
          espalda,
          const Offset(550, 540),
          Region.espaldaAlta,
          'entre escápulas',
        ),
        (espalda, const Offset(500, 710), Region.lumbar, 'lumbar'),
        (espalda, const Offset(570, 890), Region.gluteo, 'glúteo'),
        (espalda, const Offset(590, 1150), Region.isquiotibial, 'femoral'),
        (espalda, const Offset(720, 600), Region.triceps, 'brazo trasero'),
        (
          espalda,
          const Offset(725, 500),
          Region.deltoidesPost,
          'hombro trasero',
        ),
        (espalda, const Offset(590, 1520), Region.gemelo, 'pantorrilla'),
      ];

      expect(referencias.length, greaterThanOrEqualTo(20));
      for (final (figuras, punto, esperada, donde) in referencias) {
        expect(figuraEn(figuras, punto), esperada, reason: donde);
      }
    });

    test('el modelo tiene luces y sombras para dar volumen', () {
      for (final cara in mapa.caras.values) {
        expect(cara.luces, hasLength(cara.regiones.length));
        expect(cara.sombras, hasLength(cara.regiones.length));
      }
    });
  });
}

/// Busca por rejilla un punto que caiga dentro de [figura].
Offset? _puntoDentro(Figura figura) =>
    _buscarEnRejilla(figura, (punto) => figura.contiene(punto));

/// Busca por rejilla un punto en el que [region] gane el toque.
Offset? _puntoQueGana(Map<Region, Figura> figuras, Region region) =>
    _buscarEnRejilla(
      figuras[region]!,
      (punto) => figuraEn(figuras, punto) == region,
    );

Offset? _buscarEnRejilla(Figura figura, bool Function(Offset) vale) {
  final limites = figura.limites;
  for (var i = 1; i < 20; i++) {
    for (var j = 1; j < 20; j++) {
      final punto = Offset(
        limites.left + limites.width * i / 20,
        limites.top + limites.height * j / 20,
      );
      if (figura.contiene(punto) && vale(punto)) return punto;
    }
  }
  return null;
}
