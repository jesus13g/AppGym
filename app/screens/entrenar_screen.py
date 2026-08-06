"""Registro de un entrenamiento: series, repeticiones y peso por ejercicio."""

from datetime import datetime

import flet as ft

from app.theme import tokens as t
from app.theme import ui
from app.utils import formato

POR_DEFECTO = {"series": 4, "repeticiones": 10, "peso": 20.0}


def vista(page, router, id_rutina):
    conexion = router.conexion
    rutina = conexion.select_NombreRutina(id_rutina)
    ejercicios = conexion.selectAll_ejerciciosRutina(id_rutina)

    if rutina is None or not ejercicios:
        return ft.View(
            appbar=ui.barra("Entrenamiento",
                            izquierda=ui.boton_texto("Cancelar", lambda _: router.volver())),
            controls=[ui.estado_vacio(ft.CupertinoIcons.EXCLAMATIONMARK_TRIANGLE,
                                      "Esta rutina no tiene ejercicios")],
        )

    # id_ejercicio -> {"series", "repeticiones", "peso"}; se rellena con lo último
    # registrado de cada ejercicio, que casi siempre es lo que se va a repetir.
    valores = {}
    incluidos = {}

    tarjetas = []
    for ejercicio in ejercicios:
        ultima = conexion.ultima_serie_ejercicio(ejercicio.id)
        valores[ejercicio.id] = dict(ultima or POR_DEFECTO)
        incluidos[ejercicio.id] = True
        tarjetas.append(_tarjeta(page, ejercicio, valores, incluidos, ultima))

    def guardar(_=None):
        a_guardar = {i: v for i, v in valores.items() if incluidos.get(i)}
        if not a_guardar:
            ui.aviso(page, "Marca al menos un ejercicio")
            return
        if conexion.insert_newEntrenamiento(id_rutina, datetime.now(), a_guardar):
            ui.aviso(page, "Entrenamiento guardado")
            router.volver()
        else:
            ui.aviso(page, "No se pudo guardar el entrenamiento")

    hoy = ft.Container(
        content=ft.Column(
            [
                ui.texto(rutina.nombre, size=t.TITLE2, weight=t.BOLD),
                ui.texto(formato.fecha_larga(datetime.now()).capitalize(),
                         size=t.SUBHEAD, color=t.TEXTO_SEC),
            ],
            spacing=2,
        ),
        padding=ft.padding.only(left=t.L, right=t.L, top=t.M, bottom=t.L),
    )

    cuerpo = ft.Column(
        [hoy] + tarjetas + [
            ft.Container(
                content=ui.boton_principal("Guardar entrenamiento", guardar,
                                           icono=ft.CupertinoIcons.CHECK_MARK),
                padding=ft.padding.all(t.L),
            ),
            ft.Container(height=t.XL),
        ],
        spacing=t.L,
        scroll=ft.ScrollMode.AUTO,
        expand=True,
    )

    return ft.View(
        appbar=ui.barra(
            "Entrenamiento",
            izquierda=ui.boton_texto("Cancelar", lambda _: router.volver()),
            derecha=ui.boton_texto("Guardar", guardar, weight=t.SEMIBOLD),
        ),
        controls=[ft.SafeArea(cuerpo, expand=True)],
        padding=0,
    )


def _tarjeta(page, ejercicio, valores, incluidos, ultima):
    """Tarjeta de un ejercicio con sus tres steppers y el interruptor de incluir."""
    id_ejercicio = ejercicio.id

    def asignar(clave):
        def aplicar(nuevo):
            valores[id_ejercicio][clave] = nuevo
        return aplicar

    stepper_series, _ = ui.stepper(
        "Series", valores[id_ejercicio]["series"], asignar("series"),
        minimo=1, maximo=20)
    stepper_reps, _ = ui.stepper(
        "Repeticiones", valores[id_ejercicio]["repeticiones"], asignar("repeticiones"),
        minimo=1, maximo=50)
    stepper_peso, _ = ui.stepper(
        "Peso", float(valores[id_ejercicio]["peso"]), asignar("peso"),
        minimo=0, maximo=400, paso=2.5, unidad="kg", decimales=1)

    controles = ft.Column([stepper_series, ui.separador(t.L),
                           stepper_reps, ui.separador(t.L),
                           stepper_peso], spacing=0)

    def alternar(e):
        incluidos[id_ejercicio] = e.control.value
        controles.opacity = 1 if e.control.value else 0.35
        controles.disabled = not e.control.value
        controles.update()

    interruptor = ft.CupertinoSwitch(value=True, on_change=alternar, active_color=t.EXITO)

    referencia = (
        f"Último: {ultima['series']}×{ultima['repeticiones']} · {ultima['peso']:g} kg"
        if ultima else "Primera vez con este ejercicio"
    )

    cabecera = ft.Container(
        content=ft.Row(
            [
                ui.miniatura(formato.imagen_ejercicio(ejercicio), tamano=40),
                ft.Container(
                    content=ft.Column(
                        [
                            ui.texto(ejercicio.nombre, size=t.CALLOUT, weight=t.SEMIBOLD,
                                     max_lines=2),
                            ui.texto(referencia, size=t.CAPTION, color=t.TEXTO_SEC),
                        ],
                        spacing=2,
                    ),
                    expand=True,
                ),
                interruptor,
            ],
            spacing=t.M,
            vertical_alignment=ft.CrossAxisAlignment.CENTER,
        ),
        padding=ft.padding.symmetric(horizontal=t.L, vertical=t.M),
    )

    controles.animate_opacity = 150

    return ft.Container(
        content=ft.Column([cabecera, ui.separador(t.L), controles], spacing=0),
        bgcolor=t.TARJETA,
        border_radius=t.RADIO_L,
        margin=ft.margin.symmetric(horizontal=t.L),
        clip_behavior=ft.ClipBehavior.ANTI_ALIAS,
    )
