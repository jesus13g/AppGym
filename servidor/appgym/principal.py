"""La app de FastAPI.

Tres cosas que no son evidentes:

  · **Sin CORS, y no por olvido.** A esta API la llama un APK, nunca un
    navegador. No declarar ningún origen permitido es lo que hace que una página
    web no pueda hablar con ella aunque el usuario tenga la sesión abierta.

  · **Sin documentación pública.** `/docs` y `/openapi.json` quedan fuera en
    producción: describen la superficie entera a quien encuentre la URL, y el
    único cliente ya sabe hablarla. Se encienden con `APPGYM_DOCS=1` para
    desarrollar.

  · **Todos los errores salen como `{"mensaje": "..."}`**, incluidos los de
    validación de pydantic, que de fábrica salen como una lista de objetos que el
    móvil no sabría enseñar.
"""

import logging
import os
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as ErrorHttp

from . import bd
from .errores import ErrorApi
from .rutas_auth import rutas as rutas_auth
from .rutas_sincro import rutas as rutas_sincro

registro = logging.getLogger("appgym")


@asynccontextmanager
async def _ciclo(app: FastAPI) -> AsyncIterator[None]:
    yield
    await bd.cerrar()


def crear_app() -> FastAPI:
    docs = os.getenv("APPGYM_DOCS") == "1"
    app = FastAPI(
        title="AppGym",
        version="1.0.0",
        lifespan=_ciclo,
        docs_url="/docs" if docs else None,
        redoc_url=None,
        openapi_url="/openapi.json" if docs else None,
    )

    @app.exception_handler(ErrorApi)
    async def _error_api(_: Request, e: ErrorApi) -> JSONResponse:
        return JSONResponse(status_code=e.estado, content={"mensaje": e.mensaje})

    @app.exception_handler(RequestValidationError)
    async def _error_validacion(_: Request, e: RequestValidationError) -> JSONResponse:
        # Se resume el primer fallo. El cliente valida antes de enviar, así que
        # esto es una red de seguridad, no una pantalla que alguien vaya a leer a
        # menudo.
        primero = e.errors()[0] if e.errors() else {}
        campo = ".".join(str(p) for p in primero.get("loc", ()) if p != "body")
        detalle = primero.get("msg", "no vale")
        return JSONResponse(
            status_code=400,
            content={"mensaje": f"Datos incorrectos{f' en {campo}' if campo else ''}: {detalle}."},
        )

    @app.exception_handler(ErrorHttp)
    async def _error_http(_: Request, e: ErrorHttp) -> JSONResponse:
        return JSONResponse(status_code=e.status_code, content={"mensaje": str(e.detail)})

    @app.exception_handler(Exception)
    async def _error_inesperado(_: Request, e: Exception) -> JSONResponse:
        # Se registra entero aquí y sale una frase sin detalles: una traza en la
        # respuesta es un mapa del servidor para quien la lea.
        registro.exception("fallo no controlado", exc_info=e)
        return JSONResponse(status_code=500, content={"mensaje": "Error interno del servidor."})

    @app.get("/salud", include_in_schema=False)
    async def salud() -> dict[str, str]:
        """Lo que mira el `healthcheck` del compose. No toca la base a propósito:
        si la base está caída, quien tiene que quejarse es su propio healthcheck."""
        return {"estado": "vivo"}

    app.include_router(rutas_auth)
    app.include_router(rutas_sincro)
    return app


app = crear_app()
