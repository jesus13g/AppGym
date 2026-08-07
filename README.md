# AppGym

Aplicación para la gestión y revisión de rutinas de gym, con interfaz de estética iOS
y un catálogo de **1.324 ejercicios** con instrucciones en español, músculos implicados
y una animación de cada movimiento.

Escrita en **Flutter**. Antes lo estaba en Python con Flet; el histórico de git conserva
aquella versión.

## Qué hace

- **Rutinas.** Crea rutinas desde cero, desde una **plantilla** (full body, torso/pierna,
  push/pull/legs, peso corporal, máquinas) o **duplicando** una que ya tengas. Los
  ejercicios se reordenan arrastrando y se pueden mover a otra rutina.
- **Catálogo.** Buscador con filtros por zona del cuerpo, equipamiento y músculo
  objetivo. Busca por nombre en inglés o por términos en español: *«mancuerna pecho»*
  funciona igual que *«dumbbell bench press»*. Marca **favoritos**, recuerda lo último
  que has mirado y añade a una rutina sin salir de ahí.
- **Entrenamientos.** Cada serie con sus repeticiones y su peso, así que una pirámide o
  un drop set se anotan tal cual. Se precargan las de la última sesión. Notas y esfuerzo
  percibido (RPE o RIR) opcionales.
- **Sesión en curso.** Empieza el entrenamiento y ve marcando cada serie: cronómetro,
  **temporizador de descanso** (configurable por ejercicio, con aviso y vibración) y
  resumen de cierre con volumen, duración y récords batidos. Si cierras la app a mitad,
  al volver te ofrece continuar donde lo dejaste.
- **Progreso.** Evolución del peso por ejercicio, historial de sesiones editable y
  calendario mensual coloreado según la rutina entrenada cada día.
- **Cuerpo.** Peso corporal y perímetros, con media móvil de 7 días para ver la
  tendencia por debajo del ruido diario.
- **Ajustes.** Kilos o libras, paso del peso, descanso por defecto, valores de partida,
  objetivo semanal y tema claro / oscuro / del sistema.
- **Copia de seguridad.** Exporta todo tu histórico a un archivo y vuelve a importarlo
  (fusionando o reemplazando). También en CSV, una fila por serie, para una hoja de
  cálculo.

Por defecto la interfaz sigue el tema del sistema, y en Ajustes se puede forzar claro
u oscuro.

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
cuando una copia de seguridad desde *Ajustes → Datos* y guardarla fuera del móvil.

## Estructura

```
lib/
├── main.dart               punto de entrada, CupertinoApp y localización
├── datos/
│   ├── bd.dart             tablas de drift y todas las consultas
│   ├── esquemas.dart       esquemas versionados, para las migraciones
│   ├── ajustes.dart        preferencias: claves, valores por defecto y unidades
│   ├── copia.dart          exportar e importar la copia de seguridad
│   ├── respaldo.dart       duplicado del fichero antes de migrarlo
│   ├── borrador.dart       estado de la sesión en curso, en JSON
│   ├── plantillas.dart     rutinas predefinidas
│   ├── semilla.dart        carga del catálogo en la base de datos
│   ├── media.dart          descarga y resolución de imágenes y GIFs
│   ├── i18n.dart           traducciones del vocabulario del catálogo
│   ├── reloj.dart          la hora, en un punto que los tests pueden adelantar
│   └── formato.dart        formateo de fechas, pesos y textos
├── estado/
│   ├── providers.dart      providers de Riverpod
│   └── descanso.dart       temporizador de descanso
├── tema/
│   ├── tokens.dart         colores, espaciados, radios y tipografía
│   └── ui.dart             componentes que Cupertino no trae
└── pantallas/              una pantalla por fichero
assets/ejercicios.es.json   catálogo de ejercicios en español
assets/plantillas.json      rutinas predefinidas
drift_schemas/              un JSON por versión del esquema
test/                       tests de datos, de widget y de migración
docs/especificaciones.md    funcionalidades previstas y su plan de entrega
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
