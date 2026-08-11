#!/bin/sh
# Migrar y arrancar, en ese orden.
#
# Las migraciones se aplican aquí y no a mano: un despliegue que exige acordarse
# de un comando acaba, antes o después, con el código nuevo contra el esquema
# viejo. Alembic es idempotente, así que reiniciar el contenedor no hace nada.
set -e

echo "· aplicando migraciones"
alembic upgrade head

echo "· arrancando la API"
# Un solo worker: el límite de peticiones vive en memoria del proceso (ver
# `limites.py`) y con varios cada uno contaría por su cuenta. Para el volumen de
# esto sobra; el día que no sobre, el límite se muda a Redis y aquí se sube el
# número.
exec uvicorn appgym.principal:app \
    --host 0.0.0.0 \
    --port 8000 \
    --workers 1 \
    --proxy-headers \
    --forwarded-allow-ips '*'
