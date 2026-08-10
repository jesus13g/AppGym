# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

El código, los comentarios, los commits y la interfaz están en **español**. Mantén ese idioma
al añadir código.

## Comandos

```bash
flutter pub get
dart run build_runner build     # genera bd.g.dart; obligatorio tras clonar
flutter gen-l10n                # genera lib/l10n/generado/; obligatorio tras clonar
flutter run                     # app en un dispositivo o emulador
flutter analyze                 # objetivo permanente: 0 issues
flutter test                    # datos, pantallas, migraciones, copia, copia automática y su
                                # adaptador de Drive, la sincronización entera —motor, primer
                                # enlace, sellos, adaptador de Supabase y disparadores—,
                                # ajustes, métricas, músculos, geometría, progresiones,
                                # formatos, importaciones, traducciones y vocabulario
dart format lib test
flutter build apk --release     # APK local (necesita SDK de Android y Java 17)
```

Se desarrolla con **Flutter 3.44.8 / Dart 3.12.2**. La versión está fijada en
`.github/workflows/build-apk.yml`; si la subes, súbela también ahí.

**Los `*.g.dart` no se versionan** (ver `.gitignore`). Sin `build_runner build` no compila nada, ni
en local ni en CI. **`lib/l10n/generado/` tampoco**: sin `flutter gen-l10n` no existe la clase
`Textos` y no compila ninguna pantalla. Son dos generadores independientes —`gen-l10n` es un
comando del propio SDK y no pasa por `build_runner`—, así que no se pisan.

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
├── main.dart          CupertinoApp, tema (claro/oscuro/sistema), idioma
├── datos/
│   ├── bd.dart        las doce tablas y todas las consultas
│   ├── esquemas.dart  esquemas versionados, generados, para los pasos de migración
│   ├── ajustes.dart   preferencias: claves, valores por defecto y unidades
│   ├── copia.dart     exportar e importar la copia de seguridad (JSON y CSV)
│   ├── copia_automatica.dart  cuándo toca copiar, qué se rota y cuándo se avisa (puro)
│   ├── nube/          nube.dart (la costura) · drive.dart (Google) · token.dart
│   ├── sincro/        transporte.dart (la costura) · motor.dart (la reconciliación) ·
│   │                  enlace.dart (el primer enlace) · supabase.dart (el adaptador)
│   ├── identidad.dart el uuid de una fila y el sello de su versión
│   ├── respaldo.dart  duplicado del fichero .sqlite antes de migrarlo
│   ├── borrador.dart  estado de la sesión en curso, serializado a JSON
│   ├── plantillas.dart rutinas predefinidas desde assets/plantillas.json
│   ├── semilla.dart   carga del catálogo en la base de datos
│   ├── media.dart     descarga y resolución de imágenes y GIFs
│   ├── i18n.dart      vocabulario del catálogo: API por idioma
│   ├── i18n_es.dart   las tres tablas en español
│   ├── i18n_en.dart   las tres tablas en inglés
│   ├── metricas.dart  1RM, récords, semana y racha: solo funciones puras
│   ├── musculos.dart  las 21 regiones del mapa y el reparto del trabajo (puro)
│   ├── geometria.dart trazados del modelo anatómico y resolución del toque
│   ├── progresion.dart qué hacer hoy con un ejercicio: doble progresión (puro)
│   ├── reloj.dart     la hora, en un punto que los tests pueden adelantar
│   └── formato.dart   `Formato`: fechas, números, pesos y vocabulario del idioma
├── l10n/
│   ├── app_es.arb     los textos en español (la plantilla, con las descripciones)
│   ├── app_en.arb     los textos en inglés
│   ├── textos.dart    `context.t`, `idiomasSoportados` y el reexport de lo generado
│   └── generado/      `Textos` y sus delegates  ← NO se versiona
├── estado/            providers.dart · descanso.dart (el temporizador) ·
│                      copia_automatica.dart (el motor de la copia a la nube) ·
│                      sincro.dart (el motor de la sincronización)
├── tema/              tokens.dart · ui.dart
└── pantallas/         quince pantallas + cinco piezas compartidas
assets/                ejercicios.es.json (el catálogo) · instrucciones.en.json (sus pasos en
                       inglés) · plantillas.json (por idioma) · musculatura.json
drift_schemas/         un JSON por versión del esquema, para los tests de migración
supabase/              esquema.sql: las dos tablas, la RLS y las cinco funciones del servidor
tool/                  musculatura.py (el modelo anatómico) · instrucciones_en.py (los pasos
                       en inglés, desde el dataset original)
test/                  datos · pantallas · migraciones · copia · ajustes · plantillas · metricas
                       musculos · geometria · progresion · formato · i18n · traducciones ·
                       sincro · sincro_sellos · enlace · sincro_supabase · sincro_estado ·
                       importaciones · esquemas/ (generado)
docs/                  especificaciones.md (hecho) · especificaciones-2.md (I, J y K enteros,
                       hechos) · privacidad.md · sincronizacion.md (montar el servidor)
```

Seis ficheros de `pantallas/` no son pantallas, sino piezas que comparten varias:
`anadir_a_rutina.dart` (el `anadirARutina` que usan la lista del catálogo y la ficha, más el
`BotonFavorito`), `copia_seguridad.dart` (el grupo «Datos» de Ajustes, aparte porque es lo único
de esa pantalla que escribe ficheros y restaura la base entera, y de donde sale
`escribirCopiaLocal`), `copia_nube.dart` y `cuenta.dart` (los grupos «Copia automática» y «Cuenta»,
aparte por lo mismo, más sus avisos en la cabecera de Rutinas), `musculatura.dart` (el mapa
muscular, que se incrusta en la sección «Cuerpo» de Progreso y no monta scaffold propio),
`sugerencia.dart` (la línea de progresión que pintan la tarjeta de entrenar y la de resultados, con
la frase de cada motivo) y `opciones_ejercicio.dart` (la hoja de descanso y progresión de un
ejercicio, que abren la pantalla de entrenar y el detalle de la rutina).

Dos pantallas sirven doble destino: `catalogo.dart` es a la vez la pestaña Ejercicios y el modal de
añadir a una rutina (`abrirAnadirEjercicio`), y `entrenar.dart` es, según su `Modo`, la sesión viva
o el formulario de siempre.

**Hay dos documentos de especificación y no dicen lo mismo.**

**`docs/especificaciones.md` está cerrado: es lo ya construido.** Sus bloques A (limitaciones del
modelo de datos), B (uso diario), C (progreso y análisis) y D (mapa muscular) están **enteros
implementados**: series independientes, editar y borrar entrenamientos, elegir la fecha, orden,
notas y RPE, varias rutinas el mismo día, temporizador de descanso, sesión viva, la pantalla de
Ajustes completa, copia de seguridad, plantillas, favoritos, medidas del cuerpo, 1RM estimado con
sus récords, resumen semanal con racha, días de calendario pulsables y el mapa muscular. Se
consulta como el **porqué** de lo que hay: incluye el esquema de datos hasta la v6, el orden de las
migraciones y las desviaciones de lo que se implementó, que en D son largas y razonadas.

**`docs/especificaciones-2.md` está entero hecho.** Recoge los tres puntos que el anterior dejó
fuera de alcance a propósito:

- **I — internacionalización de la interfaz** (ARB + `flutter gen-l10n`, español e inglés, el
  catálogo con índice de búsqueda multilingüe). **Hecho**, con sus seis desviaciones documentadas
  en I8.
- **J — recomendación automática de progresiones** (`datos/progresion.dart`, doble progresión,
  esquema v7). **Hecho**, con sus nueve desviaciones documentadas en J6.
- **K — sincronización en la nube, cuentas y multidispositivo** (`uuid` + `actualizado` +
  lápidas, esquema v8, último en escribir gana). **Hecho entero**, en tres fases: 8a la copia
  automática, 8b el motor y 8c el servicio, con sus once y diez desviaciones documentadas. **8a no
  es sincronización y no debe llamarse así en ningún sitio**: es una copia con fecha que se sube
  sola, y dos móviles que copien el mismo día se pisan.

Antes de proponer una funcionalidad nueva, mira si ya está especificada en uno de los dos.

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
Cuerpo. **Con cuatro el texto empieza a apretarse en un móvil estrecho**, y la decisión H1 de la
especificación cerró que no habrá una cuarta. Por eso el mapa muscular comparte la sección
«Cuerpo» con las medidas: se pinta encima de ellas, dentro del mismo scroll.

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

`datos/bd.dart` tiene las doce tablas y todas las consultas. drift devuelve clases de datos planas,
así que —a diferencia de SQLAlchemy— una fila leída se puede pasar a la interfaz sin más.

```
rutinas              id, nombre (único), color, uuid, actualizado
ejercicios           id, idRutina, idCatalogo, nombre, descripcion, orden, descansoSeg,
                     repMin, repMax, incrementoKg, estrategia (las cuatro: null = «global»),
                     uuid, actualizado
catalogo_ejercicios  el dataset, de solo lectura, con índices en busqueda/bodyPart/
                     equipment/target
entrenamientos       id, idRutina, fecha, nota, duracionSeg, uuid, actualizado
serie                una fila por serie: nSerie, repeticiones, peso, calentamiento, rpe, nota
ajustes              clave, valor, actualizado
sesiones_activas     el borrador de la sesión en curso (como mucho una fila)
favoritos            idCatalogo, creado, actualizado
vistos               idCatalogo, fecha (se conservan los 10 últimos)
medidas              id, fecha, tipo, valor, actualizado — con clave única (fecha, tipo)
lapidas              tabla, clave, actualizado — lo que se borró aquí y hay que propagar
sincro_estado        una fila: los dos cursores, la última pasada y sus avisos
```

`uuid` y `actualizado` son de la sincronización y no cambian nada de lo que ya había: **la
clave primaria sigue siendo el entero** y con él trabajan todas las consultas, los providers
y las rutas. Ver [Sincronización](#sincronización-identidad-versión-y-lápidas).

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

**Migraciones:** `schemaVersion` va por 8. Todo cambio de esquema exige subirlo y añadir el paso en
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

**Antes de la v2 y de la v8 se respalda el fichero** (`datos/respaldo.dart`): son las dos
migraciones que transforman datos, y la lista `versionesQueTransforman` es lo que lo decide. La
copia se hace con la base todavía cerrada, desde el callback `databasePath` de `drift_flutter`,
porque con la conexión abierta el WAL dejaría el duplicado a medias.

Las preferencias viven en la tabla `ajustes`, de clave/valor, para que entren en la misma copia de
seguridad que el resto de los datos. Quien las interpreta es `datos/ajustes.dart`: ahí están las
claves, los valores por defecto y la conversión de unidades. `bd.ajustes()` solo trae las filas, y
`Ajustes.desdeMapa` se traga sin quejarse un valor con basura o fuera de rango —se queda con el de
fábrica—, porque una clave corrupta no puede impedir que la app arranque.

`bd.dart` **reexporta** `Ajustes`, `EscalaEsfuerzo`, `Formula`, `Perfil`, `Tema` y `Unidad`, así que
las pantallas los tienen con el `import '../datos/bd.dart'` que ya hacían. Las **claves**
(`Claves.unidad`…) y los valores admitidos (`pasosPeso`, `descansos`) no se reexportan: eso solo lo
necesitan las pantallas que los ofrecen, y va por `import '../datos/ajustes.dart'`. También sale por
ahí `Value` de drift, que lo pide `fijarProgresionEjercicio`: es el **único** símbolo de drift que
asoma fuera de `datos/`.

**La sesión en curso se guarda como JSON**, no normalizada (`datos/borrador.dart` ↔ tabla
`sesiones_activas`): es un dato efímero, se reescribe entero en cada cambio y nadie lo consulta por
partes. Se escribe con *debounce* de 2 s para no tocar disco en cada toque de un selector, y al
confirmar el entrenamiento la inserción y el borrado del borrador van en la **misma transacción**
(`insertarEntrenamiento(descartarBorrador: true)`); si no, habría un instante en el que reabrir la
app ofrecería continuar una sesión ya guardada. Ahí viven también las sugerencias descartadas: son
un dato de la sesión en curso, no una preferencia, y el formato tolera que un borrador viejo no
traiga la clave.

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

`datos/metricas.dart` es el primero de los tres módulos que **no importan Flutter ni escriben en la
base** —los otros son `musculos.dart` y `progresion.dart`—: 1RM estimado, volumen, mejor serie,
récords, reparto por semanas y racha. Recibe listas y devuelve números, así que
`test/metricas_test.dart` lo cubre con datos y fechas escritos a mano.

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

### Mapa muscular: el vocabulario, el color y el dibujo

`datos/musculos.dart` es el segundo módulo puro, con la misma forma que `metricas.dart`: traduce los
cuatro vocabularios desiguales del dataset (`bodyPart` 10 valores, `target` 19, `muscleGroup` 29,
`secondaryMuscles` 40) a **21 regiones propias**, y reparte entre ellas el trabajo de cada serie.

- **`bodyPart` no se consulta nunca.** Sus valores se solapan con los de los otros tres (`back` son
  203 ejercicios, `chest` 163) y atribuirían en bloque y mal.
- **Los pesos son 1,0 / 0,5 / 0,3** (objetivo, grupo, secundarios) y, si una región recibe por
  varias vías, **se toma el mayor y no la suma**: si no, los ejercicios bien etiquetados pesarían
  más solo por estarlo.
- **El color sale de las series ponderadas, no del volumen en kilos.** En kilos, una serie de
  sentadilla vale diez veces una de abdominales, que es una propiedad del ejercicio y no del
  entrenamiento: el mapa saldría siempre con las piernas encendidas y el abdomen apagado. El volumen
  sí se calcula y se enseña en la hoja del músculo, donde se compara consigo mismo.
- **`pesoEfectivo = max(peso, 1)`** para que las dominadas no sumen cero. Es exclusivo del mapa: el
  1RM, el resumen semanal (C16, C17) y las progresiones (J1) no lo aplican. En una sugerencia de
  carga significaría proponer «sube de 1 kg a 3,5 kg» en un ejercicio de peso corporal.
- **Un test recorre los 1.324 ejercicios** y exige que todo término caiga en una región o en la
  lista de excluidos, **y que las 21 regiones sean alcanzables**. Sin lo segundo, un término mal
  escrito pasaría la cobertura y dejaría una región muerta. Si tocas la tabla, mira ese test.
- **`cardiovascular system` no tiene región, pero sus 29 ejercicios sí reparten** por grupo y
  secundarios. Un burpee trabaja las piernas.

`datos/geometria.dart` solo importa `dart:ui` y `dart:math`, así que **no conoce `Region`**: va
parametrizado por la clave. Tres cosas que ya han costado un fallo cada una:

- **El desempate entre regiones solapadas es por área real, no por `getBounds()`.** Casi todas son
  bilaterales, y el rectángulo que envuelve las dos mitades del pectoral abarca el torso entero.
- **El toque se prueba trazado a trazado**, no contra el `Path` combinado: reflejar invierte el
  sentido de giro y el relleno `nonZero` anularía los solapes.
- **La tolerancia del dedo va en unidades del lienzo, no de pantalla.** Son unas cinco veces más;
  pasar los 12 px tal cual la deja en nada. Para eso está `Encaje.aLienzoDistancia`.

**El dibujo** (`assets/musculatura.json`, 32 KB) es original de este repositorio y así está
documentado en `README.md` — es requisito, no formalidad. Son trazados escritos como punto inicial
más segmentos cúbicos; **no hay parser de SVG** y no conviene añadirlo. Los músculos bilaterales se
declaran una vez con `"espejo": true` y se reflejan al cargar.

**El JSON no se edita a mano**: se genera con `python3 tool/musculatura.py`, donde cada región es
una lista de anclas que una spline cerrada convierte en curvas. El script escribe también una previa
en SVG, que es la única forma de ver si el dibujo sigue pareciendo un cuerpo. Al combinar los trazados de una
figura se usa `Path.combine(union)`: acumularlos sin más deja el borde de la línea media dentro del
contorno y se pinta una raya vertical por mitad del cuerpo.

Lo que ningún test puede validar es si el dibujo **parece** un cuerpo. Lo que sí está automatizado
son los invariantes: toda región dentro de la silueta, ninguna fuera del lienzo, ninguna tapada al
toque por otra, y la cara declarada igual a la dibujada. Si retocas las formas, eso es lo que avisa.

### Progresiones: proponer sin decidir

`datos/progresion.dart` es el tercer módulo puro, con la misma forma que los otros dos. Implementa
la **doble progresión**: se sube de repeticiones dentro de un rango sesión a sesión y, cuando todas
las series efectivas llegan al tope, se sube el peso un escalón y se vuelve al suelo del rango.

- **Devolver `null` es la mitad del diseño.** Sin dos sesiones previas, en cardio o con la
  progresión desactivada no hay sugerencia y **la interfaz no enseña nada**. Una sugerencia
  inventada el primer día vale menos que ninguna.
- **La app propone; nunca aplica.** No hay ajuste que lo permita: la app no sabe si has dormido mal,
  si vienes de una lesión o si la última sesión la cortaste a la mitad. «Aplicar» reescribe los
  valores del formulario y no guarda nada.
- **No añade consultas.** `sugerenciaProvider` compone `resumenSesionesEjercicioProvider`,
  `ultimasSeriesProvider` y `ajustesProvider`, que las pantallas ya piden. La única consulta nueva
  del bloque es `resumenSesionesTodos`, para los estancados del resumen semanal, y es el mismo
  `GROUP BY` sin el filtro de ejercicio.
- **El escalón de peso vive en dos unidades y hay que tenerlo presente.** `ajustes.pasoPeso` está en
  la unidad activa (alimenta el selector de peso) y la columna `incrementoKg` en kilos. La
  conversión se hace **una sola vez**, en `ConfiguracionProgresion.resolver`, y es lo que hace que
  el peso sugerido salga redondo también en libras. Hay un test que lo fija.
- **El esfuerzo entra solo si el usuario lo registra.** El RPE está apagado de fábrica, así que el
  modelo funciona sin él: si dependiera del RPE, la funcionalidad no existiría para la mayoría. Por
  lo mismo, no usarlo **no** marca la sugerencia como poco fiable; lo que la marca es tener menos de
  tres sesiones, o pedir el esfuerzo y no haberlo anotado.
- **El estancamiento se calcula, no se guarda**, por el mismo motivo que los récords en C16: al
  editar o borrar una sesión quedaría desincronizado.
- **El motivo viaja como enumerado, no como texto.** La frase se compone en
  `pantallas/sugerencia.dart`. Es lo que permitirá traducirlo (bloque I) sin tocar la lógica: si
  añades un motivo, la frase va ahí y el `switch` exhaustivo te avisa.
- **La configuración se resuelve por capas**: los ajustes globales, luego las cuatro columnas del
  ejercicio (`null` = «como el global»), y por encima lo que imponen el propio ejercicio y su
  historial —cardio nunca sugiere, y el peso corporal degrada a solo repeticiones con el rango
  ampliado a 5–15—. `fijarProgresionEjercicio` toma `Value<T>` y no `T?` justamente porque aquí
  `null` significa algo y hay que distinguirlo de «no toques esa columna».

### Copia automática: la costura, el destino y el disparador

La fase 8a sube sola el mismo JSON que `copia.dart` ya exportaba. Está partida igual que los
módulos puros del proyecto, y por el mismo motivo: **lo que decide algo se prueba sin red**.

- `datos/copia_automatica.dart` es el **cuarto módulo puro** (ni Flutter, ni base, ni red):
  `toca()`, `sobrantes()` y `avisar()`. Recibe el estado y una fecha, y devuelve decisiones.
- `datos/nube/nube.dart` es la costura: `DestinoNube`, seis métodos. **El motor no importa el SDK
  de nadie**, y por eso `test/nube_falsa.dart` puede sustituirlo por un mapa en memoria.
- `datos/nube/drive.dart` es **el único fichero que sabe que Google existe**. Cambiar de proveedor
  es escribir otro como él.
- `estado/copia_automatica.dart` es el motor: los disparadores, la espera creciente y el estado.

Ocho cosas que conviene no volver a decidir:

- **No se puede usar `google_sign_in`.** Un cliente OAuth de Android va atado a la huella SHA-1 de
  firma, y aquí el APK de release se firma con la clave de depuración, que CI regenera en cada
  ejecución. Por eso el flujo es **PKCE + bucle local** (RFC 8252) contra un cliente de tipo
  *aplicación de escritorio*, que no depende de la firma y funciona igual en un fork.
- **El ámbito es `drive.file`.** La app solo ve lo que ella creó, así que la rotación **no puede**
  borrar un fichero del usuario. Y es un ámbito no sensible: sin verificación de Google. No lo
  subas a `drive`.
- **Sin `--dart-define GOOGLE_CLIENT_ID` la funcionalidad no existe**: `nubeProvider` da `null` y el
  grupo de Ajustes no se pinta. Es lo mismo que hace `VERSION` con «local». Los tests sobrescriben
  ese provider, que es como se prueba la pantalla.
- **El *refresh token* va al almacén seguro, nunca a la tabla `ajustes`**: esa tabla se exporta
  entera en la copia de seguridad.
- **Las cinco claves `copia_nube_*` no son preferencias**, son estado de este dispositivo. No las
  lee `Ajustes.desdeMapa` sino `EstadoCopiaAutomatica`, están en `Claves.locales`, y `copia.dart`
  las filtra **al exportar y al importar**. `borrarTodosLosDatos()` también las conserva: el botón
  dice «rutinas, sesiones y medidas» y desconectar la nube no es eso. **Si añades una clave que sea
  de dispositivo y no del usuario, va en `Claves.locales`.**
- **«Le toca» se decide por frontera natural** —día, lunes o mes—, no por horas transcurridas: con
  un «hace menos de 24 h», copiar a las 23:50 bloquearía la del día siguiente. Pasa por
  `datos/reloj.dart`, que es lo que permite fijar la fecha en los tests.
- **Nunca durante una sesión viva y nunca en la ruta de entrenar.** El borrador se reescribe cada
  2 s. Un fallo de la copia es un aviso —la línea de la cabecera de Rutinas—, jamás un error en
  medio de un entrenamiento.
- **`ErrorNube` distingue temporal de reconectar**, y eso es lo que decide si se reintenta.
  Reintentar un permiso revocado no lo arregla nunca y gasta batería y cuota.

`docs/privacidad.md` es requisito, no formalidad: la pantalla de consentimiento de Google pide una
URL, y «Acerca de» la enlaza. Si cambias qué datos salen del móvil, ese fichero cambia con ellos.

### Sincronización: identidad, versión y lápidas

La fase 8b fue **el motor y nada más**: sin pantalla, sin cuenta y sin red. Cada fila que se
sincroniza lleva su identidad y su versión, y todo borrado deja constancia. La **8c** es lo que la
convierte en una funcionalidad: el adaptador de Supabase, las cuentas y la pantalla.

- `datos/identidad.dart` da las dos marcas: `uuidV4()` (v4 escrito a mano, sin el paquete `uuid`) y
  `selloLocal()`, un contador **monótono** en milisegundos.
- `datos/sincro/transporte.dart` es la costura: `SincroTransporte`, ocho métodos, sin Flutter y sin
  drift. **El motor no importa el SDK de nadie**, y por eso `test/sincro_falso.dart` puede
  sustituirlo por un mapa en memoria con su propio reloj.
- `datos/sincro/motor.dart` es la reconciliación: bajar, aplicar, subir, confirmar.
- `datos/sincro/enlace.dart` es el primer enlace y sus cuatro casos.

Nueve cosas que conviene no volver a decidir:

- **El `uuid` es una identidad añadida, no un sustituto de la clave primaria.** Todas las consultas,
  los `family` de los providers y las rutas siguen trabajando con `int`; el `uuid` solo lo usa la
  capa de sincronización para traducir de identidad global a identidad local al entrar y al salir.
- **La regla del conflicto es una sola, y no compara relojes:** *al bajar, una fila remota se aplica
  salvo que la local esté pendiente de subir*. «Pendiente» es `actualizado > cursorSubida`. Lo
  pendiente gana y se sube justo después, así que el servidor acaba con ello. Comparar el sello de
  aquí con el del servidor sería comparar dos relojes distintos, y un móvil con la hora mal puesta
  ganaría todos los conflictos para siempre.
- **El sello lo pisa el servidor al aceptar la fila.** En local solo tiene que crecer, y por eso
  `selloLocal` es monótono y `AppBD` lo siembra al abrir con el mayor sello de la base: si no,
  reabrir con el reloj atrasado repetiría sellos ya usados y una fila cambiada aquí parecería
  subida.
- **Los borrados van a la tabla `lapidas`, no a una columna `borrado`.** Con la columna habría que
  filtrar las cincuenta consultas de `bd.dart` —y la que se olvidara enseñaría datos borrados—, el
  nombre de una rutina borrada seguiría ocupando su índice único y los `ON DELETE CASCADE` habría
  que reescribirlos a mano. Solo se entierra a los padres: el `CASCADE` hace el resto en los dos
  lados.
- **La sesión es la unidad, no la serie.** `serie` es la única tabla del usuario sin identidad ni
  versión: viaja dentro de su entrenamiento y se sustituye con él. Por eso **escribir una serie
  sella su entrenamiento**; si eso se rompe, dos móviles pueden acabar con una sesión mezclada, que
  es el peor resultado posible.
- **`medidas`, `favoritos` y `ajustes` se identifican por su clave natural** (`tipo|fecha`,
  `idCatalogo`, `clave`), que ya es la misma en los dos móviles. Darles un `uuid` haría que la misma
  medida llegara dos veces y chocara contra su índice único.
- **`actualizado` tiene `DEFAULT 0` en SQL y se sella a mano en cada escritura.** El cero no es un
  sello válido, es un olvido, y una fila sin sellar no se subiría nunca. `test/sincro_sellos_test.dart`
  recorre todas las escrituras públicas y lo comprueba: **si añades una escritura, añade su caso
  ahí**.
- **No hay tabla de cola de salida.** «Lo pendiente» se deduce del sello, igual que los récords se
  calculan en vez de guardarse. Una tabla menos y un modo de fallo menos.
- **Las claves de `Claves.locales` no viajan**, ni al subir ni al bajar: son de este móvil. Y
  `sincro_estado` no se exporta en la copia de seguridad, por lo mismo que no se exporta el token.

Lo que **sí** cambió de la copia de seguridad: `versionCopia` pasa a **4** y las rutinas, los
ejercicios y las sesiones exportan su `uuid`. Es lo que hace que restaurar en un móvil nuevo y
enlazarlo después funda el histórico en vez de duplicarlo. Si al restaurar ese `uuid` ya está en la
base, se genera otro: dos filas con la misma identidad no son dos filas.

### Sincronización: el servicio

La fase 8c es el adaptador, la cuenta y la pantalla. **No toca el esquema**: `schemaVersion` se
queda en 8 y `versionCopia` en 4. Lo único nuevo que había que persistir era el interruptor de este
dispositivo, y para eso ya estaba `Claves.locales`.

- `datos/sincro/supabase.dart` es **el único fichero que sabe que Supabase existe**, y
  `test/importaciones_test.dart` lo fija. Cambiar de proveedor es escribir otro como él.
- `estado/sincro.dart` es el motor: los disparadores, la espera creciente y la cuenta.
- `pantallas/cuenta.dart` es el grupo de Ajustes, la entrada y el primer enlace.
- `supabase/esquema.sql` es el servidor; `docs/sincronizacion.md`, cómo montarlo.

Diez cosas que conviene no volver a decidir:

- **Ningún SDK.** Supabase se habla REST con el `http` que ya estaba, y la fase **no añadió ni una
  dependencia**. `supabase_flutter` arrastraría realtime, storage y deep links para ocho llamadas
  HTTP, y pondría en riesgo el techo de `win32` que fija `file_picker`. Es el mismo razonamiento que
  ya está escrito en `drive.dart` para no usar el SDK de Google.
- **El reloj es del servidor y se siembra en milisegundos de época.** `selloLocal()` sella así, de
  modo que un servidor que empezara en cero dejaría el cursor de subida por debajo de todos los
  sellos locales y **cada pasada resubiría el histórico entero**. Está escrito en el SQL y hay que
  respetarlo en cualquier servidor que lo sustituya. Por lo mismo, `subir` **no** mira la hora de
  pared: si adelantara el reloj, el `cursorPrevio` no casaría nunca con el `cursorBajada` del
  cliente y cada móvil se descargaría su propio eco.
- **`appgym_bajar` lee el reloj antes que las filas y las acota con él.** Al revés, una subida que
  se colara en medio adelantaría el cursor por encima de filas no entregadas. Es la única forma de
  perder datos que hay en el servidor.
- **Se entra con un código de seis cifras, no con un enlace mágico.** Un enlace exige deep links,
  un *intent-filter* y un dominio, y aquí el APK se instala a mano. Requiere que la plantilla de
  correo del proveedor incluya `{{ .Token }}`: es el paso de montaje que más se olvida.
- **La sesión entera —id, correo y refresco— va al almacén seguro**, bajo `claveSincro`. El correo
  también, y no por la exportación: `sesionActual()` tiene que contestarse **sin red**, o un móvil
  sin cobertura diría «sin cuenta» y el usuario volvería a entrar, cayendo otra vez por el primer
  enlace.
- **GoTrue rota el *refresh token*.** Cada renovación invalida el anterior, así que hay que
  reescribir el almacén cada vez, y solo puede haber **una renovación en vuelo**: dos canjearían el
  mismo token y la segunda mataría la sesión. `drive.dart` no hace ninguna de las dos cosas porque
  Google no rota; copiarlo tal cual dejaría al usuario fuera a las pocas horas.
- **Dos mapeadores de error, no uno.** Un 400 en un RPC es un rechazo del servidor; en `/verify` es
  «te has equivocado de código», y esa frase la tiene que leer el usuario.
- **`DisparadorSincro` es otro enumerado a propósito**, no el `Disparador` de la copia automática:
  son dos costuras independientes y `raiz.dart` importa las dos.
- **La app se repinta por el contador `cambios` de `VistaSincro`**, que `raiz.dart` escucha para
  llamar a `invalidarTodo`. El motor tiene un `Ref` y no un `WidgetRef`, así que no puede invalidar
  por su cuenta. **Si añades un provider de datos, sigue yendo en `invalidarTodo`.**
- **Con la pregunta del primer enlace sin contestar no se sincroniza.** Una pasada normal aplicaría
  «fusionar» sin haberlo preguntado, y ese es el único punto del bloque donde K7 exige preguntar.

### Catálogo de ejercicios

1.324 ejercicios de [hasaneyldrm/exercises-dataset](https://github.com/hasaneyldrm/exercises-dataset).

- `assets/ejercicios.es.json` (~1 MB) se versiona y está declarado en `pubspec.yaml`. `semilla.dart`
  lo vuelca en la tabla del catálogo de forma idempotente (compara recuentos) y lo parsea en un
  isolate con `compute()`, para no congelar el primer frame.
- La columna `busqueda` es el índice: el nombre **más** las traducciones de **todos** los idiomas
  (`i18n_es.dart` e `i18n_en.dart`), normalizado sin acentos. Por eso «mancuerna pecho» y «dumbbell
  chest» devuelven lo mismo sea cual sea el idioma activo, y por eso **cambiar de idioma no toca la
  base**: un índice por idioma obligaría a reescribir 1.324 filas en cada toque del selector.
- **Al tocar las tablas de `i18n_*.dart` hay que subir `versionIndice`** (`semilla.dart`). El
  recuento de filas no cambia cuando lo que cambia es lo que se escribe en cada fila, así que sin
  ese segundo disparador el índice viejo se quedaría. Sube el entero y el catálogo se resiembra una
  vez en el siguiente arranque; la clave se guarda en `ajustes.version_indice`.
- Dart no trae normalización Unicode, así que `normalizar()` sustituye los caracteres acentuados en
  vez de descomponerlos en NFKD. Si añades vocabulario con diacríticos raros, amplía el mapa.
- Los nombres de ejercicio solo existen en inglés y se muestran tal cual; lo que se traduce son las
  categorías (`bodyPart`, `equipment`, `target`, músculos) y **las instrucciones**.
- Las instrucciones se guardan como un mapa por idioma en la columna `instrucciones`. Las españolas
  vienen del propio catálogo y las inglesas de `assets/instrucciones.en.json`, que genera
  `python3 tool/instrucciones_en.py` desde el dataset original. `pasosDe` elige el idioma al pintar
  y cae al español, y admite además la lista suelta de antes de la v2 del índice.
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

### Idioma: los textos fuera del código

La app está en **español e inglés**. Ninguna cadena visible vive en `lib/pantallas` ni en
`lib/tema`: todas están en `lib/l10n/app_es.arb` (la plantilla, con las descripciones) y
`app_en.arb`, y `flutter gen-l10n` genera de ahí la clase `Textos`.

- **Se escribe `context.t.loQueSea`**, con la extensión de `lib/l10n/textos.dart`. Ese fichero es
  el único punto de entrada: reexporta lo generado, que no se versiona. Nadie importa `generado/`.
- **`tema/ui.dart` no importa `Textos`.** Un componente compartido no sabe en qué idioma está la
  app: recibe el texto ya resuelto. Por eso `dialogoConfirmar`, `elegirEnHoja`, `selectorFecha`,
  `DeslizarParaBorrar`, `Sugerencia` y `BarraDescanso` piden sus etiquetas.
- **Un `enum` no lleva su etiqueta.** `Tema`, `Perfil`, `Metrica`, `Region`… se pintan desde un
  `switch` exhaustivo contra `Textos`, de modo que añadir un valor rompe la compilación justo donde
  falta la traducción. La clave del `enum` sí es estable cuando se persiste.
- **Convención de claves:** `ambitoConcepto` en `camelCase` y en español, con el ámbito por delante
  (`rutinasVacio`, `entrenarAnadirSerie`, `ajustesUnidad`); las compartidas van con `comun`.
- **Cada texto nuevo son dos ediciones**, una por idioma, y `test/traducciones_test.dart` no deja
  saltárselo: compara los dos conjuntos de claves y los parámetros de cada frase.
- **`Formato` (`datos/formato.dart`) es el idioma hecho objeto**: fechas con `DateFormat`, números
  con `NumberFormat`, pesos en la unidad activa y el vocabulario del catálogo. Se pide con
  `formatoDe(context, ref)` dentro de `build` y con `leerFormato(context, ref)` en un callback
  —`ref.watch` solo vale en `build`—. El idioma lo toma del **árbol de widgets**, no de la
  preferencia: es el que `CupertinoApp` resolvió de verdad.
- **La semana empieza en lunes en los dos idiomas**, a propósito: la racha y el reparto por semanas
  están definidos así, y seguir al idioma daría rachas distintas en dos móviles del mismo usuario.
  Ver la nota de `metricas.lunesDe`.
- **Lo que no se traduce:** `AppGym`, `kg`, `lb`, `s`, `min`, `RPE`, `RIR`, `1RM` y los nombres de
  ejercicio del catálogo, que solo existen en inglés.
- **Lo que nunca se traduce porque está persistido:** las claves de `tiposMedida` (`peso`,
  `grasa`…), las de `Claves`, los `bodyPart` de los filtros del catálogo y los nombres de los
  `enum` que se guardan. Están escritos en la base de todos los móviles y en todas las copias
  exportadas; hay un test de migración que lo fija.
- **Lo que el usuario ya creó no se renombra.** Una rutina creada desde una plantilla en inglés se
  llama `Push`; cambiar de idioma después **no** la toca: ya es su dato, con el nombre que él puede
  editar.

### Sistema de diseño

`tema/tokens.dart` (constantes) y `tema/ui.dart` (componentes).

Los colores son los **semánticos de Cupertino**, que en Flutter son `CupertinoDynamicColor` y **no
valen tal cual**: hay que resolverlos contra el contexto o no cambian entre claro y oscuro. Está
encapsulado en la extensión `Paleta`, así que en las pantallas se escribe `context.texto`,
`context.tarjeta`, `context.acento`. **No uses `CupertinoColors` directamente** y no metas hex
literales salvo en `coloresRutina`, que identifica rutinas y debe ser estable en ambos temas.

En `ui.dart` solo está lo que Flutter no trae. El inventario completo es `estilo`, `TituloGrande`,
`Grupo`, `Pildora`, `PuntoColor`, `Miniatura`, `BotonPrincipal`, `SelectorEnLinea`, `EstadoVacio`,
`Cargando`, `BarraProgreso`, `BarraDescanso`, `CheckSerie`, `DeslizarParaBorrar`, `Sugerencia`,
`barra`, `selectorFecha`, `elegirEnHoja`, `dialogoTexto`, `dialogoConfirmar` y `aviso`. Para lo demás usa el
widget del framework: `CupertinoListSection.insetGrouped` (envuelto en `ui.Grupo`),
`CupertinoListTile`, `CupertinoSearchTextField`, `CupertinoSlidingSegmentedControl`.

`elegirEnHoja<T>` devuelve `(T,)?`, un registro de un elemento, **no `T?`**: hace falta para
distinguir «cancelar» (`null`) de «elegir nada» (`(null,)`), que es un valor legítimo — el descanso
«como el global», el rango de progresión propio o el filtro «todos» del catálogo.

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

`pubspec.yaml` es la única fuente de dependencias; hoy son trece, y tres de ellas ya estaban en el
árbol: `intl` la arrastra `flutter_localizations`, y se declara —**sin fijar versión**— para poder
usar `DateFormat` y `NumberFormat` directamente; `crypto` la arrastra `http` y `url_launcher` la
arrastra `share_plus`, así que declararlas para la copia automática no añadió nada que descargar.
`share_plus` y `file_picker` son de la copia de seguridad: sin ellas la única salida sería escribir
en el directorio de documentos y cantar la ruta, que en Android no hay quien alcance.

**La restricción de `win32` manda sobre tres paquetes.** `file_picker` pide `win32 ^5`, así que
`share_plus` se queda en la 12 —la 13 exige `win32 ^6`— y `flutter_secure_storage` en la 9, por lo
mismo. Solo afecta al escritorio de Windows, que aquí no se compila, pero romper eso deja `pub get`
sin resolver. `flutter_secure_storage` es la **única** dependencia nueva de verdad de la fase 8a, y
está para el *refresh token*: la alternativa era la tabla `ajustes`, que se exporta.

**Ningún SDK de proveedor, de nadie.** Drive se habla por REST v3 y Supabase por PostgREST y
GoTrue, los dos con el `http` de siempre: la fase 8c **no añadió ni una dependencia**. Ver el
porqué en la
cabecera de `lib/datos/nube/drive.dart`.

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
