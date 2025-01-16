import flet as ft
from app.utils.widgetFactory import WidgetFactory
from app.utils.conexionBD import ConexionBD
from datetime import datetime   

class AddEntrenamientoScreen:
    def __init__(self, page: ft.Page, id_rutina):
        self.page = page
        self.widget_factory = WidgetFactory()
        self.conexion = ConexionBD()
        self.id_rutina = id_rutina
        self.slider_values = {}

    def mostrar(self):
        self.page.controls.clear()
        self.page.add(self.widget_factory.create_appBar())

        titulo = self.widget_factory.label_title("Agregar Entrenamiento")

        containerEjercicios = self.widget_factory.create_containerEntrenamientoEjercicios(id_rutina=self.id_rutina,
                                                                                                slider_values=self.slider_values)

        row_buttons = ft.Row(
            controls=[self.widget_factory.button_icon(icon=ft.Icons.ARROW_BACK, color="blue", on_click=self.go_back), 
                      self.widget_factory.button_simple("Agregar", self.go_addEntrenamiento)],
            spacing=40,
            alignment=ft.MainAxisAlignment.CENTER,   # Centrar horizontalmente
        )

        self.page.add(titulo, 
                        containerEjercicios,
                        row_buttons)
        self.page.update()


    def go_back(self, e):
        from app.screens.screensRutinas.infoRutinaScreen import InfoRutinaScreen
        app = InfoRutinaScreen(self.page, self.id_rutina)
        app.mostrar()

    def go_addEntrenamiento(self, e):
        print(self.slider_values)
        self.conexion.insert_newEntrenamiento(id_rutina=self.id_rutina,
                                                fecha=datetime.now(),
                                                series=self.slider_values) 
        self.go_back(e)
            