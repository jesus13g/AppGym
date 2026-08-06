"""Tokens de diseño: colores, espaciados, radios y tipografía estilo iOS.

Los colores son los semánticos de Cupertino, que en Flutter ya son adaptativos:
el mismo token se resuelve a un valor distinto en tema claro y oscuro, así que
no hace falta duplicar la paleta ni escuchar cambios de tema a mano.
"""

import flet as ft

# ── Colores ──────────────────────────────────────────────────────────────────
FONDO = ft.CupertinoColors.SYSTEM_GROUPED_BACKGROUND          # fondo de pantalla
TARJETA = ft.CupertinoColors.SECONDARY_SYSTEM_GROUPED_BACKGROUND  # fondo de las listas
BARRA = ft.CupertinoColors.SYSTEM_BACKGROUND                   # appbar y tab bar

TEXTO = ft.CupertinoColors.LABEL
TEXTO_SEC = ft.CupertinoColors.SECONDARY_LABEL
TEXTO_TER = ft.CupertinoColors.TERTIARY_LABEL
PLACEHOLDER = ft.CupertinoColors.PLACEHOLDER_TEXT

SEPARADOR = ft.CupertinoColors.SEPARATOR
RELLENO = ft.CupertinoColors.TERTIARY_SYSTEM_FILL             # fondo de campos y píldoras

ACENTO = ft.CupertinoColors.SYSTEM_BLUE
DESTRUCTIVO = ft.CupertinoColors.SYSTEM_RED
EXITO = ft.CupertinoColors.SYSTEM_GREEN

# Paleta con la que se colorean las rutinas (mismo orden que COLORES_RUTINA
# en app/utils/conexionBD.py).
PALETA_RUTINAS = ["#0A84FF", "#30D158", "#FF9F0A", "#FF375F",
                  "#BF5AF2", "#40C8E0", "#5E5CE6", "#FFD60A"]

# ── Espaciado ────────────────────────────────────────────────────────────────
XS = 4
S = 8
M = 12
L = 16
XL = 20
XXL = 28

# ── Radios ───────────────────────────────────────────────────────────────────
RADIO_S = 8
RADIO_M = 10
RADIO_L = 14
RADIO_XL = 22

# ── Tipografía (escala de iOS) ───────────────────────────────────────────────
LARGE_TITLE = 34
TITLE1 = 28
TITLE2 = 22
TITLE3 = 20
HEADLINE = 17
BODY = 17
CALLOUT = 16
SUBHEAD = 15
FOOTNOTE = 13
CAPTION = 12

SEMIBOLD = ft.FontWeight.W_600
BOLD = ft.FontWeight.W_700

# Alto mínimo de una fila táctil, según las guías de Apple.
ALTO_FILA = 44

# ── Temas de la página ───────────────────────────────────────────────────────

def _transiciones():
    """Transiciones de empuje estilo iOS en todas las plataformas."""
    return ft.PageTransitionsTheme(
        ios=ft.PageTransitionTheme.CUPERTINO,
        android=ft.PageTransitionTheme.CUPERTINO,
        macos=ft.PageTransitionTheme.CUPERTINO,
        windows=ft.PageTransitionTheme.CUPERTINO,
        linux=ft.PageTransitionTheme.CUPERTINO,
    )


def tema_claro():
    return ft.Theme(page_transitions=_transiciones(), font_family=None, use_material3=True)


def tema_oscuro():
    return ft.Theme(page_transitions=_transiciones(), font_family=None, use_material3=True)
