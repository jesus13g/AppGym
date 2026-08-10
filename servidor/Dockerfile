# La imagen de la API. Slim y sin compilador: `argon2-cffi` y `asyncpg` traen
# ruedas precompiladas para linux/amd64 y linux/arm64, que es donde esto corre.
FROM python:3.12-slim

# PYTHONUNBUFFERED para que los logs salgan en el acto por `docker compose logs`,
# que si no aparecen a trozos y a destiempo.
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# Las dependencias en su propia capa: cambiar el código no vuelve a bajarlas.
COPY pyproject.toml ./
RUN pip install --no-cache-dir \
      "fastapi>=0.115" "uvicorn[standard]>=0.34" "sqlalchemy[asyncio]>=2.0.36" \
      "asyncpg>=0.30" "alembic>=1.14" "pydantic[email]>=2.10" "pydantic-settings>=2.7" \
      "pyjwt>=2.10" "argon2-cffi>=23.1" "psycopg2-binary>=2.9"

COPY appgym ./appgym
COPY migraciones ./migraciones
COPY alembic.ini arrancar.sh ./
RUN chmod +x arrancar.sh

# Sin privilegios: si algún día se escapa algo del proceso, que se escape a una
# cuenta que no puede tocar nada.
RUN useradd --system --uid 10001 appgym && chown -R appgym:appgym /app
USER appgym

EXPOSE 8000
CMD ["./arrancar.sh"]
