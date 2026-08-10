# Conectar la app al backend: lo que falta

Este documento contesta a una pregunta concreta —*¿qué queda para que el sistema de
usuarios de AppGym hable de verdad con un servidor?*— y no repite lo que ya está
escrito en otro sitio. El paso a paso del montaje vive en
[`sincronizacion.md`](sincronizacion.md); el manual del propio servicio, en
[`../servidor/README.md`](../servidor/README.md); el porqué de cada decisión, en el
bloque K de [`especificaciones-2.md`](especificaciones-2.md). Aquí solo está **el
estado y el trabajo restante**, en el orden en que hay que hacerlo.

---

## El resumen en dos líneas

**No falta código, ni de la app ni del servidor.** El bloque K está entero y el
backend propio también: cuentas con JWT, el buzón con reloj, el despliegue en
`docker compose` y sus tests.

Lo que falta es **desplegarlo y probarlo con dos móviles**: una máquina con un
dominio, cinco minutos de `docker compose`, dos secretos en CI y una tarde de
pruebas con la app instalada.

---

## Punto de partida: qué hay ya escrito

| Pieza | Dónde | Estado |
|---|---|---|
| La costura del transporte (9 métodos) | `lib/datos/sincro/transporte.dart` | hecho |
| La reconciliación (bajar, aplicar, subir, confirmar) | `lib/datos/sincro/motor.dart` | hecho |
| El primer enlace y sus cuatro casos | `lib/datos/sincro/enlace.dart` | hecho |
| El adaptador del servidor (REST, sin SDK) | `lib/datos/sincro/servidor.dart` | hecho |
| El anclaje de certificado | `lib/datos/sincro/anclaje.dart` | hecho |
| Disparadores, espera creciente y avisos | `lib/estado/sincro.dart` | hecho |
| Entrar, crear cuenta, salir, borrarla, primer enlace | `lib/pantallas/cuenta.dart` | hecho |
| Identidad (`uuid`), sellos y lápidas en el esquema v8 | `lib/datos/bd.dart` | hecho |
| El servidor: cuentas, JWT y el buzón con reloj | `servidor/appgym/` | escrito y probado, **sin desplegar** |
| El despliegue: Docker, compose, Caddy, migraciones | `servidor/` | escrito, **sin ejecutar en un VPS** |
| El paso de la URL y el anclaje por `--dart-define` | `.github/workflows/build-apk.yml` | hecho, **secretos por poner** |

El interruptor de todo esto es `sincroDisponible` (`servidor.dart:59`): si `API_URL`
llega vacía, `sincroProvider` da `null`, el grupo «Cuenta» de Ajustes **no se
pinta** y no hay disparador que haga nada. Es decir: hoy, en cualquier compilación
sin esa variable, **la funcionalidad de usuarios no existe** aunque el código esté.

---

## Los pasos que faltan

### Paso 1 — Una máquina y un dominio

Un VPS con Docker y un registro `A` apuntando a él, con los puertos 80 y 443
abiertos. Es el único gasto recurrente de todo esto y la única pieza que no está
en el repositorio.

Alternativas que valen igual: un miniPC en casa con un túnel (Cloudflare Tunnel,
Tailscale) o un PaaS que corra un `Dockerfile` —el compose no ata a ningún
proveedor—. Lo que no vale es no tener TLS.

### Paso 2 — Levantarlo

→ [`sincronizacion.md`](sincronizacion.md) §2. Son cuatro órdenes: clonar, copiar
el `.env`, generar las dos claves y `docker compose up -d --build`. Caddy resuelve
el certificado solo, y las migraciones las aplica el contenedor al arrancar.

Comprobación: `curl https://tu-dominio/salud` devuelve `{"estado":"vivo"}`.

### Paso 3 — Los secretos y la compilación

- **En CI:** los secretos `API_URL` y `API_ANCLAS` del repositorio. El workflow ya
  los pasa por `--dart-define`; no hay que tocar el YAML.
- **En local:** los mismos dos `--dart-define` en el `flutter build apk --release`.

El anclaje —qué PEM poner y cómo sacarlo— está en
[`sincronizacion.md`](sincronizacion.md) §4. **Sin él la app funciona igual**, con
TLS normal y sin anclaje.

**Cómo comprobar que han entrado**: instala el APK y abre *Ajustes*. Si aparece el
grupo «Cuenta», la URL llegó.

### Paso 4 — Cerrar el registro

Crea tu cuenta desde la app y pon `APPGYM_REGISTRO_ABIERTO=false`. El APK es
público: con el registro abierto, cualquiera que saque la URL puede darse de alta
en tu servidor, y eso es tu cuota y datos de salud ajenos que pasas a custodiar.

### Paso 5 — La prueba con dos dispositivos

Es el trabajo real que queda. Los tests cubren el servidor (`pytest`, contra
PostgreSQL de verdad), el adaptador (`flutter test`) y el contrato entre los dos
(`flutter test --tags red`, con el servidor levantado), pero no el sistema
instalado en dos móviles. Por este orden:

- [ ] Crear la cuenta desde el móvil A. Y probar a **entrar con la contraseña
      equivocada**: el mensaje del servidor se enseña tal cual y tiene que ser
      legible.
- [ ] Entrar en el móvil B con la misma cuenta.
- [ ] **Los cuatro casos del primer enlace** (`enlace.dart`): cuenta vacía y móvil
      con datos; cuenta con datos y móvil vacío; los dos con datos → la pregunta,
      con sus cifras, y sus tres salidas —fusionar, este dispositivo manda, la nube
      manda—; los dos vacíos. **La salida destructiva exporta una copia antes**:
      comprobar que el fichero aparece.
- [ ] Guardar un entrenamiento en A, sincronizar, y verlo en B con sus series y su
      nota.
- [ ] Editar la misma rutina en los dos con el avión puesto, y ver que converge al
      reconectar (gana quien llega el último).
- [ ] Borrar una rutina en A y comprobar que **desaparece** en B (la lápida y su
      cascada).
- [ ] Modo avión: guardar, ver que no aparece ningún error en la ruta de entrenar,
      y que el aviso sale más tarde en la cabecera de Rutinas.
- [ ] Cerrar sesión conservando los datos → la base local queda intacta. Y que
      **la sesión del otro móvil sigue viva**.
- [ ] Borrar la cuenta → los datos remotos se van, los locales se quedan.
- [ ] Dejar el móvil una semana sin abrir y volver: la sesión se renueva sola. Es
      lo que ejercita la rotación del refresco, que es lo que más fácilmente rompe
      un adaptador nuevo.
- [ ] **Prueba del anclaje**, si lo has activado: con un proxy interpuesto
      (mitmproxy) delante, la app **no** debe poder sincronizar. Si sincroniza, el
      anclaje no está funcionando.

### Paso 6 — Operación

- **Las copias.** El `pg_dump` diario del cron de
  [`sincronizacion.md`](sincronizacion.md) §7, y **restaurarlo una vez** para saber
  que funciona.
- **Las actualizaciones.** `git pull && docker compose up -d --build`. Las
  migraciones se aplican solas al arrancar el contenedor.
- **El disco.** Un usuario son megabytes; lo que crece de verdad son las copias, y
  por eso el cron las rota a catorce días.
- **Si el servidor se apaga**, la app sigue entera: avisa una vez y funciona en
  local. Eso está probado con el transporte falso devolviendo error permanente.

### Paso 7 — Privacidad y textos

[`privacidad.md`](privacidad.md) describe lo que sale del móvil: rutinas,
ejercicios, entrenamientos con sus series, medidas, favoritos, preferencias y el
correo. **Nada más.** Si al desplegar decides mandar algo distinto, ese fichero
cambia con ello. Si no cambia nada, aquí no hay trabajo.

---

## Lo que NO hay que hacer

Media hora de trabajo evitada por cada línea de esta lista:

- **No añadir ningún SDK ni ninguna dependencia al cliente.** Se habla REST con el
  `http` que ya estaba.
- **No montar *deep links* ni tocar el `AndroidManifest.xml`.** El permiso de
  INTERNET ya está y es lo único que hacía falta.
- **No tocar `schemaVersion` ni `versionCopia`.** Siguen en 8 y en 4. Conectar el
  backend no es un cambio de esquema.
- **No poner `APPGYM_JWT_SECRETO` en CI, en el APK ni en el repositorio.** Vive
  solo en el `.env` del servidor.
- **No exponer el puerto de la API ni el de Postgres** en el compose. Solo Caddy
  habla con la API, y eso es lo que hace fiable la cabecera `X-Forwarded-For` que
  lee el límite de peticiones.
- **No tocar las tres invariantes del reloj** (`servidor/appgym/sincro.py`): se
  siembra en milisegundos de época, `subir` no mira la hora de pared y `bajar` lee
  el reloj **antes** que las filas. Cada una tapa un fallo que no se ve hasta que
  el usuario tiene datos, y las tres tienen su test.

---

## Limitaciones que hereda quien lo despliegue

No son cosas por hacer; son cosas que hay que saber antes de encenderlo.

- **No hay «he olvidado mi contraseña».** Hasta que el servidor tenga correo
  saliente, una contraseña perdida es una cuenta perdida. Por eso el diálogo de
  crear cuenta la pide dos veces y lo dice en su texto. Los datos locales del móvil
  no se pierden por eso.
- **«Este dispositivo manda» vacía el servidor con un borrado duro, sin lápidas.**
  Un *tercer* dispositivo ya enlazado no se entera y conserva sus datos locales.
  Con dos dispositivos, que es el caso de uso de K, no se da.
- **El aviso de la cabecera aproxima** «cambios pendientes desde hace más de un
  día» por «sin una pasada buena en más de un día».
- **La sesión en curso no se sincroniza** (K6), no hay tiempo real y no hay
  resolución manual de conflictos (K5).
- **Sin cifrado extremo a extremo.** Evaluado y aplazado en K9: con una
  autenticación sin segundo factor, perder la clave sería perderlo todo.
- **El límite de peticiones vive en memoria del proceso**, así que el servidor
  corre con un solo *worker*. Para este volumen sobra; el día que no sobre, se muda
  a Redis y se suben los *workers*.

---

## Si el backend acabara siendo otro

Sigue siendo reversible y el trabajo está acotado: **escribir otro fichero como
`servidor.dart`**, implementando los nueve métodos de `SincroTransporte`:

```
sesionActual()   registrar(correo, contrasena)   entrar(correo, contrasena)   salir()
bajar(cursor)    subir(paquete)                  resumen()   vaciar()   borrarCuenta()
```

Con tres requisitos que no son del proveedor sino del motor: el reloj es **suyo**,
se siembra en milisegundos de época y solo crece; `subir` devuelve
`{sellos, cursor, cursorPrevio}`; y `bajar` acota las filas con el cursor que va a
devolver. La especificación ejecutable de todo eso es `test/sincro_falso.dart`, y
`test/importaciones_test.dart` es lo que impide que el nombre del servidor se
escape de `lib/datos/sincro/`.

---

## Checklist

```
[ ] 1. Máquina con Docker, dominio apuntando y puertos 80/443 abiertos
[ ] 2. .env relleno (dominio, contraseña, llave) y `docker compose up -d --build`
[ ] 2. `curl https://tu-dominio/salud` contesta
[ ] 3. Secretos API_URL y API_ANCLAS en el repositorio
[ ] 3. APK instalado: el grupo «Cuenta» aparece en Ajustes
[ ] 4. Tu cuenta creada y APPGYM_REGISTRO_ABIERTO=false
[ ] 5. Prueba con dos dispositivos, con los cuatro casos del primer enlace
[ ] 5. Prueba del anclaje con un proxy interpuesto
[ ] 6. `pg_dump` diario en el cron, y una restauración probada
[ ] 7. privacidad.md sigue diciendo la verdad
```
