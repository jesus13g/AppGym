"""Ejercicios de una rutina con acceso a su progreso individual."""

import flet as ft

from app.theme import tokens as t
from app.theme import ui
from app.utils import formato


def vista(page, router, id_rutina):
    conexion = router.conexion
    rutina = conexion.select_NombreRutina(id_rutina)
    if rutina is None:
        return ft.View(
            appbar=ui.barra("Resultados"),
            controls=[ui.estado_vacio(ft.CupertinoIcons.EXCLAMATIONMARK_TRIANGLE,
                                      "Esta rutina ya no existe")],
        )

    ejercicios = conexion.selectAll_ejerciciosRutina(id_rutina)

    filas = []
    for ejercicio in ejercicios:
        registros = conexion.series_con_fecha(id_rutina, ejercicio.id)
        if not registros:
            subtitulo = "Sin registros"
            al_pulsar = None
        else:
            ultimo = registros[-1]
            maximo = max(r["peso"] for r in registros)
            subtitulo = (f"{formato.plural(len(registros), 'registro', 'registros')} · "
                         f"último {ultimo['peso']:g} kg · máx {maximo:g} kg")
            al_pulsar = (lambda e, i=ejercicio.id:
                         router.ir("resultado_ejercicio", id_rutina=id_rutina, id_ejercicio=i))

        filas.append(ui.fila(
            ejercicio.nombre,
            subtitulo=subtitulo,
            izquierda=ui.miniatura(formato.imagen_ejercicio(ejercicio)),
            on_click=al_pulsar,
            chevron=al_pulsar is not None,
        ))

    if not filas:
        cuerpo = ui.estado_vacio(ft.CupertinoIcons.CHART_BAR,
                                 "Esta rutina no tiene ejercicios")
    else:
        cuerpo = ft.Column(
            [
                ui.titulo_grande(rutina.nombre),
                ui.grupo(filas, cabecera="Ejercicios"),
                ft.Container(height=t.XXL),
            ],
            spacing=0,
            scroll=ft.ScrollMode.AUTO,
            expand=True,
        )

    return ft.View(
        appbar=ui.barra(rutina.nombre, titulo_anterior="Progreso"),
        controls=[ft.SafeArea(cuerpo, expand=True)],
        padding=0,
    )
