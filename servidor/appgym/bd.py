"""La conexión y la sesión.

Una transacción por petición: la dependencia abre, la ruta trabaja y el
`async with` confirma al salir o deshace si algo levantó. Es la misma regla que
el motor del móvil aplica al aplicar un paquete —entra entero o no entra—, y es
lo que hace que una subida cortada a la mitad no deje el reloj adelantado sobre
filas que no llegaron a escribirse.
"""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from .config import ajustes

_motor: AsyncEngine | None = None
_sesiones: async_sessionmaker[AsyncSession] | None = None


def motor() -> AsyncEngine:
    global _motor
    if _motor is None:
        _motor = create_async_engine(
            ajustes().bd_url,
            pool_pre_ping=True,
            pool_size=5,
            max_overflow=5,
        )
    return _motor


def sesiones() -> async_sessionmaker[AsyncSession]:
    global _sesiones
    if _sesiones is None:
        _sesiones = async_sessionmaker(motor(), expire_on_commit=False)
    return _sesiones


async def cerrar() -> None:
    """Cierra el pool. La llama el apagado de la app y los tests."""
    global _motor, _sesiones
    if _motor is not None:
        await _motor.dispose()
    _motor = None
    _sesiones = None


async def sesion() -> AsyncIterator[AsyncSession]:
    """La dependencia de FastAPI. Una transacción por petición."""
    async with sesiones()() as s, s.begin():
        yield s


@asynccontextmanager
async def aparte() -> AsyncIterator[AsyncSession]:
    """Una transacción propia, que **sobrevive al fallo de la petición**.

    Hace falta para lo que hay que dejar escrito justo antes de contestar con un
    error: anotar un intento fallido y revocar una familia de refrescos. Con la
    transacción de la petición no sirve —levantar la deshace entera, así que el
    contador nunca subiría y el bloqueo por intentos no existiría—, y ese es
    exactamente el tipo de fallo que solo se descubre cuando alguien está
    probando contraseñas.
    """
    async with sesiones()() as s, s.begin():
        yield s
