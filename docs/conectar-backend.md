# Conectar la app a un backend: lo que falta

Este documento contesta a una pregunta concreta —*¿qué queda para que el sistema de usuarios
de AppGym hable de verdad con un servidor?*— y no repite lo que ya está escrito en otro
sitio. El paso a paso del montaje vive en [`sincronizacion.md`](sincronizacion.md); el
porqué de cada decisión, en el bloque K de
[`especificaciones-2.md`](especificaciones-2.md). Aquí solo está **el estado y el trabajo
restante**, en el orden en que hay que hacerlo.

---

## El resumen en dos líneas

**No falta código de la app.** El bloque K está entero: la cuenta, el motor de
reconciliación, el adaptador REST de Supabase, el primer enlace, los disparadores, la
pantalla de Ajustes y el SQL del servidor están escritos y cubiertos por la suite.

Lo que falta es **desplegar y verificar**: un proyecto de Supabase, tres ajustes de correo
—uno de ellos no está hoy en la documentación y sin él nadie puede entrar—, dos secretos en
CI, una verificación manual del servidor que ningún `flutter test` puede hacer, y una prueba
con dos dispositivos reales.

---

## Punto de partida: qué hay ya escrito

| Pieza | Fichero | Estado |
|---|---|---|
| La costura del transporte (8 métodos) | `lib/datos/sincro/transporte.dart` | hecho |
| La reconciliación (bajar, aplicar, subir, confirmar) | `lib/datos/sincro/motor.dart` | hecho |
| El primer enlace y sus cuatro casos | `lib/datos/sincro/enlace.dart` | hecho |
| El adaptador de Supabase (REST, sin SDK) | `lib/datos/sincro/supabase.dart` | hecho |
| Disparadores, espera creciente y avisos | `lib/estado/sincro.dart` | hecho |
| Entrar, salir, borrar cuenta, primer enlace en Ajustes | `lib/pantallas/cuenta.dart` | hecho |
| Identidad (`uuid`), sellos y lápidas en el esquema v8 | `lib/datos/bd.dart`, `identidad.dart` | hecho |
| El servidor: dos tablas, RLS y cinco funciones | `supabase/esquema.sql` | escrito, **sin desplegar** |
| El paso de credenciales por `--dart-define` | `.github/workflows/build-apk.yml` | hecho, **secretos por poner** |

El interruptor de todo esto es `sincroDisponible` (`supabase.dart:64`): si `SUPABASE_URL` o
`SUPABASE_ANON_KEY` llegan vacías, `sincroProvider` da `null`, el grupo «Cuenta» de Ajustes
**no se pinta** y no hay disparador que haga nada. Es decir: hoy, en cualquier compilación
sin esos dos valores, **la funcionalidad de usuarios no existe** aunque el código esté.

---

## Los pasos que faltan

### Paso 0 — Decidir de quién es el proyecto

Es una decisión, no una tarea, y condiciona los pasos 2 y 6.

- **Proyecto personal, de un solo usuario.** Lo más barato y lo que el README ya describe.
  Después de crear tu cuenta, desactiva *Allow new users to sign up*.
- **Proyecto abierto a quien instale el APK.** Entonces pasas a custodiar **datos de salud
  de terceros** y su correo electrónico, con las obligaciones que eso trae (ver
  [`privacidad.md`](privacidad.md) y K9). El APK se publica en cada merge a `main` y
  cualquiera puede instalarlo: con el registro abierto, cualquiera puede crear una cuenta en
  tu proyecto, y es tu cuota y tu responsabilidad.

Todo lo demás es idéntico en los dos casos.

### Paso 1 — Crear el proyecto y aplicar el esquema

→ [`sincronizacion.md`](sincronizacion.md), apartados 1 y 2. En corto: proyecto nuevo,
`supabase/esquema.sql` pegado entero en el editor SQL, y **`appgym` fuera de *Exposed
schemas*** para que la única superficie REST sean las cinco funciones.

Anota la *Project URL* y la *anon public key*. La `service_role` **no se usa nunca**: si
acaba en el APK, cualquiera que lo descargue puede leer y borrar los datos de todos.

### Paso 2 — El correo (aquí están los dos fallos que dejan la app inservible)

AppGym entra con un **código de seis cifras** que llega por correo. Sin correo no hay
autenticación y sin autenticación no hay nada. Son tres ajustes, y los dos primeros son
los que rompen el montaje:

1. **La plantilla tiene que incluir `{{ .Token }}`** (*Authentication → Emails → Magic
   Link*). La de fábrica solo trae `{{ .ConfirmationURL }}`: el usuario recibiría un enlace,
   no tendría ningún código que teclear y no podría entrar. Ya está en
   [`sincronizacion.md`](sincronizacion.md) §3, con la plantilla de ejemplo.

2. **SMTP propio, y esto no está hoy en ninguna parte de la documentación del repositorio.**
   El servicio de correo de fábrica de Supabase es *best-effort*, está limitado a **2 correos
   por hora en todo el proyecto** y **solo entrega a direcciones del equipo del proyecto**.
   Traducido a esta app: con el correo de fábrica, **el único que puede entrar eres tú**, y
   como mucho dos veces por hora. Cualquier otra dirección recibe un rechazo que en la app
   aparece como un fallo al pedir el código. Hay que configurar un proveedor SMTP en
   *Project Settings → Authentication → SMTP Settings*; con uno propio el límite por omisión
   sube a 30 correos por hora y es ajustable en *Rate Limits*.

   Esto **no es opcional** salvo en el caso «proyecto personal de un solo usuario» del paso 0,
   y aun ahí conviene: dos correos por hora se agotan probando.

3. **Email activado y «Confirm email» activado** (*Authentication → Providers → Email*).

Nada de esto exige *deep links*, *intent-filter* ni dominio: fue justamente el motivo de
entrar con código y no con enlace mágico (desviación K, `transporte.dart:206`).

### Paso 3 — Los secretos y la compilación

- **En CI:** los secretos `SUPABASE_URL` y `SUPABASE_ANON_KEY` del repositorio
  (*Settings → Secrets and variables → Actions*). El workflow ya los pasa por
  `--dart-define` (`build-apk.yml:146`); no hay que tocar el YAML. Si no están, llegan
  vacíos, la sincronización queda desactivada y el APK se construye igual.
- **En local:** los mismos dos `--dart-define` en el `flutter build apk --release`.

**Cómo comprobar que han entrado**, sin leer ningún log: instala el APK y abre *Ajustes*. Si
aparece el grupo «Cuenta», `sincroDisponible` es cierto. Si no aparece, las variables
llegaron vacías y no hay nada más que mirar.

### Paso 4 — Verificar el servidor

**Ni una línea de `supabase/esquema.sql` se puede probar con `flutter test`.** Es la única
parte del proyecto en esa situación, y por eso el guion de verificación existe:
[`sincronizacion.md`](sincronizacion.md) §5, seis consultas que se pegan en el editor SQL.
El contrato que tienen que cumplir es el que implementa `test/sincro_falso.dart`.

Lo que hay que ver con los ojos, porque un fallo aquí no se manifiesta hasta que el usuario
tiene datos:

- **El reloj arranca por encima de 1,7 · 10¹²** (milisegundos de época). Un servidor que
  empezara en cero haría que cada pasada resubiera el histórico entero, para siempre.
- **`cursorPrevio` de una subida es el `cursor` de la anterior.** Si `subir` adelantara el
  reloj a la hora de pared, cada móvil se descargaría su propio eco.
- **Una lápida viaja como `datos: null`** y el resumen no la cuenta.
- **Vaciar borra las filas y no reinicia el reloj.**
- **El aislamiento:** con la sesión de un usuario,
  `select count(*) from appgym.filas where usuario <> auth.uid()` da **0**, ni error ni
  datos. Es el único test que necesita red y el que K9 exige.

### Paso 5 — La prueba de extremo a extremo, con dos dispositivos

Es el trabajo real que queda, y no lo cubre la suite: los tests prueban el motor contra un
transporte falso, no el sistema montado. Con dos dispositivos (o un móvil y un emulador),
por este orden:

- [ ] Pedir el código, recibirlo y entrar. Y **teclear uno mal**: el mensaje del servidor se
      enseña tal cual y tiene que ser legible.
- [ ] **Los cuatro casos del primer enlace** (`enlace.dart`): cuenta vacía y móvil con datos;
      cuenta con datos y móvil vacío; los dos con datos → la pregunta, con sus cifras, y sus
      tres salidas —fusionar, este dispositivo manda, la nube manda—; los dos vacíos.
      **La salida destructiva exporta una copia antes**: comprobar que el fichero aparece.
- [ ] Guardar un entrenamiento en A, sincronizar, y verlo en B con sus series y su nota.
- [ ] Editar la misma rutina en los dos con el avión puesto, y ver que converge al reconectar
      (gana quien llega el último; el pendiente local se sube justo después).
- [ ] Borrar una rutina en A y comprobar que **desaparece** en B (la lápida y su cascada).
- [ ] Modo avión: guardar, ver que no aparece ningún error en la ruta de entrenar, y que el
      aviso sale más tarde en la cabecera de Rutinas.
- [ ] Cerrar sesión conservando los datos → la base local queda intacta y utilizable.
- [ ] Borrar la cuenta → los datos remotos se van, los locales se quedan.
- [ ] Dejar el móvil una semana sin abrir y volver: la sesión se renueva sola. Es lo que
      ejercita la rotación del *refresh token* de GoTrue, que es lo que más fácilmente rompe
      un adaptador nuevo.

### Paso 6 — Operación: lo que hay que asumir antes de encenderlo

- **El plan gratuito pausa el proyecto a los 7 días de inactividad.** Pausado, el proyecto
  no responde y hay que despausarlo a mano desde el panel. Para una app de gimnasio que se
  usa a diario no debería darse, pero con un solo usuario que se va de vacaciones, sí. La
  app aguanta: avisa una vez y sigue funcionando en local.
- **El plan gratuito no trae copias de seguridad automáticas.** Las diarias empiezan en el
  plan Pro. La copia real de los datos sigue siendo la del móvil: *Ajustes → Datos*, o la
  copia automática a Drive de la fase 8a. **La nube de sincronización no es una copia de
  seguridad** y no debe presentarse como tal.
- **Existe una factura posible.** El volumen no es el problema —un año de entrenamiento es
  del orden de un megabyte por usuario—; el problema es el compromiso. La salida digna ya
  está construida (K11): la app funciona entera sin cuenta, la exportación no depende de
  nada externo, y si el servicio se apaga la app avisa una vez y sigue en local.
- **Rate limits.** Los de correo del paso 2, y los de `/verify`. Un 429 llega a la app como
  `ErrorSincro.temporal` y entra en la espera creciente (5 s, 30 s, 2 min, 10 min, y para).

### Paso 7 — Privacidad y textos (solo si cambia lo que sale del móvil)

[`privacidad.md`](privacidad.md) es requisito, no formalidad, y hoy describe lo que sale:
rutinas, ejercicios, entrenamientos con sus series, medidas, favoritos, preferencias y el
correo. **Nada más.** Si al conectar el backend se decide mandar algo distinto, ese fichero
cambia con ello. Si no cambia nada, no hay trabajo aquí.

### Paso 8 — El job de CI contra el proyecto real (opcional, y a propósito)

K11 preveía un job más, solo en `main`, que ejecutara pruebas de red contra el proyecto de
verdad y se saltara si los secretos no están. **No se implementó**, y está documentado como
desviación: exige credenciales vivas y K11 ya dice que no bloquea la publicación del APK. En
su lugar quedó el guion manual del paso 4. Si se monta, va como job aparte y sin `needs` que
bloquee al APK.

---

## Lo que NO hay que hacer

Media hora de trabajo evitada por cada línea de esta lista:

- **No añadir `supabase_flutter` ni ningún SDK.** Se habla REST con el `http` que ya estaba.
  La fase 8c no añadió ni una dependencia, y `supabase_flutter` arrastraría realtime, storage
  y deep links para ocho llamadas HTTP, además de poner en riesgo el techo de `win32` que fija
  `file_picker`.
- **No montar *deep links* ni tocar el `AndroidManifest.xml`.** El permiso de INTERNET ya
  está y es lo único que hacía falta; se entra con un código tecleado.
- **No tocar `schemaVersion` ni `versionCopia`.** Siguen en 8 y en 4. Conectar el backend no
  es un cambio de esquema: lo único que había que persistir era el interruptor de este
  dispositivo, y para eso ya está `Claves.locales`.
- **No exponer el esquema `appgym`** en *Exposed schemas*, y no quitar la RLS «porque las
  funciones ya filtran».
- **No meter la `service_role` en ningún `--dart-define`, secreto de CI ni fichero.**
- **No hacer que el servidor mire la hora de pared** en `appgym_subir`, ni reiniciar el reloj
  en `appgym_vaciar`. Las dos cosas están razonadas en `esquema.sql` y las dos rompen la
  sincronización de forma silenciosa.
- **No reordenar las dos consultas de `appgym_bajar`**: el reloj se lee **antes** que las
  filas. Es la única forma de perder datos que hay en todo el fichero.

---

## Limitaciones que hereda quien lo conecte

No son cosas por hacer; son cosas que hay que saber antes de encenderlo, y todas están
razonadas en su sitio.

- **«Este dispositivo manda» vacía el servidor con un borrado duro, sin lápidas.** Un
  *tercer* dispositivo ya enlazado no se entera y conserva sus datos locales. Con dos
  dispositivos, que es el caso de uso de K, no se da.
- **El aviso de la cabecera aproxima** «cambios pendientes desde hace más de un día» por «sin
  una pasada buena en más de un día».
- **La sesión en curso no se sincroniza.** Empezar en el móvil y continuar en la tableta no
  está en alcance (K6).
- **Sin cifrado extremo a extremo.** Evaluado y aplazado en K9: con autenticación sin
  contraseña, perder la clave sería perderlo todo.
- **Sin sincronización en tiempo real, y sin resolución manual de conflictos.** La regla es
  una sola: al bajar, una fila remota se aplica salvo que la local esté pendiente de subir.

---

## Si el backend acabara siendo otro

La decisión sigue siendo reversible y el trabajo está acotado: **escribir otro fichero como
`supabase.dart`**, implementando los ocho métodos de `SincroTransporte`:

```
sesionActual()   pedirCodigo(correo)   entrar(correo, codigo)   salir()
bajar(cursor)    subir(paquete)        resumen()                vaciar()  borrarCuenta()
```

Con tres requisitos que no son del proveedor sino del motor, y que el nuevo servidor tiene
que cumplir igual: el reloj es **suyo**, se siembra en milisegundos de época y solo crece;
`subir` devuelve `{sellos, cursor, cursorPrevio}`; y `bajar` acota las filas con el cursor
que va a devolver. La especificación ejecutable de todo eso es `test/sincro_falso.dart`, y
`test/importaciones_test.dart` es lo que impide que el nombre del proveedor se escape de
`lib/datos/sincro/`.

---

## Checklist

```
[ ] 0. Decidido: proyecto personal (registro cerrado) o abierto
[ ] 1. Proyecto creado; esquema.sql ejecutado; `appgym` fuera de Exposed schemas
[ ] 2. Email activado, «Confirm email» activado
[ ] 2. Plantilla de Magic Link con {{ .Token }}
[ ] 2. SMTP propio configurado          ← sin esto solo entra el dueño del proyecto
[ ] 3. Secretos SUPABASE_URL y SUPABASE_ANON_KEY en el repositorio
[ ] 3. APK instalado: el grupo «Cuenta» aparece en Ajustes
[ ] 4. Guion SQL de verificación pasado, incluido el aislamiento entre usuarios
[ ] 5. Prueba con dos dispositivos, con los cuatro casos del primer enlace
[ ] 6. Asumidos: pausa a los 7 días, sin copias automáticas, la factura posible
[ ] 7. privacidad.md sigue diciendo la verdad
[ ] 8. (opcional) Job de CI contra el proyecto real
```

---

## Fuentes de los datos de plataforma

Los límites del proveedor cambian; los del paso 2 y el 6 se comprobaron en agosto de 2026 y
conviene confirmarlos en el panel antes de montar:

- [Project Pausing — Supabase Docs](https://supabase.com/docs/guides/platform/free-project-pausing)
  (pausa a los 7 días de inactividad en el plan gratuito)
- [Send emails with custom SMTP — Supabase Docs](https://supabase.com/docs/guides/auth/auth-smtp)
  y [Auth Rate Limits](https://supabase.com/docs/guides/auth/rate-limits) (2 correos/hora y
  solo al equipo con el servicio de fábrica; 30/hora ajustables con SMTP propio)
- [Database Backups — Supabase Docs](https://supabase.com/docs/guides/platform/backups)
  (las copias diarias empiezan en el plan Pro)
