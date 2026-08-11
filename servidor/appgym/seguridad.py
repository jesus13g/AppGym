"""Contraseñas, JWT y la dependencia que identifica al usuario.

Tres decisiones que conviene no volver a tomar:

  · **Argon2id para las contraseñas y SHA-256 para los refrescos.** No es
    incoherencia: una contraseña la elige una persona y hay que encarecer el
    diccionario; un refresco son 32 bytes aleatorios y no hay diccionario que
    probar, así que lo único que se necesita es que la base no guarde el secreto
    en claro. Y esa comprobación ocurre en cada renovación, donde un Argon2 se
    notaría.

  · **El acceso dura quince minutos y no es revocable; el refresco dura sesenta
    días y sí lo es.** Revocar un JWT exige consultarlo en la base en cada
    petición, que es justo lo que un JWT viene a evitar. La ventana de quince
    minutos es el precio, y a cambio `usuario_actual` sí carga al usuario, así
    que una cuenta borrada deja de funcionar en el acto.

  · **`aud` e `iss` se validan.** Un token firmado con el mismo secreto para otra
    cosa no vale aquí. Es gratis y cierra una clase entera de errores.
"""

import hashlib
import secrets
import uuid
from datetime import UTC, datetime, timedelta

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError, VerifyMismatchError
from fastapi import Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession

from .bd import sesion
from .config import ajustes
from .errores import NoAutenticado
from .modelos import Usuario

_hasher = PasswordHasher()

# Un hash de mentira contra el que verificar cuando el correo no existe. Sin esto,
# «no hay cuenta» contestaría en un microsegundo y «contraseña incorrecta» en
# cien milisegundos, y el tiempo de respuesta diría qué correos tienen cuenta por
# más que el mensaje sea el mismo.
_HASH_SEÑUELO = _hasher.hash("no existe esta cuenta, esto es un señuelo")


# ── Contraseñas ───────────────────────────────────────────────────────────────


def cifrar_contrasena(contrasena: str) -> str:
    return _hasher.hash(contrasena)


def comprobar_contrasena(hash_guardado: str | None, contrasena: str) -> bool:
    """Compara, y **tarda lo mismo** si el usuario no existe."""
    try:
        _hasher.verify(hash_guardado or _HASH_SEÑUELO, contrasena)
    except (VerifyMismatchError, VerificationError, InvalidHashError):
        return False
    return hash_guardado is not None


def hay_que_recifrar(hash_guardado: str) -> bool:
    """Si los parámetros de Argon2 han subido desde que se guardó."""
    return _hasher.check_needs_rehash(hash_guardado)


# ── El acceso (JWT) ───────────────────────────────────────────────────────────


def crear_acceso(usuario_id: uuid.UUID) -> tuple[str, int]:
    """Devuelve el token y cuántos segundos vive."""
    a = ajustes()
    ahora = datetime.now(UTC)
    segundos = a.acceso_minutos * 60
    carga = {
        "sub": str(usuario_id),
        "iss": a.jwt_emisor,
        "aud": a.jwt_audiencia,
        "iat": int(ahora.timestamp()),
        "exp": int((ahora + timedelta(seconds=segundos)).timestamp()),
        "jti": secrets.token_urlsafe(12),
    }
    return jwt.encode(carga, a.jwt_secreto, algorithm="HS256"), segundos


def leer_acceso(token: str) -> uuid.UUID:
    a = ajustes()
    try:
        carga = jwt.decode(
            token,
            a.jwt_secreto,
            algorithms=["HS256"],
            audience=a.jwt_audiencia,
            issuer=a.jwt_emisor,
            options={"require": ["exp", "iat", "sub", "aud", "iss"]},
        )
        return uuid.UUID(carga["sub"])
    except (jwt.InvalidTokenError, ValueError, KeyError) as e:
        raise NoAutenticado("La sesión no vale. Vuelve a entrar.") from e


# ── El refresco ───────────────────────────────────────────────────────────────


def nuevo_refresco() -> tuple[str, str]:
    """Un refresco nuevo: el token que se entrega y el hash que se guarda."""
    token = secrets.token_urlsafe(32)
    return token, huella_refresco(token)


def huella_refresco(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def caducidad_refresco() -> datetime:
    return datetime.now(UTC) + timedelta(days=ajustes().refresco_dias)


# ── Quién llama ───────────────────────────────────────────────────────────────


def _token_de(peticion: Request) -> str:
    cabecera = peticion.headers.get("Authorization", "")
    esquema, _, token = cabecera.partition(" ")
    if esquema.lower() != "bearer" or not token.strip():
        raise NoAutenticado("Falta la credencial.")
    return token.strip()


async def usuario_actual(peticion: Request, s: AsyncSession = Depends(sesion)) -> Usuario:
    """El usuario de la petición, o 401.

    **Carga al usuario de la base**, no se queda con el `sub` del token: así una
    cuenta borrada deja de funcionar en el acto y no dentro de quince minutos.
    """
    usuario_id = leer_acceso(_token_de(peticion))
    usuario = await s.get(Usuario, usuario_id)
    if usuario is None:
        raise NoAutenticado("La cuenta ya no existe.")
    return usuario
