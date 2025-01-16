import flet as ft
from app.utils.widgetFactory import WidgetFactory
from app.screens.screensRutinas.newRutinaScreen import NewRutinaScreen
from app.utils.conexionBD import ConexionBD

class RutinasScreen:
    def __init__(self, page: ft.Page):
        self.page = page
        self.widget_factory = WidgetFactory()
        self.conexion = ConexionBD()
        self.is_delete_mode = False

    def mostrar(self):
        """Muestra la página de Rutinas."""
        self.page.controls.clear()
        self.page.add(self.widget_factory.create_appBar())

        titulo = self.widget_factory.label_title("Página de Rutinas")

        separadorSup = ft.Divider(height=20, thickness=0)

        if self.is_delete_mode:
            containerRutinas = self.widget_factory.create_containerRutinas(on_click_rutina=self.go_deleteRutina)
        else:
            containerRutinas = self.widget_factory.create_containerRutinas(on_click_rutina=self.go_rutina)

        separadorInf = ft.Divider(height=20, thickness=0)

        row_buttons = ft.Row(
            controls=[self.widget_factory.button_icon(icon=ft.Icons.ARROW_BACK, color="blue", on_click=self.go_back), 
                      self.widget_factory.button_icon(icon=ft.Icons.ADD_CIRCLE, color="blue", on_click=self.go_newRutina),
                      self.widget_factory.button_icon(icon=ft.Icons.RESTORE_FROM_TRASH_ROUNDED, color="grey", on_click=self.go_changeMode_DeleteRutina, bgcolor="red") if self.is_delete_mode else self.widget_factory.button_icon(icon=ft.Icons.RESTORE_FROM_TRASH_ROUNDED, color="blue", on_click=self.go_changeMode_DeleteRutina)],
            spacing=40,
            alignment=ft.MainAxisAlignment.CENTER,   # Centrar horizontalmente
        )


        self.page.add(titulo, 
                        separadorSup,
                        containerRutinas, 
                        separadorInf, 
                        row_buttons)
        self.page.update()


    def go_back(self, e):
        """Vuelve a la página principal."""
        from app.screens.mainScreen import MainScreen
        app = MainScreen(self.page)
        app.iniciar()

    def go_rutina(self, e, id_rutina):
        from app.screens.screensRutinas.infoRutinaScreen import InfoRutinaScreen
        app = InfoRutinaScreen(self.page, id_rutina)
        app.mostrar()

    def go_newRutina(self, e):
        app = NewRutinaScreen(self.page)
        app.mostrar()

    def go_changeMode_DeleteRutina(self, e):
        self.is_delete_mode = not self.is_delete_mode # cambia el modo entre borrar y no borrar
        self.mostrar()

    def go_deleteRutina(self, e, id_rutina):
        self.conexion.delete_rutina(id_rutina)
        self.go_changeMode_DeleteRutina(e)
