#!/usr/bin/env python3
"""Genera assets/musculatura.json, el modelo anatomico del mapa muscular.

    python3 tool/musculatura.py

Escribe el asset y, al lado, un `previa.svg` y un `previa.html` para mirar el
resultado (las regiones salen coloreadas y con su nombre). El dibujo es original
de este repositorio; ver la nota de licencia del README.

Por que existe este fichero y no se edita el JSON a mano: el JSON son treinta y
tantos kilobytes de coordenadas y ahi no se puede mover un musculo. Aqui cada
region es una lista de anclas, y una spline cerrada (Catmull-Rom -> Bezier
cubica) las convierte en curvas suaves, de modo que retocar el dibujo es mover
puntos. La luz y la sombra se derivan encogiendo cada poligono hacia dos focos
opuestos: es lo que da el volumen pseudo-3D sin geometria de verdad.

Tras tocar nada de esto hay que volver a ejecutarlo y pasar `flutter test`:
`test/geometria_test.dart` comprueba los invariantes del dibujo (toda region
dentro del cuerpo, ninguna fuera del lienzo, ninguna tapada al toque por otra).
"""

import json
import os

LIENZO = (1000, 2000)


# ── Spline cerrada ───────────────────────────────────────────────────────────

def spline(puntos, tension=1.0):
    """Convierte anclas en una lista de segmentos cubicos cerrada."""
    n = len(puntos)
    segmentos = []
    for i in range(n):
        p0 = puntos[(i - 1) % n]
        p1 = puntos[i]
        p2 = puntos[(i + 1) % n]
        p3 = puntos[(i + 2) % n]
        c1 = (p1[0] + (p2[0] - p0[0]) / 6 * tension,
              p1[1] + (p2[1] - p0[1]) / 6 * tension)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6 * tension,
              p2[1] - (p3[1] - p1[1]) / 6 * tension)
        segmentos.append([r(c1[0]), r(c1[1]), r(c2[0]), r(c2[1]),
                          r(p2[0]), r(p2[1])])
    return {"i": [r(puntos[0][0]), r(puntos[0][1])], "c": segmentos}


def r(v):
    return round(v, 1)


def trazado(puntos, espejo=False, tension=1.0):
    t = spline(puntos, tension)
    if espejo:
        t["espejo"] = True
    return t


def centroide(puntos):
    return (sum(p[0] for p in puntos) / len(puntos),
            sum(p[1] for p in puntos) / len(puntos))


def encoger(puntos, factor, hacia):
    """Encoge el poligono hacia un foco desplazado desde su centroide."""
    cx, cy = centroide(puntos)
    ancho = max(p[0] for p in puntos) - min(p[0] for p in puntos)
    alto = max(p[1] for p in puntos) - min(p[1] for p in puntos)
    fx = cx + hacia[0] * ancho
    fy = cy + hacia[1] * alto
    return [(fx + (p[0] - fx) * factor, fy + (p[1] - fy) * factor)
            for p in puntos]


def mover(puntos, dx=0, dy=0):
    return [(p[0] + dx, p[1] + dy) for p in puntos]


def region(puntos, espejo=True, sombreado=True):
    """Una region con su luz y su sombra derivadas."""
    datos = {"trazados": [trazado(puntos, espejo)]}
    if sombreado:
        # La luz viene de arriba a la izquierda del lienzo; en las piezas
        # espejadas se invierte sola al reflejarse.
        datos["luz"] = [trazado(encoger(puntos, 0.52, (-0.16, -0.20)), espejo)]
        datos["sombra"] = [trazado(encoger(puntos, 0.62, (0.18, 0.22)), espejo)]
    return datos


# ── Silueta ──────────────────────────────────────────────────────────────────
#
# Media silueta (cabeza, tronco y pierna) que se cierra por la linea media, mas
# el brazo como pieza aparte. Las dos se espejan, asi que el cuerpo es simetrico
# por construccion y no por pulso.

CABEZA_TRONCO_PIERNA = [
    (500, 40), (566, 50), (614, 94), (624, 162), (614, 230), (578, 268),
    (558, 282), (554, 320), (576, 332), (632, 352), (676, 376), (706, 400),
    (700, 438), (678, 466), (662, 522), (652, 596), (640, 668), (622, 730),
    (612, 776), (624, 818), (648, 862), (664, 906), (670, 962), (662, 1046),
    (648, 1152), (634, 1258), (626, 1340), (628, 1404), (636, 1476),
    (632, 1560), (618, 1656), (602, 1750), (592, 1818), (588, 1858),
    (614, 1878), (638, 1898), (636, 1922), (600, 1932), (556, 1930),
    (526, 1922), (518, 1896), (522, 1846), (528, 1782), (536, 1690),
    (542, 1584), (540, 1490), (534, 1400), (530, 1300), (524, 1160),
    (516, 1030), (500, 940), (500, 700), (500, 400), (500, 200),
]

# El brazo cae pegado al costado: su borde interno se mete dentro del tronco a
# la altura de la axila, porque las dos piezas se unen al rellenar y un hueco
# entre brazo y torso se ve enseguida.
BRAZO = [
    (694, 386), (734, 406), (754, 452), (760, 512), (764, 580), (770, 654),
    (772, 722), (780, 776), (792, 826), (806, 890), (814, 950), (812, 1004),
    (816, 1042), (834, 1082), (838, 1140), (820, 1182), (798, 1198),
    (778, 1180), (768, 1132), (762, 1078), (758, 1040), (748, 1000),
    (736, 952), (720, 896), (706, 842), (692, 792), (676, 740), (656, 672),
    (648, 596), (652, 520), (660, 462), (672, 414),
]

SILUETA = [trazado(CABEZA_TRONCO_PIERNA, espejo=True),
           trazado(BRAZO, espejo=True)]


# Piezas que comparten las dos caras: el hombro y el brazo se dibujan igual por
# delante y por detrás, y solo cambia el músculo que se les pinta encima.

HOMBRO = [(690, 388), (738, 414), (762, 468), (758, 532),
          (724, 552), (692, 510), (676, 450)]
HOMBRO_POST = [(702, 442), (744, 466), (752, 518), (726, 544), (700, 512)]
BRAZO_ALTO = [(692, 542), (734, 556), (756, 608), (760, 674),
              (738, 724), (706, 718), (688, 652), (684, 586)]
ANTEBRAZO = [(708, 828), (752, 838), (798, 890), (820, 962),
             (820, 1032), (790, 1042), (758, 980), (728, 900)]


# ── Vista frontal ────────────────────────────────────────────────────────────

FRENTE = {
    # Esternocleidomastoideo: la banda que baja de la oreja a la clavicula.
    "cuello": region([(530, 278), (546, 294), (552, 324), (544, 346),
                      (524, 342), (518, 306)]),
    "trapecio": region([(516, 300), (566, 318), (632, 344), (694, 392),
                        (656, 388), (592, 360), (528, 340)]),
    "deltoides": region(mover(HOMBRO, -10)),
    "pectoral": region([(506, 414), (566, 402), (630, 406), (678, 434),
                        (694, 484), (668, 538), (598, 558), (536, 550),
                        (508, 516)]),
    "biceps": region(mover(BRAZO_ALTO, -12)),
    "antebrazo": region(mover(ANTEBRAZO, -16)),
    # El recto del abdomen cruza la linea media, asi que no se espeja.
    "abdomen": region([(452, 578), (500, 566), (548, 578), (566, 656),
                       (566, 742), (546, 798), (500, 814), (454, 798),
                       (434, 742), (434, 656)], espejo=False),
    "oblicuo": region([(568, 598), (614, 626), (638, 690), (634, 760),
                       (602, 802), (572, 788), (566, 700)]),
    "flexorCadera": region([(522, 822), (578, 838), (608, 882), (594, 920),
                            (546, 914), (516, 872)]),
    "abductor": region([(624, 862), (664, 890), (674, 946), (660, 1000),
                        (632, 990), (618, 930)]),
    "cuadriceps": region([(558, 946), (626, 958), (650, 1036), (646, 1154),
                          (622, 1280), (586, 1330), (556, 1296), (546, 1180),
                          (550, 1044)]),
    "aductor": region([(508, 930), (548, 948), (568, 1020), (560, 1120),
                       (540, 1190), (520, 1168), (512, 1048)]),
    "gemelo": region([(568, 1398), (616, 1408), (634, 1496), (624, 1598),
                      (596, 1644), (574, 1600), (564, 1500)]),
    "tibial": region([(532, 1430), (558, 1454), (566, 1580), (558, 1716),
                      (544, 1788), (528, 1776), (526, 1618)]),
}


# ── Vista dorsal ─────────────────────────────────────────────────────────────

ESPALDA = {
    "cuello": region([(506, 282), (540, 290), (550, 318), (542, 348),
                      (506, 352), (512, 316)]),
    # El trapecio dorsal es el yugo de la nuca a los hombros. Se queda en la
    # parte alta: por debajo mandan romboides y dorsal, y un rombo hasta media
    # espalda se los tragaría a los dos.
    "trapecio": region([(500, 286), (560, 312), (634, 346), (674, 392),
                        (642, 428), (580, 448), (540, 472), (500, 480),
                        (460, 472), (420, 448), (358, 428), (326, 392),
                        (366, 346), (440, 312)], espejo=False),
    "deltoides": region(mover(HOMBRO, -10)),
    # El deltoides posterior va encima y es mas pequeno: en el desempate por
    # area gana el, que es justo lo que se busca.
    "deltoidesPost": region(mover(HOMBRO_POST, -10)),
    "triceps": region(mover(BRAZO_ALTO, -12)),
    "antebrazo": region(mover(ANTEBRAZO, -16)),
    "espaldaAlta": region([(506, 488), (568, 488), (604, 526), (596, 584),
                           (552, 606), (506, 602)]),
    "dorsal": region([(560, 502), (630, 526), (662, 592), (648, 674),
                      (598, 728), (558, 706), (548, 612)]),
    "lumbar": region([(500, 624), (558, 646), (574, 704), (566, 766),
                      (500, 792), (434, 766), (426, 704), (442, 646)],
                     espejo=False),
    "gluteo": region([(508, 798), (578, 812), (628, 858), (638, 930),
                      (600, 974), (536, 968), (508, 908)]),
    "isquiotibial": region([(542, 978), (624, 990), (648, 1080), (638, 1212),
                            (608, 1312), (566, 1320), (544, 1200),
                            (536, 1080)]),
    "gemelo": region([(546, 1396), (608, 1406), (632, 1498), (620, 1612),
                      (586, 1670), (556, 1638), (542, 1518)]),
}


MAPA = {
    "lienzo": list(LIENZO),
    "vistas": {
        "frente": {"silueta": SILUETA, "regiones": FRENTE},
        "espalda": {"silueta": SILUETA, "regiones": ESPALDA},
    },
}


# ── Salida ───────────────────────────────────────────────────────────────────

def d_de(t):
    x, y = t["i"]
    partes = [f"M {x} {y}"]
    for c in t["c"]:
        partes.append("C " + " ".join(str(v) for v in c))
    partes.append("Z")
    return " ".join(partes)


def espejar(t):
    x, y = t["i"]
    return {"i": [1000 - x, y],
            "c": [[1000 - c[0], c[1], 1000 - c[2], c[3], 1000 - c[4], c[5]]
                  for c in t["c"]]}


COLORES = ["#e57373", "#f06292", "#ba68c8", "#9575cd", "#7986cb", "#64b5f6",
           "#4fc3f7", "#4dd0e1", "#4db6ac", "#81c784", "#aed581", "#dce775",
           "#ffd54f", "#ffb74d", "#ff8a65", "#a1887f"]


def svg(vista, titulo):
    partes = [f'<g><text x="20" y="40" font-size="34" fill="#333">{titulo}</text>']
    for t in vista["silueta"]:
        for tt in ([t, espejar(t)] if t.get("espejo") else [t]):
            partes.append(f'<path d="{d_de(tt)}" fill="#d8d8d8" stroke="#999" '
                          'stroke-width="2"/>')
    for i, (nombre, datos) in enumerate(vista["regiones"].items()):
        color = COLORES[i % len(COLORES)]
        for clave, opacidad, relleno in (("trazados", 0.85, color),
                                         ("luz", 0.35, "#ffffff"),
                                         ("sombra", 0.30, "#000000")):
            for t in datos.get(clave, []):
                for tt in ([t, espejar(t)] if t.get("espejo") else [t]):
                    borde = ' stroke="#555" stroke-width="1.5"' if clave == "trazados" else ""
                    partes.append(f'<path d="{d_de(tt)}" fill="{relleno}" '
                                  f'fill-opacity="{opacidad}"{borde}/>')
        # Etiqueta en el centroide del primer trazado.
        t = datos["trazados"][0]
        xs = [t["i"][0]] + [c[4] for c in t["c"]]
        ys = [t["i"][1]] + [c[5] for c in t["c"]]
        cx, cy = sum(xs) / len(xs), sum(ys) / len(ys)
        partes.append(f'<text x="{cx}" y="{cy}" font-size="26" fill="#111" '
                      f'text-anchor="middle">{nombre}</text>')
    partes.append("</g>")
    return "\n".join(partes)


def main():
    raiz = os.path.dirname(os.path.abspath(__file__))
    destino = "/home/user/AppGym/assets/musculatura.json"
    with open(destino, "w", encoding="utf-8") as f:
        json.dump(MAPA, f, ensure_ascii=False, separators=(",", ":"))
        f.write("\n")
    print(destino, os.path.getsize(destino), "bytes")

    cuerpo = (f'<svg xmlns="http://www.w3.org/2000/svg" width="1100" '
              f'height="1100" viewBox="0 0 2100 2000" '
              f'style="background:#fff">'
              f'{svg(MAPA["vistas"]["frente"], "FRENTE")}'
              f'<g transform="translate(1050,0)">'
              f'{svg(MAPA["vistas"]["espalda"], "ESPALDA")}</g></svg>')
    previa = os.path.join(raiz, "previa.svg")
    with open(previa, "w", encoding="utf-8") as f:
        f.write(cuerpo)
    with open(os.path.join(raiz, "previa.html"), "w", encoding="utf-8") as f:
        f.write(f"<html><body style='margin:0'>{cuerpo}</body></html>")
    print(previa)


if __name__ == "__main__":
    main()
