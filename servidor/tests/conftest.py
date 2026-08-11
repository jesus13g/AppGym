"""El montaje de los tests.

Contra **PostgreSQL de verdad**, no contra SQLite: el servidor usa `jsonb`,
`on conflict do update` y `select … for update`, que son justamente las tres
piezas donde puede estar el fallo. Un doble en memoria probaría otra cosa.

La base se especifica con `APPGYM_BD_TEST` y por omisión es
`postgresql+asyncpg://appgym:appgym@127.0.0.1:5432/appgym_test`. El esquema se
crea una vez por sesión y cada test empieza con las tablas vacías.
"""

import os
import uuid
from collections.abc import AsyncIterator

import pytest
import pytest_asyncio

os.environ.setdefault(
    "APPGYM_BD_URL",
    os.getenv("APPGYM_BD_TEST", "postgresql+asyncpg://appgym:appgym@127.0.0.1:5432/appgym_test"),
)
os.environ.setdefault("APPGYM_JWT_SECRETO", "un-secreto-de-pruebas-suficientemente-largo-123456")
os.environ.setdefault("APPGYM_REGISTRO_ABIERTO", "true")

from httpx import ASGITransport, AsyncClient  # noqa: E402
from sqlalchemy import text  # noqa: E402

from appgym import bd  # noqa: E402
from appgym.config import ajustes  # noqa: E402
from appgym.limites import limitador  # noqa: E402
from appgym.modelos import Base  # noqa: E402
from appgym.principal import crear_app  # noqa: E402


@pytest_asyncio.fixture(scope="session", autouse=True)
async def _esquema() -> AsyncIterator[None]:
    async with bd.motor().begin() as conexion:
        await conexion.run_sync(Base.metadata.drop_all)
        await conexion.run_sync(Base.metadata.create_all)
    yield
    await bd.cerrar()


@pytest_asyncio.fixture(autouse=True)
async def _limpio() -> AsyncIterator[None]:
    """Tablas vacías y contadores a cero antes de cada test."""
    async with bd.sesiones()() as s, s.begin():
        await s.execute(text("truncate usuarios, filas, relojes, refrescos cascade"))
    limitador.olvidar()
    ajustes.cache_clear()
    yield


@pytest_asyncio.fixture
async def cliente() -> AsyncIterator[AsyncClient]:
    app = crear_app()
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://pruebas") as c:
        yield c


@pytest.fixture
def correo() -> str:
    """Un correo distinto por test, para que ninguno dependa del anterior."""
    return f"{uuid.uuid4().hex[:12]}@ejemplo.com"


CONTRASENA = "unaContrasenaLarga1"


async def registrar(cliente: AsyncClient, correo: str, contrasena: str = CONTRASENA) -> dict:
    respuesta = await cliente.post(
        "/auth/registro", json={"correo": correo, "contrasena": contrasena}
    )
    assert respuesta.status_code == 201, respuesta.text
    return respuesta.json()


def cabeceras(sesion: dict) -> dict[str, str]:
    return {"Authorization": f"Bearer {sesion['acceso']}"}
