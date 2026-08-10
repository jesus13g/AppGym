# Montar el servidor de la sincronización

La sincronización de AppGym necesita **su propio servidor**: el de `servidor/`,
FastAPI y PostgreSQL, que se despliega con `docker compose` en cualquier VPS. Este
documento es el montaje completo, y está escrito para que un *fork* pueda tener el
suyo sin depender del servidor de nadie.

**Nada de esto hace falta para usar la app.** Sin configurar, la sincronización *no
existe*: no hay grupo de Cuenta en Ajustes y no hay disparador que haga nada. La app
funciona entera en local, y la copia de seguridad manual y la automática a Drive
siguen sin depender de esto.

> Hasta la fase 8c esto era un proyecto de Supabase. Ya no: la decisión O2 se
> reabrió y se cerró en la opción C de K2, **servidor propio**. El porqué está en
> `especificaciones-2.md`; en corto, no depender de un BaaS y poder probar el
> servidor con `pytest` en vez de con un guion SQL pegado a mano en un panel.

## 1. Lo que hace falta

- Una máquina con Docker: un VPS de 4-6 €/mes sobra. Los datos de un año de
  entrenamiento son del orden de un megabyte por usuario; lo que se paga no es el
  volumen, es tener la máquina encendida.
- Un dominio o subdominio apuntando a su IP con un registro `A`
  (`appgym.tudominio.com`).
- Los puertos **80 y 443** abiertos. El 80 lo usa Let's Encrypt para validar el
  dominio; sin él no hay certificado.

## 2. Levantarlo

```bash
git clone <este repositorio> && cd AppGym/servidor
cp .env.ejemplo .env
$EDITOR .env          # dominio, contraseña de la base y llave de firma
docker compose up -d --build
curl https://appgym.tudominio.com/salud     # {"estado":"vivo"}
```

Las dos cosas que hay que generar, y que **no se teclean a mano**:

```bash
python3 -c "import secrets; print(secrets.token_urlsafe(24))"   # POSTGRES_PASSWORD
python3 -c "import secrets; print(secrets.token_urlsafe(48))"   # APPGYM_JWT_SECRETO
```

`APPGYM_JWT_SECRETO` es la llave con la que se firman los accesos. **No sale del
`.env`**: no va a CI, no va al APK y no se escribe en el repositorio. Si se
cambia, los accesos vivos dejan de valer y cada móvil renueva una vez; los
refrescos siguen sirviendo, porque están en la base.

Caddy pide el certificado a Let's Encrypt en el primer arranque y lo renueva solo.
En local, con `APPGYM_DOMINIO=localhost`, usa su CA interna y el compose entero
funciona igual.

## 3. Cerrar el registro en cuanto tengas tu cuenta

Crea tu cuenta desde la app (paso 5) y **entonces**:

```bash
sed -i 's/^APPGYM_REGISTRO_ABIERTO=.*/APPGYM_REGISTRO_ABIERTO=false/' .env
docker compose up -d
```

El APK de las releases es público y cualquiera puede sacar de él la URL del
servidor. Con el registro abierto, cualquiera puede darse de alta: es tu cuota, tu
disco y **datos de salud ajenos que pasas a custodiar**. Cerrarlo es una línea.

## 4. El anclaje de certificado

Es lo que hace que la app **solo** se crea a la autoridad de tu servidor. Con
anclaje, un proxy de inspección —o un certificado mal emitido por cualquier
autoridad del mundo— no puede leer ni modificar el tráfico: el apretón de manos
falla y la petición no llega a salir.

Se pasa como `--dart-define API_ANCLAS=<el PEM en base64>`. Qué poner dentro:

**Con Let's Encrypt** (lo normal). Los dos raíces de LE, que duran hasta 2035, así
que las renovaciones cada 60 días no obligan a publicar un APK:

```bash
curl -s https://letsencrypt.org/certs/isrgrootx1.pem  >  anclas.pem
curl -s https://letsencrypt.org/certs/isrg-root-x2.pem >> anclas.pem
base64 -w0 anclas.pem
```

**Con la CA interna de Caddy** (`tls internal` en el `Caddyfile`). Es el anclaje
más estrecho: ningún certificado público vale, solo el tuyo. La API no la visita
ningún navegador, así que no necesita una autoridad pública. El raíz dura diez
años:

```bash
docker compose exec caddy cat /data/caddy/pki/authorities/local/root.crt | base64 -w0
```

**Sin `API_ANCLAS` la app funciona igual**, con las autoridades del sistema: sigue
habiendo TLS, pero no hay anclaje.

> **El volumen `caddy_datos` hay que conservarlo.** Ahí viven el certificado y su
> clave. Perderlo con la CA interna significa una CA nueva, y con ella un APK
> nuevo para todos los móviles.

## 5. Compilar la app apuntando ahí

```bash
flutter build apk --release \
  --dart-define API_URL=https://appgym.tudominio.com \
  --dart-define API_ANCLAS=$(base64 -w0 anclas.pem)
```

En CI son los secretos `API_URL` y `API_ANCLAS` del repositorio (*Settings →
Secrets and variables → Actions*). Si no están, llegan vacíos, la sincronización
queda desactivada y no visible, y el APK se construye igual: es lo que hace que un
*fork* compile sin tener que tocar nada.

**Cómo comprobar que han entrado**, sin leer ningún log: instala el APK y abre
*Ajustes*. Si aparece el grupo «Cuenta», la URL llegó. Si no aparece, no.

## 6. Comprobar que el servidor hace lo que promete

A diferencia de la versión anterior —donde el servidor era SQL en un panel y no
había forma de probarlo—, aquí eso está automatizado:

```bash
cd servidor
createdb appgym_test
pytest -q          # el reloj, el aislamiento, la cuenta, la concurrencia
```

Y el contrato entre la app y el servidor, de extremo a extremo, con el servidor
levantado de verdad:

```bash
docker compose up -d
flutter test --tags red --dart-define API_URL=https://localhost
```

Ese test está fuera de la suite por defecto (`flutter test` no lo ejecuta) porque
necesita el servidor en pie. Es el sustituto del guion SQL manual que había aquí.

## 7. Las copias

El plan es un `pg_dump` diario, comprimido y rotado a 14 días, en el cron del
anfitrión:

```cron
0 4 * * * cd /ruta/AppGym/servidor && docker compose exec -T db \
  pg_dump -U appgym appgym | gzip > copias/appgym-$(date +\%F).sql.gz && \
  find copias -name 'appgym-*.sql.gz' -mtime +14 -delete
```

**Prueba la restauración una vez.** Una copia que no se ha restaurado nunca no es
una copia, es un fichero.

Aun así, conviene tenerlo claro: **la nube no es la copia de seguridad del
usuario**. La suya es la exportación de *Ajustes → Datos*, que no depende de nada
externo, y la copia automática a Drive de la fase 8a.

## Qué sale del móvil

Exactamente las tablas que lista K6 en `especificaciones-2.md`: rutinas,
ejercicios, entrenamientos con sus series, medidas, favoritos y preferencias. Más
el correo, para la cuenta. **Nada más.** El detalle, en lenguaje llano, está en
[`privacidad.md`](privacidad.md).

Lo que **no** sale: el catálogo de ejercicios (1.324 filas regenerables desde un
*asset*), el historial de navegación, la sesión en curso, las imágenes —que son
© Gym visual y redistribuirlas fuera de sus condiciones no sería legal— y las
claves de dispositivo de `Claves.locales`.

Y lo que el servidor **no** guarda de la cuenta: la contraseña. Guarda su hash
Argon2id, que no se puede deshacer.
