"""Pestaña de progreso: resumen por rutina y calendario de entrenamientos."""

from datetime import date, datetime, timedelta

import flet as ft

from app.theme import tokens as t
from app.theme import ui
from app.utils import formato


def vista(page, router, pestana=0, mes=None, anio=None):
    """
    :param pestana: 0 = Resumen, 1 = Calendario
    :param mes/anio: mes visible del calendario (por defecto, el actual)
    """
    hoy = date.today()
    mes = mes or hoy.month
    anio = anio or hoy.year

    contenido = ft.Container(expand=True)

    def elegir(indice):
        # Se navega en la misma pila para conservar la pestaña seleccionada.
        router.pila[-1].params = {"pestana": indice, "mes": mes, "anio": anio}
        router.refrescar()

    selector = ft.Container(
        content=ft.CupertinoSlidingSegmentedButton(
            selected_index=pestana,
            on_change=lambda e: elegir(e.control.selected_index),
            thumb_color=t.TARJETA,
            controls=[
                ft.Container(content=ui.texto("Resumen", size=t.SUBHEAD),
                             padding=ft.padding.symmetric(horizontal=t.L, vertical=t.XS),
                             alignment=ft.alignment.center),
                ft.Container(content=ui.texto("Calendario", size=t.SUBHEAD),
                             padding=ft.padding.symmetric(horizontal=t.L, vertical=t.XS),
                             alignment=ft.alignment.center),
            ],
        ),
        padding=ft.padding.symmetric(horizontal=t.L, vertical=t.S),
    )

    if pestana == 0:
        contenido.content = _resumen(router)
    else:
        contenido.content = _calendario(router, mes, anio, elegir_mes(router, pestana))

    cuerpo = ft.Column(
        [ui.titulo_grande("Progreso"), selector, contenido],
        spacing=0,
        expand=True,
    )

    return ft.View(
        appbar=ui.barra("Progreso"),
        controls=[ft.SafeArea(cuerpo, expand=True)],
        padding=0,
    )


def elegir_mes(router, pestana):
    """Devuelve un callback que cambia el mes visible del calendario."""
    def cambiar(nuevo_mes, nuevo_anio):
        router.pila[-1].params = {"pestana": pestana, "mes": nuevo_mes, "anio": nuevo_anio}
        router.refrescar()
    return cambiar


# ── Resumen ──────────────────────────────────────────────────────────────────

def _resumen(router):
    resumen = router.conexion.resumen_rutinas()
    con_datos = [r for r in resumen if r["ultima_fecha"] is not None]

    if not con_datos:
        return ui.estado_vacio(
            ft.CupertinoIcons.CHART_BAR,
            "Todavía no hay datos",
            "Registra tu primer entrenamiento desde una rutina y aquí verás cómo "
            "progresas en cada ejercicio.",
        )

    filas = [
        ui.fila(
            r["nombre"],
            subtitulo=formato.hace(r["ultima_fecha"]),
            izquierda=ui.punto_color(r["color"] or t.ACENTO, 12),
            on_click=lambda e, i=r["id"]: router.ir("resultado_rutina", id_rutina=i),
        )
        for r in con_datos
    ]

    return ft.Column(
        [
            ft.Container(height=t.M),
            ui.grupo(filas, cabecera="Rutinas entrenadas",
                     pie="Entra en una rutina para ver la evolución del peso en cada ejercicio."),
            ft.Container(height=t.XXL),
        ],
        spacing=0,
        scroll=ft.ScrollMode.AUTO,
        expand=True,
    )


# ── Calendario ───────────────────────────────────────────────────────────────

def _dias_del_mes(mes, anio):
    primero = date(anio, mes, 1)
    siguiente = date(anio + 1, 1, 1) if mes == 12 else date(anio, mes + 1, 1)
    return [primero + timedelta(days=i) for i in range((siguiente - primero).days)]


def _calendario(router, mes, anio, cambiar_mes):
    conexion = router.conexion
    entrenamientos = conexion.selectAll_entrenamientos()
    colores = conexion.colores_rutinas()
    hoy = date.today()

    def desplazar(delta):
        nuevo = mes + delta
        if nuevo < 1:
            cambiar_mes(12, anio - 1)
        elif nuevo > 12:
            cambiar_mes(1, anio + 1)
        else:
            cambiar_mes(nuevo, anio)

    cabecera = ft.Container(
        content=ft.Row(
            [
                ui.boton_icono(ft.CupertinoIcons.CHEVRON_LEFT,
                               lambda _: desplazar(-1), size=18),
                ft.Container(
                    content=ui.texto(f"{formato.mes(mes)} {anio}", size=t.HEADLINE,
                                     weight=t.SEMIBOLD, align=ft.TextAlign.CENTER),
                    expand=True,
                ),
                ui.boton_icono(ft.CupertinoIcons.CHEVRON_RIGHT,
                               lambda _: desplazar(1), size=18),
            ],
            vertical_alignment=ft.CrossAxisAlignment.CENTER,
        ),
        padding=ft.padding.symmetric(horizontal=t.L, vertical=t.S),
    )

    rejilla = ft.GridView(runs_count=7, spacing=t.XS, run_spacing=t.XS,
                          child_aspect_ratio=1, padding=0)

    for etiqueta in formato.DIAS_SEMANA:
        rejilla.controls.append(
            ft.Container(
                content=ui.texto(etiqueta, size=t.CAPTION, color=t.TEXTO_SEC,
                                 align=ft.TextAlign.CENTER),
                alignment=ft.alignment.center,
            )
        )

    dias = _dias_del_mes(mes, anio)
    for _ in range(dias[0].weekday()):  # huecos hasta el primer día del mes
        rejilla.controls.append(ft.Container())

    for dia in dias:
        id_rutina = entrenamientos.get(dia)
        entrenado = id_rutina is not None
        color = colores.get(id_rutina, (None, t.ACENTO))[1] if entrenado else None
        es_hoy = dia == hoy

        rejilla.controls.append(
            ft.Container(
                content=ui.texto(
                    str(dia.day),
                    size=t.SUBHEAD,
                    weight=t.SEMIBOLD if (entrenado or es_hoy) else None,
                    color=ft.Colors.WHITE if entrenado else (t.ACENTO if es_hoy else t.TEXTO),
                    align=ft.TextAlign.CENTER,
                ),
                alignment=ft.alignment.center,
                bgcolor=color,
                border_radius=100,
                border=ft.border.all(1.5, t.ACENTO) if es_hoy and not entrenado else None,
            )
        )

    rutinas_del_mes = {
        entrenamientos[d] for d in dias if d in entrenamientos
    }
    if rutinas_del_mes:
        leyenda = ft.Container(
            content=ft.Row(
                [
                    ft.Row([ui.punto_color(colores[i][1], 10),
                            ui.texto(colores[i][0], size=t.FOOTNOTE, color=t.TEXTO_SEC)],
                           spacing=t.XS, tight=True)
                    for i in sorted(rutinas_del_mes) if i in colores
                ],
                spacing=t.L,
                wrap=True,
                run_spacing=t.S,
            ),
            padding=ft.padding.symmetric(horizontal=t.L, vertical=t.L),
        )
    else:
        leyenda = ft.Container(
            content=ui.texto("Ningún entrenamiento este mes", size=t.FOOTNOTE,
                             color=t.TEXTO_SEC, align=ft.TextAlign.CENTER),
            alignment=ft.alignment.center,
            padding=ft.padding.symmetric(vertical=t.L),
        )

    tarjeta = ft.Container(
        content=ft.Column([cabecera, ui.separador(0), ft.Container(content=rejilla, height=290,
                                                                   padding=t.M)],
                          spacing=0),
        bgcolor=t.TARJETA,
        border_radius=t.RADIO_L,
        margin=ft.margin.symmetric(horizontal=t.L),
    )

    return ft.Column(
        [ft.Container(height=t.M), tarjeta, leyenda, ft.Container(height=t.XL)],
        spacing=0,
        scroll=ft.ScrollMode.AUTO,
        expand=True,
    )
