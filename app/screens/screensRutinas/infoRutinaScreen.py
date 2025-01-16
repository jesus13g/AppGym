import flet as ft
from app.utils.widgetFactory import WidgetFactory
from app.utils.conexionBD import ConexionBD

class InfoRutinaScreen:
    def __init__(self, page: ft.Page, id_rutina):
        self.page = page
        self.widget_factory = WidgetFactory()
        self.conexion = ConexionBD()
        self.id_rutina = id_rutina
        self.is_delete_mode = False

    def mostrar(self):
        """Muestra la página de Rutinas."""
        self.page.controls.clear()
        self.page.add(self.widget_factory.create_appBar())

        nombreRutina = self.conexion.select_NombreRutina(self.id_rutina).nombre

        titulo = self.widget_factory.label_title(nombreRutina)

        separadorSup = ft.Divider(height=20, thickness=0)

        if self.is_delete_mode:
            containerEjercicios = self.widget_factory.create_containerEjercicios(id_rutina=self.id_rutina, on_click_ejercicio=self.go_deleteEjercicio)
        else:
            containerEjercicios = self.widget_factory.create_containerEjercicios(id_rutina=self.id_rutina, on_click_ejercicio=self.go_ejercicio)

        separadorInf = ft.Divider(height=20, thickness=0)

        row_buttonsAdders = ft.Row(
            controls=[self.widget_factory.button_icon(icon=ft.Icons.ADD_CIRCLE, color="blue", on_click=self.go_addEjercicio),
                        self.widget_factory.button_simple("🏋️‍♂️", self.go_addEntrenamiento)],
            spacing=40,
            alignment=ft.MainAxisAlignment.CENTER,   # Centrar horizontalmente
        )

        row_buttonsActions = ft.Row(
            controls=[self.widget_factory.button_icon(icon=ft.Icons.ARROW_BACK, color="blue", on_click=self.go_back),
                      self.widget_factory.button_icon(icon=ft.Icons.RESTORE_FROM_TRASH_ROUNDED, color="gray", on_click=self.go_changeMode_DeleteRutina, bgcolor="red") if self.is_delete_mode else self.widget_factory.button_icon(icon=ft.Icons.RESTORE_FROM_TRASH_ROUNDED, color="blue", on_click=self.go_changeMode_DeleteRutina)],
            spacing=40,
            alignment=ft.MainAxisAlignment.CENTER,   # Centrar horizontalmente
        )

        self.page.add(titulo, 
                        separadorSup,
                        containerEjercicios,
                        separadorInf,
                        row_buttonsAdders,
                        row_buttonsActions)
        self.page.update()



    def go_back(self, e):
        """Vuelve a la página de Rutinas."""
        from app.screens.screensRutinas.rutinasScreen import RutinasScreen
        app = RutinasScreen(self.page)
        app.mostrar()

    def go_ejercicio(self, e, id_ejercicio):
        from app.screens.screensRutinas.infoEjercicioScreen import InfoEjercicioScreen
        app = InfoEjercicioScreen(self.page, id_ejercicio)
        app.mostrar()

    def go_addEjercicio(self, e):
        from app.screens.screensRutinas.addEjercicioScreen import AddEjercicioScreen
        app = AddEjercicioScreen(self.page, self.id_rutina)
        app.mostrar()

    def go_addEntrenamiento(self, e):
        from app.screens.screensRutinas.addEntrenamientoScreen import AddEntrenamientoScreen
        app = AddEntrenamientoScreen(self.page, self.id_rutina)
        app.mostrar()

    def go_changeMode_DeleteRutina(self, e):
        self.is_delete_mode = not self.is_delete_mode # cambia el modo entre borrar y no borrar
        self.mostrar()

    def go_deleteEjercicio(self, e, id_ejercicio):
        self.conexion.delete_ejercicio(self.id_rutina, id_ejercicio)
        self.go_changeMode_DeleteRutina(e)
    
    