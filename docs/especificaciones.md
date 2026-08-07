# AppGym — Especificaciones de nuevas funcionalidades

> Documento de especificación funcional y técnica para la siguiente iteración de AppGym.
> Escrito sobre el código actual: **Flutter 3.44.8 / Dart 3.12.2**, `drift` sobre SQLite,
> `Riverpod` para el estado, interfaz **solo Cupertino**, catálogo de 1.324 ejercicios,
> nueve pantallas y 27 tests. Ver `CLAUDE.md` para la arquitectura vigente.

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
| **Interfaz** | Pantallas, widgets y navegación |
| **Datos** | Cambios en `lib/datos/bd.dart` y su migración |
| **API de datos** | Métodos nuevos o modificados en `AppBD`, y providers en `lib/estado/providers.dart` |
| **Criterios de aceptación** | Lista verificable; es lo que se prueba antes de dar por cerrado el punto |
| **Riesgos** | Lo que puede romperse |

**Convenciones transversales que aplican a todo el documento.** Salen de `CLAUDE.md` y no se
negocian punto por punto:

1. **Español** en código, comentarios, commits e interfaz.
2. **Solo Cupertino.** No se importa `material.dart` en ningún sitio. Lo que solo exista en Material
   se compone en `lib/tema/ui.dart`, como ya se hizo con `BarraProgreso`.
3. **Colores por la extensión `Paleta`**: `context.texto`, `context.tarjeta`, `context.acento`.
   Nada de `CupertinoColors` directo ni hex literales, salvo `coloresRutina` (`bd.dart:21`).
4. **Migraciones de drift.** Todo cambio de esquema sube `schemaVersion` (hoy en 1, `bd.dart:191`) y
   añade su paso en `MigrationStrategy`. Sin eso, las bases de datos ya instaladas se rompen.
5. **Estado: invalidar, no reconstruir.** Cada vista nueva declara su provider; tras una escritura
   se invalida lo afectado con los ayudantes de `providers.dart:117-138`, que hay que ampliar.
6. **Consultas preagregadas.** Al añadir una vista, se añade la consulta que le dé los datos ya
   resueltos. Nada de una consulta por fila pintada.
7. **Tests.** `flutter test` monta las pantallas de verdad contra `NativeDatabase.memory()`
   sobrescribiendo `bdProvider`. **Cada punto de este documento añade sus tests**; los 27 actuales
   son el suelo, no el techo.
8. **`flutter analyze` con 0 issues** es condición de entrega de cada punto.
9. **Unidades.** El peso se guarda **siempre en kilogramos**. La conversión a libras es solo de
   presentación (ver [B9](#b9-pantalla-de-ajustes)).
10. **Dependencias nuevas.** Cada una se justifica en el punto que la pide. Ninguna se añade «por si
    acaso»: hoy son seis y la app se sostiene con eso.

> **Nota sobre la versión anterior de este documento.** La primera redacción se hizo contra el
> código Flet/Python que vivía en `main` antes de incorporar la reescritura en Flutter. El análisis
> funcional se mantuvo íntegro —los seis problemas del modelo son los mismos—, pero todas las
> referencias técnicas se han rehecho. Tres conclusiones de entonces han quedado **anuladas** por la
> reescritura y se señalan donde corresponde: ya hay tests, ya hay CI y `PRAGMA foreign_keys` ya
> está activado.

---

## A. Limitaciones del modelo de datos

> **Bloque implementado.** A1–A6 están en el código desde la iteración de agosto de 2026, con sus
> migraciones (esquema v2 a v4) y sus tests. Lo que sigue se conserva como el porqué de cada
> decisión; donde la implementación se desvió, se dice en la sección [E](#e-modelo-de-datos-consolidado).

### A1. Series independientes por ejercicio

> **Es la especificación central de esta iteración.** C16, C17 y D dependen de ella, y B8 se
> beneficia directamente. Debe implementarse antes que ninguna otra del bloque A.

**Problema.**
La tabla `SeriesTabla` (`lib/datos/bd.dart:101`) guarda **una única fila agregada** por ejercicio y
sesión: `nSerie` es *el número de series*, no el índice de una serie. Se ve claramente en
`insertarEntrenamiento` (`bd.dart:461`), que recibe `Map<int, UltimaSerie>` — un solo valor por
ejercicio— y en la tarjeta de registro (`lib/pantallas/entrenar.dart:305-348`), con sus tres
selectores: series, repeticiones y peso.

Registrar 4 series obliga a que las cuatro compartan repeticiones y peso. En la práctica, un
entrenamiento real casi nunca es así: pirámides, drop sets, o simplemente que la última serie baja
de 50 a 45 kg. Hoy eso no se puede anotar, y el gráfico de `resultado_ejercicio.dart` mide un dato
que el usuario ha tenido que redondear a mano.

**Comportamiento.**

- Cada serie es una fila propia, con sus repeticiones y su peso.
- En la pantalla de registro, cada ejercicio muestra la lista de sus series, con:
  - añadir serie (copia los valores de la última, que es el gesto más frecuente),
  - eliminar serie (deslizando, con `ui.DeslizarParaBorrar`, coherente con el resto de la app),
  - editar repeticiones y peso de cada una de forma independiente.
- Al abrir el registro, las series se precargan con **las de la última sesión de ese ejercicio**
  (número de series incluido), no con un valor agregado.
- Una serie puede marcarse como **serie de calentamiento**: se guarda, pero queda excluida de todas
  las métricas de volumen, récords y 1RM.

**Interfaz.**

Se rehace `_Tarjeta` (`lib/pantallas/entrenar.dart:207`). Cada tarjeta pasa de tres
`ui.SelectorNumerico` a una tabla compacta:

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

- La fila de serie necesita un `ui.SelectorEnLinea` nuevo: el `SelectorNumerico` actual
  (`lib/tema/ui.dart:222`) ocupa una fila entera con su etiqueta a la izquierda. El nuevo va en
  horizontal y sin etiqueta, para que repeticiones y peso quepan en la misma línea. Ambos comparten
  la lógica de incremento, límites y formato decimal.
- El `CupertinoSwitch` de «incluir ejercicio» (`entrenar.dart:289`) desaparece: un ejercicio
  **sin series** simplemente no se guarda. Eso elimina el mapa `_incluidos` (`entrenar.dart:39`) y
  su propagación por toda la pantalla.
- La serie de calentamiento se pinta con el número en `context.textoTer` y un icono de llama.
- **Cuidado con el `overflow`**: cuatro controles en una fila es justo el caso que ya provocó un
  `RenderFlex overflowed` en los tests de widget. La fila debe ser flexible y llevar su test.

**Datos.**

```dart
@DataClassName('Serie')
class SeriesTabla extends Table {
  @override
  String get tableName => 'serie';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get idEntrenamiento =>
      integer().references(Entrenamientos, #id, onDelete: KeyAction.cascade)();
  IntColumn get idEjercicio =>
      integer().references(Ejercicios, #id, onDelete: KeyAction.cascade)();

  /// AHORA: índice de la serie (1..N) dentro del ejercicio, no el recuento.
  IntColumn get nSerie => integer()();
  IntColumn get repeticiones => integer()();
  RealColumn get peso => real()();
  BoolColumn get calentamiento => boolean().withDefault(const Constant(false))();
  // rpe y nota se añaden en A5
}
```

Se conserva el nombre `nSerie` para no tocar el resto de consultas, **pero cambia su semántica**.
El comentario del modelo debe dejarlo explícito: es exactamente el tipo de cambio que confunde seis
meses después.

También se retira la clase `UltimaSerie` (`bd.dart:165`) como tipo de entrada de
`insertarEntrenamiento`: pasa a ser una lista de series y conviene renombrarla a `ValoresSerie`
para que el nombre no siga sugiriendo «lo último registrado».

**Migración (`schemaVersion` 1 → 2), no repetible:**

```dart
onUpgrade: stepByStep(
  from1To2: (m, schema) async {
    await m.addColumn(schema.serie, schema.serie.calentamiento);
    // Expandir cada fila agregada en N filas, una por serie.
    await customStatement('''
      INSERT INTO serie (id_entrenamiento, id_ejercicio, n_serie, repeticiones, peso, calentamiento)
      SELECT ...
    ''');
  },
),
```

1. Para cada fila existente con `nSerie = N`, crear `N` filas con `nSerie = 1..N` y las mismas
   `repeticiones` y `peso`.
2. `calentamiento = false` en todas.
3. Todo en una transacción: drift ya envuelve `onUpgrade`, pero conviene verificarlo con un test.
4. **Antes** de migrar se copia el fichero de base de datos a `appgym.bak-v1.sqlite` en el mismo
   directorio que devuelve `path_provider`.

El histórico migrado es **fiel**: 4 series de 10×60 kg se convierten en 4 filas de 10×60 kg, que es
justo lo que el usuario quiso decir.

> drift permite generar el esquema de cada versión (`drift_dev schema dump` / `make-migrations`) y
> escribir tests que migran una base real de la v1 a la v2. Esta migración es la que justifica
> montar ese flujo; una vez montado, sirve para todas las demás.

**API de datos.**

| Método de `AppBD` | Cambio |
|---|---|
| `insertarEntrenamiento(idRutina, fecha, series)` | `series` pasa de `Map<int, UltimaSerie>` a `Map<int, List<ValoresSerie>>` |
| `ultimaSerieEjercicio(idEjercicio)` | Devuelve `List<ValoresSerie>` con todas las series de la última sesión |
| `seriesConFecha(idRutina, idEjercicio)` | Devuelve una entrada por serie; quien necesite agregado lo calcula |
| `resumenSesionesEjercicio(idRutina, idEjercicio)` | **Nuevo.** Agrega por sesión: fecha, series efectivas, volumen, peso máximo y mejor 1RM estimado |

Providers afectados: `ultimaSerieProvider` (`providers.dart:84`) cambia de tipo, y
`seriesConFechaProvider` (`providers.dart:103`) mantiene firma pero cambia el contenido.
`resultado_ejercicio.dart` pasa a consumir un `resumenSesionesEjercicioProvider` nuevo: si siguiera
con `seriesConFecha`, el gráfico pintaría una barra por **serie** en vez de por sesión, que es una
regresión visible.

**Criterios de aceptación.**

- [ ] Una base de datos de la v1 se abre sin pérdida: mismo número de rutinas, mismos ejercicios y
      el mismo volumen total antes y después. **Test de migración con base real.**
- [ ] Se puede registrar una sesión con series de distinto peso y se muestra en el histórico.
- [ ] Al abrir el registro de una rutina ya entrenada, se precargan tantas filas como series tuvo
      la última sesión, con sus valores.
- [ ] Las series de calentamiento no aparecen en volumen, máximos ni 1RM.
- [ ] Existe la copia `appgym.bak-v1.sqlite` tras la primera migración.
- [ ] Test de widget de la tarjeta de registro con 6 series, sin `RenderFlex overflowed`.

**Riesgos.** Es la única migración destructiva del documento. Es también la primera migración real
del proyecto (`schemaVersion` lleva en 1 desde el principio), así que el mecanismo entero se estrena
aquí. Conviene estrenarlo con red: tests de migración antes que código de pantalla.

---

### A2. Editar y borrar entrenamientos

**Problema.**
`AppBD` tiene `insertarEntrenamiento` y varias consultas, pero **ningún método de actualización ni
de borrado de entrenamientos** (`bd.dart:456-578`). Una sesión guardada por error se queda para
siempre: contamina el gráfico, el calendario y —tras C16/C17— las estadísticas. Además no hay
ninguna pantalla desde la que listar las sesiones pasadas de una rutina.

**Comportamiento.**

- Desde el detalle de una rutina se accede a **Historial de sesiones**: los entrenamientos de esa
  rutina, más recientes primero, con fecha, número de ejercicios y volumen total.
- Al pulsar una sesión se abre su detalle: los ejercicios con sus series, en solo lectura.
- Desde el detalle: **Editar** (reabre el registro con los datos cargados) y **Eliminar** (con
  `ui.dialogoConfirmar`, en estilo destructivo).
- También se puede eliminar deslizando la fila en el historial, con `ui.DeslizarParaBorrar`.

**Interfaz.**

- Nueva pantalla `lib/pantallas/historial.dart`, con su `abrirHistorial(context, idRutina)`.
- Nueva pantalla `lib/pantallas/sesion.dart`, con su `abrirSesion(context, idEntrenamiento)`.
- En `lib/pantallas/rutina.dart`, el bloque «Sesiones» de la cabecera de estadísticas pasa a ser
  pulsable y lleva al historial.
- `PantallaEntrenar` (`entrenar.dart:25`) gana un parámetro opcional `idEntrenamiento`. Si viene
  informado: título «Editar entrenamiento», las series se cargan de esa sesión y al guardar se
  actualiza en vez de insertar.

**Datos.** Sin cambios de esquema.

> **Anulado respecto a la versión Flet del documento:** allí se advertía de que `PRAGMA
> foreign_keys` no estaba activado y los `ON DELETE CASCADE` no se aplicaban. En Flutter **ya se
> activa** en `beforeOpen` (`bd.dart:199`), y hay un test que lo comprueba. No hay nada que hacer
> aquí.

**API de datos.**

```dart
/// Una sesión con todo lo necesario para pintarla o reeditarla.
Future<SesionCompleta?> sesion(int idEntrenamiento);

/// Reemplaza en bloque las series de una sesión, en una transacción.
Future<bool> actualizarEntrenamiento(
  int idEntrenamiento,
  DateTime fecha,
  Map<int, List<ValoresSerie>> series,
);

Future<void> borrarEntrenamiento(int idEntrenamiento);

/// [{id, fecha, nEjercicios, nSeries, volumen}], más recientes primero.
Future<List<ResumenSesion>> historialRutina(int idRutina, {int limite = 50, int desplazamiento = 0});
```

`actualizarEntrenamiento` borra las series de la sesión y las reinserta; no intenta hacer *diff*,
que para este tamaño de datos no aporta nada y sí complica el código.

Providers nuevos: `sesionProvider`, `historialRutinaProvider`. `invalidarEntrenamientos`
(`providers.dart:132`) debe invalidarlos también — es el punto donde es fácil olvidarse y dejar una
pantalla mostrando datos viejos.

**Criterios de aceptación.**

- [ ] Se puede corregir el peso de una serie de una sesión de hace un mes y el gráfico lo refleja
      al volver, sin reiniciar la app.
- [ ] Al eliminar un entrenamiento desaparece del calendario, del historial y de las estadísticas
      de la rutina, y sus series se borran (test de conteo sobre la tabla `serie`).
- [ ] Editar una sesión **no** cambia su fecha salvo que se cambie explícitamente (A3).
- [ ] Eliminar pide confirmación y avisa de que no se puede deshacer.
- [ ] Test de widget: editar desde el historial y comprobar que la lista se repinta.

---

### A3. Registrar un entrenamiento en otra fecha

**Problema.**
`_guardar()` fija `DateTime.now()` (`lib/pantallas/entrenar.dart:83`), y la cabecera pinta
`formato.fechaLarga(DateTime.now())` (`entrenar.dart:160`). No se puede anotar el entrenamiento de
ayer, que es exactamente lo que pasa cuando uno se acuerda de la app al día siguiente.

**Comportamiento.**

- La fecha de la cabecera es pulsable. Por defecto, hoy.
- No se permiten fechas futuras.
- Al editar una sesión existente (A2), el selector arranca en su fecha original.
- Si se elige un día pasado se guarda a las 12:00 de ese día, para que el orden dentro del día sea
  estable y no dependa de la hora a la que se anotó.

**Interfaz.**
`CupertinoDatePicker` en modo `date` dentro de un `showCupertinoModalPopup`, con `maximumDate` en
hoy. Es Cupertino nativo, no hace falta dependencia ni componente propio. La localización en español
ya está resuelta por `flutter_localizations` en `main.dart`.

**Datos.** Sin cambios de esquema.

**API de datos.** `insertarEntrenamiento` ya recibe `fecha` (`bd.dart:463`); basta con dejar de
pasarle `DateTime.now()` fijo.

**Criterios de aceptación.**

- [ ] Se puede guardar un entrenamiento con fecha de ayer y aparece en el día correcto del
      calendario.
- [ ] No se puede seleccionar una fecha futura.
- [ ] La fecha elegida se muestra con `formato.fechaLarga` en la cabecera antes de guardar.
- [ ] Test de widget: elegir fecha y verificar la fila insertada.

---

### A4. Ordenar ejercicios dentro de la rutina

**Problema.**
`ejerciciosDeRutina` ordena por `e.id` (`bd.dart:359`), es decir, por orden de inserción. No hay
forma de reordenar: si añades el press de banca después de las aperturas, se queda debajo para
siempre. En una rutina el orden **es** la rutina.

**Comportamiento.**

- Modo «Editar» en el detalle de la rutina que permite reordenar los ejercicios arrastrando.
- El orden se respeta en el detalle de la rutina, en el registro de entrenamiento y en el detalle
  de sesión.
- Los ejercicios existentes conservan su orden actual (el de inserción) tras la migración.
- Extra del mismo punto: **mover un ejercicio a otra rutina**, conservando su histórico de series.

**Interfaz.**

- Botón «Editar» en la `navigationBar` de `lib/pantallas/rutina.dart`. Al activarlo aparecen las
  asas de arrastre y desaparece el chevron.
- **`ReorderableListView` es de Material y no se puede usar aquí.** El equivalente en
  `package:flutter/widgets.dart` sí es válido: **`ReorderableList` / `SliverReorderableList`** con
  `ReorderableDragStartListener`. Da el arrastre completo sin romper la regla de no importar
  `material.dart`, y encaja con la lista de la pantalla.

**Datos.**

```dart
class Ejercicios extends Table {
  ...
  IntColumn get orden => integer().withDefault(const Constant(0))();
}
```

**Migración (`schemaVersion` → +1):** añadir la columna y, por cada rutina, asignar
`orden = 0,1,2…` siguiendo el `id` actual, con una sentencia por rutina o un `UPDATE` con
`ROW_NUMBER()`.

**API de datos.**

```dart
Future<void> reordenarEjercicios(int idRutina, List<int> idsEnOrden);
Future<bool> moverEjercicio(int idEjercicio, int idRutinaDestino);
```

`ejerciciosDeRutina` ordena por `orden` y luego por `id` (desempate defensivo). `insertarEjercicio`
(`bd.dart:305`) asigna `orden = max(orden) + 1` de la rutina.

**Criterios de aceptación.**

- [ ] Reordenar en la rutina cambia el orden en la pantalla de registro.
- [ ] El orden persiste tras cerrar y abrir la app.
- [ ] Mover un ejercicio a otra rutina conserva sus series.
- [ ] Una base de datos previa abre con los ejercicios en el mismo orden que tenía.

**Riesgos.** `moverEjercicio` puede crear un duplicado si ese ejercicio de catálogo ya está en la
rutina de destino; hay que comprobarlo y avisar, reutilizando la regla de `insertarEjercicio`
(`bd.dart:301-319`), que además ya tiene test.

---

### A5. Notas y RPE

**Problema.**
No hay ningún campo libre en toda la app. «Hoy me dolía el hombro», «con cinturón», «fallo en la
última» no se pueden anotar, y son justo la información que explica un bajón en el gráfico tres
semanas después.

**Comportamiento.**

- **Nota de sesión:** campo de texto libre al final del registro.
- **Nota de serie:** opcional, en el menú de cada serie, para una frase corta.
- **RPE / RIR por serie:** valor opcional de 6 a 10 en medios puntos (RPE) o de 0 a 4 (RIR). La
  escala se elige en Ajustes ([B9](#b9-pantalla-de-ajustes)); el valor se guarda **siempre
  normalizado como RPE** y se convierte al mostrar (`RIR = 10 − RPE`).
- Son opcionales: si el usuario nunca los usa, no debe verlos estorbando. El campo RPE solo aparece
  si está activado en Ajustes (por defecto, **desactivado**).

**Interfaz.**

- La nota de sesión va en un `ui.Grupo` con cabecera «Notas», con un `CupertinoTextField` multilínea.
- El RPE es un `CupertinoSlidingSegmentedControl` compacto en la fila de la serie, visible solo con
  la opción activada.
- Las sesiones con nota muestran un icono de globo en el historial (A2) y en el detalle del día (C19).

**Datos.**

```dart
class Entrenamientos extends Table {
  ...
  TextColumn get nota => text().nullable()();
}

class SeriesTabla extends Table {
  ...
  RealColumn get rpe => real().nullable()();   // 6.0–10.0, siempre en escala RPE
  TextColumn get nota => text().nullable()();
}
```

**Migración:** solo columnas nuevas (`m.addColumn`), sin transformación de datos.

**API de datos.** `insertarEntrenamiento` y `actualizarEntrenamiento` aceptan `nota` y propagan
`rpe`/`nota` por serie.

**Criterios de aceptación.**

- [ ] Se puede guardar una nota de sesión y se ve al abrirla.
- [ ] Con el RPE desactivado en Ajustes, la interfaz del registro es idéntica a no tenerlo.
- [ ] Cambiar de RPE a RIR reinterpreta los valores guardados sin migrarlos.

---

### A6. Varias rutinas el mismo día

**Problema.**
`entrenamientosPorDia()` devuelve `Map<DateTime, int>` (`bd.dart:570`). Si se entrenan dos rutinas
el mismo día, **la segunda sobrescribe a la primera** y el calendario solo pinta una. El propio
comentario del método lo reconoce (`bd.dart:566-569`). Además carga en memoria todos los
entrenamientos de la historia para pintar un solo mes, y `entrenamientosPorDiaProvider`
(`providers.dart:110`) no recibe parámetros, así que no puede acotarse.

**Comportamiento.**

- Un día puede contener varias sesiones, de la misma rutina o de rutinas distintas.
- El calendario refleja visualmente que hubo más de una.
- El detalle del día (C19) las lista todas.

**Interfaz.**

- Celda con **una** sesión: círculo relleno del color de la rutina (comportamiento actual).
- Celda con **dos o más**: círculo partido en sectores, uno por rutina distinta. En Flutter es un
  `CustomPainter` de cuatro líneas con `Canvas.drawArc`; a partir de cuatro rutinas se pintan tres
  sectores y un punto de «hay más».
- La leyenda del mes ya agrupa por rutina y solo necesita adaptarse a la nueva firma.

**Datos.** Sin cambios de esquema.

**API de datos.**

```dart
/// Sesiones de cada día dentro del rango pedido.
Future<Map<DateTime, List<SesionDelDia>>> entrenamientosPorDia({
  required DateTime desde,
  required DateTime hasta,
});
```

Sustituye a la actual. **Recibe rango**, de modo que el calendario consulta solo el mes visible.
`entrenamientosPorDiaProvider` pasa a ser un `FutureProvider.family` con el mes como parámetro,
igual que ya hace `seriesConFechaProvider` con su `ClaveSeries` (`providers.dart:101`).

**Criterios de aceptación.**

- [ ] Dos entrenamientos de rutinas distintas el mismo día pintan la celda partida.
- [ ] Dos de la **misma** rutina el mismo día pintan la celda de un solo color.
- [ ] Pintar un mes no consulta entrenamientos de otros meses.
- [ ] Test de datos que cubra los tres casos.

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
  - barra fija en la parte inferior de la pantalla de entrenamiento, con el tiempo restante en
    grande, apoyada en el `ui.BarraProgreso` que ya existe (`lib/tema/ui.dart:391`);
  - botones **+15 s**, **−15 s** y **Saltar**;
  - la app sigue navegable: se puede consultar la ficha de un ejercicio sin perder la cuenta.
- Al llegar a cero: aviso sonoro (si está activado), vibración y el contador pasa a contar **hacia
  arriba** en gris, para que se vea cuánto se ha excedido.
- Sobrevive a la navegación dentro de la app, pero **no** a cerrarla.

**Interfaz.**

- Nuevo componente `ui.BarraDescanso` en `lib/tema/ui.dart`.
- El reloj es un `Timer.periodic` de `dart:async` dentro de un `Notifier` de Riverpod, no estado de
  widget: así el descanso sobrevive a navegar a otra pantalla. `ref.onDispose` cancela el `Timer`.
- El tiempo restante se calcula como `fin.difference(DateTime.now())`, **no** acumulando ticks, para
  que no se desfase si el sistema suspende la app.
- **Sin dependencias nuevas para el aviso:** `SystemSound.play(SystemSoundType.alert)` y
  `HapticFeedback.heavyImpact()`, ambos en `package:flutter/services.dart`. Un sonido propio
  exigiría `audioplayers` y no compensa para un pitido.

**Datos.**

```dart
class Ejercicios extends Table {
  ...
  IntColumn get descansoSeg => integer().nullable()();   // null = usar el valor global
}
```

**Criterios de aceptación.**

- [ ] La cuenta atrás es exacta a ±1 s tras 3 minutos, incluso navegando entre pantallas.
- [ ] +15 s y −15 s ajustan sin reiniciar.
- [ ] Salir del entrenamiento cancela el `Timer` (test con `tester.pump` sobre el notifier).
- [ ] Con el sonido desactivado en Ajustes no suena, pero sí vibra.

**Riesgos.** Un `Timer.periodic` sin cancelar es una fuga clásica y en los tests de widget se
manifiesta como *«A Timer is still pending even after the widget tree was disposed»*. La
cancelación debe estar cubierta por un test, no por inspección.

---

### B8. Entrenamiento en curso (sesión viva)

**Problema.**
`PantallaEntrenar` es hoy un **formulario**: se rellena entero y se guarda al final
(`entrenar.dart:68-93`). Eso no encaja con cómo se usa una app en el gimnasio, donde se va anotando
serie a serie durante una hora. Y si la app se cierra a media sesión, se pierde todo: el estado vive
en `_valores` e `_incluidos`, que son campos del `State` (`entrenar.dart:36-42`).

**Comportamiento.**

- Se empieza el entrenamiento y la sesión queda **en curso**: cronómetro de duración total y cada
  serie se marca conforme se completa.
- Cabecera con progreso: `«8 / 20 series · 34:12»`.
- Al completar una serie se dispara el descanso ([B7](#b7-temporizador-de-descanso)).
- **Recuperación:** si la app se cierra con una sesión en curso, al reabrirla ofrece «Tienes un
  entrenamiento de *Empuje* empezado hace 12 minutos» → *Continuar* / *Descartar*.
- Al terminar se guarda con su duración y se muestra un **resumen de cierre**: volumen total, series
  completadas, duración, récords batidos ([C16](#c16-1rm-estimado)) y músculos trabajados
  ([D](#d-mapa-muscular-interactivo)).
- El modo formulario **se mantiene**: registrar una sesión pasada (A3) no puede exigir un
  cronómetro. La diferencia está en el punto de entrada: «Empezar entrenamiento» abre la sesión
  viva; «Registrar sesión anterior» abre el formulario.

**Interfaz.**

- `PantallaEntrenar` gana un parámetro `modo` (`Modo.vivo` | `Modo.formulario`).
- En modo vivo, cada fila de serie lleva un check circular; al marcarlo, la fila se atenúa y colapsa.
- Botón inferior fijo: «Terminar entrenamiento».
- Nueva pantalla `lib/pantallas/resumen_sesion.dart` para el cierre.
- El aviso de recuperación es un `ui.dialogoConfirmar` lanzado tras `arranqueProvider`
  (`providers.dart:30`), que ya es el punto donde la app espera antes de mostrar contenido.

**Datos.**

```dart
class Entrenamientos extends Table {
  ...
  IntColumn get duracionSeg => integer().nullable()();
}

/// Borrador de la sesión en curso. Tabla de una sola fila.
@DataClassName('SesionActiva')
class SesionesActivas extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get idRutina =>
      integer().references(Rutinas, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get inicio => dateTime()();
  DateTimeColumn get actualizado => dateTime()();

  /// JSON con las series y su estado.
  TextColumn get estado => text()();
}
```

El borrador se guarda como JSON, no normalizado: es un dato efímero, se reescribe entero en cada
cambio y no se consulta por partes. Se escribe con *debounce* de 2 s para no tocar disco en cada
pulsación de un selector.

**API de datos.**

```dart
Future<void> guardarSesionActiva(int idRutina, DateTime inicio, String estadoJson);
Future<SesionActiva?> sesionActiva();
Future<void> descartarSesionActiva();
```

Al confirmar el entrenamiento, la inserción y el descarte del borrador van en la **misma
`transaction()`**: si no, existiría un instante con la sesión guardada y el borrador vivo, que al
reabrir la app aparecería como un falso «tienes una sesión en curso».

**Criterios de aceptación.**

- [ ] Matar el proceso a mitad de sesión y reabrir recupera todas las series ya marcadas.
- [ ] Descartar el borrador no deja rastro y no vuelve a preguntar.
- [ ] La duración guardada coincide con el tiempo real transcurrido (±5 s).
- [ ] El modo formulario sigue funcionando igual que antes para sesiones pasadas.

---

### B9. Pantalla de Ajustes

**Problema.**
No existe ninguna pantalla de configuración. Hay valores razonables pero **fijos en el código**: el
paso del peso está clavado a 2,5 (`entrenar.dart:338`), los valores por defecto son `4×10×20 kg`
(`entrenar.dart:15`) y la unidad es siempre el kilogramo, escrita a mano como literal `'kg'` en
varias pantallas. Además, B7, A5, C17 y D necesitan un sitio donde configurarse.

**Comportamiento.**

| Sección | Ajuste | Valores | Por defecto |
|---|---|---|---|
| **Unidades** | Unidad de peso | kg / lb | kg |
| | Paso del peso | 0,5 / 1 / 1,25 / 2,5 / 5 | 2,5 |
| **Entrenamiento** | Descanso por defecto | 30 s – 5 min | 90 s |
| | Sonido al terminar el descanso | sí / no | sí |
| | Series por defecto | 1–10 | 4 |
| | Repeticiones por defecto | 1–30 | 10 |
| | Registrar RPE / RIR | no / RPE / RIR | no |
| **Objetivos** | Sesiones por semana | 1–7 | 3 |
| **Apariencia** | Tema | Sistema / Claro / Oscuro | Sistema |
| **Datos** | Exportar copia de seguridad | acción | — |
| | Importar copia de seguridad | acción | — |
| | Descargar media | acción + estado | — |
| | Borrar todos los datos | acción destructiva, doble confirmación | — |
| **Acerca de** | Versión, catálogo, atribución de Gym visual, licencias | informativo | — |

**Conversión de unidades.** Se guarda siempre en kg. En libras se muestra `kg × 2,20462` redondeado
al paso, y al introducir se convierte de vuelta. Un valor introducido en libras y releído puede
variar en el último decimal; se asume, porque la alternativa —guardar en la unidad activa— dejaría
el histórico en un limbo si el usuario cambia de unidad a mitad de camino.

**Tema.** `main.dart` fija hoy el `CupertinoApp`. Para que el ajuste funcione, el `brightness` debe
pasar a leerse de un provider en vez de heredarse del sistema sin más. Es un cambio pequeño pero
toca la raíz del árbol, y conviene hacerlo con cuidado: la extensión `Paleta` resuelve los colores
contra el `context`, así que un tema forzado mal propagado se nota en toda la app.

**Interfaz.**

- Nueva pantalla `lib/pantallas/ajustes.dart`.
- Acceso: icono de engranaje en la barra de la pestaña **Rutinas**, a la izquierda del `+`.
  Se descarta una cuarta pestaña: tres es el equilibrio actual del `CupertinoTabScaffold`
  (`lib/pantallas/raiz.dart`) y ajustes no es una zona de uso frecuente.
- Todo con `ui.Grupo` + `CupertinoListTile`; interruptores con `CupertinoSwitch`; selecciones con
  `CupertinoSlidingSegmentedControl` o una subpantalla de lista con marca de verificación para las
  de más de tres opciones.

**Datos.**

```dart
@DataClassName('Ajuste')
class Ajustes extends Table {
  TextColumn get clave => text()();
  TextColumn get valor => text()();   // serializado como texto, se castea al leer

  @override
  Set<Column> get primaryKey => {clave};
}
```

Se guarda en drift y no en `shared_preferences` por dos razones: evita una dependencia nueva y hace
que los ajustes entren gratis en la copia de seguridad ([B10](#b10-copia-de-seguridad-exportar-e-importar)).

Se acompaña de `lib/datos/ajustes.dart` con los valores por defecto y el tipado, expuesto como un
`ajustesProvider` que carga todo en memoria una vez: se leen en casi cada pantalla y no puede haber
una consulta por lectura.

**Criterios de aceptación.**

- [ ] Cambiar el paso del peso a 1 kg se refleja en los selectores del entrenamiento.
- [ ] Cambiar a libras muestra todos los pesos convertidos: registro, histórico, gráficos y récords.
- [ ] Cambiar a libras y volver a kg deja los valores originales intactos en la base de datos.
- [ ] Forzar tema oscuro con el sistema en claro tiñe toda la app, incluidos los diálogos.
- [ ] «Borrar todos los datos» pide confirmar dos veces y **no** borra el catálogo (se resiembra).
- [ ] Los ajustes persisten entre arranques.

---

### B10. Copia de seguridad: exportar e importar

**Problema.**
La base de datos vive en el directorio de `path_provider` y no hay ninguna vía de respaldo dentro de
la app. Todo el histórico está en un único fichero local sin copia; en Android, además, desinstalar
la app lo borra. Es el riesgo más serio del proyecto tal y como está hoy, y crece con cada mes de uso.

**Comportamiento.**

- **Exportar:** genera un `.json` con todos los datos del usuario y lo comparte o guarda. Nombre
  sugerido: `appgym-copia-2026-08-06.json`.
- **Importar:** lee un archivo de copia y ofrece dos modos:
  - **Reemplazar** — borra los datos actuales y restaura (con doble confirmación);
  - **Fusionar** — añade las rutinas que no existan; ante un nombre repetido, importa como
    «Empuje (importada)». No intenta fusionar sesiones dentro de una misma rutina: no hay forma
    fiable de detectar duplicados y el resultado sería peor que el problema.
- **Exportar CSV** (secundario): una fila por serie, para analizar en una hoja de cálculo. Columnas:
  `fecha, rutina, ejercicio, serie, repeticiones, peso_kg, rpe, calentamiento`.

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
        {"nombre": "Barbell Bench Press", "idCatalogo": "0025",
         "descripcion": null, "orden": 0, "descansoSeg": null}
      ],
      "entrenamientos": [
        {"fecha": "2026-08-01T12:00:00", "duracionSeg": 3600, "nota": null,
         "series": [
           {"ejercicio": "Barbell Bench Press", "nSerie": 1,
            "repeticiones": 10, "peso": 60.0, "rpe": null, "calentamiento": false}
         ]}
      ]
    }
  ],
  "medidas": [{"fecha": "2026-08-01", "tipo": "peso", "valor": 78.4}]
}
```

Decisiones del formato:

- **No se exporta el catálogo**: son 1.324 filas regenerables desde `assets/ejercicios.es.json`, que
  sí se versiona. Los ejercicios se referencian por `idCatalogo`; si al importar ese id no existe,
  el ejercicio se importa como personalizado conservando el nombre, y se informa al final.
- **No se exportan los ids internos**: la referencia entre series y ejercicios es por **nombre**
  dentro de la rutina, que es único por la regla de `insertarEjercicio` (`bd.dart:301`). Así una
  copia es reimportable en cualquier instalación.
- `version` permite migrar copias antiguas en el futuro.

**Interfaz.**
Requiere **una dependencia nueva**: `share_plus` para exportar (el flujo natural en móvil es
«compartir a Drive / correo») y `file_picker` para importar. Alternativa sin dependencias si se
prefiere no añadirlas: escribir en el directorio de documentos y mostrar la ruta exacta, lo que en
Android es incómodo de alcanzar. **Recomendado añadirlas**: una copia de seguridad que el usuario no
sabe dónde está no es una copia de seguridad.

**API de datos.** Módulo nuevo `lib/datos/respaldo.dart`:

```dart
Future<Map<String, dynamic>> exportar(AppBD bd);
Future<String> exportarCsv(AppBD bd);
Future<InformeImportacion> importar(AppBD bd, Map<String, dynamic> datos, {ModoImportacion modo});
List<String> validar(Map<String, dynamic> datos);   // errores legibles
```

`importar` valida **antes** de tocar nada y trabaja en una sola `transaction()`.

**Criterios de aceptación.**

- [ ] Exportar, borrar todos los datos e importar deja la app exactamente igual que antes.
- [ ] Importar un archivo corrupto o de otra aplicación no modifica nada y muestra un error claro.
- [ ] Fusionar dos veces la misma copia no duplica rutinas silenciosamente.
- [ ] El CSV abre bien en una hoja de cálculo (separador de coma, UTF-8 con BOM).
- [ ] Test de ida y vuelta: base de ejemplo → exportar → importar en base vacía → comparar.

---

### B11. Duplicar rutina y plantillas

**Problema.**
Crear una rutina hoy es: crearla vacía, entrar al catálogo, buscar y añadir ejercicios uno a uno.
Para una rutina de 8 ejercicios son 8 búsquedas. Y variantes como «Empuje A / Empuje B», que
comparten el 80 % de los ejercicios, se construyen dos veces desde cero.

**Comportamiento.**

- **Duplicar rutina:** desde el menú de la rutina. Copia nombre («Empuje (copia)»), ejercicios y su
  orden. **No** copia el histórico: la nueva rutina empieza sin sesiones.
- **Plantillas:** al crear una rutina, además de «En blanco», se ofrecen predefinidas: Full body
  (3 días), Torso/Pierna, Push/Pull/Legs, Solo peso corporal, Principiante (máquinas). Cada una
  muestra su lista de ejercicios antes de crearla y es editable después.

**Datos.**
Fichero nuevo `assets/plantillas.json`, declarado en `pubspec.yaml` junto al catálogo. Sin cambios
de esquema:

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

**Debe haber un test que valide que todos los ids de las plantillas existen en el catálogo.** Si
mañana se actualiza el dataset y un id desaparece, el test falla en vez de crearse una rutina con
un hueco silencioso.

**API de datos.**

```dart
Future<int?> duplicarRutina(int idRutina, {String? nuevoNombre});
Future<List<int>> crearRutinasDesdePlantilla(Plantilla plantilla);
```

**Criterios de aceptación.**

- [ ] Duplicar una rutina de 8 ejercicios crea otra con los mismos 8 en el mismo orden y 0 sesiones.
- [ ] Crear desde plantilla genera rutinas con los ejercicios vinculados al catálogo (con imagen y
      ficha, no como personalizados).
- [ ] Una plantilla con un id inexistente hace fallar el test, no la app.

---

### B12. Favoritos y «añadir a rutina» desde el catálogo

**Problema.**
En la pestaña **Ejercicios** solo se puede mirar la ficha. Para añadir un ejercicio a una rutina hay
que salir, entrar en la rutina y volver a buscarlo: la variante de la pantalla que permite añadir
solo se alcanza desde dentro de una rutina (`lib/pantallas/catalogo.dart`). El catálogo de 1.324
ejercicios está infrautilizado.

**Comportamiento.**

- **Añadir a rutina desde cualquier punto del catálogo**: en la fila de resultados y en la ficha. Al
  pulsar, se elige la rutina de destino en un `showCupertinoModalPopup`; si solo hay una rutina, se
  añade directamente y se avisa con `ui.aviso`.
- **Favoritos:** marcar con estrella desde la ficha o la lista. Sección «Favoritos» arriba del
  catálogo cuando no hay búsqueda activa.
- **Vistos recientemente:** los últimos 10 abiertos, también en el estado inicial del catálogo. Hoy
  esa pantalla arranca vacía, con solo el buscador.
- **Filtro por músculo objetivo:** `buscarCatalogo` (`bd.dart:406`) filtra por `bodyPart` y
  `equipment` pero no por `target`, que es la clasificación más útil (`abs` 169, `pectorals` 158,
  `biceps` 151…). Se añade como tercer filtro, con su índice en la tabla.

**Datos.**

```dart
@DataClassName('Favorito')
class Favoritos extends Table {
  TextColumn get idCatalogo => text().references(CatalogoEjercicios, #id)();
  DateTimeColumn get creado => dateTime()();

  @override
  Set<Column> get primaryKey => {idCatalogo};
}

@DataClassName('Visto')
class Vistos extends Table {
  TextColumn get idCatalogo => text().references(CatalogoEjercicios, #id)();
  DateTimeColumn get fecha => dateTime()();   // se conservan los 10 más recientes

  @override
  Set<Column> get primaryKey => {idCatalogo};
}
```

Añadir `@TableIndex` sobre `target` en `CatalogoEjercicios`, junto a los tres que ya existen
(`bd.dart:55-57`).

**API de datos.**

```dart
Future<void> marcarFavorito(String idCatalogo, bool valor);
Future<List<FichaCatalogo>> favoritos();
Future<void> registrarVisto(String idCatalogo);
Future<List<FichaCatalogo>> vistosRecientes({int limite = 10});
Future<List<FichaCatalogo>> buscarCatalogo({..., String? target});
Future<List<ResumenRutina>> rutinasQueContienen(String idCatalogo);
```

**Criterios de aceptación.**

- [ ] Se puede añadir un ejercicio a una rutina sin salir de la pestaña Ejercicios.
- [ ] La ficha indica en qué rutinas ya está ese ejercicio.
- [ ] Los favoritos persisten y se muestran al abrir el catálogo sin búsqueda.
- [ ] Filtrar por «Bíceps» devuelve los 151 ejercicios con `target = biceps`.
- [ ] La paginación de 40 en 40 sigue funcionando con el filtro nuevo.

---

### B13. Peso corporal y medidas

**Problema.**
La app mide las cargas pero no al usuario. El peso corporal es el contexto que da sentido a la
evolución de las cargas: subir 5 kg en press perdiendo 3 kg de peso corporal es un resultado muy
distinto a hacerlo ganando 4 kg.

**Comportamiento.**

- Registro de medidas con fecha: **peso corporal** y, opcionalmente, perímetros (cintura, pecho,
  brazo, muslo) y porcentaje de grasa.
- Una entrada por día y tipo; volver a registrar el mismo día sustituye el valor.
- Gráfico de evolución con `fl_chart`, que ya es dependencia, usando `LineChart` (el
  `BarChart` de `resultado_ejercicio.dart:165` no encaja para una serie temporal continua).
  Media móvil de 7 días para el peso corporal: los saltos diarios de ±1 kg son ruido y ocultan la
  tendencia.
- Si hace más de 7 días que no se registra el peso, la pestaña Progreso ofrece hacerlo con un toque.

**Interfaz.**

- Tercera opción del `CupertinoSlidingSegmentedControl` de Progreso: `Resumen · Calendario · Cuerpo`.
  Con tres cabe bien; con cuatro empezaría a apretarse (ver [H](#h-decisiones-pendientes)).
- Nueva pantalla `lib/pantallas/medidas.dart` para el histórico y la edición.

**Datos.**

```dart
@DataClassName('Medida')
class Medidas extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get fecha => dateTime()();

  /// 'peso' | 'cintura' | 'pecho' | 'brazo' | 'muslo' | 'grasa'
  TextColumn get tipo => text()();

  /// kg, cm o %, según el tipo.
  RealColumn get valor => real()();

  @override
  List<Set<Column>> get uniqueKeys => [{fecha, tipo}];
}
```

Tabla genérica en lugar de una columna por medida: añadir «cuello» en el futuro no debe requerir una
migración.

**API de datos.**

```dart
Future<void> registrarMedida(DateTime fecha, String tipo, double valor);  // upsert
Future<List<Medida>> serieMedida(String tipo, {DateTime? desde, DateTime? hasta});
Future<Medida?> ultimaMedida(String tipo);
Future<void> borrarMedida(DateTime fecha, String tipo);
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
`resultado_ejercicio.dart` compara pesos absolutos entre sesiones. Pero 10×60 kg y 5×75 kg no son
comparables mirando solo el peso: la segunda es mejor sesión y el gráfico la pintaría como una barra
más alta sin decir por qué. Falta una métrica que normalice peso y repeticiones.

**Comportamiento.**

- Para cada serie efectiva (no de calentamiento) se calcula el **1RM estimado**:
  - **Epley** (por defecto): `1RM = peso × (1 + repeticiones / 30)`
  - **Brzycki** (alternativa): `1RM = peso × 36 / (37 − repeticiones)`
- El 1RM de una **sesión** es el máximo de los de sus series.
- Las series de más de 12 repeticiones dan estimaciones poco fiables: se calculan igual pero se
  marcan como estimación de baja confianza (valor en gris con asterisco) y no cuentan para un récord.
- **Récords personales**, tres por ejercicio: peso máximo en una serie efectiva, 1RM estimado máximo
  y volumen máximo en una sesión. Al guardar una sesión que bata alguno, el resumen de cierre
  ([B8](#b8-entrenamiento-en-curso-sesión-viva)) lo celebra: «🏆 Nuevo récord en Barbell Bench
  Press: 82,5 kg estimados».

**Interfaz.**

En `lib/pantallas/resultado_ejercicio.dart`:

- La tarjeta de resumen (hoy Último / Máximo / Sesiones) pasa a **1RM estimado · Peso máximo ·
  Volumen total · Sesiones**, en dos filas de dos.
- `CupertinoSlidingSegmentedControl` sobre el gráfico para elegir la métrica del eje Y:
  `Peso · 1RM · Volumen`. Resuelve de paso la carencia de volumen sin pantalla nueva.
- Selector de rango `1M · 3M · 1A · Todo`, que sustituye al `_maxBarras = 12` fijo
  (`resultado_ejercicio.dart:16`).
- Las filas del histórico que fueron récord llevan un icono de trofeo.

**Datos.** Sin cambios de esquema: los récords se **calculan**, no se almacenan. Con volúmenes
personales (cientos de sesiones, miles de series) una consulta agregada es instantánea, y
almacenarlos abriría la puerta a que quedaran desincronizados al editar o borrar una sesión (A2).

**API de datos.** Módulo nuevo `lib/datos/metricas.dart`, funciones puras sin acceso a base de datos
y por tanto directamente testeables:

```dart
double unoRm(double peso, int repeticiones, {Formula formula = Formula.epley});
double volumen(List<ValoresSerie> series);      // Σ repeticiones × peso, sin calentamientos
ValoresSerie? mejorSerie(List<ValoresSerie> series);
bool esFiable(int repeticiones);                 // repeticiones <= 12
```

Y en `AppBD`:

```dart
Future<RecordsEjercicio> recordsEjercicio(int idEjercicio);
Future<List<Record>> recordsBatidos(int idEntrenamiento);
```

`recordsBatidos` compara contra las sesiones **anteriores en fecha**, no contra todas: así editar
una sesión antigua no convierte retroactivamente en récord algo que no lo fue.

**Criterios de aceptación.**

- [ ] `unoRm(100, 1)` devuelve exactamente `100`.
- [ ] `unoRm(60, 10)` con Epley devuelve `80.0`.
- [ ] Una sesión con una serie de 15 repeticiones no genera récord de 1RM.
- [ ] Cambiar el eje del gráfico a Volumen recalcula sin volver a consultar la base de datos.
- [ ] Borrar la sesión que tenía el récord hace que el récord pase a la siguiente mejor.

---

### C17. Resumen semanal y racha

**Problema.**
La pestaña Progreso es una lista de rutinas con su última fecha (`lib/pantallas/progreso.dart`). No
responde a la pregunta que uno se hace de verdad: *¿voy bien esta semana?*

**Comportamiento.**

Bloque nuevo en la parte superior de **Progreso › Resumen**:

- **Esta semana:** sesiones frente al objetivo de Ajustes (`3 de 4`), con anillo o barra de
  progreso, y volumen total de la semana.
- **Comparativa:** variación frente a la semana anterior en sesiones y volumen, con signo y color
  (`+12 % de volumen`). Sin datos de la semana previa se omite, en lugar de mostrar `+0 %`.
- **Racha:** semanas consecutivas cumpliendo el objetivo. Se rompe al terminar una semana sin
  alcanzarlo; **la semana en curso no rompe la racha** hasta que acaba (si no, el lunes toda racha
  valdría cero).
- **Últimos 7 días:** siete puntos, uno por día, con el color de la rutina entrenada.
- **Aviso de inactividad:** si hace más de 7 días de la última sesión, un mensaje discreto, nunca
  culpabilizador: «Hace 9 días de tu último entrenamiento».

**Definición de semana.** Lunes a domingo, coherente con `formato.diasSemana`, que ya empieza en
lunes. En Dart, `DateTime.weekday` da 1 para el lunes, así que el lunes de una fecha es
`fecha.subtract(Duration(days: fecha.weekday - 1))`.

**Interfaz.**
Tarjeta nueva sobre el grupo «Rutinas entrenadas», reutilizando `ui.BarraProgreso`
(`lib/tema/ui.dart:391`). Si se prefiere un anillo, hay que componerlo con `CustomPainter`:
`CircularProgressIndicator` es de Material y está descartado por la regla del proyecto —fue
justamente el motivo por el que nació `BarraProgreso`—.

**Datos.** Sin cambios de esquema.

**API de datos.**

```dart
Future<ResumenSemana> resumenSemana(DateTime lunes);
/// Semanas consecutivas cumpliendo el objetivo, sin contar la semana en curso.
Future<int> rachaSemanas(int objetivo);
```

`rachaSemanas` se resuelve con **una** consulta que agrupa por semana; nada de un bucle de consultas
hacia atrás.

**Criterios de aceptación.**

- [ ] Con el objetivo en 3 y 3 sesiones esta semana, el indicador está completo.
- [ ] La racha no se rompe el lunes por la mañana.
- [ ] Una semana sin entrenar rompe la racha una vez terminada.
- [ ] Sin ninguna sesión registrada, el bloque no aparece y se conserva el `ui.EstadoVacio` actual.
- [ ] Todo el resumen se calcula con 2 consultas o menos.
- [ ] Test de datos con fechas fijas que cubra el cambio de semana y la racha rota.

---

### C19. Días del calendario pulsables

**Problema.**
Las celdas del calendario de `lib/pantallas/progreso.dart` son puramente decorativas: se ve que ese
día se entrenó, pero no **qué** se hizo. Es el gesto que cualquiera intenta al ver un calendario.

**Comportamiento.**

- Pulsar un día **con** entrenamientos abre su detalle: las sesiones de ese día con rutina, hora,
  duración, ejercicios, series y nota.
- Desde ahí se puede editar o eliminar la sesión ([A2](#a2-editar-y-borrar-entrenamientos)).
- Pulsar un día **sin** entrenamientos y **pasado** ofrece «Registrar un entrenamiento en este día»
  ([A3](#a3-registrar-un-entrenamiento-en-otra-fecha)).
- Pulsar un día **futuro** no hace nada.
- La celda se atenúa al pulsarla.

**Interfaz.**

- Detalle del día en un `showCupertinoModalPopup` con el resumen y un botón «Ver sesión», que navega
  a la pantalla `sesion` creada en A2. Así no se duplica interfaz.
- La celda pasa a envolverse en un `GestureDetector`.

**Datos.** Sin cambios de esquema. Depende de la nueva `entrenamientosPorDia`
([A6](#a6-varias-rutinas-el-mismo-día)).

**Criterios de aceptación.**

- [ ] Pulsar un día entrenado muestra todas las sesiones de ese día.
- [ ] Pulsar un día vacío del pasado abre el registro con esa fecha ya seleccionada.
- [ ] Los días futuros no responden al toque.
- [ ] Eliminar una sesión desde el detalle actualiza el calendario (vía `invalidarEntrenamientos`).

---

## D. Mapa muscular interactivo

> Especificación de una vista nueva: un modelo anatómico del cuerpo, coloreado según el trabajo real
> de cada músculo, en el que al tocar un músculo se ven sus ejercicios y los entrenamientos que lo
> han trabajado. La imagen de referencia aportada (lámina anatómica con vista frontal y dorsal,
> músculos delimitados y coloreados por grupo) define el resultado visual buscado.

### D.0 Decisión técnica previa: «3D» en Flutter

La petición original habla de un **dibujo en 3D**. Conviene decidirlo explícitamente, porque
condiciona todo lo demás. En Flutter las opciones son reales, a diferencia de lo que ocurría en la
versión Flet:

| Opción | Qué implica | Veredicto |
|---|---|---|
| **3D real con malla** (`flutter_cube`, `three_dart`) | Rasterización por software de un `.obj`. Cargar un modelo anatómico decente son varios MB en el APK, y —lo decisivo— **no hay picking por submalla**: identificar qué músculo se ha tocado sobre una malla rotada exige rayos contra triángulos, implementado a mano. Todo el trabajo iría a la parte que menos valor aporta. | **Descartado** |
| **`model_viewer_plus`** | Modelo 3D real, pero renderiza en un WebView: peso, arranque lento, dos motores de render conviviendo y ninguna integración con los colores del tema. | **Descartado** |
| **Pseudo-3D vectorial** — modelo anatómico plano con sombreado, vistas frontal y dorsal | Es lo que hace la lámina de referencia: la sensación de volumen la da el sombreado, no la geometría. `CustomPainter` + `Path` es nativo, sin dependencias, y **`Path.contains(Offset)` resuelve el picking exacto**, curvas Bézier incluidas, en una línea. Se recolorea cada frame sin coste. | **Elegida** |

Se especifica por tanto un **mapa muscular pseudo-3D**: dos siluetas anatómicas sombreadas
(anterior y posterior) que se alternan, con cada músculo como región vectorial independiente,
coloreable y pulsable. La rotación se sustituye por un conmutador **Frente / Espalda**, que en
pantalla de móvil es más usable que una rotación libre.

Merece la pena subrayar por qué esto es más sólido de lo que parece: `Path.contains` es exactamente
el problema difícil (detectar qué región se ha tocado) y Flutter lo trae resuelto en el motor. Con
un modelo 3D habría que escribirlo a mano.

### D.1 Objetivo

Responder de un vistazo a tres preguntas que hoy la app no puede contestar:

1. **¿Qué estoy trabajando y qué estoy descuidando?** — un desequilibrio se ve en un mapa, no en una
   lista de rutinas.
2. **¿Qué ejercicios existen para este músculo?** — el catálogo tiene 1.324 ejercicios clasificados
   por músculo objetivo, pero hoy solo se llega a ellos escribiendo en el buscador.
3. **¿Cuándo entrené esto por última vez?** — hoy hay que ir rutina por rutina.

### D.2 Estructura de la vista

Nueva pantalla `lib/pantallas/musculatura.dart`, como **tercera opción del selector de la pestaña
Progreso** (`Resumen · Calendario · Cuerpo`), compartiendo sección con B13.

```
┌────────────────────────────────────────┐
│  Musculatura                           │
│  ┌──────────────┬──────────────┐       │
│  │   Frente     │   Espalda    │       │  ← conmutador de vista
│  └──────────────┴──────────────┘       │
│  ┌────────────────────────────────┐    │
│  │  7 días │ 30 días │ 90 días    │    │  ← periodo del mapa de calor
│  └────────────────────────────────┘    │
│                                        │
│           ╭─────────╮                  │
│          │  modelo   │                 │
│          │ anatómico │                 │  ← CustomPaint: 21 regiones pulsables
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
es poco fiable, y una lista ordenada por abandono es además la información más accionable de la
pantalla. El mapa comunica; la lista permite actuar.

### D.3 Regiones musculares

Se define un vocabulario canónico de **21 regiones**, cerrado y propio de la app, independiente de
los cuatro vocabularios desiguales del dataset (`bodyPart` 10 valores, `target` 19, `muscleGroup`
29, `secondaryMuscles` 39).

| Región | Nombre | Vista | Valores del catálogo que mapea |
|---|---|---|---|
| `cuello` | Cuello | ambas | `sternocleidomastoid`, `levator scapulae`, bodyPart `neck` |
| `trapecio` | Trapecios | ambas | `traps`, `trapezius` |
| `deltoides` | Hombros | ambas | `delts`, `deltoids`, `shoulders`, `rotator cuff` |
| `deltoidesPost` | Deltoides posterior | espalda | `rear deltoids` |
| `pectoral` | Pecho | frente | `pectorals`, `chest`, `upper chest`, `serratus anterior` |
| `biceps` | Bíceps | frente | `biceps`, `brachialis` |
| `triceps` | Tríceps | espalda | `triceps` |
| `antebrazo` | Antebrazos | ambas | `forearms`, `wrist flexors`, `wrist extensors`, `wrists`, `grip muscles`, `hands` |
| `dorsal` | Dorsales | espalda | `lats`, `latissimus dorsi` |
| `espaldaAlta` | Espalda alta | espalda | `upper back`, `rhomboids`, `back` |
| `lumbar` | Lumbares | espalda | `lower back`, `spine` |
| `abdomen` | Abdominales | frente | `abs`, `abdominals`, `core`, `lower abs` |
| `oblicuo` | Oblicuos | frente | `obliques` |
| `gluteo` | Glúteos | espalda | `glutes` |
| `cuadriceps` | Cuádriceps | frente | `quads`, `quadriceps` |
| `isquiotibial` | Isquiotibiales | espalda | `hamstrings` |
| `aductor` | Aductores | frente | `adductors`, `inner thighs`, `groin` |
| `abductor` | Abductores | frente | `abductors` |
| `flexorCadera` | Flexores de cadera | frente | `hip flexors` |
| `gemelo` | Gemelos | ambas | `calves`, `soleus` |
| `tibial` | Tibial anterior | frente | `shins`, `ankles`, `ankle stabilizers`, `feet` |

Los 29 ejercicios con `target = cardiovascular system` **no tienen región**: se agrupan aparte como
«Cardio», bajo el modelo, no sobre él.

Este mapa vive en `lib/datos/musculos.dart`:

```dart
enum Region { cuello, trapecio, deltoides, /* … */ tibial }

const regiones = <Region, DatosRegion>{
  Region.pectoral: DatosRegion(
    nombre: 'Pecho',
    vista: Vista.frente,
    terminos: {'pectorals', 'chest', 'upper chest', 'serratus anterior'},
  ),
  // …
};

Region? regionDe(String termino);
Map<Region, double> regionesDeEjercicio(FichaCatalogo ficha);
```

**Cobertura obligatoria:** un test recorre los 1.324 ejercicios de `assets/ejercicios.es.json` y
comprueba que todo valor de `target` cae en una región o en la lista explícita de excluidos. Si
mañana se actualiza el dataset y aparece un músculo nuevo, el test falla en vez de que el músculo
desaparezca en silencio del mapa. Es el mismo patrón que ya se usa para el índice de búsqueda.

### D.4 Atribución del trabajo a cada músculo

Cada serie efectiva aporta su volumen (`repeticiones × peso`) a una o varias regiones, ponderado:

| Origen en el catálogo | Peso | Motivo |
|---|---|---|
| `target` | **1,0** | Es el músculo que el ejercicio entrena; el dato más fiable del dataset |
| `muscleGroup` | **0,5** | Redundante o inconsistente en muchas filas (`forearms` aparece 165 veces como grupo); se cuenta, pero a la mitad |
| `secondaryMuscles` | **0,3** | Trabajo real pero secundario |

Reglas:

- Si una región recibe peso por varias vías en el mismo ejercicio, se toma **el mayor**, no la suma.
- Un ejercicio **personalizado** (`idCatalogo` nulo, `bd.dart:95`) no aporta a ninguna región. Se
  avisa al pie: «3 ejercicios personalizados no están representados».
- Los ejercicios de peso corporal se registran con `peso = 0` y su volumen sería nulo. Para que las
  dominadas cuenten, el mapa usa **`pesoEfectivo = max(peso, 1)`**; el resto de métricas (C16, C17)
  no aplican esta corrección. Es una aproximación consciente: el mapa mide *atención dedicada*, no
  carga absoluta.
- Los pesos de atribución son constantes del módulo, ajustables en un solo sitio.

### D.5 Escala de color

Cinco niveles sobre el **volumen relativo** de cada región dentro del periodo elegido (no absoluto:
comparar gemelos con cuádriceps en valor absoluto pintaría siempre el mapa igual).

| Nivel | Criterio | Color |
|---|---|---|
| 0 | Sin trabajo en el periodo | `context.relleno` |
| 1 | ≤ 25 % del máximo | `context.acento` al 25 % de opacidad |
| 2 | ≤ 50 % | al 50 % |
| 3 | ≤ 75 % | al 75 % |
| 4 | > 75 % | `context.acento` pleno |

Decisiones de color:

- Escala **secuencial de un solo tono**, no un semáforo rojo-verde: aquí «mucho» no es bueno ni
  malo, es simplemente más, y una escala de intensidad lo comunica sin emitir un juicio. Además
  funciona con daltonismo.
- Al salir de la extensión `Paleta`, el mapa se adapta solo a claro y oscuro. Contornos con
  `context.separador` y `context.textoTer`.
- El nivel 0 debe distinguirse claramente del 1: es el que responde a la pregunta más importante,
  «¿qué no estoy tocando?».

### D.6 Interacción

- **Tocar una región** abre un `showCupertinoModalPopup` con tres bloques:
  1. **Resumen del músculo** — volumen y series del periodo, última vez entrenado, y en qué rutinas
     aparece.
  2. **Tus entrenamientos** — últimas 5 sesiones que lo trabajaron, con fecha, rutina y ejercicio
     concreto. Cada una navega a `abrirSesion` ([A2](#a2-editar-y-borrar-entrenamientos)).
  3. **Ejercicios del catálogo** — los de esa región, primero los que ya están en alguna rutina del
     usuario. Con acceso a la ficha y a «Añadir a rutina»
     ([B12](#b12-favoritos-y-añadir-a-rutina-desde-el-catálogo)). Enlace «Ver los 151 ejercicios»
     que abre el catálogo con el filtro por `target` ya aplicado.
- **Tocar fuera de toda región** no hace nada.
- La región tocada se resalta con contorno de acento mientras la hoja está abierta.
- Cambiar de periodo recolorea sin recargar la pantalla: es un `setState` sobre el `CustomPainter`,
  con los datos ya en memoria.

### D.7 Implementación del dibujo

**Recurso gráfico.** Fichero nuevo `assets/musculatura.json`, declarado en `pubspec.yaml`:

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

- Coordenadas normalizadas a un lienzo de 1000 × 2000, escaladas al tamaño real con `Matrix4`.
- Cada región es una **lista** de trazados, porque casi todos los músculos son bilaterales
  (pectoral izquierdo y derecho son dos polígonos de la misma región).
- Sombreado: cada región lleva además trazados opcionales de luz y sombra, pintados con baja
  opacidad encima del color base. Es lo que da el aspecto de volumen sin geometría 3D.

**Dibujo.** Un `CustomPainter` que recorre las regiones y hace `canvas.drawPath(path, pintura)`. Los
`Path` se construyen una sola vez al cargar el JSON y se cachean; en `paint` solo cambia el `Paint`.

**Parseo de los trazados.** Dart no trae un parser de `d` de SVG en el framework. Dos caminos:

- escribir un parser mínimo (`M`, `L`, `C`, `Z` absolutos) en `lib/datos/svg_path.dart` — unas 80
  líneas, sin dependencias, y **totalmente testeable**; o
- generar el JSON ya como listas de puntos y curvas, evitando el parser por completo.

**Se recomienda la segunda**: el fichero lo produce una herramienta de diseño una vez, y evita
mantener un parser de un formato ajeno. Si se elige la primera, el parser necesita sus propios tests.

**Detección del toque.** Un `GestureDetector` sobre el `CustomPaint` recibe la posición local:

1. Se convierte a coordenadas del viewbox con la inversa de la matriz de escala.
2. **`path.contains(Offset)`** decide si el punto cae dentro. Es exacto para curvas Bézier y lo
   resuelve el motor de Flutter; no hace falta implementar *point-in-polygon* ni teselar nada.
3. Si dos regiones se solapan, gana la de **menor área** (`path.getBounds()` precalculado): las
   regiones pequeñas están encima y son las difíciles de acertar.
4. Si ninguna contiene el punto, se busca la más cercana dentro de un radio de ~12 px lógicos, para
   perdonar el dedo.

La lógica de resolución vive en `lib/datos/geometria.dart` como funciones puras que reciben los
`Path` ya construidos; así es testeable sin montar la pantalla.

**Rendimiento.**

- El JSON se carga y se convierte a `Path` **una sola vez** por arranque, cacheado en un provider.
  Si el fichero crece, se parsea con `compute()` en un isolate, igual que ya hace `semilla.dart` con
  el megabyte del catálogo.
- El volumen por región se resuelve con **una única consulta** que une
  `serie → entrenamiento → ejercicio → catalogo_ejercicios` en el rango de fechas; la atribución a
  regiones se hace en Dart sobre el resultado.
- `shouldRepaint` debe comparar solo los colores, no los `Path`.

**Licencia del recurso gráfico.** ⚠️ **Punto crítico.** La imagen de referencia aportada es una
lámina de terceros, con toda probabilidad protegida por derechos de autor, y **no puede incorporarse
al repositorio ni servir de calco directo**. El dibujo debe ser:

- original, o
- derivado de una fuente en dominio público (por ejemplo, las planchas del *Gray's Anatomy* de 1918), o
- de una fuente con licencia compatible y atribución explícita.

Sea cual sea el origen, se documenta en `README.md` junto a la atribución de Gym visual que ya
existe. El proyecto ya es cuidadoso con esto —`media/` está fuera del repositorio y del APK
precisamente por licencia—, y el mapa muscular no puede ser la excepción. La lámina aportada sirve
como **referencia de aspecto y nivel de detalle**, no como material de partida.

### D.8 API de datos

```dart
Future<Map<Region, TrabajoRegion>> volumenPorRegion({
  required DateTime desde,
  required DateTime hasta,
});   // volumen, series y última fecha por región

Future<List<SesionDeRegion>> sesionesDeRegion(Region region, {int limite = 5});

/// Ordenado poniendo primero los que ya están en alguna rutina del usuario.
Future<List<FichaCatalogo>> catalogoPorRegion(Region region, {int limite = 20});

Future<Map<Region, List<String>>> regionesEnRutinas();
```

Con sus providers correspondientes, y añadidos a `invalidarEntrenamientos` (`providers.dart:132`):
un entrenamiento nuevo cambia el mapa.

### D.9 Criterios de aceptación

- [ ] El modelo se dibuja en frente y espalda, y el conmutador alterna sin recargar la pantalla.
- [ ] Cada una de las 21 regiones es identificable visualmente y responde al toque en su área.
- [ ] Tocar el pectoral abre la hoja con el resumen, las últimas sesiones de pecho y ejercicios de
      pecho del catálogo.
- [ ] Sin ningún entrenamiento registrado, el modelo se ve en gris con un `ui.EstadoVacio`
      explicativo, y el catálogo por músculo sigue siendo navegable (la vista ya es útil sin
      histórico).
- [ ] Con datos, un músculo entrenado esta semana y otro sin tocar en 90 días se distinguen a simple
      vista.
- [ ] Cambiar el periodo de 7 a 90 días recolorea y no vuelve a consultar el catálogo.
- [ ] Test que recorre los 1.324 ejercicios y confirma que todo `target` tiene región.
- [ ] Test de `geometria.dart` con al menos 20 puntos de prueba que acierten su región.
- [ ] El mapa se pinta correctamente en tema claro y oscuro (test de widget en ambos).
- [ ] `README.md` documenta el origen y la licencia del dibujo anatómico.

### D.10 Riesgos

| Riesgo | Mitigación |
|---|---|
| **El recurso gráfico es el cuello de botella real.** Sin un dibujo anatómico correcto y libre, la vista no existe. No es trabajo de programación. | Abordarlo **primero**, antes que el código. Empezar con una silueta simplificada (regiones como formas geométricas suaves) y refinar después: el sistema completo funciona igual con un dibujo tosco. |
| Tocar regiones pequeñas es poco fiable en móvil | Tolerancia de 12 px, prioridad a la región menor y **lista complementaria siempre visible** |
| La atribución por pesos puede parecer arbitraria | Constantes en un solo módulo, documentadas, y un texto en la hoja que explique de qué ejercicios sale el dato |
| Los ejercicios personalizados quedan fuera del mapa | Aviso explícito al pie; mejora futura: pedir el músculo al crear un ejercicio personalizado |
| El JSON de trazados puede engordar el APK | Son trazados vectoriales, no imágenes: unas decenas de KB. Si creciera, se comprime y se parsea en isolate |

---

## E. Modelo de datos consolidado

Estado final del esquema tras aplicar todo el documento. En **negrita**, lo nuevo.

```
Rutinas              id, nombre, color
Ejercicios           id, idRutina, idCatalogo, nombre, descripcion,
                     **orden**, **descansoSeg**
CatalogoEjercicios   (sin cambios de columnas) id, nombre, bodyPart, equipment, target,
                     muscleGroup, secondaryMuscles, instrucciones, image, gif, busqueda
                     **+ índice sobre target**
Entrenamientos       id, idRutina, fecha, **duracionSeg**, **nota**
SeriesTabla          id, idEntrenamiento, idEjercicio,
                     nSerie (⚠ cambia de semántica: índice, no recuento),
                     repeticiones, peso, **calentamiento**, **rpe**, **nota**
**SesionesActivas**  id, idRutina, inicio, actualizado, estado
**Ajustes**          clave, valor
**Favoritos**        idCatalogo, creado
**Vistos**           idCatalogo, fecha
**Medidas**          id, fecha, tipo, valor
```

**Secuencia de `schemaVersion`:**

| Versión | Contenido | Destructiva | Estado |
|---|---|---|---|
| 1 | Estado inicial | — | — |
| 2 | **A1** — expansión de series agregadas a filas por serie + `calentamiento` | **Sí** | **Hecha** |
| 3 | A4 (`orden`) | No | **Hecha** |
| 4 | A5 (`nota` de sesión y de serie, `rpe`) y la tabla `Ajustes` | No | **Hecha** |
| 5 | B7 (`descansoSeg`), B8 (`duracionSeg`, `SesionesActivas`) | No | Pendiente |
| 6 | B12 (`Favoritos`, `Vistos`, índice de `target`), B13 (`Medidas`) | No | Pendiente |

Solo la versión 2 transforma datos existentes. Todas las demás añaden columnas, tablas o índices y
son seguras. Antes de la 2 se copia el fichero de base de datos.

> **Desviación al implementar.** La tabla `Ajustes` se adelantó a la v4, junto con A5: el
> interruptor del RPE tenía que poder tocarse desde algún sitio y no había ninguno. Eso corrió una
> versión el resto de la secuencia. La pantalla de Ajustes que existe hoy tiene **solo** esa
> opción y la escala RPE/RIR; B9 sigue pendiente entera.

El flujo de esquemas versionados de drift (`drift_dev schema dump`, `schema steps` y
`schema generate`) se montó al abordar la v2 y ya sirve para las que quedan:
`test/migraciones_test.dart` monta una base real de cada versión anterior y la migra hasta la
actual, comparando el esquema resultante con el volcado. El flujo está en `CLAUDE.md`.

---

## F. Plan de entrega

Orden propuesto. Cada fase deja la app funcionando y es publicable por separado.

> **Anulado respecto a la versión anterior del documento:** allí la fase 0 consistía en montar una
> red de tests desde cero, hacer testeable el singleton de la base de datos y activar las claves
> foráneas. La reescritura en Flutter **ya trae las tres cosas**: 27 tests con `NativeDatabase.memory()`
> sobrescribiendo `bdProvider`, `flutter analyze` en 0 issues y CI que verifica cada pull request y
> publica una release por cada merge a `main`. Esa fase desaparece.

### Fase 0 — Herramienta de migraciones ✅

Hecha. El volcado de esquemas versionados de drift está montado (`drift_schemas/`,
`lib/datos/esquemas.dart`, `test/esquemas/`) y `test/migraciones_test.dart` migra bases reales de
cada versión anterior hasta la actual. Hubo que ponerle techo a `drift` en `pubspec.yaml`: desde
2.34.3 el CLI de `drift_dev` no compila, y `drift_dev` no se puede subir por el analyzer.

### Fase 1 — Cimientos del modelo ✅

Hecha. **A1** (series independientes, con la migración destructiva y el respaldo previo) → **A2**
(editar/borrar, con historial y detalle de sesión) → **A3** (fecha) → **A6** (varias sesiones por
día).

### Fase 2 — Uso diario

**A4** (orden) y **A5** (notas y RPE) ✅ ya están; A5 se adelantó a B9 llevándose consigo la tabla
de ajustes y una pantalla mínima con su interruptor. Queda **B9** (la pantalla de Ajustes completa)
→ **B7** (descanso) → **B8** (sesión viva).

### Fase 3 — Protección de datos y comodidad

**B10** (copia de seguridad) → **B11** (duplicar y plantillas) → **B12** (catálogo) →
**B13** (peso corporal).

> B10 podría adelantarse a la fase 1 si se prefiere tener la copia de seguridad **antes** de la
> primera migración destructiva. Es una alternativa defendible y probablemente la más prudente,
> sobre todo si ya hay histórico instalado en un móvil.

### Fase 4 — Análisis

**C16** (1RM y récords) → **C17** (semana y racha) → **C19** (días pulsables).

### Fase 5 — Mapa muscular

**D**, en dos tiempos: primero el recurso gráfico y `musculos.dart` con sus tests (que no requieren
interfaz), y después la vista. Va al final porque se apoya en A1 para el volumen por serie y en B12
para «añadir a rutina» desde la hoja del músculo.

---

## G. Fuera de alcance

Se deja fuera de esta iteración, de forma consciente:

- **Sincronización en la nube y multidispositivo.** Cambia la naturaleza del proyecto (backend,
  cuentas, conflictos); B10 cubre la necesidad real de no perder los datos.
- **Cuentas de usuario.** La app es de un solo usuario local.
- **Integración con relojes o wearables** (Health Connect, HealthKit).
- **Recomendaciones automáticas de progresión de carga.** Interesante, pero requiere los datos que
  esta iteración justamente empieza a recoger (RPE, volumen por serie). Reconsiderar después.
- **Internacionalización de la interfaz.** Los textos siguen incrustados en las pantallas;
  `flutter_localizations` solo cubre hoy los del framework.
- **Publicación en tiendas.** El APK se sigue instalando a mano desde las releases del repositorio,
  sin firmar con una clave propia.
- **Vídeos o media adicional.** Se mantiene la relación actual con el dataset de Gym visual y sus
  condiciones de uso.
- **Ejercicios personalizados con músculo asignado.** Lo pide D, pero no se aborda ahora; se
  documenta como mejora futura.

---

## H. Decisiones pendientes

Cuestiones que conviene cerrar antes o durante la implementación:

1. **¿Cuatro pestañas o tres?** El mapa muscular (D) y las medidas (B13) compiten por sitio dentro
   de Progreso. Opciones: un tercer elemento «Cuerpo» en el `CupertinoSlidingSegmentedControl`
   (recomendado, no toca el `CupertinoTabScaffold`) o una cuarta pestaña. Afecta a D.2 y B13.
2. **¿Adelantar B10 (copia de seguridad) a la fase 1?** Ver la nota de la fase 3. Recomendado si ya
   hay histórico instalado que importe.
3. **Origen del dibujo anatómico** (D.7). Es un bloqueo real de la fase 5 y no se resuelve
   programando. Decidir entre dibujo original o fuente en dominio público.
4. **¿Parser de SVG o JSON de puntos?** (D.7). Se recomienda el JSON de puntos, para no mantener un
   parser de un formato ajeno.
5. **Fórmula de 1RM por defecto** (C16): Epley es la propuesta; Brzycki es algo más conservadora en
   repeticiones altas. Puede dejarse elegible en Ajustes a coste casi nulo.
6. **Escala de esfuerzo por defecto** (A5): RPE o RIR. Se propone dejarlo **desactivado** de inicio
   para no complicar el registro a quien no lo use.
7. **Dependencias nuevas de B10** (`share_plus`, `file_picker`). Son dos, y la alternativa sin
   dependencias empeora bastante la experiencia en Android. Recomendado aceptarlas.
