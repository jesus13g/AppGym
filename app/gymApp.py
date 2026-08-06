import flet as ft

from app.router import Router
from app.theme import tokens as t
from app.utils import media
from app.utils.conexionBD import ConexionBD
from app.utils.seed import seed_catalogo


class GymApp:
    def __init__(self, page: ft.Page):
        self.page = page
        self.conexion = ConexionBD()

    def run(self):
        self._configurar_pagina()

        self.conexion.create_tablas()
        seed_catalogo(self.conexion)

        router = Router(self.page)
        # El onboarding solo aparece mientras falte media por descargar.
        if media.descarga_completa():
            router.reemplazar("rutinas")
        else:
            router.reemplazar("setup")

    def _configurar_pagina(self):
        self.page.title = "AppGym"
        self.page.theme = t.tema_claro()
        self.page.dark_theme = t.tema_oscuro()
        self.page.theme_mode = ft.ThemeMode.SYSTEM
        self.page.bgcolor = t.FONDO
        self.page.padding = 0
        self.page.spacing = 0
        self.page.window.width = 390   # tamaño de un iPhone 14
        self.page.window.height = 844
