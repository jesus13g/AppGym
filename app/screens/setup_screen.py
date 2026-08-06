"""Primer arranque: descarga de las imágenes y animaciones de los ejercicios."""

import flet as ft

from app.theme import tokens as t
from app.theme import ui
from app.utils import media
from app.utils.seed import cargar_json


def vista(page, router):
    ejercicios = cargar_json()
    pendientes = len(media.rutas_pendientes(ejercicios))
    estado = {"descargando": False, "cancelado": False, "salido": False}

    barra_progreso = ft.ProgressBar(value=0, color=t.ACENTO, bgcolor=t.RELLENO,
                                    border_radius=t.RADIO_S, height=6, visible=False)
    detalle = ui.texto("", size=t.FOOTNOTE, color=t.TEXTO_SEC, align=ft.TextAlign.CENTER)

    def entrar(_=None):
        # La descarga corre en un hilo aparte, así que puede intentar entrar a la
        # vez que el usuario pulsa "Ahora no": solo vale la primera.
        if estado["salido"]:
            return
        estado["salido"] = True
        router.reemplazar("rutinas")

    def omitir(_=None):
        estado["cancelado"] = True
        entrar()

    def descargar(_=None):
        if estado["descargando"]:
            return
        estado["descargando"] = True
        boton_descargar.disabled = True
        boton_descargar.content.controls[-1].value = "Descargando…"
        barra_progreso.visible = True
        detalle.value = f"0 de {pendientes} archivos"
        page.update()
        page.run_thread(trabajo)

    def progreso(hechos, total, fallos):
        barra_progreso.value = hechos / total if total else 1
        sufijo = f" · {fallos} fallidos" if fallos else ""
        detalle.value = f"{hechos} de {total} archivos{sufijo}"
        try:
            page.update()
        except Exception:
            pass  # la página puede haberse cerrado a mitad de descarga

    def trabajo():
        hechos, total, fallos = media.descargar_todo(
            ejercicios,
            al_progresar=progreso,
            cancelado=lambda: estado["cancelado"],
        )
        if fallos:
            detalle.value = (f"{fallos} archivos no se pudieron descargar. "
                             "Se cargarán desde internet cuando hagan falta.")
            page.update()
        entrar()

    boton_descargar = ui.boton_principal("Descargar ahora", descargar,
                                         icono=ft.CupertinoIcons.CLOUD_DOWNLOAD)
    boton_omitir = ui.boton_texto("Ahora no", omitir, color=t.TEXTO_SEC)

    if pendientes == 0:
        # Nada que descargar (p. ej. se usó tools/fetch_media.py antes de abrir la app).
        return ft.View(
            controls=[ui.estado_vacio(
                ft.CupertinoIcons.CHECK_MARK_CIRCLED,
                "Todo listo",
                "El catálogo de ejercicios ya está descargado.",
                accion=ui.boton_principal("Empezar", entrar),
            )],
            padding=0,
        )

    megas = pendientes * 50 // 1024  # media ponderada aproximada entre JPG y GIF

    contenido = ft.Column(
        [
            ft.Container(
                width=88, height=88, bgcolor=t.ACENTO, border_radius=t.RADIO_XL,
                alignment=ft.alignment.center,
                content=ft.Icon(ft.CupertinoIcons.SPARKLES, size=44, color=ft.Colors.WHITE),
            ),
            ft.Container(height=t.S),
            ui.texto("1.324 ejercicios listos", size=t.TITLE1, weight=t.BOLD,
                     align=ft.TextAlign.CENTER),
            ft.Container(
                width=300,
                content=ui.texto(
                    "AppGym incluye un catálogo con instrucciones en español, "
                    "músculos implicados y una animación de cada movimiento.",
                    size=t.SUBHEAD, color=t.TEXTO_SEC, align=ft.TextAlign.CENTER),
            ),
            ft.Container(height=t.L),
            ft.Container(
                width=320,
                content=ui.grupo([
                    ui.fila("Imágenes y animaciones",
                            subtitulo=f"{pendientes} archivos · unos {megas} MB",
                            izquierda=ft.Icon(ft.CupertinoIcons.PHOTO_ON_RECTANGLE,
                                              color=t.ACENTO, size=24),
                            chevron=False),
                ], sangria=0),
            ),
            ft.Container(height=t.L),
            ft.Container(content=barra_progreso, width=300),
            detalle,
            ft.Container(height=t.L),
            ft.Container(content=boton_descargar, width=300),
            boton_omitir,
            ft.Container(
                width=300,
                content=ui.texto(
                    "Si lo omites, la app funciona igual y las imágenes se cargarán "
                    "desde internet cuando las necesites.",
                    size=t.CAPTION, color=t.TEXTO_TER, align=ft.TextAlign.CENTER),
            ),
            ft.Container(height=t.L),
            ui.texto(media.ATRIBUCION, size=t.CAPTION, color=t.TEXTO_TER,
                     align=ft.TextAlign.CENTER),
        ],
        spacing=t.S,
        horizontal_alignment=ft.CrossAxisAlignment.CENTER,
        alignment=ft.MainAxisAlignment.CENTER,
        scroll=ft.ScrollMode.AUTO,
        expand=True,
    )

    return ft.View(
        controls=[ft.SafeArea(
            ft.Container(content=contenido, padding=ft.padding.all(t.XL), expand=True),
            expand=True,
        )],
        padding=0,
    )
