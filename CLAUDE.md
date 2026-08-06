# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

El código, los comentarios, los commits y la interfaz están en **español**. Mantén ese idioma
al añadir código.

## Comandos

```bash
flutter pub get
dart run build_runner build     # genera bd.g.dart; obligatorio tras clonar
flutter run                     # app en un dispositivo o emulador
flutter analyze                 # objetivo permanente: 0 issues
flutter test                    # 27 tests: datos_test.dart y pantallas_test.dart
dart format lib test
flutter build apk --release     # APK local (necesita SDK de Android y Java 17)
```

Se desarrolla con **Flutter 3.44.8 / Dart 3.12.2**. La versión está fijada en
`.github/workflows/build-apk.yml`; si la subes, súbela también ahí.

**Los `*.g.dart` no se versionan** (ver `.gitignore`). Sin `build_runner build` no compila nada, ni
en local ni en CI.

### Cómo verificar cambios

A diferencia de la versión Flet de este proyecto, **aquí sí se puede comprobar todo sin interfaz**:

- `flutter analyze` valida tipos y API antes de arrancar nada.
- `flutter test` monta las pantallas de verdad contra una `NativeDatabase.memory()`, sobrescribiendo
  `bdProvider`. Los tests de widget son rápidos y ya han pillado un desbordamiento de layout real,
  así que **añade uno al tocar una pantalla**.

Dos avisos sobre el entorno de test: la fuente por defecto de `flutter test` no es la real y mide
distinto, de forma que un `RenderFlex overflowed` en un test puede no darse en el móvil (pero suele
señalar un widget que conviene hacer flexible igualmente); y las imágenes de red devuelven error, lo
que ejercita el `errorBuilder` de `ui.Miniatura`.

Lo que **no** se puede comprobar aquí: el aspecto visual y el APK. El APK lo construye CI a partir
de `main`; ver [CI y versiones](#ci-y-versiones).

## Arquitectura

App de gimnasio en **Flutter/Dart** sobre **SQLite sin más**, con `drift` como ORM y `Riverpod` para
el estado. Interfaz **solo Cupertino**: no se importa `material.dart` en ningún sitio.

```
lib/
├── main.dart          CupertinoApp, localización en español
├── datos/             bd.dart · consultas · i18n · semilla · media · formato
├── estado/            providers.dart
├── tema/              tokens.dart · ui.dart
└── pantallas/         raiz (las tres pestañas) + nueve pantallas
assets/                ejercicios.es.json, el catálogo
test/                  datos_test.dart · pantallas_test.dart
docs/                  especificaciones.md, el trabajo previsto
```

`catalogo.dart` sirve dos destinos con la misma pantalla: la pestaña Ejercicios y el modal de
añadir a una rutina (`abrirAnadirEjercicio`). Por eso hay nueve ficheros de pantalla y diez
destinos navegables.

**`docs/especificaciones.md`** recoge lo que está previsto construir: series independientes por
ejercicio, edición de entrenamientos, temporizador de descanso, ajustes, copia de seguridad,
métricas de 1RM y el mapa muscular. Antes de proponer una funcionalidad nueva, mira si ya está
ahí especificada — incluye el esquema de datos final y el orden de las migraciones.

### Navegación: pestañas con pila propia

`pantallas/raiz.dart` monta un `CupertinoTabScaffold` de tres pestañas (Rutinas · Ejercicios ·
Progreso). Cada una vive en su `CupertinoTabView`, que trae **su propio `Navigator`**: de ahí salen
gratis el botón atrás, las transiciones de empuje y el gesto de volver deslizando.

- Se navega con `Navigator.push(CupertinoPageRoute(...))`. **No hay go_router**: no hay deep links
  ni URLs que justifiquen la maquinaria.
- Cada pantalla exporta su `abrirX(context, id)`, que es lo que llaman las demás. Así el import va
  en una sola dirección y no hacen falta imports perezosos.
- Los modales (`entrenar`, añadir ejercicio) se empujan con `fullscreenDialog: true` y
  `rootNavigator: true`, para que suban por encima de la barra de pestañas.

### Estado: invalidar, no reconstruir

`estado/providers.dart` declara un provider por consulta de vista. Tras una escritura se llama a
`invalidarRutinas` / `invalidarRutina` / `invalidarEntrenamientos`, y se repinta **solo** lo que
dependía de eso.

Esto sustituye al esquema anterior, que reconstruía la pila entera en cada navegación y perdía por
el camino el estado local de la pantalla. Ahora el mes del calendario, la pestaña de progreso y el
texto de búsqueda son estado del widget y **no viajan en los parámetros de la ruta**.

Los providers se declaran **a mano**: `riverpod_generator` y `drift_dev` no coinciden en la versión
de `analyzer` que admite el `flutter_test` de este SDK. Por lo mismo, `build_runner` y `drift_dev`
llevan la restricción abierta en `pubspec.yaml` — **no las fijes** sin comprobar que `pub get`
resuelve.

### Datos

`datos/bd.dart` tiene las cinco tablas y todas las consultas. drift devuelve clases de datos planas,
así que —a diferencia de SQLAlchemy— una fila leída se puede pasar a la interfaz sin más.

Aun así se conservan las consultas preagregadas (`resumenRutinas`, `seriesConFecha`,
`coloresRutinas`, `ejerciciosDeRutina` con su join a la ficha): ahorran una consulta por fila en las
pantallas que pintan listas. **Al añadir una vista, añade la consulta que le dé los datos ya
resueltos.**

`PRAGMA foreign_keys = ON` se activa en `beforeOpen`. Sin él SQLite ignora los `ON DELETE CASCADE` y
borrar una rutina dejaría sus series huérfanas.

**Migraciones:** `schemaVersion` va por 1. Todo cambio de esquema exige subirlo y añadir el paso en
`MigrationStrategy`, o las bases de datos existentes se romperán.

### Catálogo de ejercicios

1.324 ejercicios de [hasaneyldrm/exercises-dataset](https://github.com/hasaneyldrm/exercises-dataset).

- `assets/ejercicios.es.json` (~1 MB) se versiona y está declarado en `pubspec.yaml`. `semilla.dart`
  lo vuelca en la tabla del catálogo de forma idempotente (compara recuentos) y lo parsea en un
  isolate con `compute()`, para no congelar el primer frame.
- La columna `busqueda` es el índice: nombre en inglés **más** las traducciones de `datos/i18n.dart`,
  normalizado sin acentos. Por eso «mancuerna pecho» encuentra lo mismo que «dumbbell bench press».
  Si tocas `i18n.dart`, hay que **resembrar** (`sembrarCatalogo(bd, forzar: true)`).
- Dart no trae normalización Unicode, así que `normalizar()` sustituye los caracteres acentuados en
  vez de descomponerlos en NFKD. Si añades vocabulario con diacríticos raros, amplía el mapa.
- Los nombres de ejercicio solo existen en inglés y se muestran tal cual; lo que se traduce son las
  categorías (`bodyPart`, `equipment`, `target`, músculos).
- `Ejercicio.idCatalogo` es nulo en los ejercicios personalizados del usuario.
- El buscador pagina de 40 en 40 con un `ScrollController`; nunca pintes los 1.324 de golpe.
- El duplicado se comprueba **dentro de la rutina**: dos rutinas sí pueden compartir el mismo
  ejercicio del catálogo. Hay un test que lo fija.

### Media: licencia y resolución

Las imágenes y GIFs son **© Gym visual**, redistribuidos en el dataset original bajo permiso con dos
condiciones: solo a 180×180 y con la atribución visible. **No se versionan ni se empaquetan en el
APK**, y eso lo garantizan dos cosas: no están declarados en el bloque `assets:` de `pubspec.yaml`,
y `inicializarMedia()` los descarga al directorio de `path_provider`, fuera del proyecto. La entrada
`media/` del `.gitignore` es solo una red de seguridad. Se descargan en el primer arranque desde la
pantalla de onboarding, o se resuelven contra la URL remota si el usuario la omite.

`media.resolver(ruta)` devuelve un `ImageProvider`: `FileImage` si el fichero está descargado y
`NetworkImage` si no. La app funciona durante la descarga, si se omite, o si falló a medias.
**Usa siempre `resolver()`, nunca construyas rutas a mano.** La ficha de ejercicio muestra
`media.atribucion` al pie; es requisito de licencia, no decoración.

`inicializarMedia()` se llama desde `arranqueProvider` y fija el directorio con `path_provider`
(en Android e iOS el directorio de trabajo no es escribible). Cualquier escritura a disco nueva debe
pasar por ahí.

### Sistema de diseño

`tema/tokens.dart` (constantes) y `tema/ui.dart` (componentes).

Los colores son los **semánticos de Cupertino**, que en Flutter son `CupertinoDynamicColor` y **no
valen tal cual**: hay que resolverlos contra el contexto o no cambian entre claro y oscuro. Está
encapsulado en la extensión `Paleta`, así que en las pantallas se escribe `context.texto`,
`context.tarjeta`, `context.acento`. **No uses `CupertinoColors` directamente** y no metas hex
literales salvo en `coloresRutina`, que identifica rutinas y debe ser estable en ambos temas.

En `ui.dart` solo está lo que Flutter no trae. El inventario completo es `estilo`, `TituloGrande`,
`Grupo`, `Pildora`, `PuntoColor`, `Miniatura`, `BotonPrincipal`, `SelectorNumerico`, `EstadoVacio`,
`Cargando`, `BarraProgreso`, `DeslizarParaBorrar`, `barra`, `dialogoTexto`, `dialogoConfirmar` y
`aviso`. Para lo demás usa el widget del framework: `CupertinoListSection.insetGrouped` (envuelto en
`ui.Grupo`), `CupertinoListTile`, `CupertinoSearchTextField`, `CupertinoSlidingSegmentedControl`.

**No importes `material.dart`.** Si necesitas algo que solo existe en Material (`BarraProgreso` nació
así, sustituyendo a `LinearProgressIndicator`), compónlo en `ui.dart`.

### Empaquetado

`pubspec.yaml` es la única fuente de dependencias. El permiso de **INTERNET va en
`android/app/src/main/AndroidManifest.xml`**: Flutter solo lo declara en los manifiestos de debug y
profile, así que sin esa línea el APK de release no puede descargar la media.

CI construye un APK **universal**, que pesa unos 55 MB porque lleva dentro las librerías nativas de
las tres arquitecturas. Se eligió así para que sea un único fichero que instalar a mano desde el
móvil. Con `--split-per-abi`, o compilando solo `arm64-v8a`, baja a unos 20 MB a cambio de dejar
fuera los móviles de 32 bits.

### CI y versiones

`.github/workflows/build-apk.yml` es el único workflow. **El APK sale siempre de `main`**, que es la
versión buena; las ramas de trabajo no publican nada.

| Disparador | Verifica | Construye APK | Publica release |
|---|---|---|---|
| **Pull request a `main`** | sí | sí, como *artifact* de la ejecución | no |
| **Push a `main`** (mergear un PR) | sí | sí | **sí, una nueva** |
| **`workflow_dispatch`** | sí | sí | solo si se lanza sobre `main` |

Un PR no publica release a propósito: apuntaría a código que todavía no está integrado y que puede
no llegar a mergearse nunca. Para probar un PR en el móvil se descarga su artifact desde la pestaña
*Actions*.

**Versionado.** La versión es `SERIE.<número de ejecución>`, con `SERIE` (hoy `1.0`) en el bloque
`env:` del workflow. El contador de ejecuciones lo lleva GitHub, así que sube solo y **nunca se
repite**: cada merge a `main` deja una release nueva etiquetada `v1.0.N`, y las anteriores se
quedan. No hay una release móvil que se sobrescriba, de modo que el enlace de descarga para el
móvil es `releases/latest`. Las releases **no** van marcadas como *prerelease*, precisamente para
que `releases/latest` las resuelva.

Ese mismo número se pasa a `--build-name` y `--build-number`, así que el `versionCode` de Android
también es estrictamente creciente y el móvil reconoce cada APK como una actualización del anterior.
El `version: 1.0.0+1` de `pubspec.yaml` solo se usa en compilaciones locales; CI siempre lo pisa.

Para subir de serie (a `1.1`, por ejemplo), se cambia `SERIE` en el workflow y nada más.

**Cambios que no generan versión.** `paths-ignore` deja fuera `README.md`, `CLAUDE.md` y `docs/**`:
un merge que solo toca documentación produciría un APK idéntico al anterior. Si tocas esos ficheros
**y** código en el mismo commit, sí se dispara.
