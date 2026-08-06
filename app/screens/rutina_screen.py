"""Detalle de una rutina: sus ejercicios y el acceso a registrar entrenamiento."""

import flet as ft

from app.theme import tokens as t
from app.theme import ui
from app.utils import formato


def vista(page, router, id_rutina):
    conexion = router.conexion
    rutina = conexion.select_NombreRutina(id_rutina)
    if rutina is None:
        return ft.View(
            appbar=ui.barra("Rutina"),
            controls=[ui.estado_vacio(ft.CupertinoIcons.EXCLAMATIONMARK_TRIANGLE,
                                      "Esta rutina ya no existe")],
        )

    ejercicios = conexion.selectAll_ejerciciosRutina(id_rutina)
    n_entrenamientos = conexion.count_entrenamientos_rutina(id_rutina)
    ultima = conexion.ultimo_entrenamiento_rutina(id_rutina)

    def anadir(_=None):
        router.ir("anadir_ejercicio", id_rutina=id_rutina)

    def entrenar(_=None):
        router.ir("entrenar", id_rutina=id_rutina)

    def renombrar(_=None):
        def aplicar(nombre):
            if conexion.rename_rutina(id_rutina, nombre):
                router.refrescar()
            else:
                ui.aviso(page, f"Ya existe una rutina llamada «{nombre}»")

        ui.dialogo_texto(page, "Renombrar rutina", "Nombre de la rutina",
                         valor=rutina.nombre, on_aceptar=aplicar)

    def borrar(id_ejercicio):
        def hacerlo():
            conexion.delete_ejercicio(id_rutina, id_ejercicio)
            router.refrescar()
        return hacerlo

    def abrir_ficha(ejercicio):
        if ejercicio.catalogo is None:
            return None
        return lambda e, c=ejercicio.catalogo.id: router.ir("ficha", id_catalogo=c)

    # ── Cabecera con las estadísticas de la rutina ───────────────────────────
    estadisticas = ft.Container(
        content=ft.Row(
            [
                _estadistica(str(len(ejercicios)), "Ejercicios"),
                _estadistica(str(n_entrenamientos), "Sesiones"),
                _estadistica(formato.hace(ultima), "Última"),
            ],
            alignment=ft.MainAxisAlignment.SPACE_AROUND,
        ),
        bgcolor=t.TARJETA,
        border_radius=t.RADIO_L,
        padding=ft.padding.symmetric(vertical=t.L),
        margin=ft.margin.symmetric(horizontal=t.L),
    )

    # ── Lista de ejercicios ──────────────────────────────────────────────────
    if ejercicios:
        filas = [
            ui.deslizar_para_borrar(
                page,
                ui.fila(
                    ejercicio.nombre,
                    subtitulo=formato.subtitulo_ejercicio(ejercicio),
                    izquierda=ui.miniatura(formato.imagen_ejercicio(ejercicio)),
                    on_click=abrir_ficha(ejercicio),
                    chevron=ejercicio.catalogo is not None,
                ),
                on_borrar=borrar(ejercicio.id),
                titulo=f"¿Quitar «{ejercicio.nombre}»?",
                mensaje="Se eliminarán también las series registradas de este "
                        "ejercicio en esta rutina.",
            )
            for ejercicio in ejercicios
        ]
        lista = ui.grupo(filas, cabecera="Ejercicios")
    else:
        lista = ft.Container(
            content=ui.grupo([
                ui.fila("Añadir ejercicios",
                        subtitulo="Elige del catálogo de 1.324 ejercicios",
                        izquierda=ft.Icon(ft.CupertinoIcons.ADD_CIRCLED, color=t.ACENTO, size=26),
                        on_click=anadir),
            ], cabecera="Ejercicios",
                pie="Esta rutina todavía está vacía. Añade ejercicios para poder "
                    "registrar un entrenamiento."),
        )

    acciones = ft.Container(
        content=ft.Column(
            [
                ui.boton_principal("Empezar entrenamiento", entrenar,
                                   icono=ft.CupertinoIcons.PLAY_FILL,
                                   disabled=not ejercicios),
            ],
            spacing=t.M,
        ),
        padding=ft.padding.symmetric(horizontal=t.L, vertical=t.L),
    )

    cuerpo = ft.Column(
        [
            ui.titulo_grande(rutina.nombre),
            estadisticas,
            ft.Container(height=t.XL),
            lista,
            acciones,
            ft.Container(height=t.XXL),
        ],
        spacing=0,
        scroll=ft.ScrollMode.AUTO,
        expand=True,
    )

    barra_derecha = ft.Row(
        [
            ui.boton_icono(ft.CupertinoIcons.PENCIL, renombrar, tooltip="Renombrar"),
            ui.boton_icono(ft.CupertinoIcons.ADD, anadir, tooltip="Añadir ejercicio"),
        ],
        spacing=0,
        tight=True,
    )

    return ft.View(
        appbar=ui.barra(rutina.nombre, derecha=barra_derecha, titulo_anterior="Rutinas"),
        controls=[ft.SafeArea(cuerpo, expand=True)],
        padding=0,
    )


def _estadistica(valor, etiqueta):
    return ft.Column(
        [
            ui.texto(valor, size=t.TITLE3, weight=t.SEMIBOLD, align=ft.TextAlign.CENTER),
            ui.texto(etiqueta, size=t.CAPTION, color=t.TEXTO_SEC, align=ft.TextAlign.CENTER),
        ],
        spacing=2,
        horizontal_alignment=ft.CrossAxisAlignment.CENTER,
        tight=True,
    )
