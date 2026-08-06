"""Ficha de un ejercicio del catálogo: animación, músculos e instrucciones."""

import flet as ft

from app.theme import tokens as t
from app.theme import ui
from app.utils import formato, i18n, media


def vista(page, router, id_catalogo):
    ficha = router.conexion.get_catalogo(id_catalogo)
    if ficha is None:
        return ft.View(
            appbar=ui.barra("Ejercicio"),
            controls=[ui.estado_vacio(ft.CupertinoIcons.EXCLAMATIONMARK_TRIANGLE,
                                      "Ejercicio no encontrado")],
        )

    animacion = ft.Container(
        content=ft.Image(
            src=media.resolver(ficha.gif),
            fit=ft.ImageFit.CONTAIN,
            error_content=ft.Container(
                alignment=ft.alignment.center,
                content=ft.Icon(ft.CupertinoIcons.PHOTO, size=44, color=t.TEXTO_TER),
            ),
        ),
        height=240,
        bgcolor=ft.Colors.WHITE,
        border_radius=t.RADIO_L,
        clip_behavior=ft.ClipBehavior.ANTI_ALIAS,
        margin=ft.margin.symmetric(horizontal=t.L),
        alignment=ft.alignment.center,
    )

    etiquetas = ft.Container(
        content=ft.Row(
            [
                ui.pildora(i18n.musculo(ficha.target),
                           color=ft.Colors.WHITE,
                           relleno=t.ACENTO),
                ui.pildora(i18n.equipment(ficha.equipment)),
                ui.pildora(i18n.body_part(ficha.body_part)),
            ],
            spacing=t.S,
            wrap=True,
            run_spacing=t.S,
        ),
        padding=ft.padding.symmetric(horizontal=t.L, vertical=t.M),
    )

    secundarios = formato.lista_json(ficha.secondary_muscles)
    detalles = ui.grupo(
        [
            ui.fila("Músculo principal", valor=i18n.musculo(ficha.target), chevron=False),
            ui.fila("Grupo muscular", valor=i18n.musculo(ficha.muscle_group), chevron=False),
            ui.fila("Equipamiento", valor=i18n.equipment(ficha.equipment), chevron=False),
            ui.fila("Músculos secundarios",
                    subtitulo=", ".join(i18n.musculos(secundarios)) or "—",
                    chevron=False) if secundarios else None,
        ],
        cabecera="Detalles",
    )

    pasos = formato.lista_json(ficha.instrucciones)
    if pasos:
        instrucciones = ui.grupo(
            [_paso(i + 1, paso) for i, paso in enumerate(pasos)],
            cabecera="Cómo se hace",
        )
    else:
        instrucciones = ui.grupo(
            [ui.fila("Sin instrucciones disponibles", chevron=False)],
            cabecera="Cómo se hace",
        )

    atribucion = ft.Container(
        content=ui.texto(f"Animación e imagen: {media.ATRIBUCION}",
                         size=t.CAPTION, color=t.TEXTO_TER, align=ft.TextAlign.CENTER),
        padding=ft.padding.symmetric(horizontal=t.XL, vertical=t.XL),
    )

    cuerpo = ft.Column(
        [
            ft.Container(height=t.M),
            animacion,
            ft.Container(
                content=ui.texto(ficha.nombre, size=t.TITLE2, weight=t.BOLD),
                padding=ft.padding.only(left=t.L, right=t.L, top=t.L),
            ),
            etiquetas,
            detalles,
            ft.Container(height=t.XL),
            instrucciones,
            atribucion,
        ],
        spacing=0,
        scroll=ft.ScrollMode.AUTO,
        expand=True,
    )

    return ft.View(
        appbar=ui.barra(ficha.nombre),
        controls=[ft.SafeArea(cuerpo, expand=True)],
        padding=0,
    )


def _paso(numero, texto_paso):
    """Una instrucción numerada, con el número en un círculo azul."""
    return ft.Container(
        content=ft.Row(
            [
                ft.Container(
                    width=24, height=24, bgcolor=t.ACENTO, border_radius=12,
                    alignment=ft.alignment.center,
                    content=ui.texto(str(numero), size=t.CAPTION, weight=t.SEMIBOLD,
                                     color=ft.Colors.WHITE),
                ),
                ft.Container(content=ui.texto(texto_paso, size=t.SUBHEAD), expand=True),
            ],
            spacing=t.M,
            vertical_alignment=ft.CrossAxisAlignment.START,
        ),
        padding=ft.padding.symmetric(horizontal=t.L, vertical=t.M),
    )
