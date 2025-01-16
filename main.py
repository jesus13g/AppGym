import flet as ft
from app.gymApp import GymApp

# Ejecutar la app
if __name__ == "__main__":
    def main(page: ft.Page):
        app = GymApp(page)  # Pasa `page` al inicializar GymApp.
        app.run()           # Llama al método `run` de tu aplicación.

    ft.app(target=main)      # `main` recibe automáticamente el objeto `page`.
