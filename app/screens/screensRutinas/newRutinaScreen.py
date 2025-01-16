import flet as ft
from app.utils.widgetFactory import WidgetFactory
from app.utils.conexionBD import ConexionBD

class NewRutinaScreen:
    def __init__(self, page: ft.Page):
        self.page = page
        self.widget_factory = WidgetFactory()

    def mostrar(self):
        """Muestra la página de Rutinas."""
        self.page.controls.clear()
        self.page.add(self.widget_factory.create_appBar())

        titulo = self.widget_factory.label_title("Nueva Rutina")
        
        self.nombre_rutina = self.widget_factory.create_textInput("Nombre de la rutina")

        row_buttons = ft.Row(
            controls=[self.widget_factory.button_icon(icon=ft.Icons.ARROW_BACK, color="blue", on_click=self.go_back), 
                      self.widget_factory.button_simple("Guardar", self.guardar_rutina)],
            spacing=40,
            alignment=ft.MainAxisAlignment.CENTER,   # Centrar horizontalmente
        )

        self.page.add(titulo,
                        self.nombre_rutina,
                        row_buttons)
        self.page.update()

    def go_back(self, e):
        """Vuelve a la página de rutinas."""
        from app.screens.screensRutinas.rutinasScreen import RutinasScreen
        app = RutinasScreen(self.page)
        app.mostrar()

    def guardar_rutina(self, e):
        nombre_rutina = self.nombre_rutina.value
        conexion = ConexionBD()
        conexion.insert_newRutina(nombre_rutina)
        self.go_back(e)
        