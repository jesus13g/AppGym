import flet as ft
from app.utils.widgetFactory import WidgetFactory
from app.utils.conexionBD import ConexionBD

class ResultadoEjercicioScreen:
    def __init__(self, page: ft.Page, id_rutina, id_ejercicio):
        self.page = page
        self.widget_factory = WidgetFactory()
        self.conexion = ConexionBD()
        self.id_rutina = id_rutina
        self.id_ejercicio = id_ejercicio

    def mostrar(self):
        self.page.controls.clear()
        self.page.add(self.widget_factory.create_appBar())

        # Título de la pantalla
        nombreEjercicio = self.conexion.select_ejercicio(self.id_ejercicio).nombre
        titulo = self.widget_factory.label_title("Resultados " + nombreEjercicio)
        separadorSup = ft.Divider(height=20, thickness=0)

        # Obtener datos para el gráfico
        series = self.conexion.select_series_from_entrenamientos(self.id_rutina, self.id_ejercicio)
        fechas = [self.conexion.select_entrenamiento(serie.id_entrenamiento).fecha.strftime("%b %d") for serie in series]
        n_series = [serie.n_serie for serie in series]
        repeticiones = [serie.repeticiones for serie in series]
        pesos = [serie.peso for serie in series]

        n = len(series)

        data = self.transformar_a_filas(fechas, n_series, repeticiones, pesos)
        headers = ["Fecha", "Series", "Rep", "Peso(kg)"]

        chart = self.widget_factory.create_barChart_pesos(pesos, fechas, n)

        separadorInf = ft.Divider(height=20, thickness=0)

        table = self.widget_factory.create_table(headers=headers, data=data)

        # Botón para volver atrás
        button_back = self.widget_factory.button_icon(
            icon=ft.Icons.ARROW_BACK, color="blue", on_click=self.go_back
        )

        self.page.add(titulo, separadorSup, chart, table, separadorInf, button_back)

    def go_back(self, e):
        from app.screens.screensResultados.resultadoRutinaScreen import ResultadoRutinaScreen
        app = ResultadoRutinaScreen(self.page, self.id_rutina)
        app.mostrar()

    def transformar_a_filas(self, *arrays):
        """Convierte columnas en filas."""
        return [list(fila) for fila in zip(*arrays)]

