import flet as ft
from app.utils.widgetFactory import WidgetFactory
from app.screens.screensRutinas.rutinasScreen import RutinasScreen
from app.screens.screensResultados.resultadosScreen import ResultadosScreen

class MainScreen:
    def __init__(self, page: ft.Page):
        self.page = page
        self.widget_factory = WidgetFactory()

    def iniciar(self):
        """Inicializa la página principal de la app."""
        self.page.controls.clear()
        self.page.title = "Gym app"
        self.page.bgcolor =  "#2C2C2C" # "#2C2C2C" 
        self.page.window.width = 360  # Ancho aproximado en píxeles
        self.page.window.height = 800  # Altura aproximada en píxeles
        self.page.horizontal_alignment = ft.CrossAxisAlignment.CENTER
        self.page.add(self.widget_factory.create_appBar())

        titulo = self.widget_factory.label_title("App GYM")

        separadorSup = ft.Divider(height=20, thickness=0)
        separadorInf = ft.Divider(height=20, thickness=0)

        buttons_column = ft.Column(
            controls=[self.widget_factory.button_simple("Rutinas", self.go_pageRutinas), 
                      self.widget_factory.button_simple("Resultados", self.go_pageResultados)],
            spacing=40,
            horizontal_alignment=ft.CrossAxisAlignment.CENTER,  # Centrar horizontalmente
        )

        self.page.add(
            titulo,
            separadorSup,
            buttons_column,
            separadorInf    
            )

    def go_pageRutinas(self, e):
        rutinasScreen = RutinasScreen(self.page)
        rutinasScreen.mostrar()
        

    def go_pageResultados(self, e):
        resultadosScreen = ResultadosScreen(self.page)
        resultadosScreen.mostrar()
   
