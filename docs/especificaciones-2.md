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
> Escrito sobre el código actual: **Flutter 3.44.8 / Dart 3.12.2**, `drift` sobre SQLite,
> `Riverpod` para el estado, interfaz **solo Cupertino**, catálogo de 1.324 ejercicios,
> nueve dependencias y `flutter analyze` en 0 issues. Ver `CLAUDE.md` para la arquitectura
> vigente.
>
> **Estado: los tres bloques están implementados.** I en la [Fase 6](#fase-6--internacionalización-),
> J en la [Fase 7](#fase-7--progresiones-) y K entero en las [fases 8a](#fase-8a--copia-automática-a-la-nube-del-usuario-),
> [8b](#fase-8b--sincronización-el-motor-) y [8c](#fase-8c--sincronización-el-servicio-):
> el esquema en la **v8**, la copia en la **v4**, la app en español e inglés y **583
> tests**. J se entregó antes que I, invirtiendo el orden que este documento recomienda;
> el motivo y lo que costó están en la [Fase 7](#fase-7--progresiones-).

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
  - [I8. Desviaciones al implementar](#i8-desviaciones-al-implementar)
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

  > **Al final J se entregó antes**, así que ese coste se ha asumido: cuando llegue I habrá
  > que barrer también `pantallas/sugerencia.dart` y `pantallas/opciones_ejercicio.dart`.
  > Son dos ficheros y unas veinte frases, y lo que de verdad importaba —que la lógica no
  > tenga texto dentro— sí se respetó: `progresion.dart` devuelve el motivo como enumerado y
  > no compone ni una cadena.
- **J va segundo** porque es autocontenido: un módulo puro con la forma de `metricas.dart`,
  un par de columnas y un sitio donde enseñar el resultado. No depende de K y no bloquea a
  nadie. Es también el bloque con mejor relación entre lo que aporta y lo que cuesta.
- **K va último** porque cambia la naturaleza del proyecto y porque su migración de esquema
  toca todas las tablas. Cuanto más estable esté el modelo de datos cuando llegue, menos
  probable es tener que repetir la operación.

---

## I. Internacionalización de la interfaz ✅

> **Implementado en la [Fase 6](#fase-6--internacionalización-).** Lo que sigue se
> conserva como el porqué de lo que hay; lo que se hizo distinto está en
> [I8](#i8-desviaciones-al-implementar).

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


### I8. Desviaciones al implementar

Seis, y ninguna cambia lo que ve el usuario salvo la última, que le da algo que este
documento no había previsto.

1. **`context.t` no vive en `tema/ui.dart`.** [I1](#i1-mecanismo-de-traducción) lo ponía
   ahí, pero [I2](#i2-extracción-de-los-textos-de-las-pantallas) exige que `ui.dart` no
   importe `Textos` —un componente compartido no debe saber en qué idioma está la app—, y
   las dos cosas no caben juntas. Vive en `lib/l10n/textos.dart`, que reexporta lo
   generado y es el único fichero que alguien importa: la carpeta `generado/` no se
   versiona y nadie la nombra.

2. **`idiomasSoportados` se declara a mano.** `Textos.supportedLocales` sale ordenada
   alfabéticamente, así que pondría el inglés delante, y con «Automático» Flutter cae al
   **primero** de la lista. La constante fija el español el primero y un test comprueba
   que los dos conjuntos de idiomas coinciden.

3. **`Formato` recibe los `Textos`.** [I3](#i3-fechas-números-unidades-y-plurales) lo
   quería sin importar Flutter, pero los relativos («Hace 3 días») salen de una clave ICU,
   que vive en `Textos`. Devolver el motivo como dato y componer la frase en cada pantalla
   habría repartido el `switch` de umbrales por quince ficheros. Sigue sin conocer el
   `BuildContext`, que es lo que el criterio pedía de verdad, y `metricas.dart` sigue sin
   saber de idiomas.

4. **El idioma sale del árbol de widgets, no de la preferencia.** `formatoDe(context, ref)`
   lee `Localizations.localeOf`, que es el que `CupertinoApp` resolvió de verdad; leerlo de
   la preferencia haría que «Automático» o un `es_AR` formatearan en un idioma y tradujeran
   en otro. Hay una segunda forma, `leerFormato`, para los callbacks: `ref.watch` solo vale
   dentro de `build`.

5. **`datos/copia.dart` también recibe los `Textos`.** El bloque acotaba el barrido a
   `lib/pantallas` y `lib/tema`, pero ese módulo componía en español los errores de
   validación, los avisos de importación y el sufijo «(importada)» que **acaba escrito en
   la tabla `rutinas`**. Dejarlo fuera habría enseñado frases en español dentro de la app
   en inglés.

6. **Las instrucciones de los ejercicios sí se traducen.** [I4](#i4-el-catálogo-y-el-índice-de-búsqueda)
   solo hablaba de los nombres y de las categorías, y daba por hecho lo demás; pero los
   pasos de `assets/ejercicios.es.json` estaban solo en español y son lo que más se lee de
   una ficha. El dataset original los trae en inglés y su español coincide **exactamente**
   con el nuestro, así que `tool/instrucciones_en.py` los baja a
   `assets/instrucciones.en.json` (633 KB) y la columna `instrucciones` pasa a guardar un
   mapa por idioma. Sin cambio de esquema: la resiembra por `version_indice` que este
   bloque ya exigía lo cubre, y `pasosDe` admite además la lista suelta de antes para que
   una base sin resembrar todavía no se quede sin instrucciones.

**Lo que costó, en números.** Unas 380 claves en cada ARB, 21 ficheros de `lib/`
tocados, 47 tests nuevos (de 343 a 390) y dos aserciones numéricas cambiadas —las del
separador de miles, que es justo lo que [I3](#i3-fechas-números-unidades-y-plurales)
arregla—. Ninguna aserción de texto en español se tocó, que era el criterio caro.

**Lo único que queda en español dentro de `lib/pantallas` y `lib/tema`** son los
separadores « · » de las líneas compuestas, dos mensajes de `assert` —que son para quien
programa— y el `'Español'` del selector de idioma, que va en su propio idioma a propósito:
un idioma se ofrece con su nombre, o quien no entiende el activo no sabe cuál elegir.

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

- [x] `lib/datos/progresion.dart` no importa Flutter ni escribe en la base. Es un módulo
      puro, como `metricas.dart` y `musculos.dart`. Importa solo `bd.dart`, por los tipos.
- [x] `test/progresion_test.dart` cubre, con historiales escritos a mano:
      rango completado → sube peso; rango incompleto → sube repeticiones; repeticiones
      caídas → baja peso; RPE ≥ 9,5 → mantiene aunque tocara subir; tres sesiones sin
      mejora → descarga; menos de dos sesiones → `null`; ejercicio de peso corporal → solo
      repeticiones; cardio → `null`. Son 39 tests: los ocho de aquí más los perfiles, la
      descarga que no se repite, el rango observado y la resolución por capas.
- [x] El peso sugerido es **siempre** un múltiplo del escalón vigente, en kilogramos, con
      el usuario en libras incluido. Hay un test específico, y comprueba además que el
      valor cae donde el selector de peso lo puede enseñar.
- [x] Con `progresionActiva` en falso, ni la tarjeta de entrenar ni la de resultados
      enseñan nada, y no se calcula: se comprueba que el provider no se pide, con un espía
      que lo sobrescribe.
- [x] La migración 6 → 7 pasa el test de migración desde cada versión anterior y el esquema
      resultante coincide con el volcado.
- [x] Una copia de seguridad de la versión 2 se importa sin errores y deja las cuatro
      columnas nuevas en `null`.
- [x] La línea de sugerencia no desborda a 375 px. Test con `_comoUnMovil` — que además
      cazó un desbordamiento real en la hoja de opciones antes de verse en un móvil.
- [x] Aplicar una sugerencia **no** guarda nada: solo cambia los valores del formulario.
- [x] Descartar una sugerencia la mantiene descartada al navegar a la ficha y volver (vive
      en el borrador), y vuelve a aparecer en la sesión siguiente.

**Desviaciones de lo implementado.**

1. **`ResumenSesionEjercicio` no traía las repeticiones totales.** Tenía `nSeries`,
   `volumen`, `pesoMaximo` y las dos estimaciones de 1RM, pero no la suma de repeticiones,
   que es lo que necesitan tanto el estancamiento ([J4](#j4-estancamiento-y-descarga)) como
   saber si una sesión completó el rango. Se añadió `SUM(s.repeticiones)` a la consulta y el
   campo a la clase: un agregado más en un `GROUP BY` que ya existía, no una consulta nueva.
2. **La regla del esfuerzo no necesitó ninguna consulta.** Ninguna vista devuelve el RPE
   junto a la fecha de sesión, y parecía el hueco del bloque; pero el RPE solo se mira en
   **la última** sesión, y `ultimasSeriesEjercicio` ya devuelve `ValoresSerie` con el suyo.
3. **No existía «la hoja de opciones del ejercicio dentro de una rutina»** que
   [J2](#j2-configuración-por-ejercicio) daba por hecha: el descanso propio se elegía con
   una pulsación larga sobre el temporizador de la tarjeta, y era un selector suelto. Se
   creó esa hoja (`pantallas/opciones_ejercicio.dart`), el descanso pasó a ser su primera
   fila —que es literalmente el boceto de J2— y se abre desde el mismo gesto de siempre y
   desde el detalle de la rutina, manteniendo pulsado el ejercicio.
4. **La descarga vuelve al último peso donde se completó el rango**, con el −10 % de
   respaldo (decisión [O5](#o-decisiones-pendientes)). Como el historial viene agregado, «se
   completó el rango» se deduce de `repeticiones >= nSeries * repMax`. Es exacto salvo que
   alguien pase del tope en unas series y no llegue en otras, que es un caso que la
   sugerencia de aquella sesión ya corrigió.
5. **`ajustes.pasoPeso` está en la unidad activa, no en kilos**, cosa que J2 no decía: es lo
   que alimenta el selector de peso. La columna `incrementoKg` sí es kilos, como pedía. La
   conversión se hace en un solo sitio, al resolver la configuración, y es lo que hace que
   el peso sugerido salga redondo también con el usuario en libras.
6. **«No fiable» no incluye «el usuario no registra el esfuerzo».** J1 lo listaba, pero con
   el RPE apagado de fábrica eso marcaría **todas** las sugerencias y vaciaría la marca de
   significado. Marca lo que de verdad es dudoso: menos de tres sesiones de historial, o el
   esfuerzo activado y sin anotar en la última sesión.
7. **La sugerencia también aparece en la sesión viva** (decisión
   [O8](#o-decisiones-pendientes)), pero solo antes de marcar la primera serie del
   ejercicio: al marcarla desaparece. Y no aparece nunca al **editar** una sesión guardada,
   que J3 no contemplaba — lo que se está anotando ahí ya pasó.
8. **El estancamiento sale de una consulta nueva**, `resumenSesionesTodos`: el mismo
   `GROUP BY` sin el filtro de ejercicio. La línea del resumen semanal necesita todos los
   ejercicios a la vez, y pedirlos de uno en uno habría sido una consulta por ejercicio de
   la app. El reparto y la detección siguen en el módulo puro.
9. **`bd.dart` reexporta `Value` de drift.** Lo pide `fijarProgresionEjercicio`, cuyos
   parámetros son `Value<T>` y no `T?` porque aquí `null` es un valor con significado —«como
   el global»— y hay que poder distinguirlo de «esta llamada no toca esa columna». Es el
   único símbolo de drift que asoma fuera de `datos/`.

**Riesgos.**

| Riesgo | Mitigación |
|---|---|
| La sugerencia es mala y el usuario la sigue | No se aplica sola, se explica el motivo en una línea, y la descarga lleva la nota de sus límites. La app propone lo que se deduce de los datos, y lo dice |
| Un usuario que hace 5×5 ve sugerencias de 8–12 sin parar | El rango es configurable por ejercicio ([J2](#j2-configuración-por-ejercicio)), y el ejercicio detecta el rango real del historial para proponer la configuración la primera vez |
| Una línea más en una tarjeta ya densa | Es descartable, ocupa dos líneas de texto y no aparece cuando no hay sugerencia — que es siempre en las dos primeras sesiones de cada ejercicio |
| El cálculo en cada repintado de la tarjeta | Va en su provider, cacheado por Riverpod, y se invalida solo al guardar una sesión. Es un recorrido en memoria sobre datos ya consultados |
| Cuatro columnas más en `ejercicios` que casi siempre son `null` | Son anulables y sin índice: en SQLite una columna nula ocupa un byte por fila |

---

## K. Sincronización en la nube, cuentas y multidispositivo ✅

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

> **Estado. El bloque K está entregado entero**: la **fase 8a** (copia automática), la
> **8b** (el motor) y la **8c** (el adaptador, las cuentas y la pantalla). Este apartado es
> la especificación tal y como se escribió, y se conserva como el porqué.
>
> Al implementar 8b se desviaron once cosas de lo que aquí se preveía, y al implementar 8c
> otras diez; están enumeradas y razonadas en
> [las once desviaciones de la fase 8b](#las-once-desviaciones-de-la-fase-8b) y en
> [las diez desviaciones de la fase 8c](#las-diez-desviaciones-de-la-fase-8c). Las que
> cambian lo que este apartado dice son seis:
>
> - **8b:** las lápidas van en su propia tabla en vez de en una columna `borrado`, la tabla
>   `serie` no lleva identidad ni versión, y **el reloj no decide un conflicto**.
> - **8c:** se entra con un **código de seis cifras** y no con un enlace mágico ([K3](#k3-cuentas-e-identidad));
>   **no hay SDK** —Supabase se habla REST, cero dependencias nuevas ([K2](#k2-elección-de-backend))—;
>   y **no hay fila «Dispositivos»** ([K8](#k8-interfaz)).

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

**Criterios de aceptación. Todos cumplidos**, entre las fases 8b y 8c. El primero se
reformuló al implementarlo y se explica en su propia línea.

- [x] Sin cuenta y sin red, la app se comporta **exactamente** como antes de este bloque.
      Se comprueba pasando los 441 tests anteriores sin modificar ninguno —salvo los dos
      ajustes mecánicos que se explican en la fase 8b—.
- [x] `lib/datos/sincro/` es el único directorio que sabe del proveedor. **Reformulado al
      implementarlo, porque no hay SDK que aislar** (desviación 3): lo que fija
      `test/importaciones_test.dart` es que hablar con la red esté aislado en tres ficheros,
      que la costura no importe Flutter ni drift, que el motor no conozca a ningún proveedor
      y que la URL, la clave y las rutas REST solo aparezcan en el adaptador. De paso queda
      escrito el test de `material.dart`, que este mismo apartado daba por hecho y no lo
      estaba.
- [x] El motor de reconciliación no importa Flutter ni el SDK: recibe un `SincroTransporte`.
- [x] `test/sincro_test.dart` cubre los escenarios de [K10](#k10-la-costura-de-test), sin
      red. El de las series que llegan antes que su entrenamiento se prueba un nivel más
      arriba, por la desviación 7.
- [x] La migración 7 → 8 rellena `uuid` en todas las filas de todas las tablas que lo
      llevan, pasa el test de migración desde cada versión anterior y hace el respaldo
      previo del fichero.
- [x] Dos dispositivos con el mismo histórico convergen: tras sincronizar los dos, sus
      bases dan el mismo resumen (rutinas, sesiones, series, volumen total).
- [x] Un fallo de red al guardar un entrenamiento **no** produce ningún aviso ni bloquea
      nada: el motor no se llama desde la ruta de entrenar y un error del transporte se
      anota y se devuelve, sin tocar la base.
- [x] Cerrar sesión conservando los datos deja la base local intacta y utilizable. Test en
      `sincro_estado_test.dart`, junto con la otra salida —borrar los datos de este móvil—
      y con el reinicio de los cursores, que sin él dejaría medio histórico sin bajar al
      entrar con otra cuenta.
- [x] Borrar la cuenta borra los datos remotos y deja los locales. Test.
- [x] Ni el token ni los cursores de sincronización aparecen en la exportación de la copia
      de seguridad. Test, y ahora con el token ya existiendo: **no hace falta filtrarlo,
      porque no está en la base** —la sesión vive en el almacén seguro de la plataforma—. El
      interruptor de este dispositivo sí está en `ajustes`, y por eso está en
      `Claves.locales`, con su test.
- [x] Con la sincronización sin configurar (compilación local), el grupo de Ajustes no se
      enseña. Test de pantalla, que además comprueba que el grupo «Datos» —su vecino de más
      abajo— sigue estando: si el de la cuenta se pintara, se toparía con él al bajar.
- [x] `flutter analyze` en 0 issues y el APK sigue construyéndose en CI.

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
estado que tenía (v6). **Actualizado con lo que se construyó de verdad**: las diferencias con
lo que este apartado preveía están en las desviaciones 1, 2 y 3 de la
[fase 8b](#las-once-desviaciones-de-la-fase-8b).

```
rutinas              id, nombre, color, **uuid, actualizado**
ejercicios           id, idRutina, idCatalogo, nombre, descripcion, orden, descansoSeg,
                     **repMin, repMax, incrementoKg, estrategia**,
                     **uuid, actualizado**
catalogo_ejercicios  (sin cambios de columnas; cambia el contenido de `busqueda`,
                     que pasa a ser multilingüe — I4)
entrenamientos       id, idRutina, fecha, nota, duracionSeg,
                     **uuid, actualizado**
serie                (sin cambios: la sesión es la unidad de reconciliación y sus series
                     viajan dentro de ella, así que no necesitan identidad ni versión)
ajustes              clave, valor, **actualizado**
                     (+ claves nuevas: idioma, progresion_activa, rep_min, rep_max,
                      perfil_progresion, version_indice)
sesiones_activas     (sin cambios; no se sincroniza)
favoritos            idCatalogo, creado, **actualizado**
vistos               (sin cambios; no se sincroniza)
medidas              id, fecha, tipo, valor, **actualizado**
**lapidas**          tabla, clave, actualizado — lo que se borró aquí, para que el borrado
                     llegue al otro dispositivo. En una tabla y no en una columna `borrado`
                     por dentro: así el borrado sigue siendo un borrado y ninguna de las
                     cincuenta consultas de `bd.dart` tiene que filtrar
**sincro_estado**    id, cursorSubida, cursorBajada, ultimaSincro, subidas, bajadas,
                     avisos, ultimoError — una fila, fuera de `ajustes` a propósito:
                     `ajustes` se exporta en la copia de seguridad
```

Las tres tablas con `uuid` son aquellas cuya clave natural no sirve: una rutina se renombra,
un ejercicio no es único ni por nombre ni por catálogo, y dos sesiones del mismo día en la
misma rutina son dos sesiones. Las otras tres se identifican por la clave que ya tenían y que
es la misma en los dos móviles: `(fecha, tipo)`, `idCatalogo` y `clave`.

**Secuencia de `schemaVersion`:**

| Versión | Contenido | Destructiva | Estado |
|---|---|---|---|
| 1–6 | Todo el documento anterior | Solo la 2 | **Hechas** |
| 7 | **J2** — `repMin`, `repMax`, `incrementoKg`, `estrategia` en `ejercicios` | No | **Hecha** |
| 8 | **K4** — `uuid` y `actualizado` en las tablas sincronizables, más las tablas `lapidas` y `sincro_estado` | No, pero toca todas sus filas | **Hecha** |

El bloque I **no cambia el esquema**: el idioma es una clave más en la tabla de clave/valor,
y `busqueda` ya existe. Lo que sí necesita es una resiembra del catálogo, disparada por la
clave `version_indice` ([I4](#i4-el-catálogo-y-el-índice-de-búsqueda)).

**Formato de la copia de seguridad.** `versionCopia` pasa de **2 a 4**, y los dos escalones
están hechos:

| Cambio | Bloque | Versión |
|---|---|---|
| Los ejercicios llevan `repMin`, `repMax`, `incrementoKg`, `estrategia` | J2 | 3 |
| Las rutinas, los ejercicios y las sesiones llevan su `uuid`, para que una copia restaurada en otro móvil no duplique al sincronizar | K4 | 4 |
| Se exportan las claves de ajustes nuevas (ya entra la tabla entera, no hay cambio de código) | I6, J2 | 3 |

Una copia de la versión 2 o de la 3 se sigue importando: lo que falta entra como `null` —que
en J2 es «como el global»— y los `uuid` que falten se generan al importar. Y si el `uuid` que
viene ya está en esta base, también se genera uno nuevo: dos filas con la misma identidad no
son dos filas. `copia_test.dart` cubre los tres casos.

Y **el token de sesión no entra en la copia** ([K3](#k3-cuentas-e-identidad)), ni los
cursores de sincronización ([K4](#k4-modelo-de-sincronización)). Es el único dato de la app
que se guarda fuera de la base o en una tabla excluida, y ese es exactamente el motivo.

---

## M. Plan de entrega

Continuación del plan del documento anterior, que llegó hasta la **Fase 5** (mapa muscular).
Cada fase deja la app funcionando y es publicable por separado.

### Fase 6 — Internacionalización ✅

Hecha, y en el orden previsto salvo por una cosa: el mecanismo ([I1](#i1-mecanismo-de-traducción))
y los formatos ([I3](#i3-fechas-números-unidades-y-plurales)) fueron primero, como decía el
plan, pero las quince pantallas se agruparon en **dos tandas** en vez de quince commits, de
menos textos a más. El corte por pantalla no aportaba nada: lo que hacía seguro el barrido
era tener `flutter analyze` en 0 y los tests en verde al final de cada tanda, no el tamaño
del commit.

Las seis desviaciones están en [I8](#i8-desviaciones-al-implementar). La de fondo es la
sexta: las instrucciones de los ejercicios estaban solo en español y este bloque no las
mencionaba.

`schemaVersion` **no se mueve**: el bloque no toca ninguna tabla. Lo que sí cambia es lo
que se escribe en dos columnas —`busqueda` e `instrucciones`—, y para eso está la clave de
ajustes `version_indice`, que resiembra el catálogo una vez.

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

### Fase 7 — Progresiones ✅

Hecha, y en los dos tiempos previstos: primero `progresion.dart` con sus tests —donde
estaba la dificultad real y nada necesitaba pantalla— y después el esquema, la vista y la
copia. Se entregó **antes que la fase 6**, que sigue pendiente: J no depende de I, así que
los textos de este bloque están escritos en español en el código como el resto de la app, y
el motivo de cada sugerencia viaja **como dato** hasta la pantalla —que es donde se compone
la frase— precisamente para que la internacionalización no tenga que tocar la lógica.

`schemaVersion` pasa a 7 con la migración más inocua del proyecto: cuatro columnas
anulables donde `null` significa «como el global». `versionCopia` pasa a 3.

Lo que no estaba previsto y apareció al implementar está en las nueve desviaciones de
[J6](#j6-criterios-de-aceptación-y-riesgos). La de fondo es la primera: el historial por
sesión no traía las repeticiones totales, y sin ellas ni el estancamiento ni «esta sesión
completó el rango» se pueden calcular. La más visible, la tercera: la hoja de opciones del
ejercicio que J2 daba por existente había que construirla.

Es la fase más barata de las tres y la que más se nota al usar la app.

### Fase 8a — Copia automática a la nube del usuario ✅

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

**Hecha**, con Google Drive como destino y sin tocar el esquema: `schemaVersion` sigue en 7
y `versionCopia` en 3. El reparto quedó como preveía la costura de [K10](#k10-la-costura-de-test):
`datos/copia_automatica.dart` es puro y decide *cuándo*, `datos/nube/nube.dart` es la
interfaz de seis métodos, `datos/nube/drive.dart` el único fichero que sabe que Google
existe, y `estado/copia_automatica.dart` el motor con los disparadores. 51 tests nuevos, la
suite en 441.

#### Las ocho desviaciones de la fase 8a

1. **`google_sign_in` no se podía usar, y eso cambió el flujo entero.** Un cliente OAuth de
   tipo *Android* va atado al `applicationId` **y a la huella SHA-1 del certificado de
   firma**, y este proyecto firma el APK de release con la clave de depuración
   (`android/app/build.gradle.kts`), que un runner de GitHub genera nueva en cada
   ejecución: la huella cambiaría en cada release y el inicio de sesión no funcionaría
   nunca. Tampoco en un fork ni en una compilación local. Se usa en su lugar el flujo de
   código con **PKCE y redirección al bucle local** (RFC 8252) contra un cliente de tipo
   *Aplicación de escritorio*, que es el único que Google sigue admitiendo con
   `http://127.0.0.1:<puerto>` y **no depende de la firma**. La app levanta un `HttpServer`
   efímero, abre el navegador y recoge el código de la redirección.
2. **No entra ningún SDK de Google.** Drive se habla por REST v3 con el `http` que ya
   estaba declarado. De las tres dependencias añadidas, `crypto` (el reto S256) y
   `url_launcher` (abrir el navegador) **ya estaban en el árbol** como transitivas, así que
   la única nueva de verdad es `flutter_secure_storage`, para el *refresh token*. Es la
   opción que [O6](#o-decisiones-pendientes) recomendaba.
3. **El ámbito es `drive.file`, no `drive`.** La app solo ve y modifica lo que ella misma
   creó. Además de ser privilegio mínimo, hace **imposible** que la rotación borre un
   fichero del usuario —la lista sobre la que decide no puede contener otra cosa— y es un
   ámbito *no sensible*, así que la pantalla de consentimiento no necesita verificación de
   Google ni evaluación de seguridad.
4. **Las cinco claves de estado no son preferencias, y por eso no las lee `Ajustes`.**
   Viven en la tabla `ajustes` porque ahí ya hay una tabla clave/valor, pero las interpreta
   `EstadoCopiaAutomatica` y están en el conjunto nuevo `Claves.locales`, que `copia.dart`
   filtra **al exportar y al importar**. Restaurar una copia en un móvil nuevo no puede
   traerse la cuenta conectada del viejo. Entró en ese conjunto también `version_indice`,
   que ya era estado de dispositivo y se estaba exportando por descuido.
5. **`borrarTodosLosDatos()` conserva ahora las claves locales.** No estaba previsto y es
   un fallo que había: esa función vacía la tabla `ajustes` entera, así que tanto «borrar
   todos los datos» como importar con «reemplazar» habrían **desconectado la copia
   automática sin pedirlo**, dejando además la cuenta olvidada en la tabla con su token
   todavía en el almacén seguro. El botón dice «rutinas, sesiones y medidas», y ahora eso
   es lo que borra.
6. **«Le toca» se decide por frontera natural, no por horas transcurridas.** Con un «hace
   menos de 24 h», una copia a las 23:50 bloquearía la del día siguiente y bastaría
   entrenar dos noches seguidas para saltarse una. Se compara el día, el lunes —con el
   `metricas.lunesDe` que ya existía, y por su mismo motivo— o el mes.
7. **No hay `compute()` para serializar.** Estaba previsto llevarlo a un isolate como hace
   `semilla.dart` con el megabyte del catálogo, pero una copia de años de entrenamiento
   ronda el megabyte y `jsonEncode` la resuelve en milisegundos: arrancar el isolate cuesta
   más que lo que ahorra. Se serializa sin indentar, que es la mitad de bytes que subir.
8. **El adaptador de Drive se prueba entero sin red.** Era lo que parecía imposible. Con
   `MockClient` van el canje del código, la renovación del token, el `invalid_grant` y el
   cuerpo *multipart*; y **el bucle local se prueba de verdad**, levantando el `HttpServer`
   y haciendo de navegador con un `GET` a la redirección. Lo único que queda fuera es
   `launchUrl` y los servidores de Google.

**Lo que hay que hacer fuera del código** para que funcione en las releases oficiales: un
proyecto en Google Cloud con la Drive API activada, una pantalla de consentimiento en
producción que enlace `docs/privacidad.md`, un cliente OAuth de tipo *Aplicación de
escritorio*, y sus dos valores como secretos `GOOGLE_CLIENT_ID` y `GOOGLE_CLIENT_SECRET`.
Sin ellos la copia automática queda **desactivada y no visible**, y todo lo demás —incluida
CI— sigue igual.

### Fase 8b — Sincronización: el motor ✅

Bloque **K**, la mitad que no se ve, y **sin ningún SDK todavía**:

1. Migración 7 → 8 (`uuid`, `actualizado`, las lápidas y `sincro_estado`), con su respaldo
   previo y sus tests de migración.
2. `SincroTransporte` y la implementación falsa en memoria.
3. El motor de reconciliación, con los escenarios de
   [K10](#k10-la-costura-de-test) en verde.
4. La lógica del primer enlace ([K7](#k7-el-primer-enlace)) con sus cuatro casos.

Al terminar esta fase **el APK no cambia para el usuario**: no hay pantalla, no hay cuenta y
no hay red. Pero está hecha la parte difícil y está probada entera.

**Hecha**, y en el orden previsto. `schemaVersion` pasa a 8 y `versionCopia` a 4. El reparto
quedó así:

| Fichero | Qué es |
|---|---|
| `datos/identidad.dart` | `uuidV4` y `selloLocal`: la identidad y la versión de una fila |
| `datos/bd.dart` | las columnas nuevas, las dos tablas nuevas, la migración y la API que el motor necesita |
| `datos/sincro/transporte.dart` | la costura: ocho métodos, sin Flutter y sin drift |
| `datos/sincro/motor.dart` | bajar, aplicar, subir, confirmar |
| `datos/sincro/enlace.dart` | el primer enlace y sus cuatro casos |
| `test/sincro_falso.dart` | el servidor de mentira, con su propio reloj |

65 tests nuevos —22 de sincronización, 25 de sellos y lápidas, 11 del primer enlace y el
resto repartidos entre migraciones y copia—, la suite en **506**. Los 441 anteriores pasan
sin tocar nada salvo dos ajustes mecánicos: un constructor de `Ejercicio` escrito a mano en
`progresion_test.dart`, que ahora pide las dos columnas nuevas, y el test del respaldo
previo, cuyo comportamiento **sí** cambia a propósito (ver la desviación 11).

#### Las once desviaciones de la fase 8b

1. **Las lápidas van en su propia tabla, no en una columna `borrado`.** Es la desviación de
   fondo y de ella salen varias de las demás. Marcar la fila en su sitio, como pedía
   [K4](#k4-modelo-de-sincronización), obligaría a filtrar las cincuenta consultas de
   `bd.dart` —y una que se olvidara enseñaría datos borrados—, dejaría el nombre de una
   rutina borrada ocupando su índice único, de modo que no se podría volver a crear, y
   anularía los `ON DELETE CASCADE`, que habría que reescribir a mano. Con la tabla
   `lapidas (tabla, clave, actualizado)` el borrado sigue siendo un borrado, ninguna consulta
   cambia y el criterio de aceptación de que los 441 tests anteriores pasen sin tocarse se
   cumple de verdad. Solo se entierra a los padres: al aplicar la lápida, el `CASCADE` del
   otro móvil se lleva a los hijos igual que se los llevó aquí.
2. **`serie` no lleva ni `uuid` ni `actualizado`.** Sale de aplicar [K5](#k5-conflictos) hasta
   el final: si la sesión es la unidad de reconciliación, la serie no necesita identidad
   propia —viaja dentro de su entrenamiento y se sustituye con él—. De paso, la tabla más
   numerosa, la que hacía cara la migración en una base de dos años, se queda sin tocar. A
   cambio, **escribir una serie sella su entrenamiento**, que es lo que convierte al bloque
   en una unidad de verdad.
3. **`medidas`, `favoritos` y `ajustes` tampoco llevan `uuid`.** Ya tienen una clave estable
   en los dos móviles —`(fecha, tipo)`, `idCatalogo` y `clave`—, que la propia [K6](#k6-qué-se-sincroniza-y-qué-no)
   reconoce al hablar de las medidas. Darles además un `uuid` haría que la misma medida
   llegara dos veces con dos identidades y chocara contra su índice único, que es
   exactamente el problema que la identidad venía a evitar.
4. **El reloj no decide un conflicto: decide el cursor de subida.** K4 decía «gana la fila
   con el `actualizado` más alto» y a la vez que el reloj del móvil no es de fiar; las dos
   cosas no se sostienen juntas, porque comparar el sello local de aquí con el del servidor
   es comparar dos relojes. La regla que se implementó es una sola: **al bajar, una fila
   remota se aplica salvo que la local esté pendiente de subir**, y lo pendiente se sube a
   continuación, así que el servidor acaba con ella. Gana quien llega el último al servidor,
   que es lo único que un cliente con la hora mal puesta no puede falsear, y es lo que hace
   verificable el octavo escenario de K10 sin inventarse un reloj de confianza.
5. **`SincroTransporte` tiene ocho métodos, no seis.** Sobran dos de los previstos y faltaban
   dos: `resumen()`, para poder enseñar las cifras de los dos lados antes de preguntar en el
   primer enlace, y `vaciar()`, para «este dispositivo manda», que sin él tendría que
   enterrar una por una las filas del otro lado —la misma operación, hecha cara y a trozos—.
6. **La respuesta a una subida trae también el cursor previo del servidor.** Sin eso, el
   dispositivo que acaba de subir se descarga su propio eco en la pasada siguiente, y con dos
   móviles activos las mismas filas van y vienen sin parar. Con el cursor previo el cliente
   sabe si lo que hay entre él y el cursor nuevo es solo suyo y puede adelantar también el
   cursor de bajada. Hay un test que lo fija.
7. **La cuarentena reordena dentro del paquete; no hay tabla de cuarentena.** Como el paquete
   trae el delta entero y se aplica en una transacción, una fila solo puede llegar antes que
   su padre por el orden en que venga, y eso se arregla ordenando por dependencias y
   reintentando mientras se avance. Lo que quede sin colocar después de eso es un huérfano de
   verdad —su padre se borró— y no se va a resolver esperando: se descarta con un aviso. El
   caso literal de K10, «series que llegan antes que su entrenamiento», no puede darse porque
   las series viajan dentro de su sesión; lo que se prueba es la misma propiedad un nivel más
   arriba.
8. **`actualizado` lleva `DEFAULT 0` en SQL y se sella a mano en cada escritura.** Sin el
   valor por defecto, `ALTER TABLE ADD COLUMN` no admite una columna obligatoria y la
   migración sobre bases existentes no se puede escribir; y drift **no deja** combinar
   `withDefault` con un `clientDefault` que sellara las inserciones solo. El cero no es un
   sello válido: una fila sin sellar no se subiría nunca y el fallo no se vería hasta que al
   usuario le faltaran datos en el otro móvil. El contrapeso es `test/sincro_sellos_test.dart`,
   que recorre **todas** las escrituras públicas y comprueba que cada una deja algo
   pendiente, y cada borrado su lápida. Por lo mismo, la unicidad del `uuid` va como índice y
   no como `UNIQUE` de columna: SQLite no deja añadir una columna única con `ALTER TABLE`.
9. **`borrarTodosLosDatos` gana un parámetro y, por defecto, propaga.** Con lápidas, que es
   lo que el botón de Ajustes quiere decir. Sin ellas en «la cuenta manda» del primer enlace,
   donde enterrar lo local se llevaría por delante la cuenta, que es justo el lado que el
   usuario acaba de decir que manda.
10. **`versionCopia` pasa a 4 y la identidad viaja en la copia de seguridad.** Lo pedía
    [L](#l-modelo-de-datos-consolidado) y el plan de la fase no lo listaba, pero dejarlo
    fuera rompía el caso de uso que 8a existe para resolver: restaurar en un móvil nuevo y
    enlazarlo después duplicaría el histórico entero. Con el `uuid` dentro, las filas se
    reconocen y se funden. Si al restaurar ese `uuid` ya está aquí —una copia importada dos
    veces— se genera uno nuevo: dos filas con la misma identidad no son dos filas. Las copias
    de la 2 y la 3 se siguen importando.
11. **El respaldo previo del fichero cubre ahora cualquier base anterior a la v8**, y no solo
    las de la v1. `respaldo.dart` tenía escrita la v2 como única migración que transforma
    datos; ahora hay dos, y la lista `versionesQueTransforman` es lo que decide. El nombre del
    fichero ya llevaba la versión de partida, así que el respaldo de la v2 y el de la v8 no se
    pisan. Es el único cambio de comportamiento visible de la fase, y solo lo ve quien mire
    el directorio de la app.

### Fase 8c — Sincronización: el servicio ✅

1. El adaptador del proveedor, aislado en `lib/datos/sincro/`.
2. Cuentas: entrar por enlace mágico, cerrar sesión, borrar la cuenta ([K3](#k3-cuentas-e-identidad)).
3. La interfaz de Ajustes y el indicador ([K8](#k8-interfaz)).
4. Los disparadores y la espera creciente.
5. La configuración por `--dart-define` y los secretos de CI ([K11](#k11-operación-costes-y-forks)).
6. La política de privacidad en `docs/` y su enlace desde «Acerca de».

**Hecha**, y en ese orden. **Sin migración de esquema**: `schemaVersion` se queda en 8 y
`versionCopia` en 4. Lo único nuevo que había que persistir era el interruptor de este
dispositivo, y para eso ya estaba `Claves.locales`; la contabilidad vive en `sincro_estado`
—que existe desde 8b— y la sesión en el almacén seguro. El reparto quedó así:

| Fichero | Qué es |
|---|---|
| `supabase/esquema.sql` | el servidor: dos tablas, la RLS y cinco funciones |
| `datos/sincro/transporte.dart` | la costura, que pasa de ocho métodos a nueve |
| `datos/sincro/supabase.dart` | el adaptador: el único fichero que sabe que Supabase existe |
| `datos/nube/token.dart` | el almacén seguro, ahora parametrizado por clave |
| `estado/sincro.dart` | el motor: los disparadores, la espera creciente y la cuenta |
| `pantallas/cuenta.dart` | el grupo de Ajustes, la entrada, el primer enlace y el aviso |
| `pantallas/sincro_detalle.dart` | «Última vez», con los avisos de [K5](#k5-conflictos) |
| `docs/sincronizacion.md` | cómo montar el servidor en un *fork*, y cómo verificarlo a mano |

#### Las diez desviaciones de la fase 8c

1. **Ningún SDK: Supabase se habla REST, y la fase no añade ni una dependencia.**
   [K2](#k2-elección-de-backend) contaba con `supabase_flutter` y lo llamaba «con diferencia
   la dependencia más grande del proyecto». Lo es, y para nada: el adaptador son cuatro POST
   de RPC y cuatro de autenticación, y ese paquete arrastra `gotrue`, `postgrest`,
   `realtime`, `storage` y `functions_client` —con *websockets*, *deep links* y preferencias
   compartidas— además de arriesgar el techo de `win32` que fija `file_picker ^11` y que ya
   mantiene a `share_plus` en la 12 y a `flutter_secure_storage` en la 9. Es exactamente el
   razonamiento que ya está escrito en `datos/nube/drive.dart` para no usar el SDK de
   Google, aplicado otra vez.
2. **Se entra con un código de seis cifras, no con un enlace mágico.**
   [K3](#k3-cuentas-e-identidad) pedía *magic link*, y en un móvil eso significa volver a la
   app desde el correo: *deep links*, un *intent-filter* en el manifiesto y un dominio de
   redirección configurado en el proveedor. Aquí el APK se instala a mano desde una release
   y un *fork* tendría que montar todo eso para que la funcionalidad existiera. El código
   llega en el mismo correo, por el mismo endpoint, y no depende de nada. Es la misma clase
   de decisión que renunciar a `google_sign_in` en la 8a.
3. **`SincroTransporte` pasa a nueve métodos.** El código parte la entrada en dos pasos, así
   que aparece `pedirCodigo(correo)` y `entrar` pasa a `entrar(correo, codigo)`. Nadie
   llamaba todavía a `entrar`, de modo que el cambio de firma solo tocó el transporte falso.
4. **El servidor es un buzón con reloj, no seis tablas espejo.** K2 eligió Supabase en parte
   porque «el modelo relacional es el que ya tenemos»; lo relacional se queda donde sirve,
   en el SQLite del móvil. En el servidor, una tabla `filas(usuario, tabla, clave,
   actualizado, datos jsonb)`. El motivo de fondo: la costura de 8b ya es genérica por fila,
   `serie` no tiene identidad propia —viaja dentro de su entrenamiento—, el motor tolera
   huérfanos a propósito (la cuarentena), de modo que una clave foránea aquí rechazaría
   paquetes que el cliente sabe colocar; y sobre todo, el APK se instala a mano y conviven
   versiones arbitrarias, así que con tablas espejo una columna nueva en el móvil exigiría
   desplegar una migración en el servidor **antes**. Con `jsonb`, el servidor no se entera.
5. **El reloj del servidor se siembra con la hora de época en milisegundos.** No estaba
   escrito en ningún sitio y es la clase de detalle que no se ve en los tests y arruina la
   app en producción: `identidad.selloLocal()` sella en milisegundos de época, así que un
   servidor que empezara en cero dejaría el `cursorSubida` del móvil por debajo de todos sus
   sellos locales y **cada pasada resubiría el histórico entero**. El transporte falso
   arranca en 1.000.000 «a propósito»; ahí era una precaución, aquí es un requisito.
6. **`appgym_bajar` lee el reloj antes que las filas y las acota con él.** Al revés —filas
   primero, reloj después— una subida de otro dispositivo que se colara en medio adelantaría
   el cursor por encima de filas no entregadas, y esas filas no se bajarían nunca. Es la
   única forma de perder datos que hay en el servidor, así que el orden de esas dos
   consultas no es estético.
7. **La sesión entera va al almacén seguro, no solo el token.** [K3](#k3-cuentas-e-identidad)
   hablaba del token; el correo también hace falta, y ponerlo en `Claves.locales` habría
   sido peor por un motivo que solo se ve al escribirlo: `sesionActual()` tiene que
   contestarse **sin red**. Si hiciera falta renovar el token para saber si hay cuenta, un
   móvil sin cobertura diría «sin cuenta», el usuario volvería a entrar y caería otra vez
   por el primer enlace, que es el riesgo número uno de todo el bloque.
8. **No hay fila «Dispositivos».** [K8](#k8-interfaz) la pedía, con su nombre editable y su
   «revocar». Exigiría una tabla más en el servidor, registrarse en cada pasada y un revocar
   que, sin introspección de tokens, no echa de verdad al otro móvil: prometería algo que no
   cumple. Cerrar sesión en el aparato que se tiene delante —que es lo que se hace al
   venderlo o prestarlo— sí está, con sus dos salidas.
9. **Si el usuario cancela la pregunta del primer enlace, no se sincroniza hasta que la
   conteste.** K7 no dice qué pasa al cancelar. La sesión queda abierta y el grupo enseña
   «Elegir qué datos mandan» en vez de «Sincronizar ahora». La alternativa —dejar que la
   pasada siguiente fusionara— elegiría por el usuario en el único punto del bloque donde
   K7 exige preguntar, aunque fusionar sea la recomendada y no pierda nada.
10. **El aviso de la cabecera aproxima «cambios pendientes desde hace más de un día» por «sin
    una pasada buena en más de un día».** Contar lo pendiente de verdad son siete consultas
    en cada repintado de la pestaña por la que se entra a la app, y lo que el usuario acaba
    viendo es lo mismo.

**Lo que no se hizo, y se dice:** el job opcional de CI con tests contra el proyecto real
([K11](#k11-operación-costes-y-forks)). Exige credenciales vivas, y K11 ya dice que no
bloquea la publicación del APK. En su lugar, `docs/sincronizacion.md` lleva el guion de
verificación manual del servidor —que es la única parte del proyecto que `flutter test` no
puede tocar— y el contrato que tiene que cumplir es el que implementa `test/sincro_falso.dart`.

**Limitación conocida de «este dispositivo manda»:** vacía el servidor con un borrado duro,
sin lápidas, que es lo que hace el transporte falso contra el que se escribieron los tests
del motor. Un *tercer* dispositivo ya enlazado no se entera y conserva sus datos locales;
tampoco los resucita, porque no están pendientes. La alternativa —enterrarlo todo— propagaría
el borrado a los datos locales de ese tercer móvil, que es peor. Con dos dispositivos, que es
el caso de uso de K, no se da.

### Fase 8d — el backend propio ✅

**La decisión [O2](#o-decisiones-pendientes) se reabrió y se ha cerrado en la opción C de
[K2](#k2-elección-de-backend): servidor propio.** No es un cambio de alcance —lo que la app
hace es exactamente lo mismo— sino de dónde vive el otro lado. Está en `servidor/`: FastAPI,
PostgreSQL y `docker compose`.

**Por qué se reabrió.** Tres cosas que solo se vieron al ir a desplegar:

1. **El correo de fábrica del proveedor solo entrega a direcciones del equipo del proyecto**,
   y está limitado a dos mensajes por hora. Con el código de seis cifras de la 8c, eso
   significa que **nadie más que el dueño del proyecto podía entrar** sin montar un SMTP
   propio. La infraestructura de correo que se quería evitar aparecía igual.
2. **Ni una línea del servidor se podía probar.** `supabase/esquema.sql` era la única parte
   del proyecto sin tests, y `docs/sincronizacion.md` llevaba un guion para verificarlo a
   mano pegándolo en un panel. Eso contradice la frase con la que empieza `CLAUDE.md`.
3. **El plan gratuito pausa el proyecto a los siete días de inactividad y no trae copias.**

**Lo que costó, medido.** El motor de reconciliación, el primer enlace, los sellos, las
lápidas y sus tests **no se tocaron**: era lo que K2 prometió por escrito —«cambiar de B a C
es escribir otro adaptador, no reescribir el bloque»— y se ha cobrado. Cambió el adaptador
(`supabase.dart` → `servidor.dart`), dos de los nueve métodos de la costura, la pantalla de
entrada y sus textos. Sin migración: `schemaVersion` sigue en 8 y `versionCopia` en 4, y no
había ni un usuario que migrar porque el servicio nunca llegó a desplegarse.

#### Las cinco desviaciones de la fase 8d

1. **Se entra con contraseña, no con un código por correo.** Es la tercera vuelta de
   [K3](#k3-cuentas-e-identidad), que pedía enlace mágico y en la 8c se quedó en código. Con
   servidor propio, el correo saliente es infraestructura que hay que montar, pagar y vigilar
   **antes** de que nadie pueda entrar; con contraseña, el día que el servidor está en pie ya
   se puede usar. Argon2id en el servidor, y el mismo mensaje para «ese correo no existe» y
   «esa contraseña no es», que es lo que evita que se pueda averiguar quién tiene cuenta.
2. **Crear cuenta y entrar dejan de ser el mismo botón.** K3 los quería juntos y con un
   código se podía; con contraseña, quien se equivoca al teclear su correo se crearía una
   cuenta nueva y vacía en vez de leer «contraseña incorrecta». Son dos filas en Ajustes y
   dos rutas en la API.
3. **No hay «he olvidado mi contraseña», y se dice.** Hasta que el servidor tenga correo
   saliente, una contraseña perdida es una cuenta perdida —los datos locales del móvil no,
   que la app es local-primero—. Por eso el diálogo de crear cuenta la pide dos veces y lo
   advierte en su texto.
4. **El aislamiento ya no es *row level security*, y no hace falta que lo sea.** K9 lo
   describía como RLS porque el cliente hablaba directamente con la base del proveedor. Aquí
   el cliente **solo** habla con la API, y toda consulta filtra por el usuario que viene
   firmado en el JWT; ningún identificador de usuario entra por el cuerpo ni por la URL. La
   diferencia práctica es que ese aislamiento **se prueba en la suite del servidor**, y antes
   era el único test que necesitaba red.
5. **La app puede anclar el certificado del servidor** (`datos/sincro/anclaje.dart`,
   `--dart-define API_ANCLAS`). Se ancla a la autoridad y no al certificado hoja: anclar la
   hoja obligaría a publicar un APK en cada renovación, y un APK que se instala a mano tarda
   semanas en llegar a todos los móviles. Sin esa variable, la app funciona igual con TLS
   normal.

**El job de CI que K11 pedía ya existe**, aunque no como lo describía: no es un job de red
contra el proyecto real, es `.github/workflows/servidor.yml`, que corre `ruff` y `pytest`
contra un PostgreSQL de verdad. No bloquea ni produce el APK, como K11 exigía. El contrato
entre las dos mitades se comprueba además de extremo a extremo con `flutter test --tags red`,
que necesita el compose levantado y por eso está fuera de la suite por defecto.

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
   **Cerrada: K se ha hecho entero.** 8a, 8b y 8c entregadas. La factura que 8c traía
   —el proveedor y el compromiso de mantenerlo— se ha abaratado en lo que se podía: sin
   dependencia nueva (se habla REST), con el servidor reproducible desde un fichero SQL
   versionado, y con la app funcionando entera si el servicio se apaga. Lo que no se puede
   quitar es que ahora existe un servidor con datos de salud de otras personas, y de eso
   hablan [K9](#k9-seguridad-y-privacidad) y `docs/privacidad.md`.

2. **¿Qué proveedor, si se hace K completo?** ([K2](#k2-elección-de-backend))
   **Reabierta y cerrada de nuevo en la opción C: servidor propio** (fase 8d, arriba). El
   motivo y lo que costó están ahí; lo que sigue es la decisión anterior, que se conserva
   porque explica por qué el cambio salió barato.
   **Cerrada en su día: Supabase, pero hablado por REST y sin su SDK.** La RLS es lo que aísla las
   cuentas y es del servidor, no del cliente; y el cliente son ocho llamadas HTTP, para las
   que `supabase_flutter` no aporta nada a cambio de ser la dependencia más grande del
   proyecto. Sigue todo detrás de `SincroTransporte`, así que la decisión sigue siendo
   reversible: cambiar de proveedor es escribir otro `supabase.dart`.

3. **¿El inglés es el segundo idioma?** ([I1](#i1-mecanismo-de-traducción))
   Es el que más alcance da por el mismo esfuerzo y el que ya está medio hecho, porque el
   catálogo viene en inglés. **Recomendación:** sí. Si el objetivo real fuera otro mercado
   concreto, la elección cambia y el mecanismo no.

4. **¿El rango de repeticiones por defecto es 8–12?** ([J1](#j1-el-modelo-de-progresión))
   **Cerrada: sí, y con la propuesta.** 8–12 de fábrica, y `progresion.rangoObservado` mira
   las tres últimas sesiones y aproxima el rango real al estándar más cercano de siete
   (3–5 … 15–25). Si difiere del configurado, la hoja del ejercicio lo ofrece **el primero**
   y anotado, y el pie de la sección lo explica. No cambia nada solo: quien decide es el
   usuario, que es la regla de todo el bloque.

5. **¿La descarga baja un 10 % o vuelve al último peso donde se completó el rango?**
   ([J4](#j4-estancamiento-y-descarga))
   **Cerrada: el último peso completado, con el 10 % de respaldo.** Se recorre el historial
   hacia atrás buscando una sesión que completara el rango con menos peso que el actual; si
   no la hay, se baja un 10 % redondeado al escalón hacia abajo. Los dos caminos tienen su
   test, que es lo que permitió decidirlo con los números delante.

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
   **Cerrada: en las dos, y en la viva solo hasta marcar la primera serie.** La línea ocupa
   dos renglones sobre la lista de series y desaparece en cuanto se marca una: a partir de
   ahí ya no hay nada que proponer, porque el entrenamiento está en marcha. Se añadió un
   tercer caso que no estaba en la pregunta: al **editar** una sesión guardada tampoco
   aparece, porque ahí no se decide nada, se corrige lo que ya pasó.
