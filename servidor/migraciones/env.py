"""El arranque de Alembic.

La URL sale de `APPGYM_BD_URL`, la misma que usa el servidor, y se traduce a
síncrona: las migraciones no ganan nada siendo asíncronas y `psycopg2` evita
tener que montar un bucle de eventos para ejecutarlas.
"""

import os
import sys
from logging.config import fileConfig
from pathlib import Path

from alembic import context
from sqlalchemy import engine_from_config, pool

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from appgym.modelos import Base  # noqa: E402

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

metadatos = Base.metadata


def _url() -> str:
    url = os.getenv("APPGYM_BD_URL", "postgresql+asyncpg://appgym:appgym@localhost:5432/appgym")
    return url.replace("+asyncpg", "+psycopg2")


def offline() -> None:
    context.configure(url=_url(), target_metadata=metadatos, literal_binds=True, compare_type=True)
    with context.begin_transaction():
        context.run_migrations()


def online() -> None:
    config.set_main_option("sqlalchemy.url", _url())
    motor = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    with motor.connect() as conexion:
        context.configure(connection=conexion, target_metadata=metadatos, compare_type=True)
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    offline()
else:
    online()
