import flet as ft
from app.utils.widgetFactory import WidgetFactory
from app.utils.conexionBD import ConexionBD

class ResultadoRutinaScreen:
    def __init__(self, page: ft.Page, id_rutina):
        self.page = page
        self.widget_factory = WidgetFactory()
        self.conexion = ConexionBD()
        self.id_rutina = id_rutina

    def mostrar(self):
        self.page.controls.clear()
        self.page.add(self.widget_factory.create_appBar())

        nombreRutina = self.conexion.select_NombreRutina(self.id_rutina).nombre

        titulo = self.widget_factory.label_title("Resultados "+ nombreRutina)

        separadorSup = ft.Divider(height=20, thickness=0)

        container_ejerciciosRutina = self.widget_factory.create_containerEjercicios(id_rutina=self.id_rutina, 
                                                                                        on_click_ejercicio=self.go_resultadoEjercicio)
        separadorInf = ft.Divider(height=20, thickness=0)

        boton_volver = self.widget_factory.button_icon(icon=ft.Icons.ARROW_BACK, color="blue", on_click=self.go_back)

        self.page.add(titulo, 
                        separadorSup,
                        container_ejerciciosRutina,
                        separadorInf,
                        boton_volver)

        
    def go_back(self, e):
        from app.screens.screensResultados.resultadosScreen import ResultadosScreen
        app = ResultadosScreen(self.page)
        app.mostrar()

    def go_resultadoEjercicio(self, e, id_ejercicio):
        from app.screens.screensResultados.resultadoEjercicioScreen import ResultadoEjercicioScreen
        app = ResultadoEjercicioScreen(self.page, self.id_rutina, id_ejercicio)
        app.mostrar()
