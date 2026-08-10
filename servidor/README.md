# El servidor de AppGym

La API que sostiene las cuentas y la sincronización: **FastAPI + PostgreSQL**, con
autenticación por correo y contraseña y JWT. Se despliega con `docker compose` en
cualquier VPS y **no depende de ningún servicio gestionado**.

Es un buzón con reloj. El servidor **no sabe qué es una rutina**: guarda lo que el
móvil transporta (tabla, clave, sello y datos) y lo único que decide es el sello,
que es justamente lo que un cliente con la hora mal puesta no puede falsear. La
lógica de reconciliación —qué gana cuando dos móviles cambian lo mismo— vive
entera en la app.

## La API

| | |
|---|---|
| `POST /auth/registro` | crea la cuenta y devuelve sesión |
| `POST /auth/entrar` | correo y contraseña → sesión |
| `POST /auth/refrescar` | canjea el refresco por uno nuevo (rota) |
| `POST /auth/salir` | revoca **este** refresco y solo este |
| `DELETE /auth/cuenta` | borra la cuenta y sus datos |
| `POST /sincro/subir` | escribe filas y devuelve el sello de cada una |
| `GET /sincro/bajar?cursor=N` | lo que haya con sello posterior a N |
| `GET /sincro/resumen` | cuántas rutinas y sesiones hay en la cuenta |
| `POST /sincro/vaciar` | borra los datos y conserva la cuenta |

Todos los errores salen como `{"mensaje": "..."}`, en español y en una frase que
el usuario pueda leer.

## En local

Con Docker:

```bash
cp .env.ejemplo .env      # rellena POSTGRES_PASSWORD y APPGYM_JWT_SECRETO
sed -i 's/^APPGYM_DOMINIO=.*/APPGYM_DOMINIO=localhost/' .env
docker compose up -d --build
curl -k https://localhost/salud
```

Sin Docker, contra un Postgres que ya tengas:

```bash
pip install -e ".[dev]"
export APPGYM_BD_URL="postgresql+asyncpg://appgym:appgym@127.0.0.1:5432/appgym"
export APPGYM_JWT_SECRETO="$(python3 -c 'import secrets;print(secrets.token_urlsafe(48))')"
alembic upgrade head
uvicorn appgym.principal:app --reload
```

Con `APPGYM_DOCS=1` se encienden `/docs` y `/openapi.json`, que en producción
están apagados a propósito.

## Los tests

```bash
createdb appgym_test                 # una vez
pytest                               # 41 casos
ruff check . && ruff format --check .
```

Van contra **PostgreSQL de verdad**, no contra SQLite: el servidor usa `jsonb`,
`on conflict do update` y `select … for update`, que son las tres piezas donde
puede estar el fallo. La base sale de `APPGYM_BD_TEST` y por omisión es
`postgresql+asyncpg://appgym:appgym@127.0.0.1:5432/appgym_test`.

Lo que cubren, y por qué cada uno:

- **El reloj** (`test_sincro.py`) — que arranca en milisegundos de época, que los
  sellos crecen de uno en uno y que `cursorPrevio` es el cursor de la subida
  anterior. Las tres invariantes que, incumplidas, hacen que el móvil resuba su
  histórico entero o se descargue su propio eco en cada pasada.
- **El aislamiento** (`test_aislamiento.py`) — que ninguna operación de una cuenta
  ve, escribe ni borra nada de otra. En la versión anterior, con Supabase, este
  test **necesitaba red**; ahora no.
- **La cuenta** (`test_auth.py`) — bloqueo por intentos, el mismo mensaje para
  «no existe» y «contraseña incorrecta», rotación del refresco y, sobre todo, que
  **reutilizar un refresco mata la familia entera**.
- **La concurrencia** (`test_concurrencia.py`) — dos móviles subiendo a la vez no
  se llevan el mismo sello.
- **Las migraciones** (`test_migraciones.py`) — que el esquema que deja Alembic es
  el de los modelos. Caza la columna que se añadió al modelo y no a la migración.

## En un VPS

Hace falta un dominio apuntando a la máquina (un registro `A`) y los puertos 80 y
443 abiertos. Todo lo demás lo hace el compose.

```bash
git clone <este repo> && cd AppGym/servidor
cp .env.ejemplo .env && $EDITOR .env       # dominio, contraseña y llave
docker compose up -d --build
```

Caddy pide el certificado a Let's Encrypt en el primer arranque y lo renueva
solo. El paso a paso completo —incluido el anclaje de certificado de la app— está
en [`../docs/sincronizacion.md`](../docs/sincronizacion.md).

**En cuanto tengas tu cuenta creada, pon `APPGYM_REGISTRO_ABIERTO=false`** y
`docker compose up -d`. El APK es público y cualquiera que saque la URL podría
darse de alta: es tu cuota y datos de salud ajenos que pasarías a custodiar.

### Las copias

El plan es un `pg_dump` diario, comprimido y rotado a 14 días, en el cron del
anfitrión:

```cron
0 4 * * * cd /ruta/AppGym/servidor && docker compose exec -T db \
  pg_dump -U appgym appgym | gzip > copias/appgym-$(date +\%F).sql.gz && \
  find copias -name 'appgym-*.sql.gz' -mtime +14 -delete
```

Restaurar es `gunzip -c copia.sql.gz | docker compose exec -T db psql -U appgym appgym`
sobre una base vacía. **Prueba la restauración una vez**: una copia que no se ha
restaurado nunca no es una copia, es un fichero.

La nube no es la copia de seguridad del usuario, y no debe presentarse como tal:
la suya es la exportación de *Ajustes → Datos*, que no depende de nada externo.

## Estructura

```
appgym/
├── principal.py    la app FastAPI, los manejadores de error y /salud
├── config.py       los ajustes, todos por variable de entorno
├── bd.py           el motor, la sesión y la transacción aparte
├── modelos.py      usuarios · refrescos · filas · relojes
├── esquemas.py     los DTO, con los nombres que ya usa el cliente
├── seguridad.py    Argon2id, JWT y la dependencia `usuario_actual`
├── errores.py      los fallos y su código HTTP
├── limites.py      el límite de peticiones por IP
├── sincro.py       el buzón con reloj: subir · bajar · resumen · vaciar
├── rutas_auth.py   la cuenta
└── rutas_sincro.py los datos
```
