import flet as ft
from app.utils.widgetFactory import WidgetFactory
from app.utils.conexionBD import ConexionBD

class AddEjercicioScreen:
    def __init__(self, page: ft.Page, id_rutina):
        self.page = page
        self.widget_factory = WidgetFactory()
        self.conexion = ConexionBD()
        self.id_rutina = id_rutina

    def mostrar(self):
        self.page.controls.clear()
        self.page.add(self.widget_factory.create_appBar())

        titulo = self.widget_factory.label_title("Agregar Ejercicio")

        self.inputNombre = self.widget_factory.create_textInput("Nombre del ejercicio")

        self.inputDescrp = self.widget_factory.create_textInput("Descripción del ejercicio", height=200, multiline=True)

        row_buttons = ft.Row(
            controls=[self.widget_factory.button_icon(icon=ft.Icons.ARROW_BACK, color="blue", on_click=self.go_back), 
                      self.widget_factory.button_simple("Agregar", self.go_addEjercicio)],
            spacing=40,
            alignment=ft.MainAxisAlignment.CENTER,   # Centrar horizontalmente
        )

        self.page.add(titulo, 
                        self.inputNombre, 
                        self.inputDescrp,
                        row_buttons)
        self.page.update()


    def go_back(self, e):
        from app.screens.screensRutinas.infoRutinaScreen import InfoRutinaScreen
        app = InfoRutinaScreen(self.page, self.id_rutina)
        app.mostrar()
        

    def go_addEjercicio(self, e):
        nombre = self.inputNombre.value
        descripcion = self.inputDescrp.value
        self.conexion.insert_newEjercicio(self.id_rutina, nombre, descripcion)
        self.go_back(e)