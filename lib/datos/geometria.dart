/// Los trazados del modelo anatómico y la resolución del toque.
///
/// Es el otro módulo puro de la app: solo importa `dart:ui`, así que **no
/// conoce el enum `Region`** —que vive en `musculos.dart`, que a su vez arrastra
/// la base de datos— y va parametrizado por la clave. Quien carga el mapa pasa
/// la función que traduce el nombre del JSON a lo que quiera usar de clave.
///
/// Lo difícil de una vista así es saber qué región se ha tocado, y Flutter lo
/// trae resuelto: [Path.contains] es exacto con curvas de Bézier. Con un modelo
/// 3D habría que lanzar rayos contra triángulos a mano.
library;

import 'dart:math' as math;
import 'dart:ui';

// ── El modelo ────────────────────────────────────────────────────────────────

/// Un segmento cúbico de Bézier: dos tiradores y el punto final.
class Curva {
  const Curva(this.c1, this.c2, this.fin);

  final Offset c1;
  final Offset c2;
  final Offset fin;
}

/// Un trazado cerrado: dónde empieza y por dónde sigue.
///
/// No hay parser de la `d` de SVG a propósito: el JSON ya viene como puntos y
/// curvas, así que no hay que mantener un formato ajeno ni sus tests.
class Trazado {
  const Trazado({
    required this.inicio,
    required this.curvas,
    this.espejo = false,
  });

  final Offset inicio;
  final List<Curva> curvas;

  /// Si además de este trazado hay que dibujar su reflejo.
  ///
  /// Casi todos los músculos son bilaterales. Definir un lado y reflejar el
  /// otro halva el fichero y hace que la simetría sea exacta por construcción,
  /// no por pulso.
  final bool espejo;

  static Trazado desdeJson(Map<String, dynamic> json) {
    final inicio = (json['i'] as List).cast<num>();
    return Trazado(
      inicio: Offset(inicio[0].toDouble(), inicio[1].toDouble()),
      curvas: [
        for (final c in json['c'] as List)
          if ((c as List).cast<num>() case final v)
            Curva(
              Offset(v[0].toDouble(), v[1].toDouble()),
              Offset(v[2].toDouble(), v[3].toDouble()),
              Offset(v[4].toDouble(), v[5].toDouble()),
            ),
      ],
      espejo: json['espejo'] == true,
    );
  }
}

/// Una pieza dibujada del modelo: sus trazados ya convertidos en [Path].
class Figura {
  const Figura({
    required this.partes,
    required this.completo,
    required this.area,
    required this.limites,
  });

  /// Un [Path] por trazado, con los reflejos ya generados.
  ///
  /// El toque se prueba **parte a parte** y no contra [completo]: reflejar
  /// invierte el sentido de giro del trazado, y con el relleno `nonZero` dos
  /// subtrazados de sentidos opuestos que llegaran a solaparse se anularían y
  /// `contains` diría que no dentro de la propia región.
  final List<Path> partes;

  /// Todas las partes en un solo [Path], que es como se pinta de una vez.
  final Path completo;

  /// Suma de las áreas de las partes.
  ///
  /// Es lo que desempata cuando dos regiones se solapan, y tiene que ser el
  /// área y no el rectángulo que las envuelve: el pectoral son dos polígonos
  /// separados por el esternón, así que su rectángulo abarca el torso entero y
  /// desempatar con él elegiría siempre mal.
  final double area;

  final Rect limites;

  bool contiene(Offset punto) {
    for (final parte in partes) {
      if (parte.contains(punto)) return true;
    }
    return false;
  }
}

/// El modelo completo: las dos caras y el lienzo en el que están dibujadas.
class MapaCuerpo<K> {
  const MapaCuerpo({required this.lienzo, required this.caras});

  final Size lienzo;
  final Map<String, CaraCuerpo<K>> caras;
}

/// Una cara del modelo: la silueta y sus regiones.
class CaraCuerpo<K> {
  const CaraCuerpo({
    required this.silueta,
    required this.regiones,
    required this.luces,
    required this.sombras,
  });

  final Figura silueta;
  final Map<K, Figura> regiones;

  /// Trazados de luz y de sombra, que se pintan encima del color base a baja
  /// opacidad. Es lo que da volumen sin geometría de verdad.
  final Map<K, Figura> luces;
  final Map<K, Figura> sombras;
}

// ── Construcción ─────────────────────────────────────────────────────────────

/// Construye una figura desde sus trazados, reflejando los que lo pidan.
///
/// [anchoEspejo] es el ancho del lienzo: el reflejo es `x' = ancho − x`.
Figura construirFigura(List<Trazado> trazados, {required double anchoEspejo}) {
  final partes = <Path>[];
  var area = 0.0;
  for (final trazado in trazados) {
    partes.add(_aPath(trazado));
    area += areaTrazado(trazado);
    if (trazado.espejo) {
      final reflejo = _reflejar(trazado, anchoEspejo);
      partes.add(_aPath(reflejo));
      area += areaTrazado(reflejo);
    }
  }
  // El combinado se hace con una **unión** y no acumulando subtrazados: al
  // reflejar, las dos mitades comparten el borde de la línea media, y sumarlas
  // sin más deja ese borde dentro del contorno, que se pinta como una raya
  // vertical por mitad del cuerpo. La unión también funde el brazo con el
  // torso, que se solapan en la axila.
  var completo = Path();
  for (final parte in partes) {
    completo = Path.combine(PathOperation.union, completo, parte);
  }
  return Figura(
    partes: partes,
    completo: completo,
    area: area,
    limites: completo.getBounds(),
  );
}

Path _aPath(Trazado trazado) {
  final path = Path()..moveTo(trazado.inicio.dx, trazado.inicio.dy);
  for (final c in trazado.curvas) {
    path.cubicTo(c.c1.dx, c.c1.dy, c.c2.dx, c.c2.dy, c.fin.dx, c.fin.dy);
  }
  return path..close();
}

Trazado _reflejar(Trazado trazado, double ancho) {
  Offset refleja(Offset p) => Offset(ancho - p.dx, p.dy);
  return Trazado(
    inicio: refleja(trazado.inicio),
    curvas: [
      for (final c in trazado.curvas)
        Curva(refleja(c.c1), refleja(c.c2), refleja(c.fin)),
    ],
  );
}

/// El área que encierra un trazado, por la fórmula del cordón sobre sus
/// extremos. Siempre positiva: el sentido de giro no importa aquí.
double areaTrazado(Trazado trazado) {
  final puntos = <Offset>[
    trazado.inicio,
    for (final c in trazado.curvas) c.fin,
  ];
  var suma = 0.0;
  for (var i = 0; i < puntos.length; i++) {
    final a = puntos[i];
    final b = puntos[(i + 1) % puntos.length];
    suma += a.dx * b.dy - b.dx * a.dy;
  }
  return suma.abs() / 2;
}

/// Carga el mapa desde el JSON del asset, ya convertido en [Path].
///
/// [clave] traduce el nombre de una región del fichero a la clave que use quien
/// llama; devolver `null` descarta esa región, de modo que un nombre que sobre
/// en el JSON no revienta la carga.
MapaCuerpo<K> cargarMapa<K>(
  Map<String, dynamic> json,
  K? Function(String nombre) clave,
) {
  final lienzo = (json['lienzo'] as List).cast<num>();
  final ancho = lienzo[0].toDouble();

  List<Trazado> trazados(Object? valor) => [
    for (final t in (valor as List? ?? const []))
      Trazado.desdeJson(t as Map<String, dynamic>),
  ];

  Map<K, Figura> figuras(Map<String, dynamic> regiones, String parte) {
    final salida = <K, Figura>{};
    for (final MapEntry(key: nombre, value: datos) in regiones.entries) {
      final k = clave(nombre);
      if (k == null) continue;
      final lista = trazados((datos as Map<String, dynamic>)[parte]);
      if (lista.isEmpty) continue;
      salida[k] = construirFigura(lista, anchoEspejo: ancho);
    }
    return salida;
  }

  final caras = <String, CaraCuerpo<K>>{};
  for (final MapEntry(key: nombre, value: cara)
      in (json['vistas'] as Map<String, dynamic>).entries) {
    final datos = cara as Map<String, dynamic>;
    final regiones = datos['regiones'] as Map<String, dynamic>;
    caras[nombre] = CaraCuerpo<K>(
      silueta: construirFigura(trazados(datos['silueta']), anchoEspejo: ancho),
      regiones: figuras(regiones, 'trazados'),
      luces: figuras(regiones, 'luz'),
      sombras: figuras(regiones, 'sombra'),
    );
  }

  return MapaCuerpo<K>(lienzo: Size(ancho, lienzo[1].toDouble()), caras: caras);
}

// ── Encaje y toque ───────────────────────────────────────────────────────────

/// Cómo se coloca el lienzo del dibujo dentro del hueco que le da la pantalla.
class Encaje {
  const Encaje({required this.escala, required this.desplazamiento});

  /// El encaje que mete [lienzo] dentro de [destino] sin deformarlo, centrado.
  factory Encaje.contener({required Size destino, required Size lienzo}) {
    final escala =
        (destino.width / lienzo.width) < (destino.height / lienzo.height)
        ? destino.width / lienzo.width
        : destino.height / lienzo.height;
    return Encaje(
      escala: escala,
      desplazamiento: Offset(
        (destino.width - lienzo.width * escala) / 2,
        (destino.height - lienzo.height * escala) / 2,
      ),
    );
  }

  final double escala;
  final Offset desplazamiento;

  /// Un punto de la pantalla llevado a coordenadas del lienzo.
  Offset aLienzo(Offset local) => (local - desplazamiento) / escala;

  /// Una distancia de pantalla en unidades del lienzo.
  ///
  /// Es fácil de olvidar y no se nota hasta que se toca con el dedo: 12 px de
  /// pantalla son unos 57 del lienzo, así que pasar los 12 tal cual dejaría la
  /// tolerancia en nada.
  double aLienzoDistancia(double px) => px / escala;
}

/// Ocho direcciones para perdonar el dedo alrededor del punto tocado.
const _direcciones = 8;

/// Qué figura de [figuras] se ha tocado en [punto], o `null` si ninguna.
///
/// 1. Si varias lo contienen gana la de **menor área**: las regiones pequeñas
///    están encima y son las difíciles de acertar con el dedo.
/// 2. Si ninguna lo contiene se prueba en un anillo de [tolerancia] alrededor.
/// 3. Si sigue sin haber ninguna, `null`: tocar fuera del cuerpo no hace nada.
///
/// [tolerancia] va en unidades del lienzo, no de pantalla (ver
/// [Encaje.aLienzoDistancia]).
K? figuraEn<K>(Map<K, Figura> figuras, Offset punto, {double tolerancia = 0}) {
  final directo = _menorQueContiene(figuras, punto);
  if (directo != null || tolerancia <= 0) return directo;

  for (final radio in [tolerancia / 2, tolerancia]) {
    K? mejor;
    var menor = double.infinity;
    for (var i = 0; i < _direcciones; i++) {
      final angulo = 2 * math.pi * i / _direcciones;
      final cerca =
          punto + Offset(radio * math.cos(angulo), radio * math.sin(angulo));
      final clave = _menorQueContiene(figuras, cerca);
      if (clave != null && figuras[clave]!.area < menor) {
        menor = figuras[clave]!.area;
        mejor = clave;
      }
    }
    if (mejor != null) return mejor;
  }
  return null;
}

K? _menorQueContiene<K>(Map<K, Figura> figuras, Offset punto) {
  K? mejor;
  var menor = double.infinity;
  for (final MapEntry(key: clave, value: figura) in figuras.entries) {
    if (figura.area < menor && figura.contiene(punto)) {
      menor = figura.area;
      mejor = clave;
    }
  }
  return mejor;
}
