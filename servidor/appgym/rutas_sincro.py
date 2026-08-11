"""Las cuatro operaciones de los datos.

Capa fina: autenticar, validar el tamaño y llamar a `sincro.py`. **Ningún
identificador de usuario entra por el cuerpo ni por la URL** — el usuario es
siempre el del token, y esa es toda la historia del aislamiento en este servidor.
"""

from fastapi import APIRouter, Depends, Query, Response, status
from sqlalchemy.ext.asyncio import AsyncSession

from . import sincro
from .bd import sesion
from .config import ajustes
from .errores import Rechazado
from .esquemas import Cifras, Paquete, RespuestaSubida, Subida
from .limites import limite_datos
from .modelos import Usuario
from .seguridad import usuario_actual

rutas = APIRouter(prefix="/sincro", tags=["datos"], dependencies=[Depends(limite_datos)])


@rutas.post("/subir")
async def subir(
    cuerpo: Subida,
    usuario: Usuario = Depends(usuario_actual),
    s: AsyncSession = Depends(sesion),
) -> RespuestaSubida:
    if len(cuerpo.filas) > ajustes().filas_maximas:
        raise Rechazado(
            f"Demasiadas filas en un envío (máximo {ajustes().filas_maximas}). "
            "El cliente debería mandarlas en lotes."
        )
    return await sincro.subir(s, usuario.id, cuerpo.filas)


@rutas.get("/bajar")
async def bajar(
    cursor: int = Query(0, ge=0),
    usuario: Usuario = Depends(usuario_actual),
    s: AsyncSession = Depends(sesion),
) -> Paquete:
    return await sincro.bajar(s, usuario.id, cursor)


@rutas.get("/resumen")
async def resumen(
    usuario: Usuario = Depends(usuario_actual),
    s: AsyncSession = Depends(sesion),
) -> Cifras:
    return await sincro.resumen(s, usuario.id)


@rutas.post("/vaciar", status_code=status.HTTP_204_NO_CONTENT)
async def vaciar(
    usuario: Usuario = Depends(usuario_actual),
    s: AsyncSession = Depends(sesion),
) -> Response:
    await sincro.vaciar(s, usuario.id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
