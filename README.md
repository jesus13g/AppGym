# AppGym

Aplicación para la gestión y revisión de rutinas de gym, con interfaz de estética iOS
y un catálogo de **1.324 ejercicios** con instrucciones en español, músculos implicados
y una animación de cada movimiento.

## Qué hace

- **Rutinas.** Crea rutinas y añádeles ejercicios del catálogo (o personalizados si lo
  que buscas no está). Se borran deslizando hacia la izquierda.
- **Catálogo.** Buscador con filtros por zona del cuerpo y equipamiento. Busca por
  nombre en inglés o por términos en español: *«mancuerna pecho»* funciona igual que
  *«dumbbell bench press»*.
- **Entrenamientos.** Registra series, repeticiones y peso por ejercicio. Los valores
  se precargan con los del último entrenamiento de ese mismo ejercicio.
- **Progreso.** Evolución del peso por ejercicio y calendario mensual coloreado según
  la rutina entrenada cada día.

La interfaz sigue el tema del sistema: se ve en claro u oscuro automáticamente.

## Probarla en el móvil (Android)

Cada push a una rama `claude/**` compila un APK en GitHub Actions y lo publica en la
release **[`apk-preview`](../../releases/tag/apk-preview)**. Desde el móvil:

1. Abre la release y descarga `AppGym.apk`.
2. Ábrelo. Android pedirá permiso para instalar apps de origen desconocido la
   primera vez (*Ajustes → Instalar apps desconocidas → Chrome*).
3. En el primer arranque, pulsa **«Ahora no»** en la descarga de imágenes si estás con
   datos móviles: la app funciona igual y carga cada imagen cuando la necesita.

También se puede lanzar a mano desde la pestaña *Actions* → *Construir APK* → *Run
workflow*. Para iOS haría falta un Mac y una cuenta de desarrollador de Apple, así que
por ahí no hay atajo.

## Instalación

```bash
python -m venv env
source env/bin/activate        # en Windows: env\Scripts\activate
pip install -r requirements.txt
python main.py
```

Con `APPGYM_WEB=1 python main.py` se abre en el navegador en lugar de en una ventana.

### Primer arranque

La primera vez, la app ofrece descargar las imágenes y animaciones de los ejercicios
(unos 2.600 archivos, ~130 MB) a la carpeta `media/`. La descarga es **reanudable**: si
se corta, al volver a lanzarla solo baja lo que falte.

Puedes **omitirla**: la app funciona igual y carga cada imagen desde internet cuando la
necesita. Y si prefieres bajarla antes de abrir la app:

```bash
python tools/fetch_media.py
```

La base de datos (`DataBase.db`) y la carpeta `media/` no se versionan. Una base de
datos de una versión anterior de la app se migra sola al arrancar, conservando rutinas,
ejercicios e histórico.

En desarrollo ambos viven junto al proyecto; en la app empaquetada (Android, iOS o un
ejecutable de escritorio) van al almacenamiento privado que asigna el sistema, porque
el directorio de trabajo no es escribible. Lo resuelve `app/utils/almacenamiento.py`.

## Estructura

```
main.py                     punto de entrada
app/
├── gymApp.py               arranque: tablas, migración, catálogo y router
├── router.py               pila de vistas, pestañas y transiciones iOS
├── theme/
│   ├── tokens.py           colores, espaciados, radios y tipografía
│   └── ui.py               componentes (listas agrupadas, steppers, diálogos…)
├── data/
│   └── ejercicios.es.json  catálogo de ejercicios en español
├── screens/                una pantalla por fichero, cada una devuelve un ft.View
└── utils/
    ├── modelo.py           modelos SQLAlchemy
    ├── conexionBD.py       conexión y consultas
    ├── seed.py             carga del catálogo en la base de datos
    ├── media.py            descarga y resolución de imágenes y GIFs
    ├── i18n.py             traducciones del vocabulario del catálogo
    └── formato.py          formateo de fechas y textos
tools/fetch_media.py        descarga de media por línea de comandos
```

## Créditos y licencias

Los ejercicios provienen del dataset
[hasaneyldrm/exercises-dataset](https://github.com/hasaneyldrm/exercises-dataset).

- **Datos** (nombres, categorías, músculos, equipamiento e instrucciones): licencia MIT.
- **Media** (imágenes y GIFs): **© Gym visual — https://gymvisual.com/**. Se distribuye
  únicamente a 180×180 y debe conservar la atribución visible. Por eso este repositorio
  **no incluye** los archivos: se descargan del origen y `media/` está en el
  `.gitignore`. Su uso se rige por los
  [términos de Gym visual](https://gymvisual.com/content/3-terms-and-conditions-of-use).
