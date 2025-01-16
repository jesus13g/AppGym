import flet as ft
from app.utils.widgetFactory import WidgetFactory
from app.utils.conexionBD import ConexionBD

class InfoEjercicioScreen:
    def __init__(self, Page: ft.Page, id_ejercicio):
        self.page = Page
        self.widget_factory = WidgetFactory()
        self.conexion = ConexionBD()
        self.id_ejercicio = id_ejercicio
        self.ejercicio = self.conexion.select_ejercicio(self.id_ejercicio)



    def mostrar(self):
        self.page.controls.clear()  
        self.page.add(self.widget_factory.create_appBar())

        titulo = self.widget_factory.label_title(self.ejercicio.nombre)

        separadorSup = ft.Divider(height=20, thickness=0)

        descripcion = self.widget_factory.label_simpleText(self.ejercicio.descripcion)

        buttonBack = self.widget_factory.button_icon(icon=ft.Icons.ARROW_BACK, color="blue", on_click=self.go_back)

        self.page.add(titulo, separadorSup, descripcion, buttonBack)

    def go_back(self, e):
        from app.screens.screensRutinas.infoRutinaScreen import InfoRutinaScreen
        app = InfoRutinaScreen(self.page, self.ejercicio.id_rutina)
        app.mostrar()