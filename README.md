# AppGym

Aplicación para la gestión y revisión de rutinas de gym, con interfaz de estética iOS
y un catálogo de **1.324 ejercicios** con instrucciones, músculos implicados y una
animación de cada movimiento. **En español y en inglés.**

Escrita en **Flutter**. Antes lo estaba en Python con Flet; el histórico de git conserva
aquella versión.

## Qué hace

- **Rutinas.** Crea rutinas desde cero, desde una **plantilla** (full body, torso/pierna,
  push/pull/legs, peso corporal, máquinas) o **duplicando** una que ya tengas. Los
  ejercicios se reordenan arrastrando y se pueden mover a otra rutina.
- **Catálogo.** Buscador con filtros por zona del cuerpo, equipamiento y músculo
  objetivo. El buscador entiende los dos idiomas a la vez, sea cual sea el activo:
  *«mancuerna pecho»* funciona igual que *«dumbbell bench press»*. Marca **favoritos**,
  recuerda lo último que has mirado y añade a una rutina sin salir de ahí.
- **Entrenamientos.** Cada serie con sus repeticiones y su peso, así que una pirámide o
  un drop set se anotan tal cual. Se precargan las de la última sesión. Notas y esfuerzo
  percibido (RPE o RIR) opcionales.
- **Sesión en curso.** Empieza el entrenamiento y ve marcando cada serie: cronómetro,
  **temporizador de descanso** (configurable por ejercicio, con aviso y vibración) y
  resumen de cierre con volumen, duración y récords batidos. Si cierras la app a mitad,
  al volver te ofrece continuar donde lo dejaste.
- **Progreso.** Evolución del peso por ejercicio, historial de sesiones editable y
  calendario mensual coloreado según la rutina entrenada cada día.
- **Cuerpo.** Un **mapa muscular** con vista frontal y dorsal, coloreado según lo que
  has trabajado cada músculo en los últimos 7, 30 o 90 días: se ve de un vistazo qué
  estás descuidando. Toca un músculo y salen sus últimas sesiones y los ejercicios del
  catálogo para él. Debajo, peso corporal y perímetros, con media móvil de 7 días para
  ver la tendencia por debajo del ruido diario.
- **Ajustes.** Kilos o libras, paso del peso, descanso por defecto, valores de partida,
  objetivo semanal, tema claro / oscuro / del sistema e **idioma** (automático, español
  o inglés).
- **Copia de seguridad.** Exporta todo tu histórico a un archivo y vuelve a importarlo
  (fusionando o reemplazando). También en CSV, una fila por serie, para una hoja de
  cálculo.
- **Copia automática.** Si quieres, la copia se sube sola a **tu propio Google Drive** —a
  una carpeta `AppGym`, conservando las diez últimas— con la frecuencia que elijas. Viene
  apagada; se enciende en *Ajustes → Copia automática*. No es sincronización: es la copia
  de arriba, hecha sin que te acuerdes, para poder recuperarlo todo en un móvil nuevo.
  Qué sale del móvil y cómo se revoca está en [docs/privacidad.md](docs/privacidad.md).
- **Sincronización.** Y si de verdad usas dos aparatos —el móvil en el gimnasio, la tableta
  en casa—, una cuenta con tu correo mantiene el mismo histórico en los dos. Se entra con un
  código de seis cifras, sin contraseña, desde *Ajustes → Cuenta*. También viene apagada, la
  app funciona entera sin ella y cerrar sesión o borrar la cuenta **deja intactos los datos
  de tu móvil**. Esto sí es sincronización de verdad, no una copia con fecha.

Por defecto la interfaz sigue el tema y el idioma del sistema, y en Ajustes se puede
forzar cualquiera de los dos. El idioma se cambia sin reiniciar; los nombres de las
rutinas que ya has creado no se tocan, porque son tuyos.

## Probarla en el móvil (Android)

Cada cambio que entra en `main` compila un APK en GitHub Actions y publica una
**[release nueva](../../releases/latest)**. Desde el móvil:

1. Abre la [última release](../../releases/latest) y descarga `AppGym.apk`.
2. Ábrelo. Android pedirá permiso para instalar apps de origen desconocido la
   primera vez (*Ajustes → Instalar apps desconocidas → Chrome*).
3. En el primer arranque, pulsa **«Ahora no»** en la descarga de imágenes si estás con
   datos móviles: la app funciona igual y carga cada imagen cuando la necesita.

Las versiones se numeran `1.0.N` y no se sobrescriben: las anteriores siguen
disponibles en la [lista de releases](../../releases), por si hay que volver a una.

Un pull request a `main` también compila su APK, pero como *artifact* de la ejecución
en lugar de release: se descarga desde la pestaña *Actions*, entrando en la ejecución
del PR. Sirve para probar un cambio antes de mergearlo.

También se puede lanzar a mano desde *Actions* → *Construir APK* → *Run workflow*. Para
iOS haría falta un Mac y una cuenta de desarrollador de Apple, así que por ahí no hay
atajo.

## Desarrollo

Requiere **Flutter 3.44.8** o posterior.

```bash
flutter pub get
dart run build_runner build     # genera el código de drift; obligatorio tras clonar
flutter gen-l10n                # genera las traducciones; obligatorio tras clonar
flutter run
```

Comprobaciones, las mismas que corren en CI:

```bash
flutter analyze
flutter test
dart format --set-exit-if-changed lib test
```

Para compilar el APK en local hacen falta además el SDK de Android y Java 17:

```bash
flutter build apk --release
```

### Primer arranque

La primera vez, la app ofrece descargar las imágenes y animaciones de los ejercicios
(unos 2.600 archivos, ~130 MB). La descarga es **reanudable**: si se corta, al volver a
lanzarla solo baja lo que falte.

Puedes **omitirla**: la app funciona igual y carga cada imagen desde internet cuando la
necesita.

La base de datos y la carpeta de media van al almacenamiento privado que asigna el
sistema, porque en Android e iOS el directorio de trabajo no es escribible. Ninguno de
los dos se versiona.

**Desinstalar la app borra la base de datos**, así que conviene exportar de vez en
cuando una copia de seguridad desde *Ajustes → Datos* y guardarla fuera del móvil, o
encender la copia automática para no tener que acordarse.

**Sobre la copia automática en las releases oficiales.** Apunta a un proyecto de Google
Cloud personal, sin ninguna garantía de disponibilidad: puede dejar de funcionar en
cualquier momento y la exportación manual seguirá estando igual. Una compilación local o un
fork la traen **desactivada y no visible**, y la app funciona exactamente igual sin ella.
Para apuntarla a un proyecto propio, crea un cliente OAuth de tipo *aplicación de
escritorio* con la Drive API activada y pásalo al compilar:

```bash
flutter build apk --release \
  --dart-define GOOGLE_CLIENT_ID=... --dart-define GOOGLE_CLIENT_SECRET=...
```

En CI son los secretos `GOOGLE_CLIENT_ID` y `GOOGLE_CLIENT_SECRET` del repositorio.

**Sobre la sincronización en las releases oficiales.** Igual: apunta a un servidor personal,
sin ninguna garantía de disponibilidad. Una compilación local o un fork la traen
**desactivada y no visible**, y la app funciona exactamente igual sin ella.

El servidor es de este repositorio: [`servidor/`](servidor/), FastAPI y PostgreSQL, con
cuentas por correo y contraseña y JWT. Se levanta con `docker compose` en cualquier VPS —el
paso a paso está en [`docs/sincronizacion.md`](docs/sincronizacion.md)— y la app se compila
apuntando ahí:

```bash
flutter build apk --release \
  --dart-define API_URL=https://appgym.tudominio.com \
  --dart-define API_ANCLAS=$(base64 -w0 anclas.pem)
```

En CI son los secretos `API_URL` y `API_ANCLAS`. El segundo es el anclaje de certificado: con
él, la app **solo** se cree la autoridad de tu servidor, así que un proxy interpuesto no puede
leer el tráfico. Es opcional; sin él hay TLS normal.

La llave con la que el servidor firma los accesos (`APPGYM_JWT_SECRETO`) vive **solo** en su
`.env` y no aparece ni en CI ni en el APK.

## Estructura

```
lib/
├── main.dart               punto de entrada, CupertinoApp, tema e idioma
├── datos/
│   ├── bd.dart             tablas de drift y todas las consultas
│   ├── esquemas.dart       esquemas versionados, para las migraciones
│   ├── ajustes.dart        preferencias: claves, valores por defecto y unidades
│   ├── copia.dart          exportar e importar la copia de seguridad
│   ├── copia_automatica.dart  cuándo toca copiar, qué se rota y cuándo se avisa
│   ├── nube/               la costura del destino y el adaptador de Google Drive
│   ├── sincro/             la costura del transporte, el motor, el primer enlace, el
│                           adaptador del servidor y el anclaje de certificado
│   ├── identidad.dart      el uuid de una fila y el sello de su versión
│   ├── respaldo.dart       duplicado del fichero antes de migrarlo
│   ├── borrador.dart       estado de la sesión en curso, en JSON
│   ├── plantillas.dart     rutinas predefinidas
│   ├── semilla.dart        carga del catálogo en la base de datos
│   ├── media.dart          descarga y resolución de imágenes y GIFs
│   ├── i18n.dart           traducciones del vocabulario del catálogo (es · en)
│   ├── musculos.dart       las 21 regiones del mapa y el reparto del trabajo
│   ├── geometria.dart      los trazados del modelo anatómico y el toque
│   ├── reloj.dart          la hora, en un punto que los tests pueden adelantar
│   └── formato.dart        fechas, números y pesos del idioma activo
├── l10n/                   los textos de la interfaz, un ARB por idioma
├── estado/
│   ├── providers.dart      providers de Riverpod
│   ├── copia_automatica.dart  el motor de la copia a la nube
│   ├── sincro.dart         el motor de la sincronización: disparadores y cuenta
│   └── descanso.dart       temporizador de descanso
├── tema/
│   ├── tokens.dart         colores, espaciados, radios y tipografía
│   └── ui.dart             componentes que Cupertino no trae
└── pantallas/              una pantalla por fichero
assets/ejercicios.es.json   catálogo de ejercicios, con sus pasos en español
assets/instrucciones.en.json
                            los mismos pasos en inglés
assets/plantillas.json      rutinas predefinidas, con sus nombres por idioma
assets/musculatura.json     el modelo anatómico del mapa muscular
tool/musculatura.py         genera el modelo anatómico y una previa para verlo
tool/instrucciones_en.py    baja los pasos en inglés del dataset original
drift_schemas/              un JSON por versión del esquema
servidor/                   el backend: FastAPI, PostgreSQL, JWT y su docker compose
test/                       tests de datos, de widget y de migración
docs/especificaciones.md    primera iteración, completada (bloques A–D)
docs/especificaciones-2.md  segunda iteración: idiomas, progresiones, copia automática y
                            sincronización, completada
docs/sincronizacion.md      cómo montar el servidor de sincronización en un fork
docs/conectar-backend.md    qué falta para desplegarlo y darlo por bueno
```

## Créditos y licencias

Los ejercicios provienen del dataset
[hasaneyldrm/exercises-dataset](https://github.com/hasaneyldrm/exercises-dataset).

- **Datos** (nombres, categorías, músculos, equipamiento e instrucciones): licencia MIT.
- **Media** (imágenes y GIFs): **© Gym visual — https://gymvisual.com/**. Se distribuye
  únicamente a 180×180 y debe conservar la atribución visible. Por eso este repositorio
  **no incluye** los archivos ni se empaquetan en el APK: se descargan del origen. Su uso
  se rige por los
  [términos de Gym visual](https://gymvisual.com/content/3-terms-and-conditions-of-use).

El **modelo anatómico** del mapa muscular (`assets/musculatura.json`) es **obra original
de este repositorio** y se distribuye con la misma licencia que el resto del código. No
deriva de ninguna lámina de terceros: es un dibujo esquemático propio, con la silueta y
las 21 regiones musculares escritas directamente como trazados vectoriales (punto inicial
y segmentos cúbicos de Bézier) sobre un lienzo de 1000 × 2000. Los músculos bilaterales se
definen una vez y se reflejan al cargar. Se genera con `python3 tool/musculatura.py`, que
escribe además una previa en SVG para poder mirar el resultado; el JSON no se edita a
mano.
