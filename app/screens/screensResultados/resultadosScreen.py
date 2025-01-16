import flet as ft
from app.utils.widgetFactory import WidgetFactory

class ResultadosScreen:
    def __init__(self, page: ft.Page):
        self.page = page
        self.widget_factory = WidgetFactory()

    def mostrar(self):
        """Muestra la página de Resultados."""
        self.page.controls.clear()
        self.page.add(self.widget_factory.create_appBar())

        titulo = self.widget_factory.label_title("Resultados rutinas") 

        separadorSup = ft.Divider(height=20, thickness=0)

        container_rutinas = self.widget_factory.create_containerRutinas(on_click_rutina=self.go_rutina)

        separadorInf = ft.Divider(height=20, thickness=0)

        row_buttons = ft.Row(
            controls=[self.widget_factory.button_icon(icon=ft.Icons.ARROW_BACK, color="blue", on_click=self.go_back),
                        self.widget_factory.button_icon(icon=ft.Icons.CALENDAR_MONTH, color="blue", on_click=self.go_calendario)],
            spacing=40,
            alignment=ft.MainAxisAlignment.CENTER,   # Centrar horizontalmente
        )

        self.page.add(titulo, 
                        separadorSup, 
                        container_rutinas, 
                        separadorInf,
                        row_buttons)
        self.page.update()

    def go_back(self, e):
        """Vuelve a la página principal."""
        from app.screens.mainScreen import MainScreen
        app = MainScreen(self.page)
        app.iniciar()


    def go_rutina(self, e, id_rutina):
        from app.screens.screensResultados.resultadoRutinaScreen import ResultadoRutinaScreen
        app = ResultadoRutinaScreen(self.page, id_rutina)
        app.mostrar()

    def go_calendario(self, e):
        from app.screens.screensResultados.calendarioScreen import CalendarioScreen
        app = CalendarioScreen(self.page)
        app.mostrar()