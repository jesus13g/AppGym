import flet as ft
from .conexionBD import ConexionBD
from datetime import datetime, date, timedelta

class WidgetFactory:
    def __init__(self):
        self.Color_BLACK = ft.Colors.BLACK
        self.Color_WHITE = ft.Colors.WHITE
        self.Color_AMBER = ft.Colors.AMBER_100
        self.Color_GREY = "#656565"

    ##################################################################################################################

    def label_title(self, title: str):
        """Crea un título estilizado."""
        return ft.Text(value=title, size=24, color=self.Color_WHITE, weight="bold", text_align="center")

    ##################################################################################################################

    def label_simpleText(self, text: str, size=16, color="white"):
        """Crea un texto simple."""
        return ft.Text(value=text, size=16, color=color, text_align="left")

    ##################################################################################################################

    def button_simple(self, text: str, on_click, bgcolor=None):
        """Crea un botón simple."""
        return ft.ElevatedButton(text=text, on_click=on_click, bgcolor=bgcolor, style=ft.ButtonStyle(padding=10)) 


    def button_icon(self, icon, color, on_click, bgcolor=None):
        """Crea un botón con un icono."""
        return ft.ElevatedButton(content=ft.Icon(name=icon, color=color), on_click=on_click, bgcolor=bgcolor, style=ft.ButtonStyle(padding=10))

    ##################################################################################################################

    def create_slider(self, name: str, ejercicio_key: int, value_key: str, slider_values, min_value=0, max_value=100, start_value=50):
        """Crea un slider con un nombre y un label para mostrar su valor."""
        label_valorSlider = ft.Text(value="50", size=16, color=self.Color_GREY)

        def on_slider_change(e):
            # Actualizar el label
            label_valorSlider.value = f"{int(e.control.value)}"
            label_valorSlider.update()

            # Actualizar el valor en el diccionario
            slider_values[ejercicio_key][value_key] = int(e.control.value)

        slider = ft.Slider(min=min_value, max=max_value, value=start_value, on_change=on_slider_change, active_color=self.Color_GREY)

        return ft.Column([
            ft.Row([self.label_simpleText(name, color=self.Color_GREY), label_valorSlider], spacing=10),
            slider
        ], spacing=10)


    ##################################################################################################################

    def create_textInput(self, hint_text: str, height=60, multiline=False, font_size=16):
        """Crea un campo de entrada de texto."""
        return ft.TextField(
            hint_text=hint_text,
            multiline=multiline,
            height=height,
            text_size=font_size,
            bgcolor=self.Color_BLACK,
            color=self.Color_WHITE
        )

    ##################################################################################################################

    def create_appBar(self):
        """Crea una barra de aplicación."""
        return ft.AppBar(
            toolbar_height=20,
            force_material_transparency=True
        )
    ##################################################################################################################

    def create_containerRutinas(self, on_click_rutina):
        """Crea un contenedor con botones para las rutinas."""
        conexion = ConexionBD()
        rutinas = conexion.selectAll_rutinas()

        if not rutinas:
            print("No tienes rutinas :(")
            return self.label_simpleText("No tienes rutinas :(")

        buttons = [
            ft.ElevatedButton(
                text=rutina.nombre,
                on_click=lambda e, id=rutina.id: on_click_rutina(e, id)
            )
            for rutina in rutinas
        ]

        return ft.Column(buttons, spacing=10)

    ##################################################################################################################

    def create_containerEjercicios(self, id_rutina, on_click_ejercicio):
        """Crea un contenedor con botones para los ejercicios."""
        conexion = ConexionBD()
        ejercicios = conexion.selectAll_ejerciciosRutina(id_rutina)    

        if not ejercicios:
            print("No tienes ejercicios :(")
            return self.label_simpleText("No tienes ejercicios :(")
        buttons = [
            ft.ElevatedButton(
                text=ejercicio.nombre,
                on_click=lambda e, id=ejercicio.id: on_click_ejercicio(e, id)
            )
            for ejercicio in ejercicios
        ]

        return ft.Column(buttons, spacing=10)

    ##################################################################################################################s

    def create_containerEntrenamientoEjercicios(self, id_rutina, slider_values):
        conexion = ConexionBD()

        ejercicios = conexion.selectAll_ejerciciosRutina(id_rutina)

        container_ejercicios = []

        for ejercicio in ejercicios:
            # Clave única para cada ejercicio
            ejercicio_key = ejercicio.id

            # Inicializar valores por defecto
            slider_values[ejercicio_key] = {
                "series": 5,
                "repeticiones": 10,
                "peso": 50,
            }

            # Crear el contenido del desplegable
            sliders_content = ft.Column([
                self.create_slider("\tnº series:", ejercicio_key, "series", slider_values, 0, 10, 5),
                self.create_slider("\tnº repeticiones:", ejercicio_key, "repeticiones", slider_values, 0, 20, 10),
                self.create_slider("\tPeso (kg):", ejercicio_key, "peso", slider_values, 0, 150, 50)
                ], 
                spacing=10)

            # Crear el panel de expansión para cada ejercicio
            expansion_panel = ft.ExpansionPanel(
                header=self.label_simpleText("\t"+str(ejercicio.nombre), size=12, color=self.Color_GREY),
                bgcolor=ft.Colors.AMBER_300,
                content=sliders_content,
                expanded=False) # Inicia colapsado

            container_ejercicios.append(expansion_panel)
        
        return ft.ExpansionPanelList(container_ejercicios, spacing=10)


##################################################################################################################

    def create_barChart_pesos(self, pesos, fechas, n):
        # Crear los grupos de barras
        bar_groups = [
            ft.BarChartGroup(
                x=i,
                bar_rods=[ 
                    ft.BarChartRod(
                        from_y=0,
                        to_y=pesos[i],
                        width=40,
                        color=ft.Colors.BLUE,
                        tooltip=f"{fechas[i]} | Peso: {pesos[i]} kg",
                        border_radius=5
                    ),
                ],
            )
            for i in range(n)
        ]

        # Gráfico de barras
        chart = ft.BarChart(
            bar_groups=bar_groups,
            border=ft.border.all(1, ft.Colors.GREY_400),
            bottom_axis=ft.ChartAxis(
                labels=[
                    ft.ChartAxisLabel(
                        value=i, label=ft.Container(ft.Text(fechas[i]), padding=5)
                    )
                    for i in range(len(fechas))
                ],
                labels_size=12,
            ),
            horizontal_grid_lines=ft.ChartGridLines(
                color=ft.Colors.GREY_300, width=1, dash_pattern=[3, 3]
            ),
            tooltip_bgcolor=ft.Colors.with_opacity(0.8, ft.Colors.BLACK),
            max_y=max(pesos) + 10,  # Espacio adicional
            interactive=True,
            expand=True,
        )

        return chart


##################################################################################################################

    def create_table(self, headers, data):
        """
        Crea una tabla.
        headers: lista de strings
        data: lista de listas de strings
        """
        # Convertir datos a cadena
        dataStr = self.convert_dataToString(data)

        # Crear las cabeceras de la tabla
        table_headers = [
            ft.DataColumn(ft.Text(header, color=self.Color_WHITE)) for header in headers
        ]

        # Crear las filas de datos
        table_rows = [
            ft.DataRow(
                cells=[
                    ft.DataCell(
                        ft.Text(cell, color=self.Color_WHITE))
                    for cell in row
                ]
            )
            for row in dataStr
        ]

        # Retornar el DataTable
        return ft.DataTable(
            columns=table_headers,
            rows=table_rows,
            border=ft.border.all(1, self.Color_GREY),
            heading_row_color=self.Color_GREY,
            column_spacing=20,
        )


    def convert_dataToString(self, data):
        """Convierte los datos de la tabla a strings."""
        return [[str(cell) for cell in row] for row in data]


##################################################################################################################

    def generar_dias(self, mes, anio):
        primer_dia = date(anio, mes, 1)
        ultimo_dia = (
            primer_dia.replace(month=mes + 1) if mes < 12 else date(anio + 1, 1, 1)
        ) - timedelta(days=1)
        dias_mes = [primer_dia + timedelta(days=i) for i in range((ultimo_dia - primer_dia).days + 1)]
        return dias_mes

    
    def create_containerCalendario(self, mes, anio, fechas_entrenamientos=None):
        if fechas_entrenamientos is None:
            fechas_entrenamientos = []

        dias = self.generar_dias(mes, anio)

        # Crear el GridView
        grid = ft.GridView(
            expand=True,
            runs_count=7,  # 7 días de la semana
            spacing=5,
            run_spacing=5,
        )

        # Añadir encabezado de días de la semana
        dias_semana = ["L", "M", "X", "J", "V", "S", "D"]
        for dia in dias_semana:
            grid.controls.append(ft.Text(dia, weight="bold", color=self.Color_WHITE))

        # Calcular huecos iniciales para alinear el primer día
        primer_dia_semana = dias[0].weekday()
        for _ in range(primer_dia_semana):
            grid.controls.append(ft.Container())  # Espacios vacíos para los días previos al inicio del mes

        # Crear los días del calendario
        for dia in dias:
            # Establecer el color de fondo según si el día es especial
            bgcolor = (
                self.getColor_rutina(fechas_entrenamientos[dia])  # Color especial  
                if dia in fechas_entrenamientos
                else self.Color_AMBER  # Color normal
            )

            grid.controls.append(
                ft.Container(
                    content=ft.Text(str(dia.day), weight="bold", color=self.Color_BLACK),
                    alignment=ft.alignment.center,
                    bgcolor=bgcolor,
                    border_radius=ft.border_radius.all(20),
                )
            )

        return grid

    def getColor_rutina(self, id_rutina):
        colores = [
                ft.Colors.RED,
                ft.Colors.GREEN,
                ft.Colors.BLUE,
                ft.Colors.YELLOW,
                ft.Colors.ORANGE,
                ft.Colors.PURPLE,
                ft.Colors.CYAN
        ]
        return colores[id_rutina - 1]


##################################################################################################################

    def create_leyendaCalendario(self, rutinas):
        container_leyendaRutinas = ft.Row(spacing=20, alignment=ft.MainAxisAlignment.CENTER)
        conexion = ConexionBD()

        if rutinas is None:
            print("No tienes rutinas :(")
            return self.label_simpleText("No tienes rutinas :(")
        else:
            for r in rutinas:
                rutina = conexion.select_NombreRutina(id_rutina=r)
                if rutina is not None:
                    container_leyendaRutinas.controls.append(
                        self.label_simpleText(f"{conexion.select_NombreRutina(id_rutina=r).nombre}", 
                                                                                size=20, 
                                                                                color=self.getColor_rutina(r)
                        )
                    )
            return container_leyendaRutinas