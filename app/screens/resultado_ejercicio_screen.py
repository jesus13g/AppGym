"""Evolución de un ejercicio: gráfico de peso e histórico de series."""

import flet as ft

from app.theme import tokens as t
from app.theme import ui
from app.utils import formato

MAX_BARRAS = 12  # se muestran las últimas N sesiones para que el gráfico se lea


def vista(page, router, id_rutina, id_ejercicio):
    conexion = router.conexion
    ejercicio = conexion.select_ejercicio(id_ejercicio)
    registros = conexion.series_con_fecha(id_rutina, id_ejercicio)

    nombre = ejercicio.nombre if ejercicio else "Ejercicio"

    if not registros:
        return ft.View(
            appbar=ui.barra(nombre),
            controls=[ui.estado_vacio(
                ft.CupertinoIcons.CHART_BAR,
                "Sin registros todavía",
                "Registra un entrenamiento con este ejercicio para ver aquí su evolución.",
            )],
            padding=0,
        )

    recientes = registros[-MAX_BARRAS:]
    pesos = [r["peso"] for r in recientes]
    maximo = max(r["peso"] for r in registros)
    ultimo = registros[-1]

    resumen = ft.Container(
        content=ft.Row(
            [
                _dato(f"{ultimo['peso']:g} kg", "Último"),
                _dato(f"{maximo:g} kg", "Máximo"),
                _dato(str(len(registros)), "Sesiones"),
            ],
            alignment=ft.MainAxisAlignment.SPACE_AROUND,
        ),
        bgcolor=t.TARJETA,
        border_radius=t.RADIO_L,
        padding=ft.padding.symmetric(vertical=t.L),
        margin=ft.margin.symmetric(horizontal=t.L),
    )

    grafico = ft.Container(
        content=_grafico(pesos, [formato.fecha_corta(r["fecha"]) for r in recientes]),
        height=240,
        bgcolor=t.TARJETA,
        border_radius=t.RADIO_L,
        padding=ft.padding.only(left=t.S, right=t.L, top=t.XL, bottom=t.S),
        margin=ft.margin.symmetric(horizontal=t.L),
    )

    historico = ui.grupo(
        [
            ui.fila(
                formato.fecha_larga(r["fecha"]),
                subtitulo=f"{r['series']} series × {r['repeticiones']} repeticiones",
                valor=f"{r['peso']:g} kg",
                chevron=False,
            )
            for r in reversed(registros)
        ],
        cabecera="Histórico",
    )

    cuerpo = ft.Column(
        [
            ui.titulo_grande(nombre),
            resumen,
            ft.Container(height=t.L),
            grafico,
            ft.Container(height=t.XL),
            historico,
            ft.Container(height=t.XXL),
        ],
        spacing=0,
        scroll=ft.ScrollMode.AUTO,
        expand=True,
    )

    return ft.View(
        appbar=ui.barra(nombre),
        controls=[ft.SafeArea(cuerpo, expand=True)],
        padding=0,
    )


def _dato(valor, etiqueta):
    return ft.Column(
        [
            ui.texto(valor, size=t.TITLE3, weight=t.SEMIBOLD, align=ft.TextAlign.CENTER),
            ui.texto(etiqueta, size=t.CAPTION, color=t.TEXTO_SEC, align=ft.TextAlign.CENTER),
        ],
        spacing=2,
        horizontal_alignment=ft.CrossAxisAlignment.CENTER,
        tight=True,
    )


def _grafico(pesos, fechas):
    """Gráfico de barras del peso por sesión, con el estilo plano de iOS."""
    grupos = [
        ft.BarChartGroup(
            x=i,
            bar_rods=[
                ft.BarChartRod(
                    from_y=0,
                    to_y=peso,
                    width=16,
                    color=t.ACENTO,
                    tooltip=f"{fechas[i]} · {peso:g} kg",
                    border_radius=ft.border_radius.vertical(top=6),
                )
            ],
        )
        for i, peso in enumerate(pesos)
    ]

    return ft.BarChart(
        bar_groups=grupos,
        bottom_axis=ft.ChartAxis(
            labels=[
                ft.ChartAxisLabel(
                    value=i,
                    label=ft.Container(
                        content=ui.texto(fechas[i], size=t.CAPTION - 2, color=t.TEXTO_SEC),
                        padding=ft.padding.only(top=t.XS),
                    ),
                )
                for i in range(len(fechas))
            ],
            labels_size=26,
        ),
        left_axis=ft.ChartAxis(labels_size=34),
        horizontal_grid_lines=ft.ChartGridLines(color=t.SEPARADOR, width=0.5,
                                                dash_pattern=[4, 4]),
        tooltip_bgcolor=ft.Colors.with_opacity(0.85, ft.Colors.BLACK),
        # `pesos` nunca está vacío aquí, pero el +10% evita que la barra más alta
        # quede pegada al borde superior.
        max_y=max(pesos) * 1.15 + 1,
        interactive=True,
        expand=True,
    )
