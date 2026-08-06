"""Navegación de la app: pila de vistas, pestañas y transiciones estilo iOS.

Sustituye al esquema anterior, en el que cada pantalla hacía
`page.controls.clear()` y se repintaba entera: con una pila real de `ft.View`
funcionan el gesto de volver deslizando, el botón atrás de la barra y las
transiciones de empuje de Cupertino.
"""

import flet as ft

from app.theme import tokens as t
from app.utils.conexionBD import ConexionBD

# Pantallas raíz de cada pestaña, en el orden de la barra inferior.
PESTANAS = [
    ("rutinas", ft.CupertinoIcons.LIST_BULLET, "Rutinas"),
    ("catalogo", ft.CupertinoIcons.SEARCH, "Ejercicios"),
    ("progreso", ft.CupertinoIcons.CHART_BAR_ALT_FILL, "Progreso"),
]

# Rutas que se muestran como modal (suben desde abajo, con "Cancelar").
MODALES = {"anadir_ejercicio", "entrenar"}


class Destino:
    """Una entrada de la pila de navegación."""

    def __init__(self, pantalla, **params):
        self.pantalla = pantalla
        self.params = params

    @property
    def ruta(self):
        """Ruta legible, para la barra de direcciones en modo web."""
        sufijo = "/".join(str(v) for v in self.params.values())
        return f"/{self.pantalla}" + (f"/{sufijo}" if sufijo else "")


class Router:
    def __init__(self, page: ft.Page):
        self.page = page
        self.conexion = ConexionBD()
        self.pila = []
        page.on_view_pop = self._al_volver

    # ── Navegación ───────────────────────────────────────────────────────────

    def ir(self, pantalla, **params):
        """Apila una pantalla nueva encima de la actual."""
        self.pila.append(Destino(pantalla, **params))
        self._render()

    def reemplazar(self, pantalla, **params):
        """Sustituye toda la pila (cambio de pestaña o salida del onboarding)."""
        self.pila = [Destino(pantalla, **params)]
        self._render()

    def volver(self):
        """Quita la pantalla actual y repinta la anterior con datos frescos."""
        if len(self.pila) > 1:
            self.pila.pop()
            self._render()

    def refrescar(self):
        """Vuelve a construir la pantalla actual (tras crear o borrar algo)."""
        self._render()

    def cambiar_pestana(self, indice):
        self.reemplazar(PESTANAS[indice][0])

    @property
    def pestana_actual(self):
        """Índice de la pestaña a la que pertenece la pila actual, o None."""
        if not self.pila:
            return None
        raiz = self.pila[0].pantalla
        for i, (pantalla, _, _) in enumerate(PESTANAS):
            if pantalla == raiz:
                return i
        return None

    def _al_volver(self, _):
        self.volver()

    # ── Construcción de vistas ───────────────────────────────────────────────

    def _render(self):
        """Reconstruye la pila entera de vistas.

        Se rehace todo en cada navegación (la pila nunca pasa de tres niveles y
        las consultas son locales) para que al volver atrás la pantalla anterior
        muestre siempre los datos actualizados.
        """
        self.page.views.clear()
        for i, destino in enumerate(self.pila):
            vista = self._construir(destino)
            vista.route = destino.ruta
            vista.bgcolor = vista.bgcolor or t.FONDO
            if destino.pantalla in MODALES:
                vista.fullscreen_dialog = True
            # La barra de pestañas solo aparece en la raíz de la pila.
            if i == 0 and self.pestana_actual is not None:
                vista.navigation_bar = self._barra_pestanas()
            self.page.views.append(vista)
        self.page.route = self.pila[-1].ruta if self.pila else "/"
        self.page.update()

    def _barra_pestanas(self):
        return ft.CupertinoNavigationBar(
            selected_index=self.pestana_actual or 0,
            on_change=lambda e: self.cambiar_pestana(e.control.selected_index),
            bgcolor=t.BARRA,
            active_color=t.ACENTO,
            inactive_color=t.TEXTO_SEC,
            border=ft.border.only(top=ft.BorderSide(0.5, t.SEPARADOR)),
            destinations=[
                ft.NavigationBarDestination(icon=icono, label=etiqueta)
                for _, icono, etiqueta in PESTANAS
            ],
        )

    def _construir(self, destino):
        """Devuelve el `ft.View` de un destino.

        Los imports son perezosos para que las pantallas puedan importar el
        router sin ciclos.
        """
        from app.screens import (
            catalogo_screen,
            entrenar_screen,
            ficha_screen,
            progreso_screen,
            resultado_ejercicio_screen,
            resultado_rutina_screen,
            rutina_screen,
            rutinas_screen,
            setup_screen,
        )

        constructores = {
            "setup": setup_screen.vista,
            "rutinas": rutinas_screen.vista,
            "rutina": rutina_screen.vista,
            "anadir_ejercicio": catalogo_screen.vista_anadir,
            "catalogo": catalogo_screen.vista,
            "ficha": ficha_screen.vista,
            "entrenar": entrenar_screen.vista,
            "progreso": progreso_screen.vista,
            "resultado_rutina": resultado_rutina_screen.vista,
            "resultado_ejercicio": resultado_ejercicio_screen.vista,
        }

        constructor = constructores.get(destino.pantalla)
        if constructor is None:
            return ft.View(controls=[ft.Text(f"Pantalla desconocida: {destino.pantalla}")])
        return constructor(self.page, self, **destino.params)
