# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

El código, los comentarios, los commits y la interfaz están en **español**. Mantén ese idioma
al añadir código.

## Comandos

```bash
python -m venv env && ./env/bin/pip install -r requirements.txt

./env/bin/python main.py                       # ventana nativa
APPGYM_WEB=1 ./env/bin/python main.py          # navegador (puerto 8550, o APPGYM_PORT)
./env/bin/python tools/fetch_media.py          # descargar imágenes y GIFs sin abrir la app
./env/bin/flet build apk                       # APK local (necesita Flutter ≥3.24 y Java 17)
```

No hay tests, ni linter, ni formateador configurados. El APK se compila en
`.github/workflows/build-apk.yml` con cada push a `claude/**` y se publica en la release
`apk-preview`.

### Cómo verificar cambios sin interfaz

No hay suite de tests, pero las pantallas se pueden construir y validar en proceso. Es la
forma más rápida de detectar una regresión, y `before_update()` es donde Flet valida
propiedades y enums:

```python
from types import SimpleNamespace
import flet as ft
from app.utils.conexionBD import ConexionBD
from app.router import Router, Destino

ft.Control.update = lambda self: None   # no hay frontend al que enviar
page = SimpleNamespace(views=[], route=None, update=lambda *a, **k: None,
                       on_view_pop=None, open=lambda d: None,
                       close=lambda d: None, run_thread=lambda f: f())
router = Router.__new__(Router)
router.page, router.conexion, router.pila = page, ConexionBD(), []
vista = router._construir(Destino("rutinas"))
```

Con eso se pueden invocar los manejadores directamente (`fila.on_click(SimpleNamespace(control=fila))`)
para ejercitar búsqueda, altas, steppers o borrados. Ejecútalo siempre en un directorio
temporal: la BD se crea en el directorio de trabajo.

**Limitación conocida:** en sandboxes con proxy restrictivo, Flet Web no renderiza porque
Flutter descarga CanvasKit de `gstatic.com`. El renderer HTML no está en el bundle de Flet
0.25.2, así que no hay capturas de pantalla posibles: verifica por construcción y avisa de
que el aspecto visual no está comprobado.

## Arquitectura

App de gimnasio en **Python + Flet 0.25.2** (UI Flutter dirigida desde Python) sobre
**SQLite/SQLAlchemy**. Sin dependencias de UI de terceros.

### Navegación: pila explícita, no rutas por string

`app/router.py` mantiene `Router.pila`, una lista de `Destino(pantalla, **params)`. Cada
pantalla es un módulo en `app/screens/` que exporta `vista(page, router, **params)` y
**devuelve un `ft.View`** — nunca muta `page.controls`.

- `router.ir(...)` apila, `router.volver()` desapila, `router.reemplazar(...)` cambia de
  pestaña, `router.refrescar()` repinta.
- `_render()` **reconstruye la pila entera** en cada navegación. Es intencionado: al volver
  atrás la pantalla anterior muestra datos frescos sin invalidación manual. La pila nunca
  pasa de tres niveles.
- Las pantallas en `MODALES` se presentan como `fullscreen_dialog` (suben desde abajo).
- El estado local de una pantalla (texto de búsqueda, filtros, offset) vive en closures, así
  que **`router.refrescar()` lo pierde**. Para cambios que deben conservarlo, muta
  `router.pila[-1].params` y refresca (ver `progreso_screen.elegir`).
- Añadir una pantalla = crear el módulo y registrarla en el dict `constructores` de
  `Router._construir`. Los imports ahí son perezosos a propósito.

### Acceso a datos: singleton con sesiones de vida corta

`ConexionBD` (`app/utils/conexionBD.py`) es un singleton que abre y **cierra una sesión por
consulta**. Consecuencia importante: los objetos que devuelve están desasociados, así que
navegar relaciones después (`serie.entrenamiento.fecha`) falla. Por eso existen consultas
que preagregan lo que la vista necesita — `resumen_rutinas()`, `series_con_fecha()`,
`colores_rutinas()` — y `selectAll_ejerciciosRutina()` usa `joinedload(Ejercicio.catalogo)`.
**Al añadir una vista, añade la consulta que le dé los datos ya resueltos.**

### Migraciones

`create_all` crea tablas nuevas pero nunca modifica las existentes. `create_tablas()` llama
a `_migrar_columnas()`, que lee `PRAGMA table_info` y hace `ALTER TABLE ... ADD COLUMN` solo
de lo que falte. **Toda columna nueva en una tabla ya existente debe registrarse ahí**, o las
bases de datos de usuarios anteriores se romperán.

### Catálogo de ejercicios

1.324 ejercicios de [hasaneyldrm/exercises-dataset](https://github.com/hasaneyldrm/exercises-dataset).

- `app/data/ejercicios.es.json` (~1 MB) se versiona; `seed.py` lo vuelca en la tabla
  `ejercicio_catalogo` de forma idempotente (compara recuentos).
- La columna `busqueda` es el índice: nombre en inglés **más** las traducciones de
  `app/utils/i18n.py`, normalizado sin acentos. Por eso «mancuerna pecho» encuentra lo mismo
  que «dumbbell bench press». Si tocas `i18n.py`, hay que **resembrar** (`seed_catalogo(c, forzar=True)`).
- Los nombres de ejercicio solo existen en inglés y se muestran tal cual; lo que se traduce
  son las categorías (`body_part`, `equipment`, `target`, músculos).
- `Ejercicio.id_catalogo` es `NULL` en los ejercicios personalizados del usuario.
- El buscador pagina de 40 en 40 con `on_scroll`; nunca pintes los 1.324 de golpe.

### Media: licencia y resolución

Las imágenes y GIFs son **© Gym visual**, redistribuidos en el dataset original bajo permiso
con dos condiciones: solo a 180×180 y con la atribución visible. **No se versionan en este
repositorio** — `media/` está en el `.gitignore`. Se descargan del origen en el primer
arranque o con `tools/fetch_media.py`.

`media.resolver(ruta)` devuelve la ruta local si el fichero existe y la URL remota si no, y
`ft.Image` acepta ambas: la app funciona durante la descarga, si se omite o si falló a
medias. **Usa siempre `resolver()`, nunca construyas rutas a mano.** La ficha de ejercicio
muestra `media.ATRIBUCION` al pie; es requisito de licencia, no decoración.

### Almacenamiento

`app/utils/almacenamiento.py` resuelve dónde van la BD y `media/`: usa
`FLET_APP_STORAGE_DATA` cuando existe (app empaquetada — en Android e iOS el directorio de
trabajo **no es escribible**) y el directorio del proyecto en desarrollo. Cualquier escritura
a disco nueva debe pasar por ahí.

### Sistema de diseño

`app/theme/tokens.py` (constantes) y `app/theme/ui.py` (componentes: `grupo`, `fila`,
`stepper`, `pildora`, `miniatura`, `deslizar_para_borrar`, `dialogo_texto`, `barra`…).

Los colores son los **semánticos de Cupertino** (`ft.CupertinoColors.LABEL`,
`SECONDARY_SYSTEM_GROUPED_BACKGROUND`…), que Flutter resuelve solo en claro y oscuro. **No
metas hex literales** salvo en `PALETA_RUTINAS`, que identifica rutinas y debe ser estable en
ambos temas. Construye pantallas componiendo `ui.py`; si necesitas algo nuevo, añádelo ahí
en vez de improvisarlo en la pantalla.

### Peculiaridades de Flet 0.25.2 (ya sufridas)

- **No existe `CupertinoSearchTextField`** — se compone con `CupertinoTextField` + prefijo
  (`ui.campo_busqueda`).
- **`CupertinoFilledButton` no acepta color de fondo.** `ui.boton_principal` usa
  `CupertinoButton` con `bgcolor` para poder pintar acciones destructivas en rojo.
- **`Dismissible.on_confirm_dismiss` ignora el valor devuelto**: hay que llamar a
  `e.control.confirm_dismiss(True/False)`, lo que permite resolverlo tras cerrar un diálogo.
- El trabajo en segundo plano va por `page.run_thread` (ver `setup_screen`).

### Empaquetado

`pyproject.toml` declara en `[project] dependencies` **solo las tres dependencias de
ejecución** (flet, SQLAlchemy, requests): es lo que `flet build` mete en el APK, y tiene
precedencia sobre `requirements.txt`. `requirements.txt` conserva además las de escritorio y
build, que no tienen ruedas para Android. Si añades una dependencia que la app necesita en
tiempo de ejecución, va **en los dos sitios**.
