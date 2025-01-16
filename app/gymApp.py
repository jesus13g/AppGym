from .screens.mainScreen import MainScreen
import flet as ft
from app.utils.conexionBD import ConexionBD

class GymApp:
    def __init__(self, page: ft.Page):
        self.page = page
        self.page.scroll = "auto"
        self.main_screen = MainScreen(self.page)

        self.conexion = ConexionBD()
        #self.conexion.delete_all()
        self.conexion.create_tablas()

    def run(self):
        self.main_screen.iniciar()  # Llama al método para configurar la pantalla.