# Política de privacidad de AppGym

Última actualización: agosto de 2026.

## Lo corto

**AppGym no tiene servidor y no recoge nada.** Todos tus datos viven en la base
SQLite de tu propio dispositivo. No hay analítica, ni identificadores de
publicidad, ni telemetría, ni cuentas de usuario.

La única funcionalidad que saca datos del móvil es la **copia automática**, y
está **apagada de fábrica**: hay que encenderla y dar permiso expresamente.

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

## Tus derechos

- **Portabilidad y acceso.** «Exportar copia de seguridad» genera un JSON abierto
  y documentado con todo tu histórico, y «Exportar a CSV» una fila por serie. No
  dependen de nada externo.
- **Borrado.** «Borrar todos los datos» vacía la base local. Las copias de tu
  Drive las borras tú desde Drive.

## Las imágenes de los ejercicios

La app descarga las imágenes y los GIF del catálogo desde el repositorio público
del conjunto de datos original. Esas peticiones son descargas anónimas: no llevan
ningún identificador tuyo. Puedes no descargarlas y la app funciona igual.

## Sin garantía de servicio

Este es un proyecto personal, distribuido como APK desde las *releases* de
GitHub. La copia automática depende de Google Drive y de que las credenciales de
la compilación sigan activas; puede dejar de funcionar en cualquier momento. **La
exportación manual no depende de nada de eso y seguirá estando.**

## Contacto

Abriendo una incidencia en <https://github.com/jesus13g/AppGym/issues>.
