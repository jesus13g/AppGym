# AppGym

Aplicación para la gestión y revisión de rutinas de gym, con interfaz de estética iOS
y un catálogo de **1.324 ejercicios** con instrucciones en español, músculos implicados
y una animación de cada movimiento.

Escrita en **Flutter**. Antes lo estaba en Python con Flet; el histórico de git conserva
aquella versión.

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

## Estructura

```
lib/
├── main.dart               punto de entrada, CupertinoApp y localización
├── datos/
│   ├── bd.dart             tablas de drift y todas las consultas
│   ├── semilla.dart        carga del catálogo en la base de datos
│   ├── media.dart          descarga y resolución de imágenes y GIFs
│   ├── i18n.dart           traducciones del vocabulario del catálogo
│   └── formato.dart        formateo de fechas y textos
├── estado/providers.dart   providers de Riverpod
├── tema/
│   ├── tokens.dart         colores, espaciados, radios y tipografía
│   └── ui.dart             componentes que Cupertino no trae
└── pantallas/              una pantalla por fichero
assets/ejercicios.es.json   catálogo de ejercicios en español
test/                       tests de datos y de widget
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
