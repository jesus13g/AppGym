import os

import flet as ft

from app.gymApp import GymApp


def main(page: ft.Page):
    GymApp(page).run()


if __name__ == "__main__":
    # APPGYM_WEB=1 abre la app en el navegador en lugar de en una ventana nativa.
    if os.getenv("APPGYM_WEB"):
        ft.app(target=main, view=ft.AppView.WEB_BROWSER,
               port=int(os.getenv("APPGYM_PORT", "8550")))
    else:
        ft.app(target=main)
