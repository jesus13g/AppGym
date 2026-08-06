"""Catálogo de ejercicios: búsqueda, filtros y alta en una rutina.

La misma pantalla sirve para dos cosas:
  - `vista`: la pestaña de exploración del catálogo completo
  - `vista_anadir`: el modal que añade ejercicios a una rutina concreta
"""

import threading

import flet as ft

from app.theme import tokens as t
from app.theme import ui
from app.utils import formato, i18n, media

PAGINA = 40          # resultados por tanda
ESPERA_BUSQUEDA = 0.25   # segundos de reposo antes de lanzar la consulta

ZONAS = [
    (None, "Todas"),
    ("chest", "Pecho"),
    ("back", "Espalda"),
    ("upper legs", "Piernas"),
    ("lower legs", "Gemelos"),
    ("shoulders", "Hombros"),
    ("upper arms", "Brazos"),
    ("lower arms", "Antebrazos"),
    ("waist", "Core"),
    ("cardio", "Cardio"),
    ("neck", "Cuello"),
]


def vista(page, router):
    """Pestaña de exploración: al tocar un ejercicio se abre su ficha."""
    return _construir(
        page, router,
        titulo="Ejercicios",
        id_rutina=None,
        con_barra_atras=False,
    )


def vista_anadir(page, router, id_rutina):
    """Modal de alta: al tocar un ejercicio se añade a la rutina."""
    rutina = router.conexion.select_NombreRutina(id_rutina)
    return _construir(
        page, router,
        titulo="Añadir ejercicio",
        subtitulo=rutina.nombre if rutina else None,
        id_rutina=id_rutina,
        con_barra_atras=True,
    )


def _construir(page, router, titulo, id_rutina, con_barra_atras, subtitulo=None):
    conexion = router.conexion

    estado = {
        "texto": "",
        "zona": None,
        "equipo": None,
        "offset": 0,
        "hay_mas": True,
        "cargando": False,
        "temporizador": None,
    }
    ya_en_rutina = conexion.ids_catalogo_en_rutina(id_rutina) if id_rutina else set()

    resultados = ft.ListView(spacing=0, padding=ft.padding.only(bottom=t.XXL), expand=True)
    contador = ui.texto("", size=t.FOOTNOTE, color=t.TEXTO_SEC)
    etiqueta_equipo = ui.texto("Equipamiento", size=t.FOOTNOTE, color=t.ACENTO)

    # ── Alta de ejercicios ───────────────────────────────────────────────────

    def anadir(ficha, fila_control):
        if ficha.id in ya_en_rutina:
            ui.aviso(page, "Ya está en la rutina")
            return
        if conexion.insert_newEjercicio(id_rutina, ficha.nombre, id_catalogo=ficha.id):
            ya_en_rutina.add(ficha.id)
            _marcar_anadido(fila_control)
            ui.aviso(page, f"«{ficha.nombre}» añadido")
        else:
            ui.aviso(page, "No se pudo añadir el ejercicio")

    def crear_personalizado(_=None):
        def guardar(nombre):
            if conexion.insert_newEjercicio(id_rutina, nombre, descripcion=None):
                ui.aviso(page, f"«{nombre}» añadido")
                router.volver()
            else:
                ui.aviso(page, "Ya tienes un ejercicio con ese nombre")

        ui.dialogo_texto(
            page, "Ejercicio personalizado", "Nombre del ejercicio",
            mensaje="Para lo que no esté en el catálogo.",
            etiqueta_aceptar="Añadir", on_aceptar=guardar,
        )

    # ── Construcción de filas ────────────────────────────────────────────────

    def fila_resultado(ficha):
        contenedor = ft.Container()

        if id_rutina is None:
            derecha = None
            al_pulsar = lambda e, c=ficha.id: router.ir("ficha", id_catalogo=c)
        else:
            derecha = ft.Icon(
                ft.CupertinoIcons.CHECK_MARK_CIRCLED_SOLID if ficha.id in ya_en_rutina
                else ft.CupertinoIcons.PLUS_CIRCLE,
                color=t.EXITO if ficha.id in ya_en_rutina else t.ACENTO,
                size=24,
            )
            al_pulsar = lambda e, f=ficha: anadir(f, contenedor)

        interior = ui.fila(
            ficha.nombre,
            subtitulo=formato.subtitulo_catalogo(ficha),
            izquierda=ui.miniatura(media.resolver(ficha.image)),
            derecha=derecha,
            on_click=al_pulsar,
        )
        if id_rutina is not None:
            # Un toque largo (o el icono ⓘ) abre la ficha sin añadir nada.
            interior.content.controls.insert(
                len(interior.content.controls) - 1,
                ui.boton_icono(ft.CupertinoIcons.INFO_CIRCLE,
                               lambda e, c=ficha.id: router.ir("ficha", id_catalogo=c),
                               color=t.TEXTO_TER, size=20, tooltip="Ver ficha"),
            )

        contenedor.content = ft.Column([interior, ui.separador(76)], spacing=0)
        contenedor.data = ficha.id
        return contenedor

    def _marcar_anadido(contenedor):
        """Cambia el ➕ por un ✓ verde en la fila recién añadida."""
        fila_interna = contenedor.content.controls[0]
        icono = fila_interna.content.controls[-1]
        icono.name = ft.CupertinoIcons.CHECK_MARK_CIRCLED_SOLID
        icono.color = t.EXITO
        contenedor.update()

    # ── Carga y paginación ───────────────────────────────────────────────────

    def cargar(reiniciar=False):
        if estado["cargando"]:
            return
        estado["cargando"] = True
        if reiniciar:
            estado["offset"] = 0
            estado["hay_mas"] = True
            resultados.controls.clear()

        fichas = conexion.buscar_catalogo(
            texto=estado["texto"] or None,
            body_part=estado["zona"],
            equipment=estado["equipo"],
            limit=PAGINA,
            offset=estado["offset"],
        )
        estado["offset"] += len(fichas)
        estado["hay_mas"] = len(fichas) == PAGINA
        resultados.controls.extend(fila_resultado(f) for f in fichas)

        if not resultados.controls:
            resultados.controls.append(ui.estado_vacio(
                ft.CupertinoIcons.SEARCH,
                "Sin resultados",
                "Prueba con otro término o quita alguno de los filtros.",
            ))
            contador.value = ""
        elif estado["hay_mas"]:
            contador.value = f"{estado['offset']}+ ejercicios"
        else:
            contador.value = formato.plural(estado["offset"], "ejercicio", "ejercicios")

        if id_rutina is not None and not estado["hay_mas"]:
            resultados.controls.append(_fila_personalizado(crear_personalizado))

        estado["cargando"] = False
        if resultados.page:
            resultados.update()
            contador.update()

    def al_hacer_scroll(e):
        if estado["hay_mas"] and not estado["cargando"] and e.pixels >= e.max_scroll_extent - 400:
            cargar()

    resultados.on_scroll = al_hacer_scroll

    # ── Filtros ──────────────────────────────────────────────────────────────

    def buscar(e):
        """Rearma un temporizador en cada tecla para no consultar en cada letra."""
        estado["texto"] = (e.control.value or "").strip()
        if estado["temporizador"]:
            estado["temporizador"].cancel()
        estado["temporizador"] = threading.Timer(ESPERA_BUSQUEDA, lambda: cargar(reiniciar=True))
        estado["temporizador"].daemon = True
        estado["temporizador"].start()

    chips_zona = ft.Row(spacing=t.S, scroll=ft.ScrollMode.AUTO)

    def pintar_chips():
        chips_zona.controls.clear()
        for valor, etiqueta in ZONAS:
            activo = estado["zona"] == valor
            chips_zona.controls.append(
                ft.Container(
                    content=ui.texto(etiqueta, size=t.FOOTNOTE,
                                     color=ft.Colors.WHITE if activo else t.TEXTO,
                                     weight=t.SEMIBOLD if activo else None),
                    padding=ft.padding.symmetric(horizontal=t.M, vertical=t.S - 1),
                    bgcolor=t.ACENTO if activo else t.RELLENO,
                    border_radius=t.RADIO_XL,
                    on_click=lambda e, v=valor: elegir_zona(v),
                )
            )

    def elegir_zona(valor):
        estado["zona"] = valor
        pintar_chips()
        chips_zona.update()
        cargar(reiniciar=True)

    def elegir_equipo(valor):
        estado["equipo"] = valor
        etiqueta_equipo.value = i18n.equipment(valor) if valor else "Equipamiento"
        etiqueta_equipo.update()
        cargar(reiniciar=True)

    def abrir_equipos(_=None):
        opciones = [(None, "Todos")] + [
            (v, i18n.equipment(v)) for v in conexion.equipamientos_disponibles()
        ]

        def elegir(valor):
            page.close(hoja)
            elegir_equipo(valor)

        hoja = ft.CupertinoBottomSheet(
            ft.Container(
                bgcolor=t.FONDO,
                padding=ft.padding.only(top=t.M, bottom=t.XL),
                content=ft.Column(
                    [
                        ft.Container(
                            content=ui.texto("Equipamiento", size=t.HEADLINE,
                                             weight=t.SEMIBOLD, align=ft.TextAlign.CENTER),
                            padding=ft.padding.only(bottom=t.M),
                        ),
                        ft.Container(
                            content=ft.ListView(
                                [
                                    ui.fila(
                                        etiqueta,
                                        on_click=lambda e, v=valor: elegir(v),
                                        derecha=ft.Icon(ft.CupertinoIcons.CHECK_MARK,
                                                        color=t.ACENTO, size=18)
                                        if estado["equipo"] == valor else None,
                                        chevron=False,
                                    )
                                    for valor, etiqueta in opciones
                                ],
                                spacing=0,
                            ),
                            height=380,
                        ),
                    ],
                    spacing=0,
                    tight=True,
                ),
            ),
            height=460,
        )
        page.open(hoja)

    pintar_chips()

    barra_filtros = ft.Container(
        content=ft.Column(
            [
                chips_zona,
                ft.Row(
                    [
                        ft.Container(
                            content=ft.Row([
                                etiqueta_equipo,
                                ft.Icon(ft.CupertinoIcons.CHEVRON_DOWN, size=12, color=t.ACENTO),
                            ], spacing=t.XS, tight=True),
                            on_click=abrir_equipos,
                            padding=ft.padding.symmetric(vertical=t.XS),
                        ),
                        ft.Container(expand=True),
                        contador,
                    ],
                    vertical_alignment=ft.CrossAxisAlignment.CENTER,
                ),
            ],
            spacing=t.S,
        ),
        padding=ft.padding.only(left=t.L, right=t.L, bottom=t.S),
    )

    cargar(reiniciar=True)

    encabezado = [ui.campo_busqueda(buscar, "Buscar ejercicio, músculo o material"),
                  barra_filtros]
    if not con_barra_atras:
        encabezado.insert(0, ui.titulo_grande(titulo))

    cuerpo = ft.Column(
        encabezado + [ft.Container(content=resultados, expand=True)],
        spacing=0,
        expand=True,
    )

    derecha_barra = None
    if id_rutina is not None:
        derecha_barra = ui.boton_texto("Personalizado", crear_personalizado, size=t.SUBHEAD)

    return ft.View(
        appbar=ui.barra(
            titulo if con_barra_atras else "Ejercicios",
            izquierda=ui.boton_texto("Cancelar", lambda _: router.volver())
            if con_barra_atras else None,
            derecha=derecha_barra,
        ),
        controls=[ft.SafeArea(cuerpo, expand=True)],
        padding=0,
    )


def _fila_personalizado(on_click):
    """Fila final que ofrece crear un ejercicio que no está en el catálogo."""
    return ft.Container(
        content=ui.fila(
            "Crear ejercicio personalizado",
            subtitulo="Si no encuentras lo que buscas",
            izquierda=ft.Container(
                width=48, height=48, bgcolor=t.RELLENO, border_radius=t.RADIO_M,
                alignment=ft.alignment.center,
                content=ft.Icon(ft.CupertinoIcons.PENCIL_OUTLINE, color=t.ACENTO, size=22),
            ),
            on_click=on_click,
        ),
        padding=ft.padding.only(top=t.S),
    )
