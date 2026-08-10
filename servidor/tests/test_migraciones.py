"""Que las migraciones y los modelos digan lo mismo.

Es el equivalente del test de migraciones del móvil, y caza el mismo fallo: una
columna que se añadió al modelo y no a la migración. Sin esto, `create_all` en
los tests taparía el agujero y el despliegue —que solo pasa por Alembic— se
encontraría la tabla sin la columna.

Va contra una base **aparte**, que se crea y se tira aquí: aplicar migraciones
sobre la base de los demás tests las dejaría a medias.
"""

import os

import pytest
import sqlalchemy as sa
from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.config import Config
from alembic.migration import MigrationContext
from sqlalchemy import text

from appgym.modelos import Base

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _url_sincrona(nombre: str) -> str:
    url = os.environ["APPGYM_BD_URL"].replace("+asyncpg", "+psycopg2")
    return url.rsplit("/", 1)[0] + "/" + nombre


@pytest.fixture(scope="module")
def base_limpia():
    """Una base vacía donde aplicar las migraciones de cero."""
    nombre = "appgym_migraciones"
    mantenimiento = sa.create_engine(_url_sincrona("postgres"), isolation_level="AUTOCOMMIT")
    try:
        with mantenimiento.connect() as c:
            c.execute(text(f'drop database if exists "{nombre}"'))
            c.execute(text(f'create database "{nombre}"'))
    except sa.exc.ProgrammingError as e:  # pragma: no cover — falta de permisos
        pytest.skip(f"el usuario de pruebas no puede crear bases: {e}")
    finally:
        mantenimiento.dispose()

    yield _url_sincrona(nombre)

    mantenimiento = sa.create_engine(_url_sincrona("postgres"), isolation_level="AUTOCOMMIT")
    with mantenimiento.connect() as c:
        c.execute(text(f'drop database if exists "{nombre}"'))
    mantenimiento.dispose()


def test_las_migraciones_dejan_el_esquema_de_los_modelos(base_limpia, monkeypatch):
    monkeypatch.setenv("APPGYM_BD_URL", base_limpia)
    config = Config(os.path.join(RAIZ, "alembic.ini"))
    config.set_main_option("script_location", os.path.join(RAIZ, "migraciones"))

    command.upgrade(config, "head")

    motor = sa.create_engine(base_limpia)
    with motor.connect() as conexion:
        contexto = MigrationContext.configure(conexion, opts={"compare_type": True})
        diferencias = compare_metadata(contexto, Base.metadata)
    motor.dispose()

    assert diferencias == [], f"el esquema migrado no es el de los modelos: {diferencias}"
