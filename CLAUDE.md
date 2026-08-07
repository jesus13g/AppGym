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
flutter test                    # 226 tests: datos, pantallas, migraciones, copia, ajustes y métricas
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
  `bdProvider`. Los tests de widget son rápidos y ya han pillado tres desbordamientos de layout
  reales, así que **añade uno al tocar una pantalla**.

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
├── main.dart          CupertinoApp, tema (claro/oscuro/sistema), localización
├── datos/
│   ├── bd.dart        las diez tablas y todas las consultas
│   ├── esquemas.dart  esquemas versionados, generados, para los pasos de migración
│   ├── ajustes.dart   preferencias: claves, valores por defecto y unidades
│   ├── copia.dart     exportar e importar la copia de seguridad (JSON y CSV)
│   ├── respaldo.dart  duplicado del fichero .sqlite antes de migrarlo
│   ├── borrador.dart  estado de la sesión en curso, serializado a JSON
│   ├── plantillas.dart rutinas predefinidas desde assets/plantillas.json
│   ├── semilla.dart   carga del catálogo en la base de datos
│   ├── media.dart     descarga y resolución de imágenes y GIFs
│   ├── i18n.dart      vocabulario del catálogo en español
│   ├── metricas.dart  1RM, récords, semana y racha: solo funciones puras
│   ├── reloj.dart     la hora, en un punto que los tests pueden adelantar
│   └── formato.dart   fechas, pesos, duraciones y textos
├── estado/            providers.dart · descanso.dart (el temporizador)
├── tema/              tokens.dart · ui.dart
└── pantallas/         quince pantallas + dos piezas compartidas
assets/                ejercicios.es.json (el catálogo) · plantillas.json
drift_schemas/         un JSON por versión del esquema, para los tests de migración
test/                  datos · pantallas · migraciones · copia · ajustes · plantillas · metricas
                       esquemas/ (generado)
docs/                  especificaciones.md, el trabajo previsto
```

Dos ficheros de `pantallas/` no son pantallas, sino piezas que comparten varias:
`anadir_a_rutina.dart` (el `anadirARutina` que usan la lista del catálogo y la ficha, más el
`BotonFavorito`) y `copia_seguridad.dart` (el grupo «Datos» de Ajustes, aparte porque es lo único
de esa pantalla que escribe ficheros y restaura la base entera).

Dos pantallas sirven doble destino: `catalogo.dart` es a la vez la pestaña Ejercicios y el modal de
añadir a una rutina (`abrirAnadirEjercicio`), y `entrenar.dart` es, según su `Modo`, la sesión viva
o el formulario de siempre.

**`docs/especificaciones.md`** recoge lo que está previsto construir. Sus **bloques A
(limitaciones del modelo de datos), B (uso diario) y C (progreso y análisis) ya están
implementados**: series independientes, editar y borrar entrenamientos, elegir la fecha, orden,
notas y RPE, varias rutinas el mismo día, temporizador de descanso, sesión viva, la pantalla de
Ajustes completa, copia de seguridad, plantillas, favoritos, medidas del cuerpo, 1RM estimado con
sus récords, resumen semanal con racha y días de calendario pulsables. Queda **D** (mapa muscular).
Antes de proponer una funcionalidad nueva, mira si ya está ahí especificada — incluye el esquema de
datos final, el orden de las migraciones y las desviaciones de lo que se implementó.

### Navegación: pestañas con pila propia

`pantallas/raiz.dart` monta un `CupertinoTabScaffold` de tres pestañas (Rutinas · Ejercicios ·
Progreso). Cada una vive en su `CupertinoTabView`, que trae **su propio `Navigator`**: de ahí salen
gratis el botón atrás, las transiciones de empuje y el gesto de volver deslizando.

- Se navega con `Navigator.push(CupertinoPageRoute(...))`. **No hay go_router**: no hay deep links
  ni URLs que justifiquen la maquinaria.
- Cada pantalla exporta su `abrirX(context, id)`, que es lo que llaman las demás. Así el import va
  en una sola dirección y no hacen falta imports perezosos.
- Los modales (`entrenar`, añadir ejercicio, resumen de cierre) se empujan con
  `fullscreenDialog: true` y `rootNavigator: true`, para que suban por encima de la barra de
  pestañas.

Dentro de **Progreso** hay un `CupertinoSlidingSegmentedControl` de tres: Resumen · Calendario ·
Cuerpo. **Con cuatro el texto empieza a apretarse en un móvil estrecho**, así que el mapa muscular
(bloque D) tendrá que compartir sitio ahí dentro o buscarse otro; la decisión H1 de la
especificación cerró que no habrá una cuarta pestaña.

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

`invalidarTodo` es la excepción a «invalida solo lo afectado»: la usan importar una copia y borrar
los datos, donde no cambia una rutina sino la base entera y enumerar provider a provider sería el
sitio perfecto para olvidarse de uno. **Si añades un provider de datos, mételo ahí.**

`estado/descanso.dart` es el único `Notifier` con estado mutable de la app. El temporizador vive
ahí y no en un widget para que la cuenta atrás sobreviva a navegar a la ficha de un ejercicio y
volver. Dos reglas que ya han costado un fallo cada una:

- **`ref` no se puede tocar en `dispose()`** (cuelga del `BuildContext`, que para entonces está
  desactivado). `PantallaEntrenar` guarda el notifier en un campo en `initState`.
- **Escribir el estado de un provider mientras se desmonta el árbol está prohibido.** Por eso
  `dispose` para el `Timer` en el acto (`pararReloj`) y aplaza el `saltar()` un frame; y `saltar`
  comprueba `ref.mounted`, porque en ese hueco el `ProviderScope` puede haberse ido.

### Datos

`datos/bd.dart` tiene las diez tablas y todas las consultas. drift devuelve clases de datos planas,
así que —a diferencia de SQLAlchemy— una fila leída se puede pasar a la interfaz sin más.

```
rutinas              id, nombre (único), color
ejercicios           id, idRutina, idCatalogo, nombre, descripcion, orden, descansoSeg
catalogo_ejercicios  el dataset, de solo lectura, con índices en busqueda/bodyPart/
                     equipment/target
entrenamientos       id, idRutina, fecha, nota, duracionSeg
serie                una fila por serie: nSerie, repeticiones, peso, calentamiento, rpe, nota
ajustes              clave, valor
sesiones_activas     el borrador de la sesión en curso (como mucho una fila)
favoritos            idCatalogo, creado
vistos               idCatalogo, fecha (se conservan los 10 últimos)
medidas              id, fecha, tipo, valor — con clave única (fecha, tipo)
```

**`serie` guarda una fila por serie hecha.** Su columna `nSerie` es el **índice** de la serie dentro
del ejercicio, no el recuento: hasta el esquema v1 era lo contrario y el nombre se conservó para no
reescribir las consultas. Las series de calentamiento se guardan pero no cuentan en volumen, máximos
ni 1RM, así que las agregaciones las excluyen.

Aun así se conservan las consultas preagregadas (`resumenRutinas`, `seriesConFecha`,
`coloresRutinas`, `ejerciciosDeRutina` con su join a la ficha): ahorran una consulta por fila en las
pantallas que pintan listas. **Al añadir una vista, añade la consulta que le dé los datos ya
resueltos.**

`PRAGMA foreign_keys = ON` se activa en `beforeOpen`. Sin él SQLite ignora los `ON DELETE CASCADE` y
borrar una rutina dejaría sus series huérfanas.

**Migraciones:** `schemaVersion` va por 6. Todo cambio de esquema exige subirlo y añadir el paso en
`MigrationStrategy`, o las bases de datos existentes se romperán. El flujo completo, tras tocar una
tabla:

```bash
dart run build_runner build
dart run drift_dev schema dump lib/datos/bd.dart drift_schemas/       # el esquema nuevo
dart run drift_dev schema steps drift_schemas/ lib/datos/esquemas.dart   # tipos de stepByStep
dart run drift_dev schema generate drift_schemas/ test/esquemas/         # ayudantes de test
dart format lib test
```

Los tres ficheros generados **se versionan** (no son `*.g.dart`) y hay que formatearlos, porque CI
comprueba el formato de `lib` y `test`. Los pasos se escriben contra el esquema *de su versión*
(`Schema2`, `Schema3`…), no contra las tablas de `bd.dart`: así una migración vieja no se rompe
cuando el modelo actual cambie.

`test/migraciones_test.dart` monta una base de una versión anterior **de verdad**, le mete datos y
la migra hasta la actual, comparando además el esquema resultante con el volcado. Es lo que caza una
columna que se añadió al modelo y no a la migración.

**Antes de la v2 se respalda el fichero** (`datos/respaldo.dart`): es la única migración que
transforma datos. La copia se hace con la base todavía cerrada, desde el callback `databasePath` de
`drift_flutter`, porque con la conexión abierta el WAL dejaría el duplicado a medias.

Las preferencias viven en la tabla `ajustes`, de clave/valor, para que entren en la misma copia de
seguridad que el resto de los datos. Quien las interpreta es `datos/ajustes.dart`: ahí están las
claves, los valores por defecto y la conversión de unidades. `bd.ajustes()` solo trae las filas, y
`Ajustes.desdeMapa` se traga sin quejarse un valor con basura o fuera de rango —se queda con el de
fábrica—, porque una clave corrupta no puede impedir que la app arranque.

`bd.dart` **reexporta** `Ajustes`, `EscalaEsfuerzo`, `Tema` y `Unidad`, así que las pantallas los
tienen con el `import '../datos/bd.dart'` que ya hacían. Las **claves** (`Claves.unidad`…) y los
valores admitidos (`pasosPeso`, `descansos`) no se reexportan: eso solo lo necesita la pantalla de
Ajustes, y va por `import '../datos/ajustes.dart'`.

**La sesión en curso se guarda como JSON**, no normalizada (`datos/borrador.dart` ↔ tabla
`sesiones_activas`): es un dato efímero, se reescribe entero en cada cambio y nadie lo consulta por
partes. Se escribe con *debounce* de 2 s para no tocar disco en cada toque de un selector, y al
confirmar el entrenamiento la inserción y el borrado del borrador van en la **misma transacción**
(`insertarEntrenamiento(descartarBorrador: true)`); si no, habría un instante en el que reabrir la
app ofrecería continuar una sesión ya guardada.

**Las medidas se guardan a medianoche.** `registrarMedida` normaliza la fecha antes de escribir: es
lo que hace que la clave única `(fecha, tipo)` signifique de verdad «una por día». Y su `onConflict`
apunta a esa clave única, no a la primaria —que es un `id` autoincremental y nunca choca—; con un
`insertOnConflictUpdate` normal reventaría contra el índice. Hay un test que lo fija.

**El peso se guarda siempre en kilogramos.** Las libras son solo presentación: todo peso pasa por
`formato.peso(kilos, ajustes)` antes de pintarse, y el selector del registro convierte de vuelta
con `ajustes.aKilos`. En cuanto una pantalla escriba `'$valor kg'` a mano, cambiar de unidad dejará
de funcionar justo ahí.

**Nada que cronometre debe llamar a `DateTime.now()`.** El descanso y el cronómetro de la sesión
viva usan `datos/reloj.dart`, que es la costura que los tests adelantan: `tester.pump` mueve los
`Timer`, no el calendario. **El resumen semanal también pasa por ahí** aunque no cronometre nada: es
lo que permite a sus tests fijar la semana en vez de depender de cuándo se ejecute la suite.

**Dos tablas van sin clave foránea a propósito**, `favoritos` y `vistos`: `sembrarCatalogo` borra y
reinserta el catálogo entero cuando cambia el dataset, y con la clave puesta esa operación fallaría
en cuanto hubiera un favorito guardado. Hay un test que lo fija.

### Métricas: la lógica fuera de la base y fuera de la pantalla

`datos/metricas.dart` es el único módulo de la app que **no importa Flutter ni escribe en la base**:
1RM estimado, volumen, mejor serie, récords, reparto por semanas y racha. Recibe listas y devuelve
números, así que `test/metricas_test.dart` lo cubre con datos y fechas escritos a mano.

- **Los récords se calculan, no se almacenan.** Guardarlos abriría la puerta a que quedaran
  desincronizados al editar o borrar una sesión; recorrer el histórico en memoria es instantáneo con
  volúmenes personales. Por lo mismo, `recordsEjercicio` y `sesionesConRecord` trabajan sobre la
  lista que `resumenSesionesEjercicio` **ya devolvió** a la pantalla: cambiar el eje del gráfico o el
  rango no vuelve a consultar.
- **Con una repetición el 1RM es el peso tal cual.** Epley cruda daría 103,3 para 100 kg, que no es
  una estimación sino un máximo medido. El caso especial está en `unoRm` **y** en la expresión SQL;
  las dos consultas que estiman la componen desde `AppBD._expresion1RM`, para que no puedan
  discrepar. Si tocas una, mira la otra.
- **Más de doce repeticiones no estiman un máximo.** Se calcula igual y se enseña marcado, pero no
  cuenta para un récord: de ahí que `ResumenSesionEjercicio` traiga `mejor1RM` y `mejor1RMFiable`,
  y que la segunda pueda ser nula.
- **La semana se agrupa en Dart, no con `strftime`.** Las funciones de fecha de SQLite trabajan en
  UTC y partirían mal las semanas en huso local. `sesionesConVolumen` es la única consulta del
  resumen semanal; el reparto lo hace `porSemana`.
- **La racha no cuenta la semana en curso.** Si contara, el lunes por la mañana toda racha valdría
  cero. Y tiene suelo en la primera semana registrada, o seguiría contando semanas vacías hacia
  atrás para siempre.

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
`Grupo`, `Pildora`, `PuntoColor`, `Miniatura`, `BotonPrincipal`, `SelectorEnLinea`, `EstadoVacio`,
`Cargando`, `BarraProgreso`, `BarraDescanso`, `CheckSerie`, `DeslizarParaBorrar`, `barra`,
`selectorFecha`, `elegirEnHoja`, `dialogoTexto`, `dialogoConfirmar` y `aviso`. Para lo demás usa el
widget del framework: `CupertinoListSection.insetGrouped` (envuelto en `ui.Grupo`),
`CupertinoListTile`, `CupertinoSearchTextField`, `CupertinoSlidingSegmentedControl`.

`elegirEnHoja<T>` devuelve `(T,)?`, un registro de un elemento, **no `T?`**: hace falta para
distinguir «cancelar» (`null`) de «elegir nada» (`(null,)`), que es un valor legítimo — el descanso
«como el global» o el filtro «todos» del catálogo.

**No importes `material.dart`.** Si necesitas algo que solo existe en Material (`BarraProgreso` nació
así, sustituyendo a `LinearProgressIndicator`; `ReorderableListView` se sustituye por
`SliverReorderableList` de `widgets.dart`), compónlo en `ui.dart`.

**Cuidado con el ancho de un móvil.** Los tests de widget que montan la pantalla de registro y el
detalle de rutina fijan la ventana a 375 px con `_comoUnMovil`, y ahí han saltado ya tres
desbordamientos reales que a 800 px no se veían —el último, la barra del descanso—. Al pintar una
fila con varios controles, hazla flexible.

**En la sesión viva no se puede usar `pumpAndSettle`.** El cronómetro y el descanso son
`Timer.periodic` que repintan para siempre, así que «esperar a que no queden fotogramas» no
termina nunca: los tests de ese grupo van con `_asentar`, a base de fotogramas sueltos.

### Empaquetado

`pubspec.yaml` es la única fuente de dependencias; hoy son nueve. Las dos últimas, `share_plus` y
`file_picker`, son de la copia de seguridad: sin ellas la única salida sería escribir en el
directorio de documentos y cantar la ruta, que en Android no hay quien alcance. `share_plus` se
queda en la 12 porque la 13 exige `win32 ^6` y `file_picker` pide `win32 ^5`.

El permiso de **INTERNET va en
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

Ese mismo número se pasa a `--build-name`, `--build-number` y `--dart-define=VERSION`, así que el
`versionCode` de Android es estrictamente creciente —el móvil reconoce cada APK como una
actualización del anterior— y el «Acerca de» de Ajustes puede enseñar la versión leyéndola con
`String.fromEnvironment`, sin necesidad de `package_info_plus` para una cadena de texto. En una
compilación local no hay ninguna y pone `local`. El `version: 1.0.0+1` de `pubspec.yaml` solo se usa
en local; CI siempre lo pisa.

Para subir de serie (a `1.1`, por ejemplo), se cambia `SERIE` en el workflow y nada más.

**Cambios que no generan versión.** `paths-ignore` deja fuera `README.md`, `CLAUDE.md` y `docs/**`:
un merge que solo toca documentación produciría un APK idéntico al anterior. Si tocas esos ficheros
**y** código en el mismo commit, sí se dispara.
