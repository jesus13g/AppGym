# AppGym — Especificaciones, segunda iteración

> Continuación de [`especificaciones.md`](especificaciones.md), que está **entero
> implementado** y se conserva como historia: sus bloques A (modelo de datos), B (uso
> diario), C (progreso y análisis) y D (mapa muscular) describen el porqué de lo que hoy
> hay en el código, y no se tocan.
>
> Este documento recoge las **tres funcionalidades que aquel dejó fuera de alcance a
> propósito** y que ahora sí se abordan. Las tres estaban ya nombradas en su sección G,
> con el motivo por el que se aplazaron; cada bloque de aquí empieza recordando ese
> motivo y diciendo qué ha cambiado para que deje de valer.
>
> Escrito sobre el código actual: **Flutter 3.44.8 / Dart 3.12.2**, `drift` sobre SQLite
> (`schemaVersion` 6), `Riverpod` para el estado, interfaz **solo Cupertino**, catálogo de
> 1.324 ejercicios, nueve dependencias, 291 tests y `flutter analyze` en 0 issues. Ver
> `CLAUDE.md` para la arquitectura vigente.
>
> **Estado: ninguno de los tres bloques está implementado.** Todo lo que sigue es lo
> previsto, no lo hecho.

## Índice

- [0. Cómo leer este documento](#0-cómo-leer-este-documento)
- [I. Internacionalización de la interfaz](#i-internacionalización-de-la-interfaz)
  - [I1. Mecanismo de traducción](#i1-mecanismo-de-traducción)
  - [I2. Extracción de los textos de las pantallas](#i2-extracción-de-los-textos-de-las-pantallas)
  - [I3. Fechas, números, unidades y plurales](#i3-fechas-números-unidades-y-plurales)
  - [I4. El catálogo y el índice de búsqueda](#i4-el-catálogo-y-el-índice-de-búsqueda)
  - [I5. Plantillas y vocabularios de datos](#i5-plantillas-y-vocabularios-de-datos)
  - [I6. Elegir idioma](#i6-elegir-idioma)
  - [I7. Tests, CI y el coste de mantener dos idiomas](#i7-tests-ci-y-el-coste-de-mantener-dos-idiomas)
- [J. Recomendación automática de progresiones](#j-recomendación-automática-de-progresiones)
  - [J1. El modelo de progresión](#j1-el-modelo-de-progresión)
  - [J2. Configuración por ejercicio](#j2-configuración-por-ejercicio)
  - [J3. Dónde aparece la sugerencia](#j3-dónde-aparece-la-sugerencia)
  - [J4. Estancamiento y descarga](#j4-estancamiento-y-descarga)
  - [J5. API de datos y providers](#j5-api-de-datos-y-providers)
  - [J6. Criterios de aceptación y riesgos](#j6-criterios-de-aceptación-y-riesgos)
- [K. Sincronización en la nube, cuentas y multidispositivo](#k-sincronización-en-la-nube-cuentas-y-multidispositivo)
  - [K1. El principio: local primero](#k1-el-principio-local-primero)
  - [K2. Elección de backend](#k2-elección-de-backend)
  - [K3. Cuentas e identidad](#k3-cuentas-e-identidad)
  - [K4. Modelo de sincronización](#k4-modelo-de-sincronización)
  - [K5. Conflictos](#k5-conflictos)
  - [K6. Qué se sincroniza y qué no](#k6-qué-se-sincroniza-y-qué-no)
  - [K7. El primer enlace](#k7-el-primer-enlace)
  - [K8. Interfaz](#k8-interfaz)
  - [K9. Seguridad y privacidad](#k9-seguridad-y-privacidad)
  - [K10. La costura de test](#k10-la-costura-de-test)
  - [K11. Operación, costes y forks](#k11-operación-costes-y-forks)
  - [K12. Criterios de aceptación y riesgos](#k12-criterios-de-aceptación-y-riesgos)
- [L. Modelo de datos consolidado](#l-modelo-de-datos-consolidado)
- [M. Plan de entrega](#m-plan-de-entrega)
- [N. Fuera de alcance](#n-fuera-de-alcance)
- [O. Decisiones pendientes](#o-decisiones-pendientes)

---

## 0. Cómo leer este documento

Misma estructura que el documento anterior, y por el mismo motivo: que cada punto se pueda
dar por cerrado sin discutir qué significaba.

| Campo | Significado |
|---|---|
| **Problema** | Qué falla o falta hoy, con referencia al fichero y línea actuales |
| **Comportamiento** | Qué debe hacer la app, en términos de usuario |
| **Interfaz** | Pantallas, widgets y navegación |
| **Datos** | Cambios en `lib/datos/bd.dart` y su migración |
| **API de datos** | Métodos nuevos o modificados en `AppBD`, y providers en `lib/estado/providers.dart` |
| **Criterios de aceptación** | Lista verificable; es lo que se prueba antes de dar por cerrado el punto |
| **Riesgos** | Lo que puede romperse |

**Las convenciones transversales del documento anterior siguen vigentes íntegras** (sección
0 de `especificaciones.md`): español en código y commits, solo Cupertino, colores por la
extensión `Paleta`, migraciones con su paso en `MigrationStrategy`, invalidar en vez de
reconstruir, consultas preagregadas, tests por cada punto, `flutter analyze` en 0 issues,
el peso siempre en kilogramos y ninguna dependencia sin justificar.

Tres se matizan aquí, y conviene leerlas antes de empezar:

1. **«Español en la interfaz» pasa a significar otra cosa.** Sigue siendo español en el
   código, los comentarios y los commits — eso no cambia y no se negocia. Pero los textos
   que ve el usuario dejan de estar en español *en el código* para estar en un fichero de
   recursos por idioma, con el español como idioma de referencia. El bloque [I](#i-internacionalización-de-la-interfaz)
   es exactamente ese cambio.
2. **«Ninguna dependencia sin justificar» se pone a prueba.** El bloque K necesita un
   cliente de backend, que no es una utilidad de 200 líneas sino una pieza con su propio
   ciclo de vida y su propio servicio detrás. Ese es el coste real de K y se discute en
   [K2](#k2-elección-de-backend) y [K11](#k11-operación-costes-y-forks), no de pasada.
3. **«Todo se puede comprobar sin interfaz» hay que ganárselo otra vez.** El motor de
   sincronización se prueba entero en `flutter test`, contra un transporte falso en
   memoria y dos bases de datos ([K10](#k10-la-costura-de-test)). Si eso no se monta
   primero, K se convierte en la primera parte del proyecto que solo se puede verificar a
   mano — que es justo lo que este repositorio lleva evitando desde la reescritura.

**Orden de lectura y de entrega.** Los tres bloques van en el orden en que deben
implementarse, que no es el orden en que se pidieron:

```
I (idiomas)  →  J (progresiones)  →  K (nube)
   barato        lógica pura,          caro, invasivo
   invasivo      aislado               y con servicio detrás
```

- **I va primero** porque es un barrido por todas las pantallas. Si J y K entran antes,
  ambos añaden pantallas nuevas con textos incrustados y el barrido se hace dos veces. Con
  I hecho, J y K nacen traducidos.
- **J va segundo** porque es autocontenido: un módulo puro con la forma de `metricas.dart`,
  un par de columnas y un sitio donde enseñar el resultado. No depende de K y no bloquea a
  nadie. Es también el bloque con mejor relación entre lo que aporta y lo que cuesta.
- **K va último** porque cambia la naturaleza del proyecto y porque su migración de esquema
  toca todas las tablas. Cuanto más estable esté el modelo de datos cuando llegue, menos
  probable es tener que repetir la operación.

---

## I. Internacionalización de la interfaz

> **Lo que decía el documento anterior:** *«Internacionalización de la interfaz. Los textos
> siguen incrustados en las pantallas; `flutter_localizations` solo cubre hoy los del
> framework.»*
>
> **Qué ha cambiado:** que ya no van a entrar quince pantallas más. La app está completa en
> funcionalidad, así que el inventario de textos es finito y se puede cerrar de una vez. Y
> que los dos bloques que vienen detrás traen pantallas nuevas: hacerlo ahora es hacerlo
> una vez.

Este bloque **no añade una funcionalidad al usuario español**, que es el que hay hoy. Lo que
hace es abrir la app a cualquier otro, y de paso separar el texto de la lógica, que es una
mejora estructural con valor propio: hoy no hay forma de listar lo que la app le dice al
usuario sin leerse quince ficheros.

### I1. Mecanismo de traducción

**Problema.**

Los textos están escritos donde se usan: `'Rutinas'` en `raiz.dart`, `'Sin entrenar'` en
`formato.dart:52`, `'Añadir serie'` en `entrenar.dart`, `'Peso corporal'` en la constante
`tiposMedida` (`bd.dart:155`). Un recuento rápido sobre `lib/pantallas` y `lib/tema/ui.dart`
da **324 literales distintos de más de una palabra**, y por encima de 400 contando las
etiquetas de una sola. `main.dart:41` ya declara `supportedLocales: [Locale('es'),
Locale('en')]` y fija `locale: const Locale('es')`, pero eso hoy solo afecta a los textos
del propio framework (el menú de selección de texto, el gesto de volver): los nuestros
salen en español pase lo que pase.

**Comportamiento.**

- La app se traduce con **ARB + `flutter gen-l10n`**, el mecanismo oficial de Flutter.
- Idiomas de partida: **español** (referencia, `app_es.arb`) e **inglés** (`app_en.arb`).
- El idioma se elige en Ajustes; por defecto se sigue al del sistema, y si el sistema está
  en un idioma que no tenemos, se cae a inglés.
- Ninguna cadena visible queda en el código. La única excepción admitida son los nombres
  propios que no se traducen: `AppGym`, `kg`, `lb`, `RPE`, `RIR`, `1RM`, y los nombres de
  ejercicio del catálogo, que solo existen en inglés (ver [I4](#i4-el-catálogo-y-el-índice-de-búsqueda)).

**Por qué ARB y no un mapa a mano.**

La alternativa barata sería un `Map<String, String>` por idioma en un fichero Dart, sin
generador ni dependencias. Se descarta:

| | ARB + `gen-l10n` | Mapa en Dart |
|---|---|---|
| Claves | Comprobadas en compilación: una clave que no existe **no compila** | En ejecución: una clave mal escrita devuelve `null` y se ve en el móvil |
| Parámetros | Tipados (`t.seriesHechas(4)`) | Interpolación a mano, sin comprobar |
| Plurales y géneros | Sintaxis ICU, resuelta por `intl` | A mano, con un `if` por idioma |
| Traductor externo | ARB es formato estándar; lo abre cualquier herramienta | Hay que editar Dart |
| Coste | Un fichero `l10n.yaml`, un paso en CI y `intl` | Cero |

Y el argumento que zanja la duda: **`gen-l10n` no pasa por `build_runner`**. Es un comando
del propio SDK de Flutter, así que no entra en el conflicto de versiones de `analyzer` que
obliga a declarar los providers a mano y a poner techo a `drift` (ver `CLAUDE.md`). El
generador de traducciones y el de drift no se pisan porque no comparten nada.

**Dependencias.**

- `flutter_localizations` — **ya está** en `pubspec.yaml`.
- `intl` — nueva, pero es la que `flutter_localizations` ya arrastra: se declara para
  poder usar `DateFormat` y `NumberFormat` directamente ([I3](#i3-fechas-números-unidades-y-plurales)),
  no para meter un paquete que no estuviera. Hay que declararla **sin versión fija**
  (`intl: any`) o con la que fije el SDK, o `pub get` deja de resolver en cuanto Flutter
  suba de versión.

Con esto la app pasa de nueve dependencias a diez, y la décima ya estaba en el árbol.

**Datos.** Ninguno. El idioma es una preferencia más ([I6](#i6-elegir-idioma)).

**Estructura de ficheros.**

```
l10n.yaml                        configuración del generador
lib/l10n/
├── app_es.arb                   español, idioma de referencia (con las descripciones)
└── app_en.arb                   inglés
lib/l10n/generado/               AppLocalizations y sus delegates  ← NO se versiona
```

```yaml
# l10n.yaml
arb-dir: lib/l10n
template-arb-file: app_es.arb
output-dir: lib/l10n/generado
output-localization-file: textos.dart
output-class: Textos
synthetic-package: false
nullable-getter: false
```

- **Lo generado no se versiona**, coherente con los `*.g.dart` (`.gitignore`). Se añade
  `lib/l10n/generado/` al `.gitignore` y `flutter gen-l10n` al arranque de CI, junto al
  `build_runner build` que ya hay. Sin ese paso no compila nada, igual que hoy pasa con
  drift, y eso ya está documentado como normal en este proyecto.
- La clase se llama **`Textos`** y no `AppLocalizations`, porque el código de esta app está
  en español y ese nombre se va a escribir mil veces.
- El acceso, envuelto en una extensión que vive con las demás de `tema/ui.dart`, para que
  en las pantallas se lea corto y coherente con `context.texto` / `context.acento`:

```dart
extension Traducciones on BuildContext {
  Textos get t => Textos.of(this);
}

// en la pantalla:
Text(context.t.rutinas)
Text(context.t.seriesHechas(hechas, total))
```

**Convención de claves.** `ambitoConcepto`, en `camelCase` y en español, con el ámbito por
delante: `rutinasVacio`, `rutinasNueva`, `entrenarAnadirSerie`, `ajustesUnidad`,
`ajustesUnidadDetalle`. El ámbito es la pantalla o el módulo, y las compartidas van con
`comun`: `comunGuardar`, `comunCancelar`, `comunBorrar`. Sin ámbito, en dos meses hay tres
claves distintas para «Guardar» y ninguna se puede reutilizar sin miedo.

**Criterios de aceptación.**

- [ ] `flutter gen-l10n` genera `Textos` con los dos idiomas y CI lo ejecuta antes de
      analizar, probar y construir.
- [ ] `lib/l10n/generado/` está en `.gitignore` y no aparece en el repositorio.
- [ ] Una clave que no existe **rompe la compilación**, no la ejecución. Se comprueba
      escribiendo una a propósito y viendo fallar `flutter analyze`.
- [ ] `pubspec.yaml` sigue resolviendo con `flutter pub get` limpio.
- [ ] `dart format --set-exit-if-changed lib test` sigue pasando, con lo generado fuera.

**Riesgos.**

| Riesgo | Mitigación |
|---|---|
| Un paso de generación más antes de compilar | Es el mismo patrón que `build_runner`, ya documentado en `CLAUDE.md` y en CI. Se añade a la lista de comandos del README |
| `intl` fijada a una versión que choque con el SDK | Se declara sin fijar; es la que ya arrastra `flutter_localizations` |
| Claves huérfanas al borrar una pantalla | `flutter gen-l10n` avisa de las que están en `app_en.arb` y no en la plantilla; para las que sobran en ambos, un test de cobertura ([I7](#i7-tests-ci-y-el-coste-de-mantener-dos-idiomas)) |

### I2. Extracción de los textos de las pantallas

**Problema.**

Los 400 y pico literales están repartidos así, de más a menos:

| Fichero | Literales de más de una palabra |
|---|---|
| `pantallas/ajustes.dart` | 43 |
| `pantallas/copia_seguridad.dart` | 43 |
| `pantallas/entrenar.dart` | 33 |
| `pantallas/catalogo.dart` | 32 |
| `datos/formato.dart` | 31 |
| `pantallas/progreso.dart` | 29 |
| `pantallas/rutina.dart` | 28 |
| `pantallas/musculatura.dart` | 26 |
| `pantallas/rutinas.dart` | 25 |
| resto de pantallas + `tema/ui.dart` | ~130 |

No es una lista homogénea. Hay tres clases de texto y cada una se trata distinto:

1. **Texto de pantalla.** Títulos, botones, estados vacíos, avisos. Va a ARB tal cual.
2. **Texto compuesto en `formato.dart`.** `'Hace $dias días'`, `'12 de marzo de 2026'`,
   `'4 series · 8.750 kg'`. No basta con traducir la plantilla: cambia el orden, cambia el
   plural y cambia el separador de miles. Es [I3](#i3-fechas-números-unidades-y-plurales).
3. **Texto que hoy es un dato.** Las etiquetas de `tiposMedida` (`bd.dart:155`), los
   nombres de las plantillas (`assets/plantillas.json`), el vocabulario del catálogo
   (`datos/i18n.dart`) y los nombres de las 21 regiones musculares (`datos/musculos.dart`).
   Están mezclados con la lógica y hay que separarlos. Es [I4](#i4-el-catálogo-y-el-índice-de-búsqueda)
   y [I5](#i5-plantillas-y-vocabularios-de-datos).

**Comportamiento.**

- Se barre pantalla por pantalla, en orden de menos a más textos, para que los patrones
  raros aparezcan cuando ya hay costumbre y no en la primera.
- Cada pantalla convertida lleva su commit y sus tests pasando. **No es un único commit
  gigante**: son quince, y cada uno se puede revisar.
- Al terminar, ni `lib/pantallas/` ni `lib/tema/ui.dart` contienen una cadena visible.

**Los tres patrones que dan guerra**, y cómo se resuelven:

**a) Constantes de nivel superior con texto.** `tiposMedida` (`bd.dart:155`) es
`(clave, etiqueta, unidad)`, y `etiquetaMedida()` (`bd.dart:165`) devuelve la etiqueta ya
formada. La etiqueta no puede salir de una constante: depende del idioma, que depende del
`BuildContext`.

```dart
// Antes (bd.dart:155)
const tiposMedida = <(String, String, String)>[
  ('peso', 'Peso corporal', 'kg'),
  ...
];

// Después: la constante se queda con lo que no depende del idioma.
const tiposMedida = <(String, String)>[   // (clave, unidad)
  ('peso', 'kg'),
  ('grasa', '%'),
  ...
];

// Y la etiqueta se resuelve donde hay contexto.
String etiquetaMedida(Textos t, String tipo) => switch (tipo) {
  'peso' => t.medidaPeso,
  'grasa' => t.medidaGrasa,
  ...
  _ => tipo,
};
```

La clave (`'peso'`, `'grasa'`) **no se toca nunca**: está escrita en la columna `tipo` de la
tabla `medidas` de todos los móviles instalados y en todas las copias de seguridad
exportadas. Traducirla sería perder los datos.

**b) Enumeraciones con etiqueta.** `Unidad.sufijo` (`ajustes.dart:23`) es texto que se
pinta. `kg` y `lb` son símbolos internacionales y se quedan; pero `Tema.sistema`,
`EscalaEsfuerzo.rir` o `Formula.brzycki` se enseñan con nombre largo en Ajustes. La regla:
**el `enum` no lleva su etiqueta**; quien la pinta la pide a `Textos`. Los `switch`
exhaustivos de Dart garantizan que añadir un valor nuevo rompa la compilación en el sitio
donde falta la traducción, que es exactamente lo que se quiere.

**c) Texto dentro de `ui.dart`.** `ui.EstadoVacio`, `ui.dialogoConfirmar` y `ui.aviso`
llevan textos por defecto («Cancelar», «Aceptar»). Se quitan los valores por defecto y
pasan a ser parámetros obligatorios: un componente compartido no debe saber en qué idioma
está la app, y `ui.dart` no debería tener que importar `Textos`.

**Criterios de aceptación.**

- [ ] `grep -rE "'[^']*[áéíóúñ¿¡][^']*'" lib/pantallas lib/tema` no devuelve nada.
- [ ] Las quince pantallas y los tres componentes compartidos se pintan igual que hoy con
      el idioma en español: los tests de widget existentes pasan **sin cambiar sus
      aserciones**, porque siguen buscando el texto en español ([I7](#i7-tests-ci-y-el-coste-de-mantener-dos-idiomas)).
- [ ] `flutter analyze` en 0 issues después de cada pantalla, no solo al final.
- [ ] Ninguna clave de datos (`'peso'`, `'grasa'`, las de `Claves`, las de las plantillas)
      ha cambiado de valor. Un test lo fija leyendo una base de la versión anterior.

**Riesgos.**

| Riesgo | Mitigación |
|---|---|
| Traducir por error una clave persistida y perder datos | El test de migración monta bases reales de versiones anteriores; se añade una aserción sobre los valores de `medidas.tipo` y de `ajustes.clave` |
| Un barrido de quince pantallas invita a «arreglar de paso» otras cosas | Un commit por pantalla, y el commit solo mueve texto. Lo demás va aparte |
| Textos que se componen en tiempo de ejecución y se escapan al grep | El grep encuentra los acentuados; para el resto, revisión pantalla a pantalla contra las capturas actuales |

### I3. Fechas, números, unidades y plurales

**Problema.**

`datos/formato.dart` (176 líneas) es el módulo donde el español está más metido en la
lógica, no solo en el texto:

```dart
const meses = <String>['Enero', 'Febrero', ...];              // formato.dart:12
const diasSemana = <String>['L', 'M', 'X', 'J', 'V', 'S', 'D']; // formato.dart:27

String fechaLarga(DateTime? v) =>                             // formato.dart:38
    '${v.day} de ${meses[v.month - 1].toLowerCase()} de ${v.year}';

String hace(DateTime? v) { ...                                 // formato.dart:46
  if (dias == 1) return 'Ayer';
  if (dias < 7) return 'Hace $dias días';
}
```

Cuatro cosas rompen al traducir esto, y **ninguna se arregla cambiando el literal**:

1. **El orden.** «12 de marzo de 2026» es «March 12, 2026». No es la misma plantilla con
   otras palabras.
2. **La semana no empieza el mismo día.** `diasSemana` empieza en lunes, que es correcto
   en España y falso en Estados Unidos. El calendario de `progreso.dart` y la agrupación
   por semanas de `metricas.lunesDe()` (`metricas.dart:174`) dependen de eso.
3. **El plural.** «Hace 1 día / Hace 2 días» tiene dos formas en español y en inglés, pero
   ni el ruso ni el árabe tienen dos, y el mecanismo tiene que admitirlo aunque hoy no
   haya ese idioma.
4. **Los separadores decimales.** Hoy `formato.peso` escribe `8.750 kg` con el punto como
   separador de miles y la coma como decimal, que es lo español y lo contrario de lo
   inglés.

**Comportamiento.**

- Las fechas se formatean con **`DateFormat` de `intl`**, con el locale activo:
  `DateFormat.yMMMMd(locale)`, `DateFormat.MMMd(locale)`, `DateFormat.Hm(locale)`. Se
  eliminan `meses`, `mes()`, `fechaCorta()`, `fechaLarga()` y `hora()` tal como están hoy.
- Los números, con **`NumberFormat`** del mismo locale. El peso pasa de construirse a mano
  a `NumberFormat.decimalPattern(locale)`.
- Los textos relativos («Hoy», «Ayer», «Hace N días») pasan a ARB con **sintaxis ICU de
  plural**:

  ```json
  "haceDias": "{dias, plural, =0{Hoy} =1{Ayer} other{Hace {dias} días}}",
  "@haceDias": {
    "description": "Distancia hasta hoy en la lista de rutinas",
    "placeholders": { "dias": { "type": "int" } }
  }
  ```

- **La semana sigue empezando en lunes, en todos los idiomas, y eso es deliberado.** No es
  un descuido de internacionalización: la racha semanal (C17) y el reparto de
  `metricas.porSemana` están definidos sobre semanas de lunes a domingo, y cambiar el
  primer día según el locale haría que la misma base de datos diera rachas distintas en dos
  móviles del mismo usuario — que es exactamente lo que el bloque K no puede permitir. Se
  documenta en `metricas.dart` junto a `lunesDe`, donde ya hay una nota parecida.

**Firma nueva de `formato.dart`.** El módulo deja de ser un puñado de funciones globales
sin estado y pasa a recibir el idioma. Dos opciones:

| Opción | A favor | En contra |
|---|---|---|
| Pasar el `locale` a cada función | Sigue siendo puro y trivial de probar | Un parámetro más en ~20 llamadas, casi siempre el mismo |
| Una clase `Formato(locale, ajustes)`, provista por Riverpod | Se pide una vez por pantalla; agrupa idioma y unidades, que casi siempre viajan juntos | Deja de ser un módulo de funciones sueltas |

**Se elige la clase.** El argumento no es la comodidad: es que `formato.peso()` ya recibe
`Ajustes` hoy, así que la mitad de las funciones ya llevan un parámetro de contexto. Juntar
idioma y ajustes en un objeto que se pide con `ref.watch(formatoProvider)` deja una sola
dependencia por pantalla en vez de dos, y **mantiene el módulo puro**: `Formato` no importa
Flutter, recibe un `String locale` y un `Ajustes`, y se prueba con los dos idiomas escritos
a mano, igual que `metricas_test.dart`.

**Criterios de aceptación.**

- [ ] `test/formato_test.dart` (nuevo) prueba fechas, pesos, duraciones y relativos en
      **es** y en **en**, con fechas fijas.
- [ ] En inglés, `1234.5 kg` se escribe `1,234.5 kg`; en español, `1.234,5 kg`.
- [ ] «Hace 1 día» / «1 day ago» / «Hoy» / «Today» salen de la clave ICU, no de un `if`.
- [ ] El calendario de Progreso y la racha semanal dan el mismo resultado en los dos
      idiomas para la misma base de datos. Hay un test que lo compara.
- [ ] `metricas.dart` sigue sin importar Flutter y sin saber de idiomas.

**Riesgos.**

| Riesgo | Mitigación |
|---|---|
| `DateFormat` necesita que los datos del locale estén cargados | `flutter_localizations` los inicializa; se comprueba en un test de widget que monta con `Locale('en')` |
| Cambiar el formateo del peso rompe el gráfico o la exportación | La exportación de la copia de seguridad **escribe números JSON, no texto formateado** (`copia.dart:112`) y no se toca. Hay un test de ida y vuelta que lo fija |
| La semana en lunes chirría a un usuario inglés | Es una decisión consciente y documentada. Si se quiere configurable, es una preferencia más, no un cambio de locale |

### I4. El catálogo y el índice de búsqueda

**Problema.**

Este es el punto difícil del bloque, y no se parece a los demás.

`datos/i18n.dart` (186 líneas) traduce al español los cuatro vocabularios del catálogo:
`zonasCuerpo` (10 valores), `equipamientos` (28), `musculosTabla` (40 y pico) y los
objetivos. Y esas traducciones **no son solo presentación**: alimentan la columna
`busqueda` de `catalogo_ejercicios`, que es el índice del buscador (`semilla.dart`). Por eso
buscar «mancuerna pecho» encuentra `dumbbell bench press`. La cabecera del propio fichero
lo avisa: *«Si tocas este fichero hay que volver a sembrar el catálogo»*.

O sea: el idioma de la interfaz está soldado al índice de búsqueda de 1.324 filas.

Además, el asset se llama `assets/ejercicios.es.json` — el `.es.` ya estaba puesto pensando
en esto — pero su contenido en español es solo el vocabulario de categorías: **los nombres
de ejercicio existen únicamente en inglés** en el dataset original y se muestran tal cual.

**Comportamiento.**

- Los **nombres de ejercicio no se traducen**. Ni ahora ni después. No hay traducción que
  aportar (el dataset no la trae), traducirlas a máquina daría nombres que ningún usuario
  reconocería en su gimnasio, y son 1.324. Se muestran en inglés en todos los idiomas, que
  es además como se llaman en la práctica.
- Los **vocabularios de categorías sí se traducen**, y pasan a tener una tabla por idioma.
- La columna `busqueda` **contiene los términos de todos los idiomas soportados a la vez**,
  no solo el activo.

Esa última decisión es la que evita el problema entero, y merece explicarse:

> **Un solo índice, multilingüe.** La alternativa —una columna `busqueda` por idioma, o
> resembrar el catálogo al cambiar de idioma— obliga a reescribir 1.324 filas cada vez que
> el usuario toca el selector, con el parseo del megabyte de JSON por medio. Metiendo los
> términos de los dos idiomas en la misma columna, el índice se construye una vez, cambiar
> de idioma no toca la base, y de regalo un usuario inglés que aprendió los nombres en
> español los sigue encontrando. El coste es que la columna crece; con 1.324 filas y dos
> idiomas es del orden de 200 KB más en el fichero SQLite, que es irrelevante al lado del
> megabyte del asset.

**Datos.**

Ningún cambio de esquema: la columna `busqueda` ya existe y solo cambia lo que se escribe
en ella. Pero **hay que resembrar**, y eso sí necesita disparador:

- `semilla.dart` compara recuentos para ser idempotente (`sembrarCatalogo`). Con el mismo
  número de filas no resiembra, así que el índice viejo se quedaría.
- Se añade una clave de ajustes `version_indice` (un entero) que `semilla.dart` compara
  además del recuento. Al subir la versión del vocabulario se sube ese entero y el catálogo
  se vuelve a sembrar en el siguiente arranque, una vez.

**Estructura.**

```
lib/datos/i18n.dart          se queda como la API: `traducir(termino, idioma)`
lib/datos/i18n_es.dart       los cuatro mapas en español (lo de hoy, movido)
lib/datos/i18n_en.dart       los cuatro mapas en inglés (identidad, casi todo)
```

El fichero inglés es en su mayor parte la identidad (`'chest' → 'Chest'`), pero no del todo:
`'waist' → 'Core'`, `'upper legs' → 'Thighs'`. Y existe para que el mapa de idiomas sea
uniforme: en cuanto haya un tercer idioma, tener el inglés como «el que no se traduce»
sería un caso especial en todas partes.

**Criterios de aceptación.**

- [ ] Con el idioma en inglés, la ficha de un ejercicio muestra las categorías en inglés y
      el nombre en inglés; con el idioma en español, las categorías en español y el nombre
      igualmente en inglés.
- [ ] «mancuerna pecho» y «dumbbell chest» devuelven el mismo conjunto de ejercicios, sea
      cual sea el idioma activo.
- [ ] Cambiar de idioma **no** vuelve a sembrar el catálogo: se comprueba contando las
      escrituras en un test.
- [ ] Subir `version_indice` sí resiembra, exactamente una vez.
- [ ] El test de cobertura del catálogo se amplía: **todo término de los cuatro
      vocabularios tiene traducción en los dos idiomas**, o está en la lista de excluidos.
      Es el mismo patrón que el test de `musculos.dart` que recorre los 1.324 ejercicios.

**Riesgos.**

| Riesgo | Mitigación |
|---|---|
| Un término sin traducir en inglés que salga en la interfaz en español | El test de cobertura lo caza antes de llegar al móvil |
| El índice multilingüe da falsos positivos al buscar | Los cuatro vocabularios son cerrados y pequeños; los solapes entre idiomas (`core`, `cardio`) devuelven lo mismo que ya devolvían |
| Resembrar en el arranque congela el primer frame | Ya se parsea en un isolate con `compute()`; la resiembra usa el mismo camino |

### I5. Plantillas y vocabularios de datos

**Problema.**

Quedan tres sitios con texto en español que no son ni pantalla ni catálogo:

1. **`assets/plantillas.json`** — cinco plantillas con `nombre` y `descripcion` en español
   («Full body», «Tres sesiones a la semana, todo el cuerpo en cada una…»), y dentro,
   nombres de rutina («Empuje», «Tirón», «Pierna»). Esos nombres **acaban escritos en la
   tabla `rutinas`** cuando el usuario crea la rutina desde una plantilla: no son
   presentación, son datos que el usuario luego edita.
2. **Las 21 regiones de `datos/musculos.dart`** — el `enum Region` lleva su nombre visible.
3. **Los tipos de medida** (`bd.dart:155`), ya tratados en [I2](#i2-extracción-de-los-textos-de-las-pantallas).

**Comportamiento.**

- **Las plantillas se traducen, pero lo que se escribe en la base es lo que el usuario veía
  al pulsar.** Si crea «Push / Pull / Legs» con la app en inglés, sus rutinas se llaman
  `Push`, `Pull`, `Legs`; en español, `Empuje`, `Tirón`, `Pierna`. Y no cambian después si
  cambia de idioma: ya son sus rutinas, con el nombre que él puede editar. Traducir
  retroactivamente los nombres que el usuario ya tiene sería sobrescribirle sus datos.
- **Las regiones musculares se traducen** y su nombre sale de `Textos`, no del `enum`. La
  clave del `enum` (`Region.pectoral`) no cambia: está en `assets/musculatura.json` y en la
  atribución de trabajo.

**Formato de `plantillas.json`.** Se pasa de un texto a un mapa por idioma, con el español
obligatorio como referencia:

```json
{
  "nombre": { "es": "Push / Pull / Legs", "en": "Push / Pull / Legs" },
  "descripcion": {
    "es": "Tres sesiones: empuje, tirón y pierna...",
    "en": "Three sessions: push, pull and legs..."
  },
  "rutinas": [
    { "nombre": { "es": "Empuje", "en": "Push" }, "ejercicios": ["0025", "0405", ...] }
  ]
}
```

`plantillas.dart` (111 líneas) resuelve el idioma activo al cargar y cae al español si falta
la clave. Los ids de ejercicio no cambian: son los del catálogo.

**Criterios de aceptación.**

- [ ] Las cinco plantillas se ven en los dos idiomas, con sus descripciones.
- [ ] Crear una rutina desde una plantilla en inglés escribe los nombres en inglés en la
      tabla `rutinas`; cambiar luego el idioma **no** los renombra.
- [ ] Un test carga `plantillas.json` y exige que **toda** cadena tenga las claves de todos
      los idiomas soportados. Es el equivalente al test de cobertura del catálogo, y es lo
      que impide que un idioma nuevo entre a medias.
- [ ] La hoja del músculo del mapa muscular muestra el nombre de la región traducido.

**Riesgos.**

| Riesgo | Mitigación |
|---|---|
| El JSON de plantillas se hace ilegible con un idioma más | Son cinco plantillas y unas 15 rutinas; si llegara a molestar, se parte en un fichero por idioma |
| Un usuario con rutinas en español cambia a inglés y las ve mezcladas | Es lo correcto: son sus datos. Se explica en la fila de idioma de Ajustes, en una línea |

### I6. Elegir idioma

**Problema.** No hay dónde. `main.dart:40` fija `locale: const Locale('es')` a fuego.

**Comportamiento.**

- Nueva fila **«Idioma»** en Ajustes, en el grupo de apariencia junto a «Tema»
  (`pantallas/ajustes.dart:266`), con `ui.elegirEnHoja`.
- Tres opciones: **Automático (del sistema)** · **Español** · **English**. Cada idioma se
  escribe **en su propio idioma**, que es la convención universal y evita el absurdo de
  buscar «Inglés» estando la app en inglés.
- El cambio es **inmediato**, sin reiniciar: es una preferencia más, `main.dart` la observa
  igual que ya observa `tema` (`main.dart:23`) y `CupertinoApp` se repinta.

**Datos.**

Una clave más en la tabla `ajustes`, sin migración —la tabla es de clave/valor y `Ajustes`
ya se traga lo que no entiende quedándose con el valor de fábrica (`ajustes.dart:100`):

```dart
// ajustes.dart
abstract final class Claves {
  ...
  static const idioma = 'idioma';   // 'auto' | 'es' | 'en'
}

/// Idioma de la interfaz. `null` significa seguir al del sistema.
enum Idioma {
  auto(null), es('es'), en('en');
  const Idioma(this.codigo);
  final String? codigo;
}
```

Y en `main.dart`:

```dart
final idioma = ref.watch(ajustesProvider).value?.idioma ?? Idioma.auto;
return CupertinoApp(
  locale: idioma.codigo == null ? null : Locale(idioma.codigo!),
  supportedLocales: Textos.supportedLocales,
  localizationsDelegates: Textos.localizationsDelegates,
  ...
);
```

Con `locale: null`, Flutter resuelve contra el idioma del sistema y cae al primero de
`supportedLocales` si no lo tiene — que es el comportamiento por defecto y **el motivo por
el que el español debe ir primero en la lista**.

**Criterios de aceptación.**

- [ ] Cambiar de idioma repinta la app entera sin reiniciar, incluidas las pantallas que ya
      están en la pila de navegación.
- [ ] La preferencia sobrevive a cerrar la app y entra en la copia de seguridad (está en la
      tabla `ajustes`, que ya se exporta: `copia.dart:131`).
- [ ] Con el móvil en francés y la opción en «Automático», la app sale en **español** (el
      primero de `supportedLocales`), no rota ni vacía.
- [ ] `Ajustes.desdeMapa` con `idioma: 'klingon'` devuelve `Idioma.auto` sin lanzar.

**Riesgos.**

| Riesgo | Mitigación |
|---|---|
| Cambiar el idioma con una sesión viva en curso | El idioma no toca el estado: el borrador es JSON con ids y números. Hay un test que cambia de idioma con la sesión abierta |
| El idioma viaja en la copia de seguridad y llega a otro móvil | Es lo correcto y coherente con el resto de ajustes. En K es además lo que hace que los dos dispositivos se vean igual |

### I7. Tests, CI y el coste de mantener dos idiomas

**Problema.**

Los 291 tests actuales buscan texto en español: `find.text('Rutinas')`,
`find.text('Sin entrenar')`. Si la app deja de estar en español por defecto en el entorno de
test, **fallan todos de golpe** y hay que reescribir cientos de aserciones sin saber cuáles
fallan por el idioma y cuáles por un fallo real. Es el riesgo más caro de este bloque, y no
es técnico sino de método.

**Comportamiento.**

- **El ayudante que monta las pantallas en los tests fija `Locale('es')`.** Con eso, las
  291 aserciones actuales siguen siendo válidas tal cual y el barrido de [I2](#i2-extracción-de-los-textos-de-las-pantallas)
  se puede hacer pantalla a pantalla viendo en verde lo ya convertido.
- **Se añade un grupo nuevo** —y solo uno— que monta en `Locale('en')` y comprueba lo que de
  verdad depende del idioma: una pantalla de cada tipo, los formatos de [I3](#i3-fechas-números-unidades-y-plurales),
  las categorías del catálogo de [I4](#i4-el-catálogo-y-el-índice-de-búsqueda) y las
  plantillas de [I5](#i5-plantillas-y-vocabularios-de-datos). Duplicar los 291 en inglés no
  aportaría nada: probaría a Flutter, no a la app.
- **Un test de cobertura de traducciones**: carga los dos ARB y exige que tengan **el mismo
  conjunto de claves**. Es lo que impide que una clave nueva entre solo en español y salga
  en inglés como el texto español, que es el modo de fallo típico y silencioso.

**CI.** Un paso más en `.github/workflows/build-apk.yml`, en los dos jobs, justo detrás del
`dart run build_runner build` que ya hay:

```yaml
- name: Generar las traducciones
  run: flutter gen-l10n
```

**Lo que este bloque cuesta a partir de ahora.** Conviene decirlo claro antes de empezar,
porque es permanente: **cada texto nuevo son dos ediciones**, una por idioma, y el test de
cobertura no deja saltárselo. A cambio, el que escribe la funcionalidad ya no decide la
redacción final desde el código, y el inventario completo de lo que la app dice cabe en dos
ficheros.

**Criterios de aceptación.**

- [ ] Los 291 tests actuales pasan sin modificar sus aserciones de texto.
- [ ] El grupo en inglés cubre al menos: Rutinas, Entrenar, Progreso, Catálogo, Ajustes,
      un formato de fecha, un plural y una categoría del catálogo.
- [ ] El test de cobertura falla si se añade una clave a `app_es.arb` y no a `app_en.arb`.
- [ ] CI ejecuta `flutter gen-l10n` antes de analizar, probar y construir, en los dos jobs.

---

## J. Recomendación automática de progresiones

> **Lo que decía el documento anterior:** *«Recomendaciones automáticas de progresión de
> carga. Interesante, pero requiere los datos que esta iteración justamente empieza a
> recoger (RPE, volumen por serie). Reconsiderar después.»*
>
> **Qué ha cambiado:** que esos datos ya están. A1 dio una fila por serie con su peso y sus
> repeticiones, A5 añadió el RPE por serie, y C16 dejó montado el 1RM estimado con su
> noción de serie efectiva y de fiabilidad. La condición que se puso para reconsiderarlo se
> cumple entera.

El «después» es ahora. Y sale barato: es el único de los tres bloques que no necesita ni
servicio, ni dependencia, ni casi esquema.

### J1. El modelo de progresión

**Problema.**

La app registra perfectamente lo que se hizo y no dice nada sobre lo que hacer. Al abrir el
registro de un ejercicio, las series se precargan con **las de la última sesión**
(`ultimasSeriesEjercicio`, provider `ultimasSeriesProvider`), que es el valor por defecto
más útil posible sin analizar nada — pero es literalmente «repite lo de la vez pasada». El
usuario tiene delante su historial, su 1RM estimado y sus récords, y aun así la decisión de
si hoy toca subir de 60 a 62,5 kg la toma de memoria.

Es además donde más se abandona: progresar sin criterio lleva al estancamiento, y el
estancamiento a dejarlo.

**Comportamiento.**

La app propone, para cada ejercicio y antes de empezar, **qué series hacer hoy**: peso y
repeticiones. Nunca lo aplica sola.

El modelo es **doble progresión**, que es el estándar de facto y el único que se sostiene
con los datos que hay:

> Se fija un rango de repeticiones (por defecto 8–12). Con el peso actual se sube de
> repeticiones dentro del rango sesión a sesión; cuando **todas** las series efectivas
> llegan al tope del rango, se sube el peso un escalón y se vuelve al suelo del rango.

Formalmente, sobre la última sesión efectiva del ejercicio (las series de calentamiento no
cuentan, igual que en `metricas.volumen`):

| Situación en la última sesión | Sugerencia |
|---|---|
| Todas las series alcanzaron el tope del rango **y** el esfuerzo lo permite | **Subir peso** un escalón, repeticiones al suelo del rango |
| Alguna serie por debajo del tope | **Mismo peso**, +1 repetición en la primera serie que no llegó |
| Repeticiones por debajo del suelo del rango en la mayoría de las series | **Bajar peso** un escalón |
| Dos sesiones seguidas sin mejorar (ni peso ni repeticiones ni volumen) | **Estancamiento** → ver [J4](#j4-estancamiento-y-descarga) |
| Menos de dos sesiones registradas | **No hay sugerencia**, y no se enseña nada |

**El esfuerzo entra solo si el usuario lo registra.** El RPE es opcional (`esfuerzoActivo`,
desactivado de fábrica). Cuando está activo y la última sesión tiene RPE:

- RPE medio de las series efectivas **≥ 9,5** → no se sube peso aunque toque; se mantiene.
- RPE medio **≤ 7** con todas las series al tope → se puede subir **dos** escalones si el
  usuario ha elegido el perfil agresivo (ver [J2](#j2-configuración-por-ejercicio)).

Cuando no está activo, el modelo funciona igual sin él: solo con repeticiones. Eso es
importante — **la sugerencia no puede depender de una preferencia que está desactivada por
defecto**, o la funcionalidad no existiría para la mayoría.

**El escalón de peso.** Sale de `ajustes.pasoPeso` (0,5 / 1 / 1,25 / 2,5 / 5, `ajustes.dart:81`),
con posible sobreescritura por ejercicio ([J2](#j2-configuración-por-ejercicio)). Se redondea
siempre **al múltiplo del escalón**, en kilogramos, porque el peso se guarda en kilogramos:
sugerir 63,7 kg porque el usuario tiene la app en libras y la conversión no cuadra es
exactamente el error que la regla de las unidades existe para evitar.

**Ejercicios sin peso.** Dominadas, fondos, plancha: peso 0. Ahí no hay escalón que subir,
así que la progresión es **solo por repeticiones** y el rango se amplía (por defecto 5–15).
Se detecta por que todas las series históricas tienen peso 0, no por el equipamiento del
catálogo: un usuario puede hacer dominadas lastradas y entonces sí hay peso.

> **`pesoEfectivo = max(peso, 1)` no se aplica aquí.** Es un truco exclusivo del mapa
> muscular, donde sirve para que las dominadas no sumen cero al colorear. En una sugerencia
> de carga significaría proponer «sube de 1 kg a 3,5 kg» en un ejercicio de peso corporal,
> que es absurdo. Misma nota que ya lleva `musculos.dart`.

**Cardio.** Los ejercicios cuyo `bodyPart` es `cardio` (o cuyo objetivo es
`cardiovascular system`) **no reciben sugerencia**. El modelo de series y repeticiones no
los describe, y una sugerencia mala en un sitio resta credibilidad a las buenas de todos los
demás.

**Arquitectura.** Módulo nuevo `lib/datos/progresion.dart`, con **exactamente la misma forma
que `metricas.dart`**: no importa Flutter, no toca la base de datos, recibe listas y
devuelve valores. Es el tercer módulo puro de la app, después de `metricas.dart` y
`musculos.dart`, y por el mismo motivo: así se prueba con historiales escritos a mano.

```dart
/// Qué hacer hoy con un ejercicio.
enum TipoSugerencia { subirPeso, subirRepeticiones, mantener, bajarPeso, descarga }

/// El porqué, como dato y no como texto: la frase se compone en la pantalla,
/// que es la que sabe el idioma (ver bloque I).
enum MotivoSugerencia {
  rangoCompletado,     // todas las series al tope
  rangoIncompleto,     // falta llegar al tope
  esfuerzoAlto,        // RPE >= 9,5: no se sube aunque tocara
  esfuerzoBajo,        // RPE <= 7 con el rango completo
  repeticionesCaidas,  // por debajo del suelo del rango
  estancado,           // dos sesiones sin mejora
  descargaSugerida,    // tres sesiones estancado
}

class Sugerencia {
  final TipoSugerencia tipo;
  final MotivoSugerencia motivo;

  /// Las series propuestas, listas para precargar el registro.
  final List<ValoresSerie> series;

  /// Diferencia con la última sesión, en kilogramos. Puede ser negativa o cero.
  final double deltaPeso;

  /// `false` cuando el historial es corto o el esfuerzo no está registrado:
  /// se enseña igual, pero marcada, como el 1RM de más de doce repeticiones.
  final bool fiable;
}

Sugerencia? sugerir(
  List<ResumenSesionEjercicio> historial,  // lo que ya devuelve resumenSesionesEjercicio
  List<ValoresSerie> ultimasSeries,        // lo que ya devuelve ultimasSeriesEjercicio
  ConfiguracionProgresion config,
);
```

Las dos entradas **ya existen y ya las pide la pantalla**: `resumenSesionesEjercicio` es lo
que alimenta el gráfico de `resultado_ejercicio.dart` y `ultimasSeriesEjercicio` es lo que
precarga el registro. Igual que `recordsEjercicio` trabaja sobre la lista que la pantalla ya
tiene, esto no añade ni una consulta.

**Devuelve `null`, y eso es la mitad del diseño.** Sin dos sesiones previas, con el ejercicio
marcado como cardio, o con la progresión desactivada, no hay sugerencia y la interfaz no
enseña nada. Una sugerencia inventada el primer día vale menos que ninguna.

### J2. Configuración por ejercicio

**Problema.**

El rango de repeticiones no es universal. 8–12 va bien en accesorios y es absurdo en un peso
muerto pesado (3–5) o en gemelos (12–20). Con un solo rango global, la sugerencia acierta en
la mitad del catálogo y molesta en la otra mitad.

**Comportamiento.**

Tres niveles, del más general al más concreto, cada uno sobrescribiendo al anterior:

1. **Global**, en Ajustes: rango por defecto (8–12), perfil (conservador / estándar /
   agresivo) y el interruptor general.
2. **Por ejercicio**, en el detalle del ejercicio dentro de la rutina: rango propio, escalón
   propio y estrategia (doble progresión / solo repeticiones / desactivada).
3. **Nada por sesión.** Aceptar o ignorar una sugerencia no configura nada; solo afecta a
   ese día.

**Interfaz.** El ejercicio dentro de una rutina ya tiene una hoja de opciones donde se fija
el descanso propio (B7, columna `descansoSeg`). Ahí entra un grupo más:

```
┌──────────────────────────────────────────────┐
│  Barbell Bench Press                         │
├──────────────────────────────────────────────┤
│  Descanso                    90 s        >   │
├──────────────────────────────────────────────┤
│  PROGRESIÓN                                  │
│  Estrategia            Doble progresión  >   │
│  Rango de repeticiones        8 – 12     >   │
│  Escalón de peso        Como el global   >   │
└──────────────────────────────────────────────┘
```

«Como el global» es un valor legítimo y distinto de «sin valor», que es exactamente el caso
para el que `ui.elegirEnHoja<T>` devuelve `(T,)?` en vez de `T?` — el mismo patrón que ya
usan el descanso por ejercicio y el filtro «todos» del catálogo.

**Datos.**

Tres columnas nuevas en `ejercicios`, todas anulables, todas con `null` = «como el global»:

```dart
class Ejercicios extends Table {
  ...
  /// Suelo del rango de repeticiones. Null: el de los ajustes.
  IntColumn get repMin => integer().nullable()();

  /// Tope del rango. Null: el de los ajustes.
  IntColumn get repMax => integer().nullable()();

  /// Escalón de peso propio, en kilogramos. Null: `ajustes.pasoPeso`.
  RealColumn get incrementoKg => real().nullable()();

  /// Estrategia: null = la global, 0 = desactivada, 1 = doble progresión,
  /// 2 = solo repeticiones.
  IntColumn get estrategia => integer().nullable()();
}
```

**Migración `schemaVersion` 6 → 7, no destructiva.** Cuatro `addColumn` sobre `ejercicios`,
todas anulables: las filas existentes quedan con `null`, que significa «como el global», que
es el comportamiento correcto para todo lo ya creado. Es la migración más inocua del
proyecto.

```dart
Future<void> _de6A7(Migrator m, Schema7 esquema) async {
  await m.addColumn(esquema.ejercicios, esquema.ejercicios.repMin);
  await m.addColumn(esquema.ejercicios, esquema.ejercicios.repMax);
  await m.addColumn(esquema.ejercicios, esquema.ejercicios.incrementoKg);
  await m.addColumn(esquema.ejercicios, esquema.ejercicios.estrategia);
}
```

Con el flujo de `CLAUDE.md` detrás: `build_runner build`, `drift_dev schema dump`,
`schema steps`, `schema generate` y `dart format`.

**Ajustes globales.** Cuatro claves más en la tabla `ajustes`, sin migración:

```dart
static const progresionActiva = 'progresion_activa';   // bool, por defecto true
static const repMinGlobal = 'rep_min';                 // int, por defecto 8
static const repMaxGlobal = 'rep_max';                 // int, por defecto 12
static const perfilProgresion = 'perfil_progresion';   // conservador|estandar|agresivo
```

En Ajustes van en el grupo **«Objetivos»**, donde ya viven «Sesiones por semana» y la
fórmula de 1RM (`pantallas/ajustes.dart:230`): es el mismo tipo de preferencia y no hace
falta un grupo nuevo.

> **Nota sobre la copia de seguridad.** `copia.dart` exporta los ejercicios con `orden` y
> `descansoSeg` (`copia.dart:98`). Hay que añadir las cuatro columnas nuevas y **subir
> `versionCopia` de 2 a 3**. Una copia de la versión 2 se importa igual: lo que falta entra
> como `null`, que es «como el global». Eso ya lo contempla el formato y hay un test de ida
> y vuelta que hay que ampliar.

### J3. Dónde aparece la sugerencia

**Problema.**

Una recomendación que hay que ir a buscar no la ve nadie, y una que interrumpe molesta a la
tercera vez. El sitio importa tanto como el cálculo.

**Comportamiento.**

Dos sitios, con dos propósitos distintos:

**a) En la tarjeta del ejercicio al entrenar** (`entrenar.dart:635`, `TarjetaEjercicio`),
que es donde se decide. Una línea sobre la lista de series, discreta:

```
┌──────────────────────────────────────────────┐
│ [img] Barbell Bench Press              [ ⌄ ] │
│       Último: 4×10 · 60,0 kg                 │
├──────────────────────────────────────────────┤
│  ↑ Sugerido  4×8 · 62,5 kg        [Aplicar]  │  ← una línea, con su icono
│    Completaste 4×12 la última vez            │  ← el motivo, en textoTer
├──────────────────────────────────────────────┤
│  #   Repeticiones      Peso                  │
│  1      [ 10 ]       [ 60,0 kg ]      ·      │
│  ...                                         │
```

- **«Aplicar» reescribe las series precargadas** y nada más: no guarda, no confirma. El
  usuario sigue pudiendo tocar cada número, que es como funciona hoy.
- Si no se aplica, la línea **se puede descartar** deslizando o con la «x». Descartada,
  no vuelve en esa sesión. Ese descarte vive en el borrador
  (`sesiones_activas.estado`, JSON, `borrador.dart`) y **no en una tabla**: es un dato
  efímero de la sesión en curso, exactamente lo que esa tabla existe para guardar.
- Con la sugerencia marcada como no fiable (`fiable == false`), se pinta con el mismo
  tratamiento que el 1RM de más de doce repeticiones: se enseña, pero marcada.

**b) En la pantalla de resultados del ejercicio** (`resultado_ejercicio.dart:275`,
`_Tarjeta`), que es donde se analiza. Ahí la sugerencia va como una tarjeta más, junto a los
récords, con el motivo completo y sin botón de aplicar: desde esa pantalla no se está
entrenando.

**Interfaz: el componente.** Una `ui.Pildora` no sirve —lleva dos líneas y una acción—, así
que entra un componente nuevo en `ui.dart`: `ui.Sugerencia`, con icono, título, motivo y
acción opcional. Es el patrón del inventario de `ui.dart`: ahí solo está lo que Flutter no
trae, y esto no lo trae.

**Cuidado con el ancho.** «↑ Sugerido 4×8 · 62,5 kg [Aplicar]» en 375 px es justo el tipo de
fila que ya provocó tres `RenderFlex overflowed` en este proyecto. La fila va flexible, el
texto con `Flexible` y el botón con su ancho mínimo, y **lleva su test a 375 px con
`_comoUnMovil`**, que es la costumbre de la casa.

**Lo que la sugerencia no hace, nunca:**

- **No se aplica sola.** Ni con un ajuste que lo permita. Una app que cambia los pesos sin
  que se lo pidan pierde la confianza del usuario la primera vez que se equivoca, y se
  equivocará: no sabe si el usuario ha dormido mal, si viene de una lesión o si la última
  sesión la cortó a la mitad.
- **No manda notificaciones.** Sin dependencia de notificaciones, sin permisos y sin
  segundo plano.
- **No bloquea nada.** Con la progresión desactivada, la app se comporta exactamente como
  hoy.

### J4. Estancamiento y descarga

**Problema.**

La doble progresión sola no tiene salida del estancamiento: si el usuario no llega al tope
del rango, la sugerencia repite «mismo peso, una repetición más» indefinidamente, semana
tras semana, sin que nada cambie. Ese bucle es peor que no sugerir nada, porque parece que
la app no se entera.

**Comportamiento.**

- **Estancamiento**: tres sesiones consecutivas del mismo ejercicio sin mejorar ni el peso
  máximo, ni las repeticiones totales, ni el volumen efectivo. Los tres datos ya están en
  `ResumenSesionEjercicio`, que es lo que devuelve `resumenSesionesEjercicio`.
- Al detectarlo, la sugerencia pasa a `TipoSugerencia.descarga` con motivo
  `descargaSugerida`: **bajar el peso un 10 %** (redondeado al escalón, hacia abajo) y
  volver al suelo del rango, para reconstruir desde ahí.
- La descarga **se sugiere una vez**. Si se ignora, la sugerencia vuelve a la regla normal
  la sesión siguiente: insistir es lo que convierte un consejo en una regañina.

**En el resumen semanal.** La sección Resumen de Progreso (C17) gana una línea cuando hay
ejercicios estancados: «3 ejercicios estancados», pulsable, que lleva a una lista con los
tres y su última sesión. Es información agregada que hoy nadie ve y que sale de datos ya
consultados.

> **Por qué no se guarda el estancamiento.** Mismo argumento que los récords en C16: si se
> almacenara, editar o borrar una sesión lo dejaría desincronizado. Se calcula recorriendo
> el historial que la pantalla ya tiene, que con volúmenes personales es instantáneo.

**Los límites de esto, dichos en la interfaz.** El texto que acompaña a la descarga debe
decir que es una sugerencia basada en tres sesiones de datos, no un consejo de
entrenamiento. La app no sabe si el usuario está en déficit calórico, durmiendo cuatro horas
o volviendo de una lesión, y todas esas cosas explican un estancamiento mejor que el peso de
la barra. Una frase, en la hoja de detalle, no un aviso legal.

### J5. API de datos y providers

**Métodos nuevos en `AppBD`:** ninguno para calcular. Las dos consultas que hacen falta ya
existen:

| Ya existe | Se usa para |
|---|---|
| `resumenSesionesEjercicio(idRutina, idEjercicio)` | El historial por sesión: peso máximo, repeticiones, volumen, 1RM |
| `ultimasSeriesEjercicio(idEjercicio)` | Las series de la última sesión, para precargar |

Sí hacen falta los métodos de escritura de la configuración por ejercicio:

```dart
Future<void> fijarProgresionEjercicio(
  int idEjercicio, {
  int? repMin,
  int? repMax,
  double? incrementoKg,
  int? estrategia,
});
```

**Providers nuevos** en `estado/providers.dart`:

```dart
/// La sugerencia de un ejercicio dentro de una rutina. Null si no la hay.
final sugerenciaProvider = FutureProvider.family<Sugerencia?, ClaveSeries>(...);

/// Los ejercicios estancados, para la línea del resumen semanal.
final estancadosProvider = FutureProvider<List<EjercicioEstancado>>(...);
```

`ClaveSeries` (`providers.dart:137`) ya existe y es exactamente
`({int idRutina, int idEjercicio})`, así que no hay tipo nuevo que declarar.

**`invalidarTodo` hay que ampliarlo** con los dos providers nuevos. Está dicho en
`CLAUDE.md` y es el sitio donde más fácil es olvidarse: importar una copia cambia el
historial entero y con él todas las sugerencias.

Y `invalidarEntrenamientos` debe invalidar `sugerenciaProvider` y `estancadosProvider`:
guardar una sesión cambia la sugerencia de la siguiente, que es el caso de uso central.

### J6. Criterios de aceptación y riesgos

**Criterios de aceptación.**

- [ ] `lib/datos/progresion.dart` no importa Flutter ni escribe en la base. Es un módulo
      puro, como `metricas.dart` y `musculos.dart`.
- [ ] `test/progresion_test.dart` cubre, con historiales escritos a mano:
      rango completado → sube peso; rango incompleto → sube repeticiones; repeticiones
      caídas → baja peso; RPE ≥ 9,5 → mantiene aunque tocara subir; tres sesiones sin
      mejora → descarga; menos de dos sesiones → `null`; ejercicio de peso corporal → solo
      repeticiones; cardio → `null`.
- [ ] El peso sugerido es **siempre** un múltiplo del escalón vigente, en kilogramos, con
      el usuario en libras incluido. Hay un test específico.
- [ ] Con `progresionActiva` en falso, ni la tarjeta de entrenar ni la de resultados
      enseñan nada, y no se calcula: se comprueba que el provider no se pide.
- [ ] La migración 6 → 7 pasa el test de migración desde cada versión anterior y el esquema
      resultante coincide con el volcado.
- [ ] Una copia de seguridad de la versión 2 se importa sin errores y deja las cuatro
      columnas nuevas en `null`.
- [ ] La línea de sugerencia no desborda a 375 px. Test con `_comoUnMovil`.
- [ ] Aplicar una sugerencia **no** guarda nada: solo cambia los valores del formulario.
- [ ] Descartar una sugerencia la mantiene descartada al navegar a la ficha y volver (vive
      en el borrador), y vuelve a aparecer en la sesión siguiente.

**Riesgos.**

| Riesgo | Mitigación |
|---|---|
| La sugerencia es mala y el usuario la sigue | No se aplica sola, se explica el motivo en una línea, y la descarga lleva la nota de sus límites. La app propone lo que se deduce de los datos, y lo dice |
| Un usuario que hace 5×5 ve sugerencias de 8–12 sin parar | El rango es configurable por ejercicio ([J2](#j2-configuración-por-ejercicio)), y el ejercicio detecta el rango real del historial para proponer la configuración la primera vez |
| Una línea más en una tarjeta ya densa | Es descartable, ocupa dos líneas de texto y no aparece cuando no hay sugerencia — que es siempre en las dos primeras sesiones de cada ejercicio |
| El cálculo en cada repintado de la tarjeta | Va en su provider, cacheado por Riverpod, y se invalida solo al guardar una sesión. Es un recorrido en memoria sobre datos ya consultados |
| Cuatro columnas más en `ejercicios` que casi siempre son `null` | Son anulables y sin índice: en SQLite una columna nula ocupa un byte por fila |

---

## K. Sincronización en la nube, cuentas y multidispositivo

> **Lo que decía el documento anterior:** *«Sincronización en la nube y multidispositivo.
> Cambia la naturaleza del proyecto (backend, cuentas, conflictos); B10 cubre la necesidad
> real de no perder los datos.»* Y, aparte: *«Cuentas de usuario. La app es de un solo
> usuario local.»*
>
> **Qué ha cambiado:** nada de eso ha dejado de ser verdad. Sigue cambiando la naturaleza
> del proyecto, sigue habiendo backend, cuentas y conflictos, y la copia de seguridad sigue
> cubriendo el riesgo de perder los datos. Lo que se pide ahora no es proteger los datos
> —eso está hecho— sino **usar la app en dos dispositivos**: el móvil en el gimnasio y la
> tableta en casa, con el mismo histórico. Eso una copia manual no lo da: exportar,
> compartir e importar cada día no es sincronizar, es una tarea.

Este es el bloque grande. Es más trabajo que I y J juntos, introduce la primera dependencia
de un servicio externo y es el único que puede corromper datos del usuario si sale mal. Va
al final del plan de entrega por eso, y la mayor parte de lo que sigue es la lista de cosas
que hay que decidir **antes** de escribir una línea.

### K1. El principio: local primero

Todo lo demás se deduce de esta regla, así que va primero y no se negocia:

> **La base de datos SQLite local sigue siendo la única fuente de verdad para la interfaz.
> La app funciona entera sin cuenta y sin red, exactamente como hoy. La sincronización es
> un proceso de fondo que reconcilia esa base con una copia remota, y su fallo nunca es
> visible en la ruta de entrenar.**

Las consecuencias, todas verificables:

1. **Ninguna pantalla espera a la red.** Ningún `FutureProvider` de `providers.dart` cambia
   para consultar el servidor. Se sigue leyendo de `AppBD` y punto.
2. **Sin cuenta, la app es la de hoy.** No hay pantalla de bienvenida obligatoria, ni
   registro para empezar, ni funcionalidad detrás de un inicio de sesión. La cuenta se crea
   desde Ajustes cuando el usuario la quiere, y «Continuar sin cuenta» no es un enlace
   pequeño abajo: es el estado por defecto.
3. **Un fallo de sincronización es un aviso, no un error.** En el gimnasio no hay cobertura
   la mitad de las veces. Guardar una sesión no puede fallar por eso, ni siquiera avisar en
   el momento.
4. **Desactivar la sincronización o borrar la cuenta deja los datos locales intactos.** La
   nube es una copia, no el original.

Esto no es solo una postura de diseño: es lo que permite entregar K por partes y que cada
una sea publicable, y lo que hace que un fallo del servicio no convierta la app en un
ladrillo.

### K2. Elección de backend

**Problema.**

Sincronizar necesita un sitio donde dejar los datos y algo que autentique al usuario. Eso es
infraestructura que hay que elegir, pagar y mantener, y este es un proyecto de una persona
cuyo modelo de distribución es un APK sin firmar en las releases de GitHub.

**Las opciones, honestamente.**

| Opción | Qué implica | A favor | En contra |
|---|---|---|---|
| **A. La nube del usuario** (Drive / iCloud / carpeta sincronizada) como almacén tonto: se sube el JSON de la copia de seguridad automáticamente | Sin cuentas propias, sin servidor, sin coste | Cero infraestructura. Privacidad total: los datos son del usuario, en su cuenta. Reutiliza `copia.dart` casi entero | **No es sincronización**: es una copia con fecha. Dos dispositivos que escriben el mismo día se pisan. Requiere el SDK de Drive y la pantalla de OAuth de Google, que no es poco |
| **B. BaaS gestionado** (Supabase: Postgres + Auth + RLS) | Un proyecto alojado, sin servidor propio que mantener | Autenticación, aislamiento por usuario (RLS) y una API REST sobre tablas reales, gratis en el plan de entrada. Cliente Dart oficial. El modelo relacional es el que ya tenemos | Una dependencia grande. Un servicio del que depender. Coste si crece. Cuentas propias con lo que implica (recuperar contraseña, borrar cuenta, RGPD) |
| **C. Backend propio** (un servicio pequeño con su base de datos) | Escribir y operar un servidor | Control total, sin lock-in, el protocolo es exactamente el que se necesita | Es un segundo proyecto entero, en otro lenguaje, con su despliegue, sus copias y su vigilancia. Multiplica el trabajo por dos como mínimo |
| **D. Firebase / Firestore** | Igual que B, con otro proveedor | Madurez, cliente Flutter de primera | El modelo de documentos no encaja con diez tablas relacionales con claves foráneas; habría que aplanar el esquema. Lock-in fuerte |

**Recomendación: B, con el protocolo diseñado para no depender de B.**

El argumento no es que Supabase sea la mejor herramienta en abstracto, sino que es la única
opción en la que el trabajo se concentra en **el motor de reconciliación**, que es la parte
difícil e insustituible, en vez de en operar infraestructura. Y con una condición que hace
la elección reversible:

> **Todo lo que sabe del proveedor vive detrás de una interfaz de una docena de métodos**
> (`SincroTransporte`, [K10](#k10-la-costura-de-test)). El motor de reconciliación, que es
> el 80 % del código y el 100 % de los tests, no importa el SDK del proveedor ni sabe que
> existe. Cambiar de B a C es escribir otro adaptador, no reescribir el bloque.

Esa interfaz es además lo que permite probarlo todo en `flutter test`, sin red y sin cuenta.
Si la elección se cerrara de otra forma —y [O](#o-decisiones-pendientes) la deja abierta—,
esta parte del diseño no cambia.

**La opción A no se descarta del todo**: es un buen escalón intermedio y probablemente lo
que quiere un usuario de los dos que hay. Se recoge en el plan de entrega
([M](#m-plan-de-entrega)) como **Fase 8a**, con la copia automática a la nube del usuario, y
K completo como 8b.

**Dependencias.** Una: el cliente del proveedor (`supabase_flutter`, que arrastra `gotrue`,
`postgrest`, `realtime` y `storage`). Es con diferencia la dependencia más grande que
tendría el proyecto — más que `drift` — y hay que decirlo. Se declara **solo en el
adaptador**, y `lib/datos/sincro/` es el único directorio que la importa. Un test lo fija,
igual que hay tests que fijan que no se importa `material.dart`.

### K3. Cuentas e identidad

**Problema.** Hoy no hay usuarios: hay una base de datos en un móvil.

**Comportamiento.**

- **Método de entrada: correo + enlace mágico** (*magic link*), sin contraseña.
  - No hay contraseña que recordar, que recuperar, que rotar ni que filtrar. Es menos
    superficie de ataque y menos pantallas: no hay «he olvidado mi contraseña», no hay
    requisitos de robustez, no hay almacenamiento de credenciales en el dispositivo más allá
    del token de sesión.
  - El correo es también el canal para avisar de un borrado de cuenta, que es un requisito.
- **Se evalúa y se descarta, de momento, «Iniciar sesión con Google/Apple»**: añade dos
  SDK, dos configuraciones de firma y, en el caso de Apple, un requisito de tienda que aquí
  no aplica porque no se publica en tiendas. Se puede añadir después sin cambiar el modelo
  de datos: para el servidor sigue siendo el mismo `usuario.id`.
- **Un usuario, N dispositivos.** No hay familias, ni compartir, ni entrenador. Cada
  dispositivo se registra con un identificador propio y un nombre editable («Pixel de
  Jesús»), para poder listarlos y revocarlos.
- **Cerrar sesión** ofrece dos salidas, y hay que preguntarlo:
  - *Cerrar sesión y conservar los datos en este móvil* (por defecto).
  - *Cerrar sesión y borrar los datos de este móvil* (para un móvil que se vende o se
    presta).
- **Borrar la cuenta** borra los datos del servidor y deja los locales. Es una acción
  destructiva con confirmación escrita, como el «borrar todos los datos» que ya existe en el
  grupo Datos de Ajustes.

**Datos locales de la sesión.** El token no va en la tabla `ajustes`: esa tabla **se exporta
en la copia de seguridad** (`copia.dart:131`), y un token de sesión dentro de un JSON que el
usuario comparte por correo es una fuga. Va en el almacenamiento seguro de la plataforma
(`flutter_secure_storage`, Keystore en Android) o, si se prefiere no añadir otra
dependencia, en una tabla `sesion_remota` **explícitamente excluida de la exportación**. La
primera opción es la correcta; la segunda es la aceptable. Lo que no es aceptable es la
tabla `ajustes`.

### K4. Modelo de sincronización

**Problema.**

El esquema actual está pensado para un dispositivo y se le nota en tres sitios:

1. **Las claves primarias son `autoIncrement`.** El id 7 es una rutina distinta en cada
   móvil. No hay forma de decir «esta fila es aquella».
2. **No hay marca de tiempo de modificación en ninguna tabla.** `entrenamientos.fecha` es
   cuándo se entrenó, no cuándo se editó la fila. Sin eso no hay delta que calcular.
3. **Borrar no deja rastro.** Un `DELETE` desaparece, así que un borrado en el móvil A no se
   distingue, desde B, de una fila que B tiene y A nunca tuvo.

**Comportamiento: sincronización por delta, con versión por fila.**

Tres columnas nuevas en cada tabla sincronizable:

```dart
/// Identidad estable entre dispositivos. Se genera al insertar y no cambia nunca.
TextColumn get uuid => text().unique()();

/// Cuándo se tocó la fila por última vez, en milisegundos desde época, UTC.
IntColumn get actualizado => integer()();

/// Lápida. Una fila borrada se marca, no se elimina.
BoolColumn get borrado => boolean().withDefault(const Constant(false))();
```

Y **la clave primaria entera se queda como está**. Esto es lo más importante del bloque y
hay que subrayarlo:

> **El `uuid` es una identidad *añadida*, no un sustituto de la clave primaria.** Todas las
> consultas de `bd.dart`, todos los joins, todos los `family` de los providers y todas las
> rutas de navegación siguen trabajando con `int`. El `uuid` solo lo usa la capa de
> sincronización, para traducir de identidad global a identidad local al entrar y al salir.
> La alternativa —claves primarias de texto— obligaría a reescribir 2.252 líneas de
> `bd.dart`, quince pantallas y 291 tests, con un riesgo desproporcionado y sin ninguna
> ventaja para el usuario.

**Cómo se traducen las relaciones.** Una serie apunta a su entrenamiento y a su ejercicio
por `int`. En el paquete que viaja, esos dos campos van por `uuid`; al recibir, la capa de
sincronización resuelve `uuid → id local` con un índice, y si el padre todavía no ha
llegado, la fila queda en cuarentena hasta que llegue (el orden de aplicación es rutinas →
ejercicios → entrenamientos → series, así que en la práctica no ocurre, pero el caso hay que
tratarlo o un paquete parcial rompe las claves foráneas, que están activas:
`PRAGMA foreign_keys = ON`).

**El delta.** Sin tabla de cola de salida:

- **Subir**: las filas con `actualizado > cursorSubida`.
- **Bajar**: se pide al servidor lo que tenga con `actualizado > cursorBajada`.
- Los dos cursores son dos claves en `ajustes`... **no**: van con el resto del estado de
  sincronización, en su propia tabla `sincro_estado`, por el mismo motivo del token —
  `ajustes` se exporta, y un cursor importado desde otro móvil haría que la sincronización
  se saltara datos.

> **Por qué sin cola de salida.** Una tabla `outbox` con una fila por cambio pendiente es el
> patrón habitual, y aquí sobra: como la unidad de reconciliación es **la fila entera**
> (LWW, [K5](#k5-conflictos)) y no el campo, «lo pendiente» se deduce de `actualizado`. Una
> tabla menos, un modo de fallo menos (una cola que se desincroniza de los datos que
> describe) y el mismo resultado. Es el mismo razonamiento por el que los récords se
> calculan en vez de guardarse.

**Quién pone el reloj.** `actualizado` lo escribe el **servidor** al aceptar la fila, y el
cliente guarda ese valor. El reloj del móvil no es de fiar: un usuario con la hora mal
puesta enviaría filas del año 2000 que perderían todos los conflictos, o del 2030 que los
ganarían todos para siempre. Localmente se usa un reloj monótono provisional hasta que el
servidor confirma, y en local **todo pasa por `datos/reloj.dart`**, que es la costura que
los tests adelantan. Esa regla ya existe en el proyecto para el descanso y el cronómetro; K
la extiende.

**Migración `schemaVersion` 7 → 8.** Es la migración más grande desde la v2:

```dart
Future<void> _de7A8(Migrator m, Schema8 esquema) async {
  for (final tabla in [rutinas, ejercicios, entrenamientos, serie, medidas,
                       favoritos, ajustesTabla]) {
    await m.addColumn(tabla, uuid);
    await m.addColumn(tabla, actualizado);
    await m.addColumn(tabla, borrado);
  }
  // Relleno: un uuid por fila existente y `actualizado` = ahora.
  // Se hace en Dart, fila a fila, porque SQLite no genera uuid.
}
```

**No es destructiva** —solo añade columnas y rellena—, pero **toca todas las filas de todas
las tablas**, incluida `serie`, que es la más numerosa. Con un historial de dos años son
unos pocos miles de filas: es rápido, pero se hace **dentro de una transacción** y con el
mismo respaldo previo del fichero que se hizo antes de la v2 (`datos/respaldo.dart`). El
respaldo ya está escrito y solo hay que volver a llamarlo; que exista es la razón por la que
esta migración no da miedo.

El `uuid` se genera con `Random.secure()` y formato v4 escrito a mano (36 caracteres). **No
hace falta el paquete `uuid`** para eso: son quince líneas y una dependencia menos, y aquí
las dependencias se cuentan.

### K5. Conflictos

**Problema.**

Dos dispositivos sin conexión editan lo mismo. Al reconectar hay que decidir, y la decisión
tiene que ser explicable en una frase o el usuario no confiará en ella.

**Comportamiento: último en escribir gana, con la fila como unidad.**

```
La fila con el `actualizado` más alto sustituye a la otra, entera.
```

**Por qué no una fusión por campos.** Fusionar campo a campo (el peso de A, las repeticiones
de B) produce filas que **nunca existieron en ningún dispositivo**: una serie de 8
repeticiones a 70 kg que nadie hizo. Con datos de entrenamiento eso es peor que perder una
edición, porque el usuario no puede detectarlo mirando.

**Por qué no CRDT.** Es la respuesta correcta para edición colaborativa en tiempo real. Aquí
hay **un usuario** en dos dispositivos que casi nunca usa a la vez, con datos que se añaden
mucho más de lo que se editan. El coste (metadatos por campo, un modelo que hay que entender
para depurarlo) no lo paga nadie.

**La excepción que sí hace falta: la sesión es la unidad, no la serie.** Un entrenamiento y
sus series se reconcilian **como un bloque**. Si A añadió una quinta serie y B corrigió el
peso de la segunda, no se mezclan: gana el entrenamiento con el `actualizado` más alto y sus
series son las que quedan. Mezclar daría una sesión con series de dos versiones, que es el
caso «una fila que nunca existió» llevado a su peor forma. En consecuencia, **editar
cualquier serie actualiza el `actualizado` de su entrenamiento**, que es lo que hace que el
bloque se comporte como una unidad.

**Los casos, y qué pasa en cada uno:**

| Caso | Resultado |
|---|---|
| A crea una rutina, B crea otra | Las dos. `uuid` distintos, no hay conflicto |
| A y B editan la misma rutina | Gana la más reciente, entera |
| A borra una rutina, B añade una sesión a esa rutina | **Gana el borrado** si es posterior; la sesión llega y se descarta con su padre. Si el borrado es anterior, la rutina revive con la sesión nueva |
| A y B registran la misma sesión (el mismo entrenamiento, dos veces) | **Quedan las dos.** No hay forma fiable de reconocer un duplicado, exactamente el mismo razonamiento que ya está escrito en `copia.dart` para el modo fusionar |
| A y B tocan el mismo ajuste | Gana el más reciente, por clave |
| El nombre de rutina choca (es `unique`) | El que pierde se renombra a `Nombre (2)`, y se avisa. Es lo que ya hace la importación de copias |

**Lo que el usuario ve.** Nada, en el caso normal. Solo se avisa de lo que **no se pudo
resolver sin perder algo**: una rutina renombrada por choque de nombre, o una sesión
duplicada detectada por fecha y rutina idénticas. Ese aviso va a una lista en la pantalla de
sincronización, con fecha, y se puede descartar. Un diálogo modal de resolución de
conflictos es exactamente lo que no hay que construir: interrumpe, obliga a decidir sobre
algo que el usuario no recuerda, y se dispara siempre en el peor momento.

### K6. Qué se sincroniza y qué no

Decidido tabla por tabla. Esta lista es la especificación: lo que no está aquí, no viaja.

| Tabla | ¿Sincroniza? | Por qué |
|---|---|---|
| `rutinas` | **Sí** | Es el dato central |
| `ejercicios` | **Sí** | Con su `orden`, su `descansoSeg` y su configuración de progresión (J2) |
| `entrenamientos` | **Sí** | El histórico |
| `serie` | **Sí**, como parte de su entrenamiento | [K5](#k5-conflictos) |
| `medidas` | **Sí** | Pocas filas, clave `(fecha, tipo)` que ya es única y estable entre dispositivos |
| `favoritos` | **Sí** | Es una preferencia del usuario sobre el catálogo, y el catálogo es idéntico en los dos móviles |
| `ajustes` | **Sí**, por clave, con LWW | Es lo que hace que los dos dispositivos se comporten igual: mismas unidades, mismo descanso, mismo idioma |
| `catalogo_ejercicios` | **No** | 1.324 filas regenerables desde un asset versionado. Subirlas sería pagar ancho de banda por un dato que ya está en el APK. Es la misma decisión que tomó `copia.dart` |
| `vistos` | **No** | Historial de navegación local, ruido puro. Sincronizarlo llenaría el delta de escrituras sin valor |
| `sesiones_activas` | **No** | Ver abajo |
| `sincro_estado` | **No** | Es el estado de la propia sincronización |

**La sesión viva no se sincroniza, y es una decisión, no un olvido.** «Empezar en el móvil y
seguir en la tableta» suena bien y es una trampa: el borrador se reescribe entero en cada
cambio, con *debounce* de 2 s (`borrador.dart`), así que sincronizarlo sería un flujo
constante de escrituras durante toda la sesión, y dos dispositivos con la misma sesión
abierta se pisarían sin parar sobre el dato más volátil que hay. El coste técnico es alto,
el beneficio es raro (nadie cambia de dispositivo a mitad de una serie) y el modo de fallo
es perder el entrenamiento en curso, que es el peor dato que se puede perder. Queda fuera y
se recoge en [N](#n-fuera-de-alcance).

**La media tampoco.** Las imágenes y GIFs son © Gym visual, se descargan del origen y no se
versionan ni se empaquetan (ver `CLAUDE.md`). Subirlas a un servidor propio sería
redistribuirlas fuera de las condiciones de la licencia. Cada dispositivo se las descarga,
como hace hoy.

### K7. El primer enlace

**Problema.**

El momento más peligroso de todo el bloque: un usuario con dos años de histórico local entra
por primera vez en una cuenta que puede tener datos o no tenerlos. Si eso se resuelve mal,
se le borra el histórico. Es el único punto de K donde una decisión automática es
inaceptable.

**Comportamiento.**

Al iniciar sesión, antes de sincronizar nada, la app mira qué hay a los dos lados y pregunta:

| Local | Remoto | Qué pasa |
|---|---|---|
| Vacío | Vacío | Se enlaza sin preguntar. No hay nada que decidir |
| Con datos | Vacío | Se sube todo, sin preguntar. Es el caso del primer dispositivo |
| Vacío | Con datos | Se baja todo, sin preguntar. Es el caso del segundo dispositivo |
| **Con datos** | **Con datos** | **Se pregunta**, con las tres salidas de abajo |

Las tres salidas del caso difícil, con el mismo vocabulario que ya usa la importación de
copias (`ModoImportacion`, `copia.dart:36`), que el usuario puede haber visto ya:

1. **Fusionar** (recomendada). Todo lo local sube y todo lo remoto baja; los choques se
   resuelven con las reglas de [K5](#k5-conflictos). Las rutinas con el mismo nombre y
   distinto `uuid` se renombran, no se mezclan.
2. **Este dispositivo manda.** Lo remoto se sustituye por lo local. Se avisa de cuántas
   sesiones se van a perder en la nube, con el número.
3. **La cuenta manda.** Lo local se sustituye por lo remoto. **Antes se exporta una copia
   de seguridad automática al almacenamiento del dispositivo**, sin preguntar, reutilizando
   `copia.exportar`. Es la salida que puede destruir dos años de datos y no se ofrece sin
   red de seguridad.

**Interfaz.** Una hoja con las tres opciones, cada una con su cifra: «Aquí: 3 rutinas, 214
sesiones. En la cuenta: 2 rutinas, 180 sesiones». Sin números, la pregunta no se puede
responder.

**Criterios de aceptación.**

- [ ] Los tres casos automáticos no preguntan nada.
- [ ] El cuarto pregunta siempre, y la opción destructiva exporta una copia antes.
- [ ] Fusionar dos bases con solapes deja el número de sesiones esperado, sin duplicar las
      que tienen el mismo `uuid` y sin fusionar las que no.
- [ ] Todo esto se prueba **sin red**, con dos `AppBD` en memoria y el transporte falso
      ([K10](#k10-la-costura-de-test)).

### K8. Interfaz

**El principio de [K1](#k1-el-principio-local-primero) aplicado: la sincronización se ve lo
menos posible.** No hay pestaña nueva —la decisión H1 del documento anterior sigue cerrada:
tres pestañas—, no hay pantalla de bienvenida obligatoria y no hay indicador permanente.

**a) Un grupo nuevo en Ajustes**, encima del grupo «Datos» que ya existe
(`pantallas/copia_seguridad.dart`), porque son vecinos temáticos:

```
┌──────────────────────────────────────────────┐
│  CUENTA                                      │
│                                              │
│  Sin cuenta                                  │
│  Tus datos están solo en este dispositivo.   │
│                                              │
│  [ Crear cuenta o entrar ]                   │
└──────────────────────────────────────────────┘
```

Y con sesión iniciada:

```
┌──────────────────────────────────────────────┐
│  CUENTA                                      │
│  Correo             jesus@ejemplo.com        │
│  Sincronizar                        [ ●  ]   │
│  Última vez           Hace 4 minutos    >    │
│  Dispositivos                    2      >    │
├──────────────────────────────────────────────┤
│  Sincronizar ahora                           │
│  Cerrar sesión                               │
│  Borrar la cuenta                            │
└──────────────────────────────────────────────┘
```

- «Última vez» lleva a una pantalla con el detalle: qué subió, qué bajó, los avisos de
  [K5](#k5-conflictos) y el último error si lo hubo.
- «Dispositivos» lista los enlazados con su último acceso, y permite revocar uno.
- «Borrar la cuenta» pide escribir el correo para confirmar, como el borrado de datos que ya
  existe.

**b) Un indicador, y solo cuando hace falta.** Si la última sincronización falló o hay
cambios pendientes desde hace más de un día, aparece una línea discreta en la cabecera de
Rutinas —el sitio donde se entra a la app—, pulsable, que lleva a Ajustes. Nada de un icono
girando permanente: sincronizar bien es lo normal y lo normal no se anuncia.

**c) Nunca en la ruta de entrenar.** Ni en la sesión viva, ni en el resumen de cierre, ni al
guardar. Si hay que avisar de algo, se avisa después.

**Cuándo sincroniza.** Todo en segundo plano, con la app en primer plano (no hay trabajo en
segundo plano, no hay permisos ni dependencias de eso):

| Disparador | Nota |
|---|---|
| Al arrancar la app | Después de `arranqueProvider`, sin bloquear el primer frame |
| Al volver del segundo plano | Con `AppLifecycleState.resumed`, y con un mínimo de 5 minutos entre intentos |
| Al guardar un entrenamiento | Es el cambio que importa, y el momento en que el usuario acaba de salir del gimnasio |
| Manualmente | El botón de Ajustes |
| **Nunca** durante una sesión viva | El borrador se escribe cada 2 s; sincronizar ahí es pelearse con el disco por nada |

Ante un fallo, reintento con espera creciente (5 s, 30 s, 2 min, 10 min) y parada hasta el
siguiente disparador. Sin bucle de reintentos infinito, que es como se agota una batería y
una cuota gratuita el mismo día.

### K9. Seguridad y privacidad

Los datos de entrenamiento son datos de salud en el sentido coloquial y, con las medidas
corporales (peso, grasa, perímetros) del bloque B13, en un sentido bastante literal. Salir
del dispositivo con ellos obliga a decir qué se hace.

**Lo que se guarda en el servidor.** Exactamente lo de la tabla de
[K6](#k6-qué-se-sincroniza-y-qué-no): rutinas, ejercicios, sesiones, series, medidas,
favoritos y preferencias. Y el correo, para la cuenta. **Nada más**: ni contactos, ni
localización, ni identificadores de publicidad, ni analítica. La app no tiene ninguna de esas
cosas hoy y este bloque no las trae.

**Aislamiento.** Cada fila lleva el `usuario.id` y el acceso se restringe en el servidor con
*row level security*: un usuario solo puede leer y escribir sus filas. Se comprueba con un
test contra el proyecto real —es el único test que necesita red y va marcado como tal, fuera
de la suite por defecto— que intenta leer los datos de otro usuario y espera un fallo.

**Transporte.** TLS, sin excepciones ni certificados propios.

**Cifrado extremo a extremo: evaluado y descartado, por ahora.** Cifrar en el cliente con una
clave que el servidor no tiene es lo más protector, y tiene dos costes que aquí pesan más:
el servidor no puede resolver nada sobre los datos (ni siquiera un borrado selectivo o una
migración de formato), y **perder la clave es perder los datos** sin recuperación posible,
que en una app sin contraseña —donde la recuperación es precisamente el correo— es un
agujero peor que el que tapa. Se documenta como camino futuro si el proyecto crece.

**Derechos del usuario.** Están casi resueltos porque B10 ya existe:

- **Portabilidad**: la exportación JSON/CSV ya está, y es un formato abierto y documentado.
- **Borrado**: «Borrar la cuenta» elimina las filas del servidor. Se confirma con un test.
- **Acceso**: lo mismo que la portabilidad.

**Lo que hay que escribir aparte.** Una política de privacidad, aunque sean quince líneas en
`docs/`, enlazada desde el «Acerca de» de Ajustes. En el momento en que hay una cuenta y un
servidor, no tenerla no es una opción.

### K10. La costura de test

**Este apartado es la condición de entrega del bloque, no un detalle de implementación.**

`CLAUDE.md` dice, sobre esta app frente a la versión Flet: *«aquí sí se puede comprobar todo
sin interfaz»*. K es el primer bloque capaz de romper esa frase, porque su lógica vive entre
dos dispositivos y un servidor. Se resuelve igual que se resolvieron `reloj.dart` y
`media.fijarDirectorioMedia`: con una costura.

```dart
/// Todo lo que la sincronización necesita del mundo exterior.
///
/// El motor no importa ningún SDK: habla con esto. La implementación real
/// (`SincroSupabase`) es un adaptador fino; la de test es un mapa en memoria.
abstract interface class SincroTransporte {
  Future<Sesion?> sesionActual();
  Future<void> entrar(String correo);
  Future<void> salir();

  /// Lo que el servidor tiene con `actualizado` posterior al cursor.
  Future<Paquete> bajar(int cursor);

  /// Envía filas y devuelve el `actualizado` que el servidor les puso.
  Future<RespuestaSubida> subir(Paquete paquete);

  Future<void> borrarCuenta();
}
```

Con eso, `test/sincro_test.dart` monta **dos `AppBD` en `NativeDatabase.memory()` y un
`SincroTransporte` falso**, y prueba todo lo que importa sin red, sin cuenta y sin
proveedor:

- A crea, sincroniza, B sincroniza → B lo ve.
- A y B editan lo mismo sin conexión → gana el más reciente, entero.
- A borra, B edita → la lápida se propaga y el resultado es determinista.
- Una sesión editada en los dos → queda una versión completa, nunca series mezcladas.
- El primer enlace, en sus cuatro casos ([K7](#k7-el-primer-enlace)).
- Series que llegan antes que su entrenamiento → cuarentena y aplicación correcta.
- El transporte falla a mitad de subida → nada queda a medias y el cursor no avanza.
- Reloj del cliente adelantado dos años → no gana todos los conflictos.

Esa última fila es la que justifica que `actualizado` lo ponga el servidor, y solo se puede
probar con la costura del reloj que ya existe.

**Regla de entrega: el motor se escribe y se prueba entero contra el transporte falso antes
de tocar el SDK del proveedor.** Es el mismo orden que funcionó en el bloque D, donde
`musculos.dart` y `geometria.dart` se hicieron con sus tests antes que la vista.

### K11. Operación, costes y forks

Un apartado que no suele estar en una especificación y que aquí hace falta, porque cambia lo
que el proyecto es.

**El coste.** El plan gratuito del proveedor da de sobra para un puñado de usuarios: los
datos de un año de entrenamiento son del orden de un megabyte por usuario. El problema no es
el volumen, es que **existe una factura posible** y un proyecto personal puede dejar de
pagarla. Mitigación, que es también la salida digna:

- La app funciona entera sin cuenta ([K1](#k1-el-principio-local-primero)).
- La exportación de B10 sigue estando y no depende de nada externo.
- Si el servicio se apaga, la app avisa una vez y sigue funcionando en local. **Ese
  comportamiento se prueba**, con el transporte falso devolviendo error permanente.

**El APK público.** Este repositorio publica una release por cada merge a `main`, y
cualquiera puede instalarla. Con la sincronización dentro, **cualquiera puede crear una
cuenta en el proyecto del autor**. Eso es cuota ajena y datos ajenos. Tres medidas:

1. La URL y la clave pública del proyecto entran por `--dart-define` desde secretos de
   GitHub, igual que ya entra `VERSION`. **No se escriben en el repositorio.**
2. Una compilación local sin esas variables deja la sincronización **desactivada y no
   visible**, igual que hoy una compilación local pone `local` en la versión. Un fork
   funciona sin cuenta y sin tocar nada.
3. El README dice, en una línea, que la sincronización de las releases oficiales apunta a un
   proyecto personal sin garantía de disponibilidad, y cómo apuntar la propia.

**CI.** Un job más, opcional y solo en `main`, que ejecuta los tests marcados como de red
contra el proyecto real. Si los secretos no están, se salta. Ese job **no bloquea** la
publicación del APK.

### K12. Criterios de aceptación y riesgos

**Criterios de aceptación.**

- [ ] Sin cuenta y sin red, la app se comporta **exactamente** como antes de este bloque.
      Se comprueba pasando los 291 tests anteriores sin modificar ninguno.
- [ ] `lib/datos/sincro/` es el único directorio que importa el SDK del proveedor. Hay un
      test que lo fija, como el que fija que no se importa `material.dart`.
- [ ] El motor de reconciliación no importa Flutter ni el SDK: recibe un `SincroTransporte`.
- [ ] `test/sincro_test.dart` cubre los ocho escenarios de [K10](#k10-la-costura-de-test),
      sin red.
- [ ] La migración 7 → 8 rellena `uuid` en todas las filas de todas las tablas
      sincronizables, pasa el test de migración desde cada versión anterior y hace el
      respaldo previo del fichero.
- [ ] Dos dispositivos con el mismo histórico convergen: tras sincronizar los dos, sus
      bases dan el mismo resumen (rutinas, sesiones, series, volumen total).
- [ ] Un fallo de red al guardar un entrenamiento **no** produce ningún aviso ni bloquea
      nada.
- [ ] Cerrar sesión conservando los datos deja la base local intacta y utilizable.
- [ ] Borrar la cuenta borra los datos remotos y deja los locales.
- [ ] El token de sesión **no** aparece en la exportación de la copia de seguridad. Test.
- [ ] Con la sincronización sin configurar (compilación local), el grupo de Ajustes no se
      enseña.
- [ ] `flutter analyze` en 0 issues y el APK sigue construyéndose en CI.

**Riesgos.**

| Riesgo | Mitigación |
|---|---|
| **Pérdida de datos en el primer enlace** | Es el riesgo número uno. La opción destructiva exporta una copia antes, automáticamente, y las cifras se enseñan antes de decidir ([K7](#k7-el-primer-enlace)) |
| Un fallo del motor corrompe la base local | Todo lo que entra va en transacción; el cursor no avanza si la transacción no cierra. Ocho escenarios de test y la migración con respaldo previo |
| La migración 7→8 sobre una base grande tarda o falla a la mitad | En transacción, con respaldo previo del fichero (`respaldo.dart`, ya escrito para la v2) y probada contra bases reales de todas las versiones anteriores |
| Dependencia de un servicio que puede cerrar, subir de precio o cambiar la API | Todo detrás de `SincroTransporte`; el motor y sus tests no lo conocen. Cambiar de proveedor es un adaptador |
| La dependencia más grande del proyecto entra por esto | Aislada en un directorio, con un test que lo fija, y desactivable en compilación |
| Cuentas ajenas en el proyecto personal del autor | Configuración por `--dart-define` desde secretos; sin ella, la funcionalidad no existe en el binario |
| Los datos son sensibles y ahora salen del móvil | [K9](#k9-seguridad-y-privacidad): mínimo imprescindible, RLS, TLS, borrado real y política escrita |
| El bloque es tan grande que se queda a medias | El plan de entrega lo parte en cuatro fases publicables ([M](#m-plan-de-entrega)), y la primera (8a, copia automática) ya resuelve un caso de uso real por sí sola |

---

## L. Modelo de datos consolidado

Estado del esquema tras aplicar este documento entero. En **negrita**, lo nuevo respecto al
estado actual (v6).

```
rutinas              id, nombre, color, **uuid, actualizado, borrado**
ejercicios           id, idRutina, idCatalogo, nombre, descripcion, orden, descansoSeg,
                     **repMin, repMax, incrementoKg, estrategia**,
                     **uuid, actualizado, borrado**
catalogo_ejercicios  (sin cambios de columnas; cambia el contenido de `busqueda`,
                     que pasa a ser multilingüe — I4)
entrenamientos       id, idRutina, fecha, nota, duracionSeg,
                     **uuid, actualizado, borrado**
serie                id, idEntrenamiento, idEjercicio, nSerie, repeticiones, peso,
                     calentamiento, rpe, nota, **uuid, actualizado, borrado**
ajustes              clave, valor, **actualizado**
                     (+ claves nuevas: idioma, progresion_activa, rep_min, rep_max,
                      perfil_progresion, version_indice)
sesiones_activas     (sin cambios; no se sincroniza)
favoritos            idCatalogo, creado, **uuid, actualizado, borrado**
vistos               (sin cambios; no se sincroniza)
medidas              id, fecha, tipo, valor, **uuid, actualizado, borrado**
**sincro_estado**    clave, valor — cursores y estado de la sincronización, fuera de
                     `ajustes` a propósito: `ajustes` se exporta en la copia de seguridad
```

**Secuencia de `schemaVersion`:**

| Versión | Contenido | Destructiva | Estado |
|---|---|---|---|
| 1–6 | Todo el documento anterior | Solo la 2 | **Hechas** |
| 7 | **J2** — `repMin`, `repMax`, `incrementoKg`, `estrategia` en `ejercicios` | No | Prevista |
| 8 | **K4** — `uuid`, `actualizado`, `borrado` en las tablas sincronizables, y la tabla `sincro_estado` | No, pero toca todas las filas | Prevista |

El bloque I **no cambia el esquema**: el idioma es una clave más en la tabla de clave/valor,
y `busqueda` ya existe. Lo que sí necesita es una resiembra del catálogo, disparada por la
clave `version_indice` ([I4](#i4-el-catálogo-y-el-índice-de-búsqueda)).

**Formato de la copia de seguridad.** `versionCopia` (`copia.dart:34`) pasa de **2 a 3**:

| Cambio | Bloque |
|---|---|
| Los ejercicios llevan `repMin`, `repMax`, `incrementoKg`, `estrategia` | J2 |
| Las filas llevan su `uuid`, para que una copia restaurada en otro móvil no duplique al sincronizar | K4 |
| Se exportan las claves de ajustes nuevas (ya entra la tabla entera, no hay cambio de código) | I6, J2 |

Una copia de la versión 2 se sigue importando: lo que falta entra como `null` —que en J2 es
«como el global»— y los `uuid` que falten se generan al importar. **Hay que ampliar el test
de ida y vuelta de `copia_test.dart` con una copia v2 real**, o el compromiso no es
verificable.

Y **el token de sesión no entra en la copia** ([K3](#k3-cuentas-e-identidad)), ni los
cursores de sincronización ([K4](#k4-modelo-de-sincronización)). Es el único dato de la app
que se guarda fuera de la base o en una tabla excluida, y ese es exactamente el motivo.

---

## M. Plan de entrega

Continuación del plan del documento anterior, que llegó hasta la **Fase 5** (mapa muscular).
Cada fase deja la app funcionando y es publicable por separado.

### Fase 6 — Internacionalización

Bloque **I** completo, en este orden:

1. **I1** (mecanismo): `l10n.yaml`, los dos ARB vacíos, la extensión `context.t`, el paso en
   CI, `intl` en `pubspec.yaml` y el ayudante de test fijando `Locale('es')`. Sin traducir
   nada todavía. **Este paso es el que hace que todos los demás sean seguros.**
2. **I3** (formatos): `formato.dart` a `DateFormat`/`NumberFormat` y los plurales ICU, con
   su test nuevo en los dos idiomas. Va antes que las pantallas porque casi todas lo usan.
3. **I2** (pantallas): quince commits, uno por pantalla, de menos textos a más. Los tests
   existentes van en verde todo el rato.
4. **I4** (catálogo) y **I5** (plantillas y vocabularios), que son los que tocan datos y
   tienen sus propios tests de cobertura.
5. **I6** (elegir idioma) y **I7** (el grupo de tests en inglés y el test de cobertura de
   claves).

Publicable al final, y también al final del paso 3 si hiciera falta cortar: con la app
todavía solo en español, pero con el texto ya separado del código.

### Fase 7 — Progresiones

Bloque **J** completo, en dos tiempos, como se hizo en la fase 5:

1. **Primero la lógica, sin interfaz.** `lib/datos/progresion.dart` con
   `test/progresion_test.dart` cubriendo los ocho escenarios de [J6](#j6-criterios-de-aceptación-y-riesgos).
   Nada de esto necesita pantalla, y es donde está la dificultad real.
2. **Después la vista y el esquema.** Migración 6 → 7, la configuración por ejercicio (J2),
   `ui.Sugerencia` con su test a 375 px, la línea en la tarjeta de entrenar y la tarjeta en
   resultados (J3), el estancamiento en el resumen semanal (J4), y la subida de
   `versionCopia` a 3.

Es la fase más barata de las tres y la que más se nota al usar la app.

### Fase 8a — Copia automática a la nube del usuario

**El escalón intermedio de K**, y probablemente suficiente para mucha gente: la exportación
de B10, automatizada y subida a la nube del propio usuario (Drive, Archivos, la carpeta que
tenga sincronizada), con una frecuencia configurable.

- No hay cuentas, no hay backend, no hay conflictos. No es sincronización y la interfaz no
  debe llamarlo así: es **«Copia automática»**, en el grupo Datos que ya existe.
- Reutiliza `copia.dart` entero. El trabajo real es el destino y el disparador.
- Sirve para restaurar en un móvil nuevo, que es el caso más común detrás de «lo quiero en
  la nube».

Se entrega antes que 8b y **puede quedarse ahí indefinidamente** si la decisión de
[O](#o-decisiones-pendientes) sobre el backend se cierra en contra. Ese es el motivo de que
sea una fase propia y no un paso de la siguiente.

### Fase 8b — Sincronización: el motor

Bloque **K**, la mitad que no se ve, y **sin ningún SDK todavía**:

1. Migración 7 → 8 (`uuid`, `actualizado`, `borrado`, `sincro_estado`), con su respaldo
   previo y sus tests de migración.
2. `SincroTransporte` y la implementación falsa en memoria.
3. El motor de reconciliación, con los ocho escenarios de
   [K10](#k10-la-costura-de-test) en verde.
4. La lógica del primer enlace ([K7](#k7-el-primer-enlace)) con sus cuatro casos.

Al terminar esta fase **el APK no cambia para el usuario**: no hay pantalla, no hay cuenta y
no hay red. Pero está hecha la parte difícil y está probada entera.

### Fase 8c — Sincronización: el servicio

1. El adaptador del proveedor, aislado en `lib/datos/sincro/`.
2. Cuentas: entrar por enlace mágico, cerrar sesión, borrar la cuenta ([K3](#k3-cuentas-e-identidad)).
3. La interfaz de Ajustes y el indicador ([K8](#k8-interfaz)).
4. Los disparadores y la espera creciente.
5. La configuración por `--dart-define` y los secretos de CI ([K11](#k11-operación-costes-y-forks)).
6. La política de privacidad en `docs/` y su enlace desde «Acerca de».

**Dependencias entre bloques.** Solo una, y es blanda: J y K escriben texto que el usuario
lee, así que se benefician de que I esté hecho. Si por lo que fuera hubiera que alterar el
orden, J y K son independientes entre sí y de I; lo único que pasaría es que habría que
volver a barrer sus pantallas.

---

## N. Fuera de alcance

Se deja fuera de esta iteración, de forma consciente. Varias siguen viniendo del documento
anterior, donde ya se descartaron y **siguen descartadas por el mismo motivo**.

**Nuevas de este documento:**

- **La sesión viva no se sincroniza.** Empezar en un dispositivo y continuar en otro. El
  razonamiento entero está en [K6](#k6-qué-se-sincroniza-y-qué-no): coste alto, uso raro y
  el peor dato posible que perder.
- **Compartir con otras personas.** Rutinas públicas, seguir a alguien, entrenador y
  atleta, comparar con amigos. Todo eso exige un modelo de permisos que no existe y
  moderación que no hay quien haga. La sincronización de este documento es de **un usuario
  con sus dispositivos**, y el modelo de datos que se elige lo refleja.
- **Cifrado extremo a extremo.** Evaluado en [K9](#k9-seguridad-y-privacidad) y aplazado:
  con una autenticación sin contraseña, perder la clave sería perderlo todo.
- **Sincronización en tiempo real.** Ver los cambios aparecer en la tableta mientras se
  escriben en el móvil. El proveedor lo ofrece; el caso de uso no existe para un usuario
  solo, y mantener una conexión abierta gasta batería a cambio de nada.
- **Resolución manual de conflictos.** Ningún diálogo de «elige cuál conservar»
  ([K5](#k5-conflictos)).
- **Traducción de los nombres de ejercicio.** 1.324 nombres que el dataset solo trae en
  inglés y que en el gimnasio se dicen en inglés ([I4](#i4-el-catálogo-y-el-índice-de-búsqueda)).
- **Idiomas más allá del español y el inglés.** El mecanismo los admite y el test de
  cobertura los exigiría completos; añadir uno es traducir dos ficheros ARB, un mapa de
  vocabulario y las plantillas. No se hace hasta que alguien lo pida.
- **Aplicar las progresiones automáticamente**, y con ellas cualquier forma de
  «entrenador automático» que planifique la sesión entera ([J3](#j3-dónde-aparece-la-sugerencia)).
- **Progresiones basadas en modelos** (ajuste de curvas, aprendizaje automático sobre el
  histórico). Con los datos de un usuario personal, un modelo estadístico no supera a una
  regla explicable, y una regla explicable se puede enseñar en una línea en la tarjeta.
- **Notificaciones.** Ni de descanso, ni de «te toca entrenar», ni de sincronización. Traen
  permisos, trabajo en segundo plano y al menos una dependencia.

**Que siguen fuera, del documento anterior:**

- **Integración con relojes o wearables** (Health Connect, HealthKit).
- **Publicación en tiendas.** El APK se sigue instalando a mano desde las releases.
- **Vídeos o media adicional.** Se mantiene la relación actual con el dataset de Gym visual
  y sus condiciones de uso — y por eso la media tampoco se sincroniza
  ([K6](#k6-qué-se-sincroniza-y-qué-no)).
- **Ejercicios personalizados con músculo asignado.** Lo sigue pidiendo el bloque D y sigue
  sin abordarse.

---

## O. Decisiones pendientes

Cuestiones abiertas. Las tres primeras conviene cerrarlas **antes** de empezar su bloque;
las demás se pueden cerrar durante.

1. **¿Se hace K completo, o basta con la Fase 8a?**
   Es la decisión más cara del documento. 8a (copia automática a la nube del usuario)
   resuelve «no quiero perder mis datos y quiero recuperarlos en un móvil nuevo» sin
   backend, sin cuentas y sin coste. 8b+8c resuelve «quiero entrenar en el móvil y revisar
   en la tableta», que es otra cosa y cuesta un orden de magnitud más.
   **Recomendación:** entregar 8a igualmente —es útil por sí sola y barata—, y decidir 8b/8c
   después de usarla un par de meses. Si con la copia automática el problema desaparece, la
   respuesta ya está.

2. **¿Qué proveedor, si se hace K completo?** ([K2](#k2-elección-de-backend))
   **Recomendación:** Supabase, por el encaje relacional y la RLS, con todo detrás de
   `SincroTransporte` para que la decisión sea reversible. La alternativa seria es un
   backend propio, que duplica el proyecto.

3. **¿El inglés es el segundo idioma?** ([I1](#i1-mecanismo-de-traducción))
   Es el que más alcance da por el mismo esfuerzo y el que ya está medio hecho, porque el
   catálogo viene en inglés. **Recomendación:** sí. Si el objetivo real fuera otro mercado
   concreto, la elección cambia y el mecanismo no.

4. **¿El rango de repeticiones por defecto es 8–12?** ([J1](#j1-el-modelo-de-progresión))
   Es lo más común en hipertrofia y el peor sitio posible para un usuario de fuerza pura.
   **Recomendación:** 8–12 de fábrica y, la primera vez que un ejercicio tenga tres sesiones
   con un rango claramente distinto, proponer ajustarlo en vez de sugerir contra él.

5. **¿La descarga baja un 10 % o vuelve al último peso donde se completó el rango?**
   ([J4](#j4-estancamiento-y-descarga))
   El 10 % es simple y explicable; volver al último peso completado usa datos reales del
   usuario y suele ser más ajustado.
   **Recomendación:** el último peso completado si existe en el historial, y el 10 % como
   respaldo. Se decide con los tests delante, que para eso el módulo es puro.

6. **¿`flutter_secure_storage` para el token, o una tabla excluida de la exportación?**
   ([K3](#k3-cuentas-e-identidad))
   **Recomendación:** el almacenamiento seguro. Es una dependencia más, pero la alternativa
   confía en que nadie amplíe nunca la exportación sin acordarse de excluir esa tabla, y eso
   es exactamente el tipo de compromiso que se rompe solo.

7. **¿Se sincroniza `ajustes` entero, o hay preferencias de dispositivo?**
   ([K6](#k6-qué-se-sincroniza-y-qué-no))
   El tema y el idioma podrían querer ser distintos en el móvil y en la tableta.
   **Recomendación:** entero, que es lo predecible; si aparece la queja, se marca un puñado
   de claves como locales, y el modelo de clave/valor lo admite sin migración.

8. **¿La sugerencia de progresión aparece también en la sesión viva (B8), o solo en el
   registro clásico?** ([J3](#j3-dónde-aparece-la-sugerencia))
   La sesión viva es la pantalla más densa de la app y la que menos admite un elemento más.
   **Recomendación:** en las dos, pero en la sesión viva solo antes de marcar la primera
   serie del ejercicio, y desapareciendo en cuanto se marca. Se decide viendo la pantalla,
   que es de las pocas cosas de este documento que no se puede decidir sobre el papel.
