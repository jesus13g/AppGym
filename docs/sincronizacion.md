# Montar la sincronización en un proyecto propio

La sincronización de AppGym necesita un proyecto de [Supabase](https://supabase.com). Este
documento es el montaje completo, y está escrito para que un *fork* pueda tener el suyo sin
depender del proyecto de nadie.

**Nada de esto hace falta para usar la app.** Sin configurar, la sincronización *no existe*:
no hay grupo de Cuenta en Ajustes y no hay disparador que haga nada. La app funciona entera
en local, igual que antes de la fase 8c, y la copia de seguridad manual y la automática
siguen sin depender de esto.

## 1. Crear el proyecto

Uno nuevo en [supabase.com/dashboard](https://supabase.com/dashboard). La región da igual;
la más cercana va mejor. El plan gratuito sobra: un año de entrenamiento es del orden de un
megabyte por usuario.

De *Project Settings → API* hacen falta dos valores:

- **Project URL** — `https://xxxxxxxx.supabase.co`
- **anon public key** — la clave pública. Es pública **por diseño**: lo que protege los datos
  es la RLS del paso siguiente, no el secreto de esta clave.

La **`service_role` key no se usa nunca** y no debe salir del panel. Si acaba en el APK,
cualquiera que lo descargue puede leer y borrar los datos de todos los usuarios.

## 2. Aplicar el esquema

Copiar `supabase/esquema.sql` entero en *SQL Editor → New query* y ejecutarlo. Crea:

- el esquema `appgym` con las tablas `filas` y `relojes`,
- la RLS de las dos, con una política por tabla,
- las cinco funciones que la app llama: `appgym_subir`, `appgym_bajar`, `appgym_resumen`,
  `appgym_vaciar` y `appgym_borrar_cuenta`.

Es idempotente: volver a ejecutarlo no destruye nada.

**No añadas `appgym` a *Exposed schemas*** (en *Project Settings → API*). Debe quedarse en
`public, graphql_public`, que es lo que viene de fábrica. Así la única superficie REST son
las cinco funciones. Las tablas llevan RLS igualmente, pero es superficie que no hace falta.

## 3. Activar el correo y **poner el código en la plantilla**

En *Authentication → Providers → Email*: activado, y **«Confirm email» activado**.

Y ahora el paso que más se olvida y sin el cual la app no funciona:

> En *Authentication → Emails → Magic Link*, la plantilla tiene que incluir `{{ .Token }}`.

AppGym entra con un **código de seis cifras**, no con un enlace: un enlace mágico exigiría
deep links, un *intent-filter* en el manifiesto y un dominio de redirección, y el APK aquí se
instala a mano desde una release. La plantilla de fábrica solo trae `{{ .ConfirmationURL }}`,
así que hay que añadir el código. Por ejemplo:

```html
<h2>Entrar en AppGym</h2>
<p>Tu código es:</p>
<p style="font-size:28px;letter-spacing:4px"><b>{{ .Token }}</b></p>
<p>Caduca en una hora. Si no has sido tú, ignora este correo.</p>
```

Si la plantilla no lleva `{{ .Token }}`, el usuario recibe un enlace, no tiene ningún código
que teclear y **no puede entrar**. Es el fallo más probable de todo el montaje.

**Si el proyecto es solo tuyo**, conviene además desactivar *Allow new users to sign up* en
*Authentication → Sign In / Providers* después de crear tu propia cuenta. Con el registro
abierto, cualquiera que instale el APK puede crear una cuenta en tu proyecto: es tu cuota y
son datos ajenos que pasas a custodiar.

## 4. Compilar apuntando ahí

En local:

```bash
flutter build apk --release \
  --dart-define SUPABASE_URL=https://xxxxxxxx.supabase.co \
  --dart-define SUPABASE_ANON_KEY=eyJhbGciOi...
```

En CI son los secretos `SUPABASE_URL` y `SUPABASE_ANON_KEY` del repositorio
(*Settings → Secrets and variables → Actions*). Si no están, llegan vacíos, la
sincronización queda desactivada y no visible, y el APK se construye igual: es lo que hace
que un *fork* compile sin tener que tocar nada.

## 5. Comprobar que el servidor hace lo que promete

**Ni una línea del SQL se puede probar con `flutter test`.** Es la única parte del proyecto en
esa situación, y por eso este guion existe: se pega en el editor SQL, con una sesión iniciada
desde la app para que `auth.uid()` no sea nulo, o envolviéndolo en un `set request.jwt.claims`.

El contrato que hay que ver cumplido es el que implementa `test/sincro_falso.dart`, que es la
especificación ejecutable del transporte:

```sql
-- 1. El reloj arranca en milisegundos de época, no en cero.
--    Si esto sale por debajo de 1.7e12, el móvil resubirá su histórico entero
--    en cada pasada y el fallo no se verá hasta que el usuario tenga datos.
select public.appgym_subir('[{"tabla":"rutinas","clave":"prueba-1",
                              "datos":{"nombre":"Empuje"}}]'::jsonb);
--    → cursor y cursorPrevio deben ser > 1700000000000

-- 2. Los sellos crecen, y `cursorPrevio` es donde estaba el servidor antes.
select public.appgym_subir('[{"tabla":"rutinas","clave":"prueba-2",
                              "datos":{"nombre":"Tirón"}}]'::jsonb);
--    → cursorPrevio == el `cursor` de la llamada anterior

-- 3. Bajar desde cero trae las dos; bajar desde el cursor no trae nada,
--    pero devuelve el cursor igual.
select public.appgym_bajar(0);
select public.appgym_bajar((select sello from appgym.relojes
                             where usuario = auth.uid()));

-- 4. Una lápida viaja como `datos: null`.
select public.appgym_subir('[{"tabla":"rutinas","clave":"prueba-2",
                              "datos":null}]'::jsonb);
select public.appgym_bajar(0);   -- prueba-2 sale con "datos": null

-- 5. El resumen no cuenta lápidas.
select public.appgym_resumen();  -- → {"rutinas": 1, "sesiones": 0}

-- 6. Vaciar borra las filas y NO reinicia el reloj.
select public.appgym_vaciar();
select public.appgym_resumen();                                    -- ceros
select sello from appgym.relojes where usuario = auth.uid();       -- sigue alto
```

Y el aislamiento, que es el único test que necesita red y que K9 pide: con la sesión de un
usuario, intentar leer las filas de otro tiene que devolver cero filas, no un error y no
datos.

```sql
select count(*) from appgym.filas where usuario <> auth.uid();  -- → 0
```

## Qué sale del móvil

Exactamente las tablas que lista K6 en `especificaciones-2.md`: rutinas, ejercicios,
entrenamientos con sus series, medidas, favoritos y preferencias. Más el correo, para la
cuenta. **Nada más.** El detalle, en lenguaje llano, está en
[`privacidad.md`](privacidad.md).

Lo que **no** sale: el catálogo de ejercicios (1.324 filas regenerables desde un *asset*), el
historial de navegación, la sesión en curso, las imágenes —que son © Gym visual y
redistribuirlas fuera de sus condiciones no sería legal— y las claves de dispositivo de
`Claves.locales`.
