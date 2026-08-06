# AppGym — Especificaciones de nuevas funcionalidades

> Documento de especificación funcional y técnica para la siguiente iteración de AppGym.
> Escrito sobre el código actual (rama `main`, commit `fe6438a`): Flet 0.25.2 + SQLAlchemy 2.0
> sobre SQLite, catálogo de 1.324 ejercicios, 9 pantallas y navegación por pila (`app/router.py`).

## Índice

- [0. Cómo leer este documento](#0-cómo-leer-este-documento)
- [A. Limitaciones del modelo de datos](#a-limitaciones-del-modelo-de-datos)
  - [A1. Series independientes por ejercicio](#a1-series-independientes-por-ejercicio)
  - [A2. Editar y borrar entrenamientos](#a2-editar-y-borrar-entrenamientos)
  - [A3. Registrar un entrenamiento en otra fecha](#a3-registrar-un-entrenamiento-en-otra-fecha)
  - [A4. Ordenar ejercicios dentro de la rutina](#a4-ordenar-ejercicios-dentro-de-la-rutina)
  - [A5. Notas y RPE](#a5-notas-y-rpe)
  - [A6. Varias rutinas el mismo día](#a6-varias-rutinas-el-mismo-día)
- [B. Funcionalidades nuevas de uso diario](#b-funcionalidades-nuevas-de-uso-diario)
  - [B7. Temporizador de descanso](#b7-temporizador-de-descanso)
  - [B8. Entrenamiento en curso (sesión viva)](#b8-entrenamiento-en-curso-sesión-viva)
  - [B9. Pantalla de Ajustes](#b9-pantalla-de-ajustes)
  - [B10. Copia de seguridad: exportar e importar](#b10-copia-de-seguridad-exportar-e-importar)
  - [B11. Duplicar rutina y plantillas](#b11-duplicar-rutina-y-plantillas)
  - [B12. Favoritos y «añadir a rutina» desde el catálogo](#b12-favoritos-y-añadir-a-rutina-desde-el-catálogo)
  - [B13. Peso corporal y medidas](#b13-peso-corporal-y-medidas)
- [C. Progreso y análisis](#c-progreso-y-análisis)
  - [C16. 1RM estimado](#c16-1rm-estimado)
  - [C17. Resumen semanal y racha](#c17-resumen-semanal-y-racha)
  - [C19. Días del calendario pulsables](#c19-días-del-calendario-pulsables)
- [D. Mapa muscular interactivo](#d-mapa-muscular-interactivo)
- [E. Modelo de datos consolidado](#e-modelo-de-datos-consolidado)
- [F. Plan de entrega](#f-plan-de-entrega)
- [G. Fuera de alcance](#g-fuera-de-alcance)
- [H. Decisiones pendientes](#h-decisiones-pendientes)

---

## 0. Cómo leer este documento

Cada especificación tiene la misma estructura:

| Campo | Significado |
|---|---|
| **Problema** | Qué falla o falta hoy, con referencia al fichero y línea actuales |
| **Comportamiento** | Qué debe hacer la app, en términos de usuario |
| **Interfaz** | Pantallas, controles y navegación |
| **Datos** | Cambios en `app/utils/modelo.py` y migración |
| **API de datos** | Métodos nuevos o modificados en `app/utils/conexionBD.py` |
| **Criterios de aceptación** | Lista verificable; es lo que se prueba antes de dar por cerrado el punto |
| **Riesgos** | Lo que puede romperse |

**Convenciones transversales que aplican a todo el documento:**

1. **Compatibilidad de datos.** Ninguna migración puede perder rutinas, ejercicios ni histórico.
   Cada cambio de esquema es idempotente y se ejecuta desde `ConexionBD.create_tablas()`.
2. **Versionado del esquema.** Se adopta `PRAGMA user_version` de SQLite como número de versión
   del esquema. El bloque `_migrar_columnas()` actual (`app/utils/conexionBD.py:67`) pasa a ser la
   migración `1`; cada punto de este documento que toque el esquema añade la suya. Esto sustituye
   al `PRAGMA table_info` a mano en las migraciones que transforman datos (no solo añaden columnas),
   porque esas **no** son repetibles sin corromper.
3. **Unidades.** Internamente **todo peso se guarda siempre en kilogramos**. La conversión a libras
   es exclusivamente de presentación (ver [B9](#b9-pantalla-de-ajustes)).
4. **Estilo.** Nada de widgets Material sueltos: se usan los componentes de `app/theme/ui.py` y los
   tokens de `app/theme/tokens.py`. Todo control nuevo que se repita dos veces se sube a `ui.py`.
5. **Idioma.** Interfaz y comentarios en español, igual que el código actual.
6. **Disponibilidad de widgets.** El entorno de desarrollo no tenía Flet instalado al redactar esto,
   así que cada control de Flet 0.25.2 que no sea de uso ya probado en el repo se marca con
   ⚠️ *verificar* y lleva una alternativa. No se debe subir la versión de Flet dentro de esta
   iteración: el rediseño iOS actual está calibrado contra 0.25.2.

---

## A. Limitaciones del modelo de datos

### A1. Series independientes por ejercicio

> **Es la especificación central de esta iteración.** C16, C17 y D dependen de ella, y B8 se
> beneficia directamente. Debe implementarse antes que ninguna otra del bloque A.

**Problema.**
`Serie` (`app/utils/modelo.py:68`) guarda **una única fila agregada** por ejercicio y sesión:
`n_serie` es *el número de series*, no el índice de una serie. Registrar 4 series obliga a que las
cuatro compartan repeticiones y peso. En la práctica, un entrenamiento real casi nunca es así:
pirámides, drop sets, o simplemente que la última serie baja de 50 a 45 kg. Hoy eso no se puede
anotar, y el gráfico de `resultado_ejercicio_screen.py` está midiendo un dato que el usuario ha
tenido que redondear a mano.

**Comportamiento.**

- Cada serie es una fila propia, con sus repeticiones y su peso.
- En la pantalla de registro, cada ejercicio muestra la lista de sus series, con:
  - añadir serie (copia los valores de la última, que es el gesto más frecuente),
  - eliminar serie (deslizando, coherente con el resto de la app),
  - editar repeticiones y peso de cada una de forma independiente.
- Al abrir el registro, las series se precargan con **las de la última sesión de ese ejercicio**
  (número de series incluido), no con un valor agregado.
- Una serie puede marcarse como **serie de calentamiento**: se guarda, pero queda excluida de todas
  las métricas de volumen, récords y 1RM.

**Interfaz.**

Se rehace `_tarjeta()` de `app/screens/entrenar_screen.py:87`. Cada tarjeta de ejercicio pasa de
tres steppers a una tabla compacta:

```
┌──────────────────────────────────────────────┐
│ [img] Barbell Bench Press              [ ⌄ ] │
│       Último: 4 series · 8.750 kg            │
├──────────────────────────────────────────────┤
│  #   Repeticiones      Peso                  │
│  1      [ 10 ]       [ 60,0 kg ]      ·      │  ← «·» = menú (calentamiento / borrar)
│  2      [ 10 ]       [ 60,0 kg ]      ·      │
│  3      [  8 ]       [ 65,0 kg ]      ·      │
│  4      [  6 ]       [ 70,0 kg ]      ·      │
│                                              │
│           + Añadir serie                     │
└──────────────────────────────────────────────┘
```

- La fila de serie usa un `ui.stepper` compacto nuevo (`ui.stepper_linea`), en horizontal y sin
  etiqueta, para que quepan repeticiones y peso en la misma línea. El stepper actual
  (`app/theme/ui.py:221`) se mantiene y se refactoriza para compartir la lógica de incremento,
  límites y formato decimal.
- El interruptor de «incluir ejercicio» actual se sustituye por el colapso del ejercicio: un
  ejercicio **sin series** simplemente no se guarda. Esto elimina el estado `incluidos` de
  `entrenar_screen.py:36`.
- La serie de calentamiento se pinta con el número en gris y un icono de llama.

**Datos.**

```python
class Serie(Base):
    __tablename__ = 'serie'
    id = Column(Integer, primary_key=True)
    id_entrenamiento = Column(Integer, ForeignKey('entrenamiento.id', ondelete='CASCADE'), nullable=False)
    id_ejercicio = Column(Integer, ForeignKey('ejercicio.id', ondelete='CASCADE'), nullable=False)
    n_serie = Column(Integer, nullable=False)      # AHORA: índice 1..N dentro del ejercicio
    repeticiones = Column(Integer, nullable=False)
    peso = Column(Float, nullable=False)           # siempre en kg
    calentamiento = Column(Boolean, nullable=False, default=False)
    # rpe y nota se añaden en A5
```

Se conserva el nombre `n_serie` para no tocar el resto de consultas por el nombre de la columna,
**pero cambia su semántica**. El docstring del modelo debe dejarlo explícito, porque es exactamente
el tipo de cambio que confunde seis meses después.

**Migración (`user_version` 1 → 2), no repetible:**

1. Para cada fila existente con `n_serie = N`, crear `N` filas con `n_serie = 1..N` y las mismas
   `repeticiones` y `peso`.
2. `calentamiento = 0` en todas.
3. Se hace en una única transacción; si falla, `ROLLBACK` y la app arranca con el esquema anterior
   avisando por consola.
4. Antes de ejecutarla se copia `DataBase.db` a `DataBase.db.bak-v1` en el mismo directorio.

El histórico así migrado es **fiel**: 4 series de 10×60 kg se convierten en 4 filas de 10×60 kg,
que es justo lo que el usuario quiso decir.

**API de datos.**

| Método | Cambio |
|---|---|
| `insert_newEntrenamiento(id_rutina, fecha, series)` | `series` pasa de `dict[id_ejercicio -> {series, repeticiones, peso}]` a `dict[id_ejercicio -> list[{repeticiones, peso, calentamiento}]]` |
| `ultima_serie_ejercicio(id_ejercicio)` | Devuelve `list[dict]` con todas las series de la última sesión, no un solo dict |
| `series_con_fecha(id_rutina, id_ejercicio)` | Devuelve una entrada por serie; quien necesite agregado lo calcula |
| `resumen_sesiones_ejercicio(id_rutina, id_ejercicio)` | **Nuevo.** Agrega por sesión: fecha, nº de series efectivas, volumen, peso máximo, mejor 1RM estimado |

`resultado_ejercicio_screen.py` pasa a consumir `resumen_sesiones_ejercicio`, con lo que el gráfico
deja de mezclar series sueltas en el eje X (hoy pinta una barra por fila, que tras esta migración
serían varias barras por sesión).

**Criterios de aceptación.**

- [ ] Una base de datos de la versión anterior se abre sin pérdida: mismo número de rutinas, mismos
      ejercicios y el mismo volumen total antes y después.
- [ ] Se puede registrar una sesión con series de distinto peso y se muestra correctamente en el
      histórico.
- [ ] Al abrir el registro de una rutina ya entrenada, se precargan tantas filas como series tuvo
      la última sesión, con sus valores.
- [ ] Las series de calentamiento no aparecen en volumen, máximos ni 1RM.
- [ ] Arrancar la app dos veces seguidas no duplica las series (migración idempotente vía
      `user_version`).
- [ ] Existe `DataBase.db.bak-v1` tras la primera migración.

**Riesgos.** Es la única migración destructiva del documento. Sin el respaldo previo y sin el
`user_version`, un fallo a mitad multiplica las series en cada arranque. Debe ir acompañada de
tests (ver [F. Plan de entrega](#f-plan-de-entrega)).

---

### A2. Editar y borrar entrenamientos

**Problema.**
`app/utils/conexionBD.py` tiene `insert_newEntrenamiento` y varios `select`, pero **ningún `update`
ni `delete` de entrenamientos**. Una sesión guardada por error se queda para siempre: contamina el
gráfico, el calendario y —tras C16/C17— las estadísticas. Además no hay ninguna pantalla desde la
que listar las sesiones pasadas de una rutina.

**Comportamiento.**

- Desde el detalle de una rutina se accede a **Historial de sesiones**: lista de entrenamientos de
  esa rutina, más recientes primero, con fecha, nº de ejercicios y volumen total.
- Al pulsar una sesión se abre su detalle: los ejercicios con sus series, en solo lectura.
- Desde el detalle: **Editar** (reabre el formulario de registro con los datos cargados) y
  **Eliminar** (con `ui.dialogo_confirmar`, texto destructivo).
- También se puede eliminar deslizando la fila en el historial, igual que rutinas y ejercicios.

**Interfaz.**

- Nueva pantalla `app/screens/historial_screen.py` → ruta `historial`, parámetro `id_rutina`.
- Nueva pantalla `app/screens/sesion_screen.py` → ruta `sesion`, parámetro `id_entrenamiento`.
- En `rutina_screen.py`, la tarjeta de estadísticas (`rutina_screen.py:52`) pasa a ser pulsable en
  su bloque «Sesiones» y lleva al historial.
- `entrenar_screen.vista` acepta un parámetro opcional `id_entrenamiento`. Si viene informado:
  título «Editar entrenamiento», las series se cargan de esa sesión y al guardar se hace `update`
  en lugar de `insert`.

**Datos.** Sin cambios de esquema.

**API de datos.**

```python
def select_entrenamiento_completo(self, id_entrenamiento) -> dict | None
    # {"id", "fecha", "id_rutina", "nombre_rutina", "nota",
    #  "ejercicios": [{"id", "nombre", "id_catalogo", "series": [...]}]}

def update_entrenamiento(self, id_entrenamiento, fecha, series: dict) -> bool
    # Reemplaza en bloque las series de la sesión, en una única transacción

def delete_entrenamiento(self, id_entrenamiento) -> bool

def historial_rutina(self, id_rutina, limit=50, offset=0) -> list[dict]
    # [{"id", "fecha", "n_ejercicios", "n_series", "volumen"}]
```

`update_entrenamiento` borra las series de la sesión y las reinserta; no intenta hacer *diff*, que
para el tamaño de los datos no aporta nada y sí complica el código.

**Criterios de aceptación.**

- [ ] Se puede corregir el peso de una serie de una sesión de hace un mes y el gráfico refleja el
      cambio inmediatamente.
- [ ] Al eliminar un entrenamiento desaparece del calendario, del historial y de las estadísticas
      de la rutina, y sus series se borran (verificable con `SELECT count(*) FROM serie`).
- [ ] Editar una sesión **no** cambia su fecha salvo que se cambie explícitamente (A3).
- [ ] Eliminar pide confirmación y el texto avisa de que no se puede deshacer.

**Riesgos.** El `cascade` de SQLAlchemy ya cubre el borrado de series; conviene confirmarlo con un
test en vez de asumirlo, porque SQLite no aplica `ON DELETE CASCADE` salvo que se active
`PRAGMA foreign_keys = ON`, cosa que **hoy no se hace en ninguna parte del proyecto**.
Activarlo entra en el alcance de este punto.

---

### A3. Registrar un entrenamiento en otra fecha

**Problema.**
`entrenar_screen.py:44` fija `datetime.now()` al guardar. No se puede anotar el entrenamiento de
ayer, que es exactamente lo que pasa cuando uno se acuerda de la app al día siguiente.

**Comportamiento.**

- La cabecera del registro (`entrenar_screen.py:50`) muestra la fecha y es pulsable.
- Al pulsarla se abre un selector de fecha; por defecto, hoy.
- No se permiten fechas futuras. El límite inferior es la fecha de creación de la rutina o, en su
  defecto, sin límite.
- Al editar una sesión existente (A2), el selector arranca en su fecha original.
- La hora se conserva: si se elige un día pasado, se guarda a las 12:00 de ese día, para que el
  orden dentro del día sea estable y no dependa de la hora en que se anotó.

**Interfaz.**
`ft.CupertinoDatePicker` dentro de un `ft.CupertinoBottomSheet` ⚠️ *verificar disponibilidad en
0.25.2*. Alternativa si no está: un selector propio con tres `ft.CupertinoPicker` (día, mes, año)
o, más simple, atajos «Hoy / Ayer / Anteayer» más un campo de texto con formato `dd/mm/aaaa`
validado. La alternativa de atajos cubre el 90 % de los casos reales y es la que se implementa si
el picker da problemas.

**Datos.** Sin cambios de esquema.

**API de datos.** `insert_newEntrenamiento` ya recibe `fecha`; basta con dejar de pasarle
`datetime.now()` fijo.

**Criterios de aceptación.**

- [ ] Se puede guardar un entrenamiento con fecha de ayer y aparece en el día correcto del
      calendario.
- [ ] No se puede seleccionar una fecha futura.
- [ ] La fecha elegida se muestra formateada con `formato.fecha_larga` en la cabecera antes de
      guardar.

---

### A4. Ordenar ejercicios dentro de la rutina

**Problema.**
`selectAll_ejerciciosRutina` (`app/utils/conexionBD.py:356`) ordena por `Ejercicio.id`, es decir,
por orden de inserción. No hay forma de reordenar: si añades el press de banca después de las
aperturas, se queda debajo para siempre. En una rutina el orden **es** la rutina.

**Comportamiento.**

- Modo «Editar» en el detalle de la rutina que permite reordenar los ejercicios.
- El orden se respeta en el detalle de la rutina, en el registro de entrenamiento y en el detalle
  de sesión.
- Los ejercicios ya existentes conservan su orden actual (el de inserción) tras la migración.
- Extra del mismo punto: **mover un ejercicio a otra rutina**, en el menú de la fila. Se mueve el
  ejercicio con su histórico de series intacto.

**Interfaz.**

- Botón «Editar» en la barra de `rutina_screen`. Al activarlo, cada fila muestra las asas de
  reordenación y desaparece el `chevron`.
- Control: `ft.ReorderableListView` ⚠️ *verificar disponibilidad en 0.25.2 — probablemente no
  exista en esa versión*. **Alternativa por defecto:** en modo edición, cada fila muestra dos
  botones ▲▼ que la suben o bajan una posición, con guardado inmediato. Es menos vistoso pero
  funciona en cualquier versión y es accesible con el pulgar.

**Datos.**

```python
class Ejercicio(Base):
    ...
    orden = Column(Integer, nullable=False, default=0)
```

**Migración (`user_version` → +1):** por cada rutina, asignar `orden = 0,1,2…` siguiendo el `id`
actual. Repetible sin daño (recalcula lo mismo) siempre que se ejecute solo si la columna acaba de
crearse.

**API de datos.**

```python
def reordenar_ejercicios(self, id_rutina, ids_en_orden: list[int]) -> bool
def mover_ejercicio(self, id_ejercicio, id_rutina_destino) -> bool
```

`selectAll_ejerciciosRutina` pasa a ordenar por `Ejercicio.orden, Ejercicio.id` (el `id` como
desempate defensivo). `insert_newEjercicio` asigna `orden = max(orden)+1` de la rutina.

**Criterios de aceptación.**

- [ ] Reordenar en la rutina cambia el orden en la pantalla de registro.
- [ ] El orden persiste tras cerrar y abrir la app.
- [ ] Mover un ejercicio a otra rutina conserva sus series (aparece en el histórico de la nueva).
- [ ] Una BD antigua abre con los ejercicios en el mismo orden que tenía.

**Riesgos.** `mover_ejercicio` puede crear un duplicado en la rutina de destino si el mismo
ejercicio de catálogo ya está allí; hay que comprobarlo y avisar, reutilizando la lógica de
`insert_newEjercicio` (`conexionBD.py:277`).

---

### A5. Notas y RPE

**Problema.**
No hay ningún campo libre en toda la app. «Hoy me dolía el hombro», «con cinturón», «fallo en la
última» no se pueden anotar, y son justo la información que explica un bajón en el gráfico tres
semanas después.

**Comportamiento.**

- **Nota de sesión:** un campo de texto libre al final del registro de entrenamiento.
- **Nota de serie:** opcional, en el menú de cada serie, para casos concretos (una sola frase).
- **RPE / RIR por serie:** valor opcional de 6 a 10 en medios puntos (RPE) o de 0 a 4 (RIR). Se
  elige cuál de las dos escalas se usa en Ajustes ([B9](#b9-pantalla-de-ajustes)); el valor se
  guarda **siempre normalizado como RPE** y se convierte al mostrar (`RIR = 10 − RPE`).
- Los indicadores son opcionales: si el usuario nunca los usa, no debe verlos estorbando. El campo
  RPE solo se despliega si está activado en Ajustes (por defecto, **desactivado**).

**Interfaz.**

- La nota de sesión es un `ui.campo_texto` multilínea dentro de un `ui.grupo` con cabecera «Notas».
- El RPE es un selector segmentado compacto en la fila de la serie, visible solo con la opción
  activada.
- Las sesiones con nota muestran un icono de globo en el historial (A2) y en el detalle del día
  (C19).

**Datos.**

```python
class Entrenamiento(Base):
    ...
    nota = Column(String, nullable=True)

class Serie(Base):
    ...
    rpe = Column(Float, nullable=True)     # 6.0–10.0, siempre en escala RPE
    nota = Column(String, nullable=True)
```

**Migración:** solo columnas nuevas; encaja en el mecanismo existente `_migrar_columnas()`.

**API de datos.** `insert_newEntrenamiento` y `update_entrenamiento` aceptan `nota` y propagan
`rpe`/`nota` por serie. Nuevo: `series_con_rpe(id_ejercicio, desde)` para el futuro análisis de
esfuerzo (no se explota todavía en esta iteración, pero el dato ya se recoge).

**Criterios de aceptación.**

- [ ] Se puede guardar una nota de sesión y se ve al abrir esa sesión.
- [ ] Con el RPE desactivado en Ajustes, la interfaz del registro es idéntica a no tenerlo.
- [ ] Cambiar de escala RPE a RIR en Ajustes reinterpreta los valores ya guardados sin migrarlos.

---

### A6. Varias rutinas el mismo día

**Problema.**
`selectAll_entrenamientos()` (`app/utils/conexionBD.py:678`) devuelve `dict[date] -> id_rutina`.
Si se entrenan dos rutinas el mismo día, **la segunda sobrescribe a la primera** y el calendario
solo pinta una. El propio docstring lo reconoce. Además carga en memoria todos los entrenamientos
de la historia para pintar un mes.

**Comportamiento.**

- Un día puede contener varias sesiones, de la misma rutina o de rutinas distintas.
- El calendario refleja visualmente que hubo más de una.
- El detalle del día (C19) las lista todas.

**Interfaz.**

- Celda con **una** sesión: círculo relleno del color de la rutina (comportamiento actual).
- Celda con **dos o más** sesiones: círculo partido en tantos sectores como rutinas distintas
  (dos mitades, tres tercios; a partir de 4 se muestran tres sectores más un punto). Implementado
  con un `ft.Stack` de contenedores con `border_radius` y recorte, o con
  `flet.canvas` si se implementa D (que ya introduce el dibujo vectorial).
  Fallback simple si complica: círculo del color de la primera sesión más un punto pequeño en la
  esquina indicando «hay más».
- La leyenda del mes ya agrupa por rutina y no necesita cambios más allá de la nueva firma.

**Datos.** Sin cambios de esquema.

**API de datos.**

```python
def entrenamientos_por_dia(self, desde: date, hasta: date) -> dict[date, list[dict]]
    # {date: [{"id", "id_rutina", "nombre", "color", "fecha"}]}
```

Sustituye a `selectAll_entrenamientos()`, que se elimina. **Recibe rango**, de modo que el
calendario consulta solo el mes visible en lugar de toda la historia.

**Criterios de aceptación.**

- [ ] Dos entrenamientos de rutinas distintas el mismo día pintan la celda partida.
- [ ] Dos entrenamientos de la **misma** rutina el mismo día pintan la celda de un solo color.
- [ ] Pintar el calendario de un mes no consulta entrenamientos de otros meses (verificable con el
      log de SQL de SQLAlchemy).

---

## B. Funcionalidades nuevas de uso diario

### B7. Temporizador de descanso

**Problema.**
Es la ausencia más llamativa para una app de gimnasio. Hoy el usuario cronometra el descanso con el
móvil aparte, lo que rompe el flujo de uso de la propia app.

**Comportamiento.**

- Al marcar una serie como completada ([B8](#b8-entrenamiento-en-curso-sesión-viva)) o al pulsar el
  botón de descanso, arranca una cuenta atrás.
- Duración por defecto configurable globalmente (Ajustes) y **anulable por ejercicio**: los
  descansos de sentadilla y de curl de bíceps no son iguales.
- Durante la cuenta atrás:
  - barra de progreso fija en la parte inferior de la pantalla de entrenamiento, sobre la barra de
    acciones, con el tiempo restante en grande;
  - botones **+15 s**, **−15 s** y **Saltar**;
  - la app sigue siendo navegable: se puede consultar la ficha de un ejercicio sin perder la cuenta.
- Al llegar a cero: aviso sonoro (si está activado), vibración en móvil (si está disponible) y el
  contador pasa a contar **hacia arriba** en gris, para que se vea cuánto se ha excedido.
- El temporizador sobrevive a la navegación dentro de la app, pero **no** a cerrarla.

**Interfaz.**

- Nuevo componente `ui.barra_descanso(page, segundos, al_terminar)` en `app/theme/ui.py`.
- Implementación del reloj: tarea asíncrona con `page.run_task` que actualiza el control cada
  segundo ⚠️ *verificar `page.run_task` en 0.25.2*. Alternativa: `threading.Timer` encadenado con
  `page.update()`; hay que garantizar la cancelación al salir de la vista para no dejar hilos
  colgando (`router.volver()` debe poder cancelarla).
- El tiempo restante **no** se calcula acumulando ticks sino como `fin − datetime.now()`, para que
  no se desfase si el sistema pausa la app.
- Sonido: `ft.Audio` requiere el paquete `flet-audio`, que **no está en `requirements.txt`**.
  Se añade como dependencia opcional; si no está instalado, el aviso es solo visual y no falla.

**Datos.**

```python
class Ejercicio(Base):
    ...
    descanso_seg = Column(Integer, nullable=True)   # NULL = usar el valor global
```

**Criterios de aceptación.**

- [ ] La cuenta atrás es exacta a ±1 s tras 3 minutos, incluso navegando entre pantallas.
- [ ] +15 s y −15 s ajustan sin reiniciar.
- [ ] Salir del entrenamiento cancela el temporizador y no deja hilos vivos.
- [ ] Sin `flet-audio` instalado, la app arranca y el temporizador funciona sin sonido.

**Riesgos.** Los temporizadores son la fuente clásica de fugas de hilos en Flet. La cancelación debe
estar cubierta por un test o, como mínimo, por una comprobación manual documentada.

---

### B8. Entrenamiento en curso (sesión viva)

**Problema.**
`entrenar_screen` es hoy un **formulario**: se rellena entero y se guarda al final. Eso no encaja
con cómo se usa una app en el gimnasio, donde se va anotando serie a serie durante una hora. Y si la
app se cierra a media sesión (una llamada, batería), se pierde todo lo introducido.

**Comportamiento.**

- Se empieza el entrenamiento y la sesión queda **en curso**: hay un cronómetro de duración total y
  cada serie se marca conforme se completa.
- Cabecera con progreso: `«8 / 20 series · 34:12»`.
- Al completar una serie se dispara automáticamente el descanso ([B7](#b7-temporizador-de-descanso)).
- **Recuperación:** si la app se cierra con una sesión en curso, al volver a abrirla ofrece
  «Tienes un entrenamiento de *Empuje* empezado hace 12 minutos» → *Continuar* / *Descartar*.
- Al terminar se guarda la sesión con su duración y se muestra un **resumen de cierre**: volumen
  total, series completadas, duración, récords batidos ([C16](#c16-1rm-estimado)) y músculos
  trabajados ([D](#d-mapa-muscular-interactivo)).
- El modo formulario actual **se mantiene** como alternativa: registrar una sesión pasada (A3) no
  puede exigir un cronómetro. La diferencia es el punto de entrada: «Empezar entrenamiento» abre la
  sesión viva; «Registrar sesión anterior» abre el formulario.

**Interfaz.**

- `entrenar_screen` gana un parámetro `modo` (`"vivo"` | `"formulario"`).
- En modo vivo, cada fila de serie tiene un `checkbox` circular a la izquierda; al marcarlo, la fila
  se atenúa y se colapsa.
- Botón flotante inferior: «Terminar entrenamiento».
- Nueva pantalla `app/screens/resumen_sesion_screen.py` para el cierre.
- El aviso de recuperación es un `ui.dialogo_confirmar` lanzado desde `app/gymApp.py` al arrancar.

**Datos.**

```python
class Entrenamiento(Base):
    ...
    duracion_seg = Column(Integer, nullable=True)

class SesionActiva(Base):
    """Borrador de la sesión en curso. Tabla de una sola fila."""
    __tablename__ = 'sesion_activa'
    id = Column(Integer, primary_key=True)
    id_rutina = Column(Integer, ForeignKey('rutina.id', ondelete='CASCADE'), nullable=False)
    inicio = Column(DateTime, nullable=False)
    actualizado = Column(DateTime, nullable=False)
    estado = Column(String, nullable=False)     # JSON con las series y su estado
```

El borrador se guarda como JSON, no normalizado: es un dato efímero, se reescribe entero en cada
cambio y no se consulta nunca por partes. Se guarda con *debounce* de 2 s para no escribir en disco
en cada pulsación de un stepper.

**API de datos.**

```python
def guardar_sesion_activa(self, id_rutina, inicio, estado: dict) -> bool
def leer_sesion_activa(self) -> dict | None
def descartar_sesion_activa(self) -> None
```

Al confirmar el entrenamiento, `insert_newEntrenamiento` y `descartar_sesion_activa` deben ocurrir
en la **misma transacción**, para que no exista un instante en que la sesión esté guardada y el
borrador también (aparecería un falso «tienes una sesión en curso»).

**Criterios de aceptación.**

- [ ] Matar el proceso a mitad de sesión y reabrir recupera todas las series ya marcadas.
- [ ] Descartar el borrador no deja rastro y no vuelve a preguntar.
- [ ] La duración guardada coincide con el tiempo real transcurrido (±5 s).
- [ ] El modo formulario sigue funcionando exactamente como antes para sesiones pasadas.

---

### B9. Pantalla de Ajustes

**Problema.**
No existe ninguna pantalla de configuración. Hay valores razonables pero **fijos en el código** que
el usuario debería poder cambiar: el paso del peso está clavado a 2,5 kg
(`entrenar_screen.py:104`), los valores por defecto son `4×10×20 kg` (`entrenar_screen.py:11`), y la
unidad es siempre el kilogramo. Además, varias de las funcionalidades de este documento (B7, A5,
C17, D) necesitan un sitio donde vivir.

**Comportamiento.**

Pantalla de Ajustes con estas secciones:

| Sección | Ajuste | Valores | Por defecto |
|---|---|---|---|
| **Unidades** | Unidad de peso | kg / lb | kg |
| | Paso del peso | 0,5 / 1 / 1,25 / 2,5 / 5 | 2,5 |
| **Entrenamiento** | Descanso por defecto | 30 s – 5 min | 90 s |
| | Sonido al terminar el descanso | sí / no | sí |
| | Series por defecto en ejercicio nuevo | 1–10 | 4 |
| | Repeticiones por defecto | 1–30 | 10 |
| | Registrar RPE / RIR | no / RPE / RIR | no |
| **Objetivos** | Sesiones por semana | 1–7 | 3 |
| **Apariencia** | Tema | Sistema / Claro / Oscuro | Sistema |
| **Datos** | Exportar copia de seguridad | acción | — |
| | Importar copia de seguridad | acción | — |
| | Descargar media | acción + estado (n.º de archivos, tamaño) | — |
| | Borrar todos los datos | acción destructiva con doble confirmación | — |
| **Acerca de** | Versión, catálogo (1.324 ejercicios), atribución de Gym visual, licencias | informativo | — |

**Conversión de unidades.** Es el punto delicado: **se guarda siempre en kg**. En libras se muestra
`kg × 2,20462` redondeado al paso de la unidad, y al introducir se convierte de vuelta. Esto evita
que el histórico quede en un limbo si el usuario cambia de unidad a mitad de camino, pero implica
que un valor introducido en libras y releído puede variar en el último decimal. Se asume: es
preferible a corromper la coherencia del histórico.

**Interfaz.**

- Nueva pantalla `app/screens/ajustes_screen.py`, ruta `ajustes`.
- Acceso: icono de engranaje en la barra de la pestaña **Rutinas** (a la izquierda del `+`).
  Se descarta una cuarta pestaña: tres es el equilibrio actual de `PESTANAS`
  (`app/router.py:15`) y ajustes no es una zona de uso frecuente.
- Todo con `ui.grupo` + `ui.fila`; interruptores con `ft.CupertinoSwitch`; selecciones con
  `ft.CupertinoSlidingSegmentedButton` (ya usado en `progreso_screen.py:29`) o una subpantalla de
  lista con marca de verificación para las de más de tres opciones.

**Datos.**

```python
class Ajuste(Base):
    __tablename__ = 'ajuste'
    clave = Column(String, primary_key=True)
    valor = Column(String, nullable=False)     # serializado como texto; se castea al leer
```

Se acompaña de `app/utils/ajustes.py` con los valores por defecto, el tipado y una caché en memoria
(los ajustes se leen en casi cada pantalla; no puede haber una consulta por lectura):

```python
DEFECTOS = {"unidad": "kg", "paso_peso": 2.5, "descanso_seg": 90, ...}

def leer(clave)         # con caché
def escribir(clave, valor)
def recargar()
```

**Criterios de aceptación.**

- [ ] Cambiar el paso del peso a 1 kg se refleja en los steppers del entrenamiento.
- [ ] Cambiar a libras muestra todos los pesos convertidos: registro, histórico, gráficos y récords.
- [ ] Cambiar a libras y volver a kg deja los valores originales intactos en la BD.
- [ ] «Borrar todos los datos» pide confirmar dos veces y **no** borra el catálogo (se resiembra).
- [ ] Los ajustes persisten entre arranques.

---

### B10. Copia de seguridad: exportar e importar

**Problema.**
`DataBase.db` está en `.gitignore` y no hay ninguna vía de respaldo dentro de la app. Todo el
histórico de entrenamientos vive en un único archivo local sin copia. Un formateo, un cambio de
ordenador o un borrado accidental lo pierde entero. Es el riesgo más serio del proyecto tal y como
está hoy, y crece con cada mes de uso.

**Comportamiento.**

- **Exportar:** genera un `.json` con todos los datos del usuario y lo guarda donde el usuario elija.
  Nombre sugerido: `appgym-copia-2026-08-06.json`.
- **Importar:** lee un archivo de copia y ofrece dos modos:
  - **Reemplazar** — borra los datos actuales y restaura la copia (con doble confirmación);
  - **Fusionar** — añade las rutinas de la copia que no existan; ante un nombre repetido, importa
    como «Empuje (importada)». No intenta fusionar sesiones dentro de una misma rutina, porque no
    hay forma fiable de detectar duplicados y el resultado sería peor que el problema.
- **Exportar CSV** (secundario): una fila por serie, para quien quiera analizar en una hoja de
  cálculo. Columnas: `fecha, rutina, ejercicio, serie, repeticiones, peso_kg, rpe, calentamiento`.

**Formato.**

```json
{
  "formato": "appgym-backup",
  "version": 2,
  "exportado": "2026-08-06T18:30:00",
  "ajustes": { "unidad": "kg" },
  "rutinas": [
    {
      "nombre": "Empuje", "color": "#0A84FF",
      "ejercicios": [
        {"nombre": "Barbell Bench Press", "id_catalogo": "0025",
         "descripcion": null, "orden": 0, "descanso_seg": null}
      ],
      "entrenamientos": [
        {"fecha": "2026-08-01T12:00:00", "duracion_seg": 3600, "nota": null,
         "series": [
           {"ejercicio": "Barbell Bench Press", "n_serie": 1,
            "repeticiones": 10, "peso": 60.0, "rpe": null, "calentamiento": false}
         ]}
      ]
    }
  ],
  "medidas": [{"fecha": "2026-08-01", "tipo": "peso", "valor": 78.4}]
}
```

Decisiones del formato:

- **No se exporta el catálogo**: son 1.324 filas regenerables desde `app/data/ejercicios.es.json`.
  Los ejercicios se referencian por `id_catalogo`; si al importar ese id no existe (catálogo
  cambiado), el ejercicio se importa como personalizado conservando el nombre, y se informa al
  final del proceso.
- **No se exportan los ids internos**: la referencia entre series y ejercicios es por **nombre**
  dentro de la rutina, que es único por la restricción de `insert_newEjercicio`
  (`conexionBD.py:277`). Así una copia es reimportable en cualquier instalación.
- El campo `version` permite migrar copias antiguas en el futuro.

**Interfaz.**
`ft.FilePicker` con `save_file` y `pick_files` ⚠️ *verificar comportamiento en escritorio y en el
modo web (`APPGYM_WEB=1`), donde la descarga funciona de otra manera*. Alternativa universal si el
picker no cumple: escribir el archivo en el directorio de trabajo y mostrar la ruta exacta en un
diálogo copiable.

**API de datos.** Módulo nuevo `app/utils/respaldo.py`:

```python
def exportar(conexion) -> dict
def exportar_csv(conexion) -> str
def importar(conexion, datos: dict, modo="fusionar") -> dict   # devuelve un informe
def validar(datos: dict) -> list[str]                          # errores legibles
```

`importar` valida **antes** de tocar nada y trabaja en una sola transacción.

**Criterios de aceptación.**

- [ ] Exportar, borrar todos los datos e importar deja la app exactamente igual que antes
      (mismas rutinas, sesiones, series, notas y ajustes).
- [ ] Importar un archivo corrupto o de otra aplicación no modifica nada y muestra un error claro.
- [ ] Fusionar dos veces la misma copia no duplica rutinas silenciosamente.
- [ ] El CSV abre correctamente en una hoja de cálculo con separador de coma y UTF-8 con BOM.

---

### B11. Duplicar rutina y plantillas

**Problema.**
Crear una rutina hoy es: crearla vacía, entrar al catálogo, buscar y añadir ejercicios uno a uno.
Para una rutina de 8 ejercicios son 8 búsquedas. Y variantes como «Empuje A / Empuje B», que
comparten el 80 % de los ejercicios, se construyen dos veces desde cero.

**Comportamiento.**

- **Duplicar rutina:** desde el menú de la rutina. Copia nombre («Empuje (copia)»), ejercicios y
  su orden. **No** copia el histórico de entrenamientos: la nueva rutina empieza sin sesiones.
- **Plantillas:** al crear una rutina, además de «En blanco», se ofrecen plantillas predefinidas:
  - Full body (3 días)
  - Torso / Pierna
  - Push / Pull / Legs
  - Solo peso corporal
  - Principiante (máquinas)
  Cada plantilla muestra su lista de ejercicios antes de crearla y es editable después como
  cualquier rutina.

**Datos.**
Fichero nuevo `app/data/plantillas.json`, sin cambios de esquema:

```json
[
  {
    "nombre": "Push / Pull / Legs",
    "descripcion": "Tres sesiones: empuje, tirón y pierna.",
    "rutinas": [
      {"nombre": "Empuje", "ejercicios": ["0025", "0334", "0289"]},
      {"nombre": "Tirón",  "ejercicios": ["0015", "0287"]},
      {"nombre": "Pierna", "ejercicios": ["0043", "0121"]}
    ]
  }
]
```

Los ids referencian `ejercicio_catalogo.id`. **Al arrancar debe validarse que todos los ids de las
plantillas existen en el catálogo**; si alguno falta, se omite y se registra en consola, nunca se
crea una rutina con un hueco.

**API de datos.**

```python
def duplicar_rutina(self, id_rutina, nuevo_nombre=None) -> int | None
def crear_rutina_desde_plantilla(self, plantilla: dict) -> list[int]
```

**Criterios de aceptación.**

- [ ] Duplicar una rutina de 8 ejercicios crea otra con los mismos 8 en el mismo orden y 0 sesiones.
- [ ] Crear desde plantilla genera las rutinas con sus ejercicios ya vinculados al catálogo (con
      imagen y ficha, no como ejercicios personalizados).
- [ ] Una plantilla con un id inexistente no rompe el arranque.

---

### B12. Favoritos y «añadir a rutina» desde el catálogo

**Problema.**
En la pestaña **Ejercicios** solo se puede mirar la ficha. Para añadir un ejercicio a una rutina hay
que salir, entrar en la rutina y volver a buscarlo (`catalogo_screen.vista_anadir` solo es accesible
desde dentro de una rutina). El catálogo de 1.324 ejercicios está infrautilizado.

**Comportamiento.**

- **Añadir a rutina desde cualquier punto del catálogo**: en la fila de resultados y en la ficha del
  ejercicio. Al pulsar, se elige la rutina de destino en una hoja inferior; si solo hay una rutina,
  se añade directamente y se avisa con un `ui.aviso`.
- **Favoritos:** marcar con estrella desde la ficha o la lista. Sección «Favoritos» arriba del
  catálogo cuando no hay búsqueda activa.
- **Vistos recientemente:** los últimos 10 ejercicios abiertos, también en el estado inicial del
  catálogo. Hoy esa pantalla arranca vacía con solo el buscador.
- **Filtro por músculo objetivo:** `buscar_catalogo` (`conexionBD.py:430`) filtra por `body_part` y
  `equipment` pero no por `target`, que es la clasificación más útil (`abs` 169, `pectorals` 158,
  `biceps` 151…). Se añade como tercer filtro.

**Datos.**

```python
class Favorito(Base):
    __tablename__ = 'favorito'
    id_catalogo = Column(String, ForeignKey('ejercicio_catalogo.id'), primary_key=True)
    creado = Column(DateTime, nullable=False)

class Visto(Base):
    __tablename__ = 'visto'
    id_catalogo = Column(String, ForeignKey('ejercicio_catalogo.id'), primary_key=True)
    fecha = Column(DateTime, nullable=False)     # se conservan los 10 más recientes
```

**API de datos.**

```python
def marcar_favorito(self, id_catalogo, valor: bool) -> bool
def favoritos(self) -> list[EjercicioCatalogo]
def registrar_visto(self, id_catalogo) -> None
def vistos_recientes(self, limit=10) -> list[EjercicioCatalogo]
def buscar_catalogo(..., target=None)            # nuevo filtro
def rutinas_que_contienen(self, id_catalogo) -> list[dict]   # para marcar en qué rutinas ya está
```

**Criterios de aceptación.**

- [ ] Se puede añadir un ejercicio a una rutina sin salir de la pestaña Ejercicios.
- [ ] La ficha indica en qué rutinas ya está ese ejercicio.
- [ ] Los favoritos persisten y se muestran al abrir el catálogo sin búsqueda.
- [ ] Filtrar por «Bíceps» devuelve los 151 ejercicios con `target = biceps`.

---

### B13. Peso corporal y medidas

**Problema.**
La app mide las cargas pero no al usuario. El peso corporal es el contexto que da sentido a la
evolución de las cargas (subir 5 kg en press mientras se pierden 3 kg de peso corporal es un
resultado muy distinto a hacerlo ganando 4 kg).

**Comportamiento.**

- Registro de medidas con fecha: **peso corporal** y, opcionalmente, perímetros (cintura, pecho,
  brazo, muslo) y porcentaje de grasa.
- Una entrada por día y tipo; volver a registrar el mismo día sustituye el valor.
- Gráfico de evolución con el mismo estilo que el de cargas, y suavizado de media móvil de 7 días
  para el peso corporal (los saltos diarios de ±1 kg son ruido y ocultan la tendencia).
- Acceso rápido: si hace más de 7 días que no se registra el peso, la pestaña Progreso ofrece
  hacerlo con un toque.

**Interfaz.**

- Nueva sección en la pestaña **Progreso**, como tercera opción del selector segmentado actual
  (`Resumen · Calendario · Cuerpo`) ⚠️ *el `CupertinoSlidingSegmentedButton` con 3 elementos cabe
  bien; con 4 empezaría a apretarse*.
- Nueva pantalla `app/screens/medidas_screen.py` para el histórico y la edición.

**Datos.**

```python
class Medida(Base):
    __tablename__ = 'medida'
    id = Column(Integer, primary_key=True)
    fecha = Column(Date, nullable=False)
    tipo = Column(String, nullable=False)      # 'peso' | 'cintura' | 'pecho' | 'brazo' | 'muslo' | 'grasa'
    valor = Column(Float, nullable=False)      # kg, cm o %, según el tipo
    __table_args__ = (UniqueConstraint('fecha', 'tipo'),)
```

Tabla genérica en lugar de una columna por medida: añadir «cuello» en el futuro no debe requerir una
migración.

**API de datos.**

```python
def registrar_medida(self, fecha, tipo, valor) -> bool     # upsert por (fecha, tipo)
def serie_medida(self, tipo, desde=None, hasta=None) -> list[dict]
def ultima_medida(self, tipo) -> dict | None
def borrar_medida(self, fecha, tipo) -> bool
```

**Criterios de aceptación.**

- [ ] Registrar el peso dos veces el mismo día deja un solo valor, el último.
- [ ] El gráfico muestra la media móvil de 7 días junto a los puntos reales.
- [ ] Con la unidad en libras, el peso corporal también se muestra en libras.
- [ ] Las medidas se incluyen en la copia de seguridad (B10).

---

## C. Progreso y análisis

### C16. 1RM estimado

**Problema.**
`resultado_ejercicio_screen.py` compara pesos absolutos entre sesiones. Pero 10×60 kg y 5×75 kg no
son comparables mirando solo el peso: la segunda es mejor sesión y el gráfico la pintaría como una
barra más alta sin decir por qué. Falta una métrica que normalice peso y repeticiones.

**Comportamiento.**

- Para cada serie efectiva (no de calentamiento) se calcula el **1RM estimado**:
  - **Epley** (por defecto): `1RM = peso × (1 + repeticiones / 30)`
  - **Brzycki** (alternativa): `1RM = peso × 36 / (37 − repeticiones)`
- El 1RM de una **sesión** es el máximo de los 1RM de sus series.
- Las series de más de 12 repeticiones dan estimaciones poco fiables: se calculan igual pero se
  marcan visualmente como estimación de baja confianza (valor en gris con asterisco), y no cuentan
  para un récord.
- **Récords personales.** Se detectan y se marcan tres, por ejercicio:
  - peso máximo levantado en una serie efectiva,
  - 1RM estimado máximo,
  - volumen máximo en una sesión.
  Al guardar una sesión que bata alguno, el resumen de cierre ([B8](#b8-entrenamiento-en-curso-sesión-viva))
  lo celebra explícitamente: «🏆 Nuevo récord en Barbell Bench Press: 82,5 kg estimados».

**Interfaz.**

En `resultado_ejercicio_screen.py`:

- La tarjeta de resumen (hoy: Último / Máximo / Sesiones) pasa a: **1RM estimado · Peso máximo ·
  Volumen total · Sesiones**, en dos filas de dos.
- Selector segmentado sobre el gráfico para elegir la métrica del eje Y:
  `Peso · 1RM · Volumen`. Resuelve además el punto 14 del listado original sin pantalla nueva.
- Selector de rango: `1M · 3M · 1A · Todo`, sustituyendo al `MAX_BARRAS = 12` fijo
  (`resultado_ejercicio_screen.py:9`).
- Las filas del histórico que fueron récord llevan un icono de trofeo.

**Datos.** Sin cambios de esquema: los récords se **calculan**, no se almacenan. Con volúmenes de
datos personales (cientos de sesiones, miles de series) una consulta agregada es instantánea, y
almacenarlos abriría la puerta a que quedaran desincronizados al editar o borrar una sesión (A2).

**API de datos.** Módulo nuevo `app/utils/metricas.py` (lógica pura, sin acceso a base de datos, y
por tanto directamente testeable):

```python
def uno_rm(peso, repeticiones, formula="epley") -> float
def volumen(series: list[dict]) -> float          # Σ repeticiones × peso, sin calentamientos
def mejor_serie(series: list[dict]) -> dict
def es_fiable(repeticiones) -> bool               # repeticiones <= 12
```

Y en `conexionBD.py`:

```python
def records_ejercicio(self, id_ejercicio) -> dict
    # {"peso": {...}, "uno_rm": {...}, "volumen": {...}} con valor y fecha de cada uno
def records_batidos(self, id_entrenamiento) -> list[dict]
    # récords que esa sesión estableció, comparando contra todo lo anterior a su fecha
```

`records_batidos` compara contra las sesiones **anteriores en fecha**, no contra todas: así editar
una sesión antigua no convierte retroactivamente en récord algo que no lo fue.

**Criterios de aceptación.**

- [ ] `uno_rm(100, 1)` devuelve exactamente `100`.
- [ ] `uno_rm(60, 10)` con Epley devuelve `80.0`.
- [ ] Una sesión con una serie de 15 repeticiones no genera récord de 1RM.
- [ ] Cambiar el eje del gráfico a Volumen recalcula sin volver a consultar la base de datos.
- [ ] Borrar la sesión que tenía el récord hace que el récord pase a la siguiente mejor.

---

### C17. Resumen semanal y racha

**Problema.**
La pestaña Progreso (`progreso_screen.py:73`) es una lista de rutinas con su última fecha. No
responde a la pregunta que uno se hace de verdad: *¿voy bien esta semana?*

**Comportamiento.**

Bloque nuevo en la parte superior de **Progreso › Resumen**:

- **Esta semana:** sesiones realizadas frente al objetivo de Ajustes (`3 de 4`), con un anillo o
  barra de progreso, y volumen total de la semana.
- **Comparativa:** variación frente a la semana anterior en sesiones y volumen, con signo y color
  (`+12 % de volumen`). Sin datos de la semana previa, se omite en lugar de mostrar `+0 %`.
- **Racha:** número de semanas consecutivas cumpliendo el objetivo. Se rompe al terminar una semana
  sin alcanzarlo; **la semana en curso no rompe la racha** hasta que acaba (si no, el lunes toda
  racha valdría cero).
- **Últimos 7 días:** siete puntos, uno por día, coloreados con el color de la rutina entrenada.
- **Aviso de inactividad:** si hace más de 7 días de la última sesión, un mensaje discreto, nunca
  culpabilizador: «Hace 9 días de tu último entrenamiento».

**Definición de semana.** Lunes a domingo, coherente con `formato.DIAS_SEMANA`
(`app/utils/formato.py:11`), que ya empieza en lunes. En SQLite, el lunes se obtiene con
`date(fecha, 'weekday 0', '-6 days')`.

**Interfaz.**
Tarjeta nueva sobre el grupo «Rutinas entrenadas» actual, con `ui.grupo` y un componente
`ui.anillo_progreso(valor, total, color)` nuevo en `ui.py`, dibujado con
`ft.ProgressRing` ⚠️ *verificar que admite grosor y color de pista en 0.25.2*; alternativa: barra
horizontal con `ft.ProgressBar`, ya estándar.

**Datos.** Sin cambios de esquema.

**API de datos.**

```python
def resumen_semana(self, lunes: date) -> dict
    # {"sesiones", "volumen", "series", "por_dia": {date: [id_rutina]}, "duracion_seg"}

def racha_semanas(self, objetivo: int) -> int
    # Semanas consecutivas cumpliendo el objetivo, sin contar la semana en curso
```

`racha_semanas` se resuelve con **una** consulta que agrupa por semana; nada de un bucle de
consultas hacia atrás.

**Criterios de aceptación.**

- [ ] Con el objetivo en 3 y 3 sesiones esta semana, el anillo está completo.
- [ ] La racha no se rompe el lunes por la mañana.
- [ ] Una semana sin entrenar rompe la racha una vez terminada.
- [ ] Sin ninguna sesión registrada, el bloque no aparece y se conserva el estado vacío actual
      (`progreso_screen.py:78`).
- [ ] Todo el resumen se calcula con 2 consultas o menos.

---

### C19. Días del calendario pulsables

**Problema.**
Las celdas del calendario (`progreso_screen.py:171`) son puramente decorativas: se ve que ese día se
entrenó, pero no **qué** se hizo. Es el gesto que cualquiera intenta al ver un calendario.

**Comportamiento.**

- Pulsar un día **con** entrenamientos abre su detalle: las sesiones de ese día con rutina, hora,
  duración, ejercicios, series y nota.
- Desde ahí se puede editar o eliminar la sesión ([A2](#a2-editar-y-borrar-entrenamientos)).
- Pulsar un día **sin** entrenamientos y **pasado** ofrece «Registrar un entrenamiento en este día»
  ([A3](#a3-registrar-un-entrenamiento-en-otra-fecha)).
- Pulsar un día **futuro** no hace nada.
- Feedback táctil: la celda se atenúa al pulsarla.

**Interfaz.**

- Detalle del día como `ft.CupertinoBottomSheet` si contiene una sola sesión corta; si no, se navega
  a la pantalla `sesion` creada en A2. Regla simple para no duplicar interfaz: **la hoja inferior
  muestra el resumen y un botón «Ver sesión»**, que es lo que navega.
- La celda pasa de `ft.Container` a `ft.Container` con `on_click` e `ink=True`.

**Datos.** Sin cambios de esquema. Depende de `entrenamientos_por_dia` ([A6](#a6-varias-rutinas-el-mismo-día)).

**Criterios de aceptación.**

- [ ] Pulsar un día entrenado muestra las sesiones de ese día, todas ellas.
- [ ] Pulsar un día vacío del pasado abre el registro ya con esa fecha seleccionada.
- [ ] Los días futuros no responden al toque.
- [ ] Eliminar una sesión desde el detalle actualiza el calendario al volver.

---

## D. Mapa muscular interactivo

> Especificación de una vista nueva: un modelo anatómico del cuerpo, coloreado según el trabajo
> real de cada músculo, en el que al tocar un músculo se ven sus ejercicios y los entrenamientos
> que lo han trabajado. La imagen de referencia aportada (lámina anatómica con vista frontal y
> dorsal, músculos delimitados y coloreados por grupo) define el resultado visual buscado.

### D.0 Decisión técnica previa: «3D» en Flet

La petición original habla de un **dibujo en 3D**. Conviene decidirlo explícitamente antes de
especificar, porque condiciona todo lo demás:

| Opción | Qué implica | Veredicto |
|---|---|---|
| **3D real** (modelo con malla, rotación libre) | Flet 0.25.2 no tiene motor 3D. Habría que incrustar `three.js` en un `ft.WebView`, que en 0.25.2 solo funciona con garantías en móvil, no en escritorio ni de forma coherente en el modo web. Rompería el arranque de escritorio, que es el modo principal (`main.py`), y añadiría un motor de render entero como dependencia. | **Descartado** |
| **Pseudo-3D vectorial** — modelo anatómico plano con sombreado y volumen, vistas frontal y dorsal | Es exactamente lo que hace la lámina de referencia: la sensación de volumen la da el sombreado, no la geometría. Se dibuja con `flet.canvas`, es nativo, offline, ligero y coloreable músculo a músculo en tiempo real. | **Elegida** |
| Imágenes PNG superpuestas por músculo | Requiere 2 × 21 recortes y no permite recolorear dinámicamente sin generar cada variante. Inviable para un mapa de calor de 5 niveles. | Descartado |

Se especifica por tanto un **mapa muscular pseudo-3D**: dos siluetas anatómicas sombreadas
(anterior y posterior) que se alternan, con cada músculo como región vectorial independiente,
coloreable y pulsable. La rotación se sustituye por un conmutador **Frente / Espalda** con
transición, que en pantalla de móvil es más usable que una rotación libre.

Si en el futuro se sube de versión de Flet y aparece soporte 3D, esta especificación sigue siendo
válida: cambia la capa de dibujo, no el modelo de datos ni la lógica de atribución muscular, que es
la parte con verdadero valor.

### D.1 Objetivo

Responder de un vistazo a tres preguntas que hoy la app no puede contestar:

1. **¿Qué estoy trabajando y qué estoy descuidando?** — un desequilibrio se ve en un mapa, no en una
   lista de rutinas.
2. **¿Qué ejercicios existen para este músculo?** — el catálogo tiene 1.324 ejercicios clasificados
   por músculo objetivo, pero hoy solo se llega a ellos escribiendo en un buscador.
3. **¿Cuándo entrené esto por última vez?** — hoy hay que ir rutina por rutina.

### D.2 Estructura de la vista

Nueva pantalla `app/screens/musculatura_screen.py`, ruta `musculatura`. Se coloca como **tercera
opción del selector de la pestaña Progreso** (`Resumen · Calendario · Cuerpo`), compartiendo sitio
con B13 en la sección «Cuerpo», o como pestaña propia si se decide ampliar `PESTANAS`
(ver [H. Decisiones pendientes](#h-decisiones-pendientes)).

```
┌────────────────────────────────────────┐
│  Musculatura                           │
│  ┌──────────────┬──────────────┐       │
│  │   Frente     │   Espalda    │       │  ← selector de vista
│  └──────────────┴──────────────┘       │
│  ┌────────────────────────────────┐    │
│  │  7 días │ 30 días │ 90 días    │    │  ← periodo del mapa de calor
│  └────────────────────────────────┘    │
│                                        │
│           ╭─────────╮                  │
│          │  modelo   │                 │
│          │ anatómico │                 │  ← canvas: 21 regiones pulsables
│          │ coloreado │                 │
│           ╰─────────╯                  │
│                                        │
│  ● Sin trabajar ▒▒▓▓██ Muy trabajado   │  ← leyenda del mapa de calor
│                                        │
│  Menos trabajados                      │
│  ├ Isquiotibiales   sin entrenar 21 d  │  ← lista complementaria, siempre visible
│  └ Gemelos          sin entrenar 14 d  │
└────────────────────────────────────────┘
```

La **lista complementaria no es opcional**: tocar regiones pequeñas (tibial, romboides) con el dedo
es poco fiable, y una lista ordenada por abandono es además la información más accionable de toda la
pantalla. El mapa comunica; la lista permite actuar.

### D.3 Regiones musculares

Se define un vocabulario canónico de **21 regiones**, cerrado y propio de la app, independiente de
los cuatro vocabularios desiguales del dataset (`body_part` 10 valores, `target` 19,
`muscle_group` 29, `secondary_muscles` 39).

| Región | Nombre | Vista | Valores del catálogo que mapea |
|---|---|---|---|
| `cuello` | Cuello | ambas | `sternocleidomastoid`, `levator scapulae`, body_part `neck` |
| `trapecio` | Trapecios | ambas | `traps`, `trapezius` |
| `deltoides` | Hombros | ambas | `delts`, `deltoids`, `shoulders`, `rotator cuff` |
| `deltoides_post` | Deltoides posterior | espalda | `rear deltoids` |
| `pectoral` | Pecho | frente | `pectorals`, `chest`, `upper chest`, `serratus anterior` |
| `biceps` | Bíceps | frente | `biceps`, `brachialis` |
| `triceps` | Tríceps | espalda | `triceps` |
| `antebrazo` | Antebrazos | ambas | `forearms`, `wrist flexors`, `wrist extensors`, `wrists`, `grip muscles`, `hands` |
| `dorsal` | Dorsales | espalda | `lats`, `latissimus dorsi` |
| `espalda_alta` | Espalda alta | espalda | `upper back`, `rhomboids`, `back` |
| `lumbar` | Lumbares | espalda | `lower back`, `spine` |
| `abdomen` | Abdominales | frente | `abs`, `abdominals`, `core`, `lower abs` |
| `oblicuo` | Oblicuos | frente | `obliques` |
| `gluteo` | Glúteos | espalda | `glutes` |
| `cuadriceps` | Cuádriceps | frente | `quads`, `quadriceps` |
| `isquiotibial` | Isquiotibiales | espalda | `hamstrings` |
| `aductor` | Aductores | frente | `adductors`, `inner thighs`, `groin` |
| `abductor` | Abductores | frente | `abductors` |
| `flexor_cadera` | Flexores de cadera | frente | `hip flexors` |
| `gemelo` | Gemelos | ambas | `calves`, `soleus` |
| `tibial` | Tibial anterior | frente | `shins`, `ankles`, `ankle stabilizers`, `feet` |

Los 29 ejercicios con `target = cardiovascular system` **no tienen región**: aparecen agrupados
aparte como «Cardio» bajo el modelo, no sobre él.

Este mapa vive en `app/utils/musculos.py`:

```python
REGIONES = {
    "pectoral": {
        "nombre": "Pecho",
        "vista": "frente",
        "terminos": {"pectorals", "chest", "upper chest", "serratus anterior"},
    },
    ...
}

def region_de(termino: str) -> str | None
def regiones_de_ejercicio(ficha) -> dict[str, float]   # región -> peso de atribución
```

**Cobertura obligatoria:** un test debe recorrer los 1.324 ejercicios del catálogo y comprobar que
todo valor de `target` cae en una región (o en la lista explícita de excluidos). Si mañana se
actualiza el dataset y aparece un músculo nuevo, el test falla en vez de que el músculo desaparezca
silenciosamente del mapa.

### D.4 Atribución del trabajo a cada músculo

Cada serie efectiva aporta su volumen (`repeticiones × peso`) a una o varias regiones, ponderado:

| Origen en el catálogo | Peso | Motivo |
|---|---|---|
| `target` (músculo objetivo) | **1,0** | Es el músculo que el ejercicio entrena, el dato más fiable del dataset |
| `muscle_group` | **0,5** | Redundante o inconsistente en muchas filas (`forearms` aparece 165 veces como grupo); se cuenta, pero a la mitad |
| `secondary_muscles` | **0,3** | Trabajo real pero secundario |

Reglas:

- Si una región recibe peso por varias vías en el mismo ejercicio, se toma **el mayor**, no la suma.
- Un ejercicio **personalizado** (sin `id_catalogo`) no aporta a ninguna región. Se muestra un
  aviso al pie del mapa: «3 ejercicios personalizados no están representados».
- Los ejercicios de peso corporal tienen `peso = 0` y su volumen sería nulo. Para que las dominadas
  cuenten, el volumen se calcula con **`peso efectivo = max(peso, 1)`** a efectos exclusivos del
  mapa; el resto de métricas (C16, C17) no aplican esta corrección. Es una aproximación consciente:
  el mapa mide *atención dedicada*, no carga absoluta.
- Los pesos de atribución son constantes del módulo, ajustables en un solo sitio.

### D.5 Escala de color

Cinco niveles, calculados sobre el **volumen relativo** de cada región dentro del periodo
seleccionado (no absoluto: comparar el volumen de gemelos con el de cuádriceps en valor absoluto
pintaría siempre el mapa igual).

| Nivel | Criterio | Color |
|---|---|---|
| 0 | Sin trabajo en el periodo | `t.RELLENO` (gris del sistema) |
| 1 | ≤ 25 % del máximo | Azul al 25 % de opacidad |
| 2 | ≤ 50 % | Azul al 50 % |
| 3 | ≤ 75 % | Azul al 75 % |
| 4 | > 75 % | `t.ACENTO` pleno |

Decisiones de color:

- Escala **secuencial de un solo tono** (el azul de acento de la app), no un semáforo rojo-verde:
  aquí «mucho» no es bueno ni malo, es simplemente más, y una escala de intensidad lo comunica sin
  emitir un juicio. Además funciona para daltonismo.
- El color se aplica sobre el mismo dibujo en tema claro y oscuro, así que la silueta base y las
  líneas de contorno usan `t.SEPARADOR` y `t.TEXTO_TER`, que ya son adaptativos.
- El nivel 0 debe distinguirse claramente del nivel 1: es el que responde a la pregunta más
  importante («¿qué no estoy tocando?»).

### D.6 Interacción

- **Tocar una región** abre una hoja inferior con tres bloques:
  1. **Resumen del músculo** — volumen y series del periodo, última vez que se entrenó, y en qué
     rutinas aparece.
  2. **Tus entrenamientos** — últimas 5 sesiones que trabajaron ese músculo, con fecha, rutina y
     ejercicio concreto. Cada una navega a la sesión ([A2](#a2-editar-y-borrar-entrenamientos)).
  3. **Ejercicios del catálogo** — los ejercicios cuyo `target` cae en esa región, ordenados
     poniendo primero los que ya están en alguna rutina del usuario. Con acceso a la ficha y a
     «Añadir a rutina» ([B12](#b12-favoritos-y-añadir-a-rutina-desde-el-catálogo)). Enlace «Ver los
     151 ejercicios» que abre el catálogo con el filtro ya aplicado.
- **Tocar fuera de toda región** no hace nada (no se cierra ni se deselecciona nada).
- La región tocada se resalta con contorno de acento mientras la hoja está abierta.
- Cambiar de periodo (7/30/90 días) recolorea sin recargar la pantalla.

### D.7 Implementación del dibujo

**Recurso gráfico.** Fichero nuevo `app/data/musculatura.json`:

```json
{
  "viewbox": [0, 0, 1000, 2000],
  "vistas": {
    "frente": {
      "silueta": "M 500 40 C ...",
      "regiones": {
        "pectoral": ["M 420 380 C ... Z", "M 580 380 C ... Z"],
        "abdomen":  ["M 470 520 L ... Z"]
      }
    },
    "espalda": { "...": "..." }
  }
}
```

- Coordenadas normalizadas a un lienzo de 1000 × 2000; se escalan al tamaño real de la pantalla.
- Cada región es una **lista** de trazados, porque casi todos los músculos son bilaterales
  (pectoral izquierdo y derecho son dos polígonos de la misma región).
- Sombreado: cada región lleva además un trazado de luz y otro de sombra opcionales, dibujados con
  baja opacidad encima del color base. Es lo que da el aspecto de volumen sin geometría 3D.

**Dibujo.** `flet.canvas.Canvas` con `canvas.Path` y sus segmentos (`MoveTo`, `CubicTo`, `LineTo`,
`Close`) ⚠️ *verificar la API exacta de `flet.canvas` en 0.25.2*. Alternativa si el canvas resulta
insuficiente: renderizar un SVG generado en memoria a través de `ft.Image(src=...)` con el SVG en
línea, y hacer la detección de toques con el mismo algoritmo geométrico descrito abajo; se pierde la
animación de recoloreado suave, no la funcionalidad.

**Detección del toque.** Un `ft.GestureDetector` envuelve el canvas y recibe `on_tap_down` con las
coordenadas locales:

1. Se convierten las coordenadas de pantalla al espacio del viewbox.
2. Se descartan regiones por su **caja envolvente** precalculada (barato).
3. Sobre las candidatas se aplica **point-in-polygon** por lanzamiento de rayo, usando los trazados
   aproximados a polígonos (las curvas Bézier se teselan una sola vez al cargar el JSON, no en cada
   toque).
4. Si dos regiones se solapan, gana la de **menor área**: las regiones pequeñas están encima y son
   las difíciles de acertar.
5. Si ninguna región contiene el punto, se busca la más cercana dentro de un radio de tolerancia de
   ~12 px, para perdonar el dedo.

Todo el algoritmo geométrico vive en `app/utils/geometria.py` como funciones puras, **sin
dependencia de Flet**, y por tanto es completamente testeable sin interfaz.

**Rendimiento.**

- El JSON se carga y tesela **una sola vez** por arranque y se cachea a nivel de módulo.
- Los datos de volumen por región se resuelven con **una única consulta** que une
  `serie → entrenamiento → ejercicio → ejercicio_catalogo` en el rango de fechas, y la atribución a
  regiones se hace en Python sobre el resultado. Para un usuario con 3 años de histórico son unas
  pocas miles de filas; sobra.
- Objetivo: el mapa debe pintarse en menos de 150 ms en un equipo modesto.

**Licencia del recurso gráfico.** ⚠️ **Punto crítico.** La imagen de referencia aportada es una
lámina de terceros, con toda probabilidad protegida por derechos de autor, y **no puede
incorporarse al repositorio ni servir de calco directo**. El dibujo debe ser:

- original, o
- derivado de una fuente en dominio público (por ejemplo, las planchas del *Gray's Anatomy* de 1918,
  en dominio público), o
- de una fuente con licencia compatible y atribución explícita.

Sea cual sea el origen, se documenta en `README.md` junto a la atribución de Gym visual que ya
existe. La lámina aportada sirve como **referencia de aspecto y de nivel de detalle**, no como
material de partida.

### D.8 API de datos

```python
# conexionBD.py
def volumen_por_region(self, desde: date, hasta: date) -> dict[str, dict]
    # {"pectoral": {"volumen": 12400.0, "series": 42, "ultima_fecha": date(...)}, ...}

def sesiones_de_region(self, region: str, limit=5) -> list[dict]
    # [{"id_entrenamiento", "fecha", "rutina", "color", "ejercicio", "series", "volumen"}]

def catalogo_por_region(self, region: str, limit=20) -> list[EjercicioCatalogo]
    # ordenado poniendo primero los ya presentes en alguna rutina del usuario

def regiones_en_rutinas(self) -> dict[str, list[str]]
    # región -> nombres de las rutinas que la trabajan
```

### D.9 Criterios de aceptación

- [ ] El modelo se dibuja en frente y espalda, y el conmutador alterna entre ambos sin recargar la
      pantalla.
- [ ] Cada una de las 21 regiones es identificable visualmente y responde al toque en su área.
- [ ] Tocar el pectoral abre la hoja con el resumen, las últimas sesiones de pecho y ejercicios de
      pecho del catálogo.
- [ ] Sin ningún entrenamiento registrado, el modelo se ve en gris con un estado vacío explicativo,
      y el catálogo por músculo sigue siendo navegable (la vista ya es útil sin histórico).
- [ ] Con datos, un músculo entrenado esta semana y otro sin tocar en 90 días se distinguen a simple
      vista.
- [ ] Cambiar el periodo de 7 a 90 días recolorea y no vuelve a consultar el catálogo.
- [ ] Un test recorre los 1.324 ejercicios y confirma que todo `target` tiene región (salvo los
      excluidos explícitamente).
- [ ] El mapa se pinta correctamente en tema claro y en tema oscuro.
- [ ] La detección de toque acierta la región en al menos 20 puntos de prueba definidos en un test
      de `app/utils/geometria.py`.
- [ ] `README.md` documenta el origen y la licencia del dibujo anatómico.

### D.10 Riesgos

| Riesgo | Mitigación |
|---|---|
| **El recurso gráfico es el cuello de botella real.** Sin un dibujo anatómico correcto y libre, la vista no existe. No es trabajo de programación. | Abordarlo **primero**, antes que el código. Empezar con una silueta simplificada (regiones como formas geométricas suaves) y refinar el detalle después: el sistema completo funciona igual con un dibujo tosco. |
| Tocar regiones pequeñas es poco fiable en móvil | Tolerancia de 12 px, prioridad a la región menor y **lista complementaria siempre visible** |
| La atribución por pesos puede parecer arbitraria | Constantes en un solo módulo, documentadas, y un texto en la hoja que explique de qué ejercicios sale el dato |
| Los ejercicios personalizados quedan fuera del mapa | Aviso explícito al pie; posible mejora futura: pedir el músculo al crear un ejercicio personalizado |
| `flet.canvas` puede no cubrir el caso en 0.25.2 | Alternativa SVG documentada en D.7; la lógica de regiones y atribución es independiente de la capa de dibujo |

---

## E. Modelo de datos consolidado

Estado final del esquema tras aplicar todo el documento. En **negrita**, lo nuevo.

```
rutina              id, nombre, color
ejercicio           id, id_rutina, id_catalogo, nombre, descripcion,
                    **orden**, **descanso_seg**
ejercicio_catalogo  (sin cambios) id, nombre, body_part, equipment, target,
                    muscle_group, secondary_muscles, instrucciones, image, gif, busqueda
entrenamiento       id, id_rutina, fecha, **duracion_seg**, **nota**
serie               id, id_entrenamiento, id_ejercicio,
                    n_serie (⚠ cambia de semántica: índice, no recuento),
                    repeticiones, peso, **calentamiento**, **rpe**, **nota**
**sesion_activa**   id, id_rutina, inicio, actualizado, estado
**ajuste**          clave, valor
**favorito**        id_catalogo, creado
**visto**           id_catalogo, fecha
**medida**          id, fecha, tipo, valor
```

**Secuencia de migraciones** (`PRAGMA user_version`):

| Versión | Contenido | Destructiva |
|---|---|---|
| 1 | Estado actual (`ejercicio.id_catalogo`, `rutina.color`) | No |
| 2 | **A1** — expansión de series agregadas a filas por serie + `calentamiento` | **Sí** |
| 3 | A4 (`ejercicio.orden`), A5 (`entrenamiento.nota`, `serie.rpe`, `serie.nota`) | No |
| 4 | B7 (`ejercicio.descanso_seg`), B8 (`entrenamiento.duracion_seg`, `sesion_activa`) | No |
| 5 | B9 (`ajuste`), B12 (`favorito`, `visto`), B13 (`medida`) | No |

Solo la versión 2 transforma datos existentes. Todas las demás añaden columnas o tablas y son
seguras. Antes de la 2 se hace copia del fichero de base de datos.

Además, en este bloque se activa **`PRAGMA foreign_keys = ON`** en cada conexión (hoy no está en
ninguna parte), sin lo cual los `ON DELETE CASCADE` declarados en `modelo.py` no se aplican
realmente en SQLite.

---

## F. Plan de entrega

Orden propuesto. Cada fase deja la app funcionando y es publicable por separado.

### Fase 0 — Red de seguridad (previa a todo)

Sin esto, la fase 1 es imprudente: A1 es una migración destructiva sobre el histórico del usuario.

- `pytest` en `requirements.txt` y carpeta `tests/`.
- `ConexionBD` debe aceptar una URL de base de datos distinta para poder abrir una BD en memoria en
  los tests. Hoy `__init__` ignora `db_url` a partir de la segunda instancia
  (`app/utils/conexionBD.py:37`), lo que hace el módulo intestable.
- Tests de las migraciones con bases de datos de ejemplo de cada versión.
- `PRAGMA foreign_keys = ON`.

### Fase 1 — Cimientos del modelo

**A1** (series independientes) → **A2** (editar/borrar) → **A3** (fecha) → **A6** (varias sesiones
por día). Es el bloque con más riesgo y el que desbloquea el resto; conviene hacerlo de una pieza y
con calma.

### Fase 2 — Uso diario

**B9** (Ajustes, porque B7 y A5 necesitan dónde configurarse) → **A5** (notas y RPE) →
**B7** (descanso) → **B8** (sesión viva) → **A4** (orden).

### Fase 3 — Protección de datos y comodidad

**B10** (copia de seguridad) → **B11** (duplicar y plantillas) → **B12** (catálogo) →
**B13** (peso corporal).

> B10 podría adelantarse a la fase 1 si se prefiere tener la copia de seguridad **antes** de la
> primera migración destructiva. Es una alternativa defendible y probablemente la más prudente.

### Fase 4 — Análisis

**C16** (1RM y récords) → **C17** (semana y racha) → **C19** (días pulsables).

### Fase 5 — Mapa muscular

**D**, en dos tiempos: primero el recurso gráfico y el módulo de regiones con sus tests (que no
requiere interfaz), y después la vista. Va al final porque se apoya en A1 para el volumen por
serie y en B12 para «añadir a rutina» desde la hoja del músculo.

---

## G. Fuera de alcance

Se deja fuera de esta iteración, de forma consciente:

- **Sincronización en la nube y multidispositivo.** Cambia la naturaleza del proyecto (backend,
  cuentas, conflictos); B10 cubre la necesidad real de no perder los datos.
- **Cuentas de usuario.** La app es de un solo usuario local.
- **Integración con relojes o wearables.**
- **Recomendaciones automáticas de progresión de carga.** Interesante, pero requiere los datos que
  esta iteración justamente empieza a recoger (RPE, volumen por serie). Reconsiderar después.
- **Internacionalización.** Los textos siguen incrustados en las pantallas.
- **Vídeos o media adicional.** Se mantiene la relación actual con el dataset de Gym visual y sus
  condiciones de uso.
- **Ejercicios personalizados con músculo asignado.** Lo pide D, pero no se aborda ahora; se
  documenta como mejora futura.

---

## H. Decisiones pendientes

Cuestiones que conviene cerrar antes o durante la implementación:

1. **¿Cuatro pestañas o tres?** El mapa muscular (D) y las medidas (B13) compiten por sitio dentro
   de Progreso. Opciones: un tercer elemento «Cuerpo» en el selector segmentado (recomendado, no
   toca la barra de pestañas) o una cuarta pestaña. Afecta a D.2 y B13.
2. **¿Adelantar B10 (copia de seguridad) a la fase 1?** Ver nota en la fase 3. Recomendado si el
   usuario ya tiene histórico que le importe.
3. **Origen del dibujo anatómico** (D.7). Es un bloqueo real de la fase 5 y no se resuelve
   programando. Decidir entre encargar/dibujar original o partir de una fuente en dominio público.
4. **Fórmula de 1RM por defecto** (C16): Epley es la propuesta; Brzycki es ligeramente más
   conservadora en repeticiones altas. Se puede dejar elegible en Ajustes, a coste casi nulo.
5. **Escala de esfuerzo por defecto** (A5): RPE o RIR. Se propone dejarlo **desactivado** de inicio
   para no complicar el registro a quien no lo use.
6. **Versión de Flet.** Todo el documento asume 0.25.2. Varias mejoras (reordenación por arrastre,
   selector de fecha nativo) serían más limpias en versiones recientes, pero subir de versión
   implica revisar el rediseño iOS completo. Se recomienda **no subirla en esta iteración** y
   reevaluarlo después.
