"""Componentes de interfaz con estética iOS.

Sustituye a la antigua `WidgetFactory`: aquí solo hay funciones puras que
devuelven controles de Flet, sin tocar la base de datos ni la página.
"""

import flet as ft

from app.theme import tokens as t


# ── Texto ────────────────────────────────────────────────────────────────────

def texto(valor, size=t.BODY, color=t.TEXTO, weight=None, align=None, max_lines=None):
    """Un `ft.Text` con los valores por defecto del tema."""
    return ft.Text(
        value=valor,
        size=size,
        color=color,
        weight=weight,
        text_align=align,
        max_lines=max_lines,
        overflow=ft.TextOverflow.ELLIPSIS if max_lines else None,
    )


def titulo_grande(valor):
    """Título de pantalla, al estilo de los large titles de iOS."""
    return ft.Container(
        content=texto(valor, size=t.LARGE_TITLE, weight=t.BOLD),
        padding=ft.padding.only(left=t.L, right=t.L, top=t.S, bottom=t.M),
    )


def cabecera_seccion(valor):
    """Cabecera en mayúsculas sobre un grupo de lista."""
    return ft.Container(
        content=texto(valor.upper(), size=t.FOOTNOTE, color=t.TEXTO_SEC),
        padding=ft.padding.only(left=t.XL, right=t.L, bottom=t.S),
    )


def pie_seccion(valor):
    """Texto explicativo bajo un grupo de lista."""
    return ft.Container(
        content=texto(valor, size=t.FOOTNOTE, color=t.TEXTO_SEC),
        padding=ft.padding.only(left=t.XL, right=t.XL, top=t.S),
    )


# ── Listas agrupadas ─────────────────────────────────────────────────────────

def separador(sangria=t.L):
    """La línea fina entre filas de una lista, con la sangría típica de iOS."""
    return ft.Container(
        height=0.5,
        bgcolor=t.SEPARADOR,
        margin=ft.margin.only(left=sangria),
    )


def grupo(filas, cabecera=None, pie=None, sangria=t.L):
    """Grupo de lista con esquinas redondeadas y separadores internos.

    :param filas: controles que forman las filas del grupo
    :param cabecera: texto de cabecera opcional
    :param pie: texto explicativo opcional bajo el grupo
    """
    filas = [f for f in filas if f is not None]
    if not filas:
        return ft.Container()

    contenido = []
    for i, fila in enumerate(filas):
        if i:
            contenido.append(separador(sangria))
        contenido.append(fila)

    tarjeta = ft.Container(
        content=ft.Column(contenido, spacing=0),
        bgcolor=t.TARJETA,
        border_radius=t.RADIO_L,
        clip_behavior=ft.ClipBehavior.ANTI_ALIAS,
        margin=ft.margin.symmetric(horizontal=t.L),
    )

    partes = []
    if cabecera:
        partes.append(cabecera_seccion(cabecera))
    partes.append(tarjeta)
    if pie:
        partes.append(pie_seccion(pie))
    return ft.Column(partes, spacing=0)


def fila(titulo, subtitulo=None, izquierda=None, valor=None, on_click=None,
         chevron=None, derecha=None):
    """Fila de lista al estilo iOS.

    :param izquierda: control que va antes del texto (icono, miniatura…)
    :param valor: texto gris alineado a la derecha
    :param derecha: control a la derecha, en lugar del chevron
    :param chevron: fuerza mostrar u ocultar el `>`; por defecto se muestra si hay on_click
    """
    if chevron is None:
        chevron = on_click is not None and derecha is None

    centro = [texto(titulo, size=t.BODY, max_lines=2)]
    if subtitulo:
        centro.append(texto(subtitulo, size=t.FOOTNOTE, color=t.TEXTO_SEC, max_lines=1))

    controles = []
    if izquierda is not None:
        controles.append(izquierda)
    controles.append(ft.Column(centro, spacing=2, expand=True,
                               alignment=ft.MainAxisAlignment.CENTER))
    if valor is not None:
        controles.append(texto(str(valor), size=t.BODY, color=t.TEXTO_SEC))
    if derecha is not None:
        controles.append(derecha)
    if chevron:
        controles.append(ft.Icon(ft.CupertinoIcons.CHEVRON_FORWARD,
                                 size=16, color=t.TEXTO_TER))

    contenedor = ft.Container(
        content=ft.Row(controles, spacing=t.M,
                       vertical_alignment=ft.CrossAxisAlignment.CENTER),
        padding=ft.padding.symmetric(horizontal=t.L, vertical=t.M),
        on_click=on_click,
        ink=on_click is not None,
    )
    return contenedor


# ── Elementos sueltos ────────────────────────────────────────────────────────

def pildora(valor, color=None, relleno=None):
    """Etiqueta redondeada para categorías (equipamiento, músculo…)."""
    return ft.Container(
        content=texto(valor, size=t.CAPTION, color=color or t.TEXTO_SEC),
        padding=ft.padding.symmetric(horizontal=t.S + 2, vertical=t.XS),
        bgcolor=relleno or t.RELLENO,
        border_radius=t.RADIO_XL,
    )


def punto_color(color, tamano=10):
    """Círculo de color, para identificar rutinas."""
    return ft.Container(width=tamano, height=tamano, bgcolor=color,
                        border_radius=tamano / 2)


def miniatura(src, tamano=48, radio=t.RADIO_M):
    """Miniatura del ejercicio, con hueco gris si no hay imagen disponible."""
    if not src:
        return ft.Container(width=tamano, height=tamano, bgcolor=t.RELLENO,
                            border_radius=radio,
                            content=ft.Icon(ft.CupertinoIcons.PHOTO, size=tamano / 2.5,
                                            color=t.TEXTO_TER),
                            alignment=ft.alignment.center)
    return ft.Container(
        width=tamano,
        height=tamano,
        border_radius=radio,
        bgcolor=ft.Colors.WHITE,
        clip_behavior=ft.ClipBehavior.ANTI_ALIAS,
        content=ft.Image(src=src, width=tamano, height=tamano, fit=ft.ImageFit.COVER,
                         error_content=ft.Icon(ft.CupertinoIcons.PHOTO, size=tamano / 2.5,
                                               color=t.TEXTO_TER)),
    )


# ── Botones ──────────────────────────────────────────────────────────────────

def boton_principal(etiqueta, on_click, icono=None, bgcolor=None, disabled=False):
    """Botón relleno de ancho completo.

    Se construye sobre `CupertinoButton` en vez de `CupertinoFilledButton` porque
    este último no acepta color de fondo y aquí hace falta poder pintarlo en rojo
    para las acciones destructivas.
    """
    interior = [texto(etiqueta, size=t.HEADLINE, weight=t.SEMIBOLD, color=ft.Colors.WHITE)]
    if icono:
        interior.insert(0, ft.Icon(icono, size=18, color=ft.Colors.WHITE))

    return ft.CupertinoButton(
        content=ft.Row(interior, spacing=t.S, alignment=ft.MainAxisAlignment.CENTER, tight=True),
        on_click=on_click,
        disabled=disabled,
        bgcolor=bgcolor or t.ACENTO,
        disabled_bgcolor=t.RELLENO,
        border_radius=t.RADIO_L,
        padding=ft.padding.symmetric(vertical=t.M + 2),
        expand=True,
    )


def boton_texto(etiqueta, on_click, color=None, size=t.BODY, weight=None):
    """Botón plano de barra o de fila."""
    return ft.CupertinoButton(
        content=texto(etiqueta, size=size, color=color or t.ACENTO, weight=weight),
        on_click=on_click,
        padding=ft.padding.symmetric(horizontal=t.S, vertical=t.XS),
        min_size=0,
    )


def boton_icono(icono, on_click, color=None, size=22, tooltip=None):
    """Botón de solo icono para las barras de navegación."""
    return ft.CupertinoButton(
        content=ft.Icon(icono, size=size, color=color or t.ACENTO),
        on_click=on_click,
        padding=ft.padding.all(t.XS),
        min_size=0,
        tooltip=tooltip,
    )


# ── Stepper ──────────────────────────────────────────────────────────────────

def stepper(etiqueta, valor, on_change, minimo=0, maximo=999, paso=1, unidad="",
            decimales=0):
    """Control `−  valor  +` para ajustar series, repeticiones o peso.

    Más preciso a dedo que un slider, y no obliga a abrir el teclado.

    :param on_change: callback(nuevo_valor)
    :return: (control, funcion_para_leer_el_valor)
    """
    estado = {"valor": valor}

    def formatear(v):
        cuerpo = f"{v:.{decimales}f}" if decimales else f"{int(v)}"
        return f"{cuerpo} {unidad}".strip()

    lectura = texto(formatear(valor), size=t.BODY, weight=t.SEMIBOLD, align=ft.TextAlign.CENTER)
    lectura.width = 74

    def ajustar(delta):
        def manejador(_):
            nuevo = min(maximo, max(minimo, estado["valor"] + delta))
            if nuevo == estado["valor"]:
                return
            estado["valor"] = nuevo
            lectura.value = formatear(nuevo)
            lectura.update()
            if on_change:
                on_change(nuevo)
        return manejador

    def signo(icono, delta):
        return ft.CupertinoButton(
            content=ft.Icon(icono, size=18, color=t.ACENTO),
            on_click=ajustar(delta),
            padding=ft.padding.symmetric(horizontal=t.M, vertical=t.S),
            min_size=0,
        )

    control = ft.Container(
        content=ft.Row(
            [
                ft.Container(
                    content=texto(etiqueta, size=t.SUBHEAD, color=t.TEXTO_SEC),
                    expand=True,
                ),
                ft.Container(
                    content=ft.Row(
                        [signo(ft.CupertinoIcons.MINUS, -paso),
                         lectura,
                         signo(ft.CupertinoIcons.PLUS, paso)],
                        spacing=0,
                        tight=True,
                    ),
                    bgcolor=t.RELLENO,
                    border_radius=t.RADIO_S,
                ),
            ],
            vertical_alignment=ft.CrossAxisAlignment.CENTER,
        ),
        padding=ft.padding.symmetric(horizontal=t.L, vertical=t.S),
    )
    return control, lambda: estado["valor"]


# ── Campos y buscador ────────────────────────────────────────────────────────

def campo_texto(placeholder, valor=None, on_change=None, on_submit=None,
                multilinea=False, autofocus=False):
    """Campo de texto Cupertino con el relleno gris característico."""
    return ft.CupertinoTextField(
        placeholder_text=placeholder,
        value=valor,
        on_change=on_change,
        on_submit=on_submit,
        multiline=multilinea,
        min_lines=3 if multilinea else None,
        max_lines=5 if multilinea else 1,
        autofocus=autofocus,
        bgcolor=t.RELLENO,
        border_radius=t.RADIO_M,
        color=t.TEXTO,
        placeholder_style=ft.TextStyle(color=t.PLACEHOLDER),
        padding=ft.padding.symmetric(horizontal=t.M, vertical=t.M - 2),
    )


def campo_busqueda(on_change, placeholder="Buscar"):
    """Barra de búsqueda. Flet 0.25 no trae CupertinoSearchTextField, así que se
    compone con un CupertinoTextField, la lupa como prefijo y el botón de borrar."""
    return ft.Container(
        content=ft.CupertinoTextField(
            placeholder_text=placeholder,
            on_change=on_change,
            prefix=ft.Container(
                content=ft.Icon(ft.CupertinoIcons.SEARCH, size=17, color=t.PLACEHOLDER),
                padding=ft.padding.only(left=t.S, right=t.XS),
            ),
            clear_button_visibility_mode=ft.VisibilityMode.EDITING,
            bgcolor=t.RELLENO,
            border_radius=t.RADIO_M,
            color=t.TEXTO,
            placeholder_style=ft.TextStyle(color=t.PLACEHOLDER),
            padding=ft.padding.symmetric(horizontal=t.S, vertical=t.S),
        ),
        padding=ft.padding.symmetric(horizontal=t.L, vertical=t.S),
    )


# ── Estados y feedback ───────────────────────────────────────────────────────

def estado_vacio(icono, titulo, subtitulo=None, accion=None):
    """Pantalla vacía con icono, mensaje y acción opcional."""
    controles = [
        ft.Icon(icono, size=52, color=t.TEXTO_TER),
        texto(titulo, size=t.TITLE3, weight=t.SEMIBOLD, align=ft.TextAlign.CENTER),
    ]
    if subtitulo:
        controles.append(
            ft.Container(
                content=texto(subtitulo, size=t.SUBHEAD, color=t.TEXTO_SEC,
                              align=ft.TextAlign.CENTER),
                width=280,
            )
        )
    if accion is not None:
        controles.append(ft.Container(content=accion, width=220, padding=ft.padding.only(top=t.S)))

    return ft.Container(
        content=ft.Column(controles, spacing=t.M,
                          horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                          alignment=ft.MainAxisAlignment.CENTER),
        alignment=ft.alignment.center,
        padding=ft.padding.all(t.XXL),
        expand=True,
    )


def cargando(mensaje=None):
    """Indicador de carga centrado."""
    controles = [ft.CupertinoActivityIndicator(radius=14, color=t.TEXTO_SEC)]
    if mensaje:
        controles.append(texto(mensaje, size=t.SUBHEAD, color=t.TEXTO_SEC))
    return ft.Container(
        content=ft.Column(controles, spacing=t.M,
                          horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                          alignment=ft.MainAxisAlignment.CENTER),
        alignment=ft.alignment.center,
        padding=ft.padding.all(t.XXL),
        expand=True,
    )


def deslizar_para_borrar(page, contenido, on_borrar, titulo=None, mensaje=None):
    """Envuelve una fila para poder borrarla deslizando hacia la izquierda.

    :param on_borrar: callback() que ejecuta el borrado real
    :param titulo: si se indica, se pide confirmación antes de borrar
    """
    fondo = ft.Container(
        bgcolor=t.DESTRUCTIVO,
        alignment=ft.alignment.center_right,
        padding=ft.padding.only(right=t.XL),
        content=ft.Icon(ft.CupertinoIcons.DELETE, color=ft.Colors.WHITE, size=22),
    )

    def al_confirmar(e):
        # Flet no lee el valor devuelto: hay que responder con confirm_dismiss(),
        # lo que permite resolverlo después de cerrar el diálogo.
        deslizable = e.control
        if titulo is None:
            deslizable.confirm_dismiss(True)
            return
        dialogo_confirmar(
            page,
            titulo,
            mensaje or "",
            on_aceptar=lambda: deslizable.confirm_dismiss(True),
            on_cancelar=lambda: deslizable.confirm_dismiss(False),
        )

    return ft.Dismissible(
        content=contenido,
        secondary_background=fondo,
        dismiss_direction=ft.DismissDirection.END_TO_START,
        dismiss_thresholds={ft.DismissDirection.END_TO_START: 0.4},
        on_dismiss=lambda _: on_borrar(),
        on_confirm_dismiss=al_confirmar,
    )


# ── Barras y diálogos ────────────────────────────────────────────────────────

def barra(titulo=None, izquierda=None, derecha=None, titulo_anterior=None):
    """AppBar Cupertino: título centrado, botón atrás automático."""
    return ft.CupertinoAppBar(
        leading=izquierda,
        middle=texto(titulo, size=t.HEADLINE, weight=t.SEMIBOLD) if titulo else None,
        trailing=derecha,
        previous_page_title=titulo_anterior,
        bgcolor=t.BARRA,
        border=ft.border.only(bottom=ft.BorderSide(0.5, t.SEPARADOR)),
    )


def dialogo_texto(page, titulo, placeholder, on_aceptar, valor="", mensaje=None,
                  etiqueta_aceptar="Guardar"):
    """Diálogo Cupertino con un campo de texto. Llama a on_aceptar(texto)."""
    campo = ft.CupertinoTextField(
        placeholder_text=placeholder,
        value=valor,
        autofocus=True,
        bgcolor=t.RELLENO,
        border_radius=t.RADIO_S,
        color=t.TEXTO,
        padding=ft.padding.symmetric(horizontal=t.M, vertical=t.S),
    )

    def cerrar(_=None):
        page.close(dialogo)

    def aceptar(_=None):
        valor_actual = (campo.value or "").strip()
        if not valor_actual:
            return
        page.close(dialogo)
        on_aceptar(valor_actual)

    campo.on_submit = aceptar

    cuerpo = [ft.Container(height=t.S)]
    if mensaje:
        cuerpo.append(texto(mensaje, size=t.FOOTNOTE, color=t.TEXTO_SEC,
                            align=ft.TextAlign.CENTER))
        cuerpo.append(ft.Container(height=t.S))
    cuerpo.append(campo)

    dialogo = ft.CupertinoAlertDialog(
        title=texto(titulo, size=t.HEADLINE, weight=t.SEMIBOLD),
        content=ft.Column(cuerpo, spacing=0, tight=True),
        actions=[
            ft.CupertinoDialogAction(text="Cancelar", on_click=cerrar),
            ft.CupertinoDialogAction(text=etiqueta_aceptar, is_default_action=True,
                                     on_click=aceptar),
        ],
    )
    page.open(dialogo)
    return dialogo


def dialogo_confirmar(page, titulo, mensaje, on_aceptar, on_cancelar=None,
                      etiqueta_aceptar="Eliminar"):
    """Diálogo de confirmación destructiva."""

    def cerrar(_=None):
        page.close(dialogo)
        if on_cancelar:
            on_cancelar()

    def aceptar(_=None):
        page.close(dialogo)
        on_aceptar()

    dialogo = ft.CupertinoAlertDialog(
        title=texto(titulo, size=t.HEADLINE, weight=t.SEMIBOLD),
        content=ft.Container(
            content=texto(mensaje, size=t.FOOTNOTE, color=t.TEXTO_SEC,
                          align=ft.TextAlign.CENTER),
            padding=ft.padding.only(top=t.S),
        ),
        actions=[
            ft.CupertinoDialogAction(text="Cancelar", on_click=cerrar),
            ft.CupertinoDialogAction(text=etiqueta_aceptar, is_destructive_action=True,
                                     on_click=aceptar),
        ],
    )
    page.open(dialogo)
    return dialogo


def aviso(page, mensaje):
    """Mensaje breve al pie de la pantalla."""
    page.open(ft.SnackBar(
        content=texto(mensaje, size=t.SUBHEAD, color=ft.Colors.WHITE),
        bgcolor=ft.Colors.with_opacity(0.9, ft.Colors.BLACK),
        behavior=ft.SnackBarBehavior.FLOATING,
        shape=ft.RoundedRectangleBorder(radius=t.RADIO_M),
        margin=ft.margin.all(t.L),
        duration=1800,
    ))
