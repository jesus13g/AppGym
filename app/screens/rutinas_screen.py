"""Pestaña de rutinas: la lista de rutinas del usuario."""

import flet as ft

from app.theme import tokens as t
from app.theme import ui
from app.utils import formato


def vista(page, router):
    resumen = router.conexion.resumen_rutinas()

    def crear_rutina(_=None):
        ui.dialogo_texto(
            page,
            "Nueva rutina",
            "Nombre de la rutina",
            mensaje="Por ejemplo: Empuje, Pierna, Full body…",
            etiqueta_aceptar="Crear",
            on_aceptar=_al_crear,
        )

    def _al_crear(nombre):
        id_rutina = router.conexion.insert_newRutina(nombre)
        if id_rutina is None:
            ui.aviso(page, f"Ya tienes una rutina llamada «{nombre}»")
            return
        router.ir("rutina", id_rutina=id_rutina)

    def borrar(id_rutina):
        def hacerlo():
            router.conexion.delete_rutina(id_rutina)
            router.refrescar()
        return hacerlo

    boton_nueva = ui.boton_icono(ft.CupertinoIcons.ADD, crear_rutina, tooltip="Nueva rutina")

    if not resumen:
        cuerpo = ui.estado_vacio(
            ft.CupertinoIcons.SQUARE_STACK_3D_UP,
            "Aún no tienes rutinas",
            "Crea tu primera rutina para empezar a organizar tus ejercicios y "
            "registrar tus entrenamientos.",
            accion=ui.boton_principal("Crear rutina", crear_rutina,
                                      icono=ft.CupertinoIcons.ADD),
        )
    else:
        filas = []
        for r in resumen:
            filas.append(ui.deslizar_para_borrar(
                page,
                ui.fila(
                    r["nombre"],
                    subtitulo=" · ".join([
                        formato.plural(r["n_ejercicios"], "ejercicio", "ejercicios"),
                        formato.hace(r["ultima_fecha"]),
                    ]),
                    izquierda=ui.punto_color(r["color"] or t.ACENTO, 12),
                    on_click=lambda e, i=r["id"]: router.ir("rutina", id_rutina=i),
                ),
                on_borrar=borrar(r["id"]),
                titulo=f"¿Eliminar «{r['nombre']}»?",
                mensaje="Se borrarán también sus ejercicios y todo su histórico de "
                        "entrenamientos. Esta acción no se puede deshacer.",
            ))

        cuerpo = ft.Column(
            [
                ui.titulo_grande("Rutinas"),
                ui.grupo(filas, pie="Desliza una rutina hacia la izquierda para eliminarla."),
                ft.Container(height=t.XXL),
            ],
            spacing=0,
            scroll=ft.ScrollMode.AUTO,
            expand=True,
        )

    return ft.View(
        appbar=ui.barra("Rutinas", derecha=boton_nueva),
        controls=[ft.SafeArea(cuerpo, expand=True)],
        padding=0,
    )
