from datetime import datetime, date, timedelta
import flet as ft
from app.utils.widgetFactory import WidgetFactory
from app.utils.conexionBD import ConexionBD

class CalendarioScreen:
    def __init__(self, page: ft.Page):
        self.page = page
        self.widget_factory = WidgetFactory()
        self.conexion = ConexionBD()
        self.estado = {"mes_actual": datetime.today().month, "anio_actual": datetime.today().year}

    def mostrar(self):
        self.page.controls.clear()
        self.page.add(self.widget_factory.create_appBar())

        # Título
        titulo = self.widget_factory.label_title("Calendario de rutinas")

        # Separadores
        separadorSup = ft.Divider(height=20, thickness=0)
        separadorInf = ft.Divider(height=20, thickness=0)

        # Botón de regresar
        button_back = self.widget_factory.button_icon(icon=ft.Icons.ARROW_BACK, color="blue", on_click=self.go_back)

        fechas_entrenamientos = self.conexion.selectAll_entrenamientos()
        rutinas = set(fechas_entrenamientos.values())
        
        # Contenedor de leyenda de rutinas
        container_leyendaRutinas = self.widget_factory.create_leyendaCalendario(rutinas=rutinas)

        # Contenedor de calendario y botones de navegación
        self.container_calendario = ft.Column(spacing=20, alignment=ft.MainAxisAlignment.CENTER)

        navigation_row = ft.Row(
            controls=[
                self.widget_factory.button_icon(
                    icon=ft.Icons.KEYBOARD_DOUBLE_ARROW_LEFT, color="blue", on_click=self.mes_anterior
                ),
                self.widget_factory.button_icon(
                    icon=ft.Icons.KEYBOARD_DOUBLE_ARROW_RIGHT, color="blue", on_click=self.mes_siguiente
                ),
            ],
            spacing=40,
            alignment=ft.MainAxisAlignment.SPACE_AROUND,
        )

        # Agregar los controles a la página
        self.page.add(titulo, 
                        separadorSup, 
                        self.container_calendario, 
                        navigation_row, 
                        container_leyendaRutinas, 
                        separadorInf, 
                        button_back)

        # Generar el calendario inicial
        self.actualizar_calendario(fechas_entrenamientos=fechas_entrenamientos)


    def actualizar_calendario(self, fechas_entrenamientos=None):
        self.container_calendario.controls.clear()

        container_mesAnio = ft.Row(
            controls=[
                self.widget_factory.label_simpleText(
                    f"{self.mes_toStr(self.estado['mes_actual'])} - {self.estado['anio_actual']}", size=24
                )
            ],
            spacing=20, 
            alignment=ft.MainAxisAlignment.SPACE_EVENLY
        )

        self.container_calendario.controls.append(container_mesAnio)
        self.container_calendario.controls.append(
            self.widget_factory.create_containerCalendario(
                mes=self.estado["mes_actual"],
                anio=self.estado["anio_actual"],
                fechas_entrenamientos=fechas_entrenamientos,
            )
        )
        self.container_calendario.update()



    def mes_anterior(self, e):
        if self.estado["mes_actual"] == 1:
            self.estado["mes_actual"] = 12
            self.estado["anio_actual"] -= 1
        else:
            self.estado["mes_actual"] -= 1
        fechas_entrenamientos = self.conexion.selectAll_entrenamientos()
        self.actualizar_calendario(fechas_entrenamientos=fechas_entrenamientos)


    def mes_siguiente(self, e):
        if self.estado["mes_actual"] == 12:
            self.estado["mes_actual"] = 1
            self.estado["anio_actual"] += 1
        else:
            self.estado["mes_actual"] += 1
        fechas_entrenamientos = self.conexion.selectAll_entrenamientos()
        self.actualizar_calendario(fechas_entrenamientos=fechas_entrenamientos)


    def mes_toStr(self, int_mes):
        meses = [
            "Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio",
            "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"
        ]

        return meses[int_mes - 1]


    def go_back(self, e):
        from app.screens.screensResultados.resultadosScreen import ResultadosScreen
        app = ResultadosScreen(self.page)
        app.mostrar()
