# Política de privacidad de AppGym

Última actualización: agosto de 2026.

## Lo corto

**AppGym no recoge nada.** Todos tus datos viven en la base SQLite de tu propio
dispositivo, y ahí se quedan salvo que tú digas lo contrario. No hay analítica,
ni identificadores de publicidad, ni telemetría.

Hay **dos** funcionalidades que pueden sacar datos del móvil, y las dos están
**apagadas de fábrica**: hay que encenderlas expresamente.

1. La **copia automática**, que sube el fichero de copia de seguridad a **tu
   propio Google Drive**. Aquí no hay servidor de por medio.
2. La **sincronización**, que copia tus datos a **una cuenta** para que aparezcan
   en tu tableta. Esta sí usa un servidor.

Sin encender ninguna de las dos, la app funciona entera y no sale un byte del
dispositivo.

## La copia automática

Si la enciendes, la app sube el mismo fichero JSON que genera «Exportar copia de
seguridad» a una carpeta llamada `AppGym` **de tu propio Google Drive**.

- **Van tus rutinas, tus ejercicios, tus sesiones con sus series, tus medidas
  corporales y tus preferencias.** Es exactamente lo que exporta la copia
  manual. Las medidas corporales (peso, grasa, perímetros) son datos de salud;
  por eso esto se dice aquí y por eso la funcionalidad no se enciende sola.
- **No va nada más.** Ni contactos, ni localización, ni tu agenda, ni la lista
  de apps que tienes instaladas.
- **El destino es tuyo, no nuestro.** El fichero está en tu cuenta de Drive, con
  tu cuota y bajo tu control. Quien mantiene esta app no tiene acceso a él ni a
  ninguna copia de él: **no hay ningún servidor intermedio**.
- **Se conservan las 10 copias más recientes**, y las anteriores se borran solas.

## Qué permiso se pide, y por qué ese

Se pide el ámbito de OAuth `https://www.googleapis.com/auth/drive.file`, que
permite a la app **crear ficheros y modificar únicamente los que ella misma ha
creado**.

Con ese permiso la app **no puede leer el resto de tu Drive**: ni tus documentos,
ni tus fotos, ni ningún fichero que no haya escrito ella. Se eligió justamente
por eso, pudiendo haber pedido acceso completo.

También se pide `email`, y solo se usa para enseñarte en Ajustes qué cuenta has
conectado.

## Dónde se guarda la sesión

El permiso duradero (*refresh token*) que Google entrega al conectar se guarda en
el **almacén seguro del sistema** (Keystore, mediante `EncryptedSharedPreferences`
en Android). En concreto **no** se guarda en la tabla de preferencias de la app,
porque esa tabla sí entra en el fichero de copia de seguridad que tú puedes
compartir.

Por el mismo motivo, la cuenta conectada y la fecha de la última copia **no
viajan** dentro del fichero de copia: son estado de ese dispositivo.

## Cómo se revoca

Tres caminos, y cualquiera basta:

1. **Ajustes → Copia automática → Desconectar.** Revoca el permiso contra Google
   y borra el token del dispositivo.
2. **Desde tu cuenta de Google**, en <https://myaccount.google.com/permissions>.
3. **Desinstalando la app.**

Desconectar **no borra** nada: ni los datos de tu móvil ni las copias que ya
estén en tu Drive. Esas son tuyas y se quedan donde están; puedes borrarlas desde
Drive cuando quieras.

## La sincronización

Es lo único de esta app que usa un servidor, y por eso se explica entero.

### Qué se guarda ahí

- **Tus rutinas, tus ejercicios, tus sesiones con sus series, tus medidas
  corporales y tus preferencias.** Es lo mismo que exporta la copia manual.
- **Tu correo**, que es la cuenta. Sirve para entrar y para poder avisarte si
  algún día hubiera que hacerlo.

**Y nada más.** Ni contactos, ni localización, ni identificadores de publicidad,
ni analítica, ni la lista de apps que tienes instaladas. Tampoco viaja el
catálogo de ejercicios (viene dentro de la app), ni el historial de lo que has
mirado, ni la sesión que tengas a medias.

Las medidas corporales (peso, grasa, perímetros) son datos de salud. Por eso esto
se dice aquí, por eso la funcionalidad no se enciende sola y por eso puedes
borrarla entera cuando quieras.

### Dónde y con qué aislamiento

En un proyecto de [Supabase](https://supabase.com) (PostgreSQL alojado). Cada
fila lleva tu identificador de usuario y el acceso está restringido en el propio
servidor con *row level security*: **una cuenta solo puede leer y escribir sus
filas**, y eso lo comprueba la base de datos, no la app. Todo el tráfico va por
TLS.

### Dónde se guarda tu sesión

En el **almacén seguro del sistema** (Keystore en Android), igual que el permiso
de Drive y por el mismo motivo: la tabla de preferencias entra en el fichero de
copia de seguridad que tú puedes compartir, y una sesión dentro de un JSON que
viaja por correo es una fuga. El interruptor de «Sincronizar» tampoco viaja en la
copia: es estado de ese dispositivo.

### Cifrado extremo a extremo: evaluado y descartado

Cifrar en tu dispositivo con una clave que el servidor no tenga es lo más
protector, y tiene dos costes que aquí pesan más: el servidor no podría resolver
nada sobre los datos (ni un borrado selectivo, ni una migración de formato), y
**perder la clave sería perder los datos** sin recuperación posible — en una app
sin contraseña, donde la recuperación es precisamente el correo, eso abre un
agujero peor que el que tapa. Se documenta como camino futuro.

### Sin garantía, y cómo tener el tuyo

Las *releases* oficiales apuntan a un proyecto personal, sin ninguna garantía de
disponibilidad: puede dejar de funcionar en cualquier momento. Si prefieres no
depender de eso, [`sincronizacion.md`](sincronizacion.md) explica cómo montar tu
propio proyecto en media hora. Una compilación local o un *fork* traen la
sincronización **desactivada y no visible**.

## Tus derechos

- **Portabilidad y acceso.** «Exportar copia de seguridad» genera un JSON abierto
  y documentado con todo tu histórico, y «Exportar a CSV» una fila por serie. No
  dependen de nada externo.
- **Borrado.** «Borrar todos los datos» vacía la base local. Las copias de tu
  Drive las borras tú desde Drive.
- **Borrado de la cuenta.** *Ajustes → Cuenta → Borrar la cuenta* elimina de
  verdad tu usuario y todas tus filas del servidor, en la misma operación. No
  queda una copia marcada como borrada: se borra. **Tus datos locales no se
  tocan**, porque la nube es una copia y no el original.
- **Cerrar sesión sin borrar nada.** Deja los datos donde estén, aquí y en la
  cuenta. Y si vendes o prestas el móvil, *Cerrar sesión → Borrar los datos de
  este dispositivo* limpia solo este aparato.

## Las imágenes de los ejercicios

La app descarga las imágenes y los GIF del catálogo desde el repositorio público
del conjunto de datos original. Esas peticiones son descargas anónimas: no llevan
ningún identificador tuyo. Puedes no descargarlas y la app funciona igual.

## Sin garantía de servicio

Este es un proyecto personal, distribuido como APK desde las *releases* de
GitHub. La copia automática depende de Google Drive y la sincronización de un
proyecto de Supabase personal; las dos dependen de que las credenciales de la
compilación sigan activas, y cualquiera de las dos puede dejar de funcionar en
cualquier momento. Si eso pasa, la app avisa una vez y **sigue funcionando en
local**. **La exportación manual no depende de nada de eso y seguirá estando.**

## Contacto

Abriendo una incidencia en <https://github.com/jesus13g/AppGym/issues>.
