"""La cuenta: registrarse, entrar, renovar, salir y borrarse.

**Crear cuenta y entrar son dos rutas distintas.** Con código por correo eran el
mismo botón —el código creaba la cuenta si no existía—, pero con contraseña eso
sería un desastre: quien se equivoca al teclear su correo se crearía una cuenta
nueva y vacía en vez de recibir «contraseña incorrecta», y no entendería nada.
"""

import uuid
from datetime import UTC, datetime, timedelta

from fastapi import APIRouter, Depends, Response, status
from sqlalchemy import delete, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from . import bd
from .bd import sesion
from .config import ajustes
from .errores import Conflicto, DemasiadasPeticiones, NoAutenticado, SinPermiso
from .esquemas import Credenciales, PeticionRefresco, Registro, Sesion, UsuarioPublico
from .limites import limite_auth
from .modelos import Refresco, Usuario
from .seguridad import (
    caducidad_refresco,
    cifrar_contrasena,
    comprobar_contrasena,
    crear_acceso,
    hay_que_recifrar,
    huella_refresco,
    nuevo_refresco,
    usuario_actual,
)

rutas = APIRouter(prefix="/auth", tags=["cuenta"], dependencies=[Depends(limite_auth)])

# La misma frase para «ese correo no existe» y para «esa contraseña no es»: si
# fueran distintas, cualquiera podría averiguar qué correos tienen cuenta en este
# servidor probándolos de uno en uno.
_CREDENCIALES_MAL = "Correo o contraseña incorrectos."


async def _abrir_sesion(
    s: AsyncSession, usuario: Usuario, familia: uuid.UUID | None = None
) -> Sesion:
    """Emite el acceso y un refresco nuevo, y guarda su huella."""
    token, huella = nuevo_refresco()
    s.add(
        Refresco(
            usuario_id=usuario.id,
            token_hash=huella,
            familia=familia or uuid.uuid4(),
            caduca=caducidad_refresco(),
        )
    )
    acceso, expira_en = crear_acceso(usuario.id)
    return Sesion(
        acceso=acceso,
        refresco=token,
        expira_en=expira_en,
        usuario=UsuarioPublico.model_validate(usuario),
    )


async def _anotar_fallo(usuario_id: uuid.UUID) -> None:
    """Suma un intento fallido y bloquea la cuenta si ya son demasiados.

    **En su propia transacción**, porque justo después se levanta y la de la
    petición se deshace entera: ver la nota de `bd.aparte`. El incremento va en
    SQL y no en el objeto para que dos intentos a la vez no se pisen.
    """
    a = ajustes()
    async with bd.aparte() as s:
        fallos = await s.scalar(
            update(Usuario)
            .where(Usuario.id == usuario_id)
            .values(intentos_fallidos=Usuario.intentos_fallidos + 1)
            .returning(Usuario.intentos_fallidos)
        )
        if fallos is not None and fallos >= a.intentos_maximos:
            await s.execute(
                update(Usuario)
                .where(Usuario.id == usuario_id)
                .values(
                    intentos_fallidos=0,
                    bloqueado_hasta=datetime.now(UTC) + timedelta(minutes=a.bloqueo_minutos),
                )
            )


async def _revocar_familia(usuario_id: uuid.UUID, familia: uuid.UUID) -> None:
    """Mata la cadena entera de refrescos. También en su propia transacción."""
    async with bd.aparte() as s:
        await s.execute(
            update(Refresco)
            .where(Refresco.usuario_id == usuario_id, Refresco.familia == familia)
            .values(revocado=True)
        )


@rutas.post("/registro", status_code=status.HTTP_201_CREATED)
async def registro(datos: Registro, s: AsyncSession = Depends(sesion)) -> Sesion:
    if not ajustes().registro_abierto:
        raise SinPermiso("Este servidor no admite cuentas nuevas.")

    ya_esta = await s.scalar(select(Usuario.id).where(Usuario.correo == datos.correo))
    if ya_esta is not None:
        # Aquí sí se dice que el correo existe, y no hay forma de evitarlo sin
        # dejar la pantalla inservible: el usuario tiene que saber si debe entrar
        # en vez de registrarse. Lo que lo compensa es que el registro se puede
        # cerrar con `APPGYM_REGISTRO_ABIERTO=false`.
        raise Conflicto("Ese correo ya tiene una cuenta. Entra con tu contraseña.")

    usuario = Usuario(correo=datos.correo, contrasena_hash=cifrar_contrasena(datos.contrasena))
    s.add(usuario)
    await s.flush()
    return await _abrir_sesion(s, usuario)


@rutas.post("/entrar")
async def entrar(datos: Credenciales, s: AsyncSession = Depends(sesion)) -> Sesion:
    usuario = await s.scalar(select(Usuario).where(Usuario.correo == datos.correo))

    if usuario is not None and usuario.bloqueado_hasta is not None:
        if usuario.bloqueado_hasta > datetime.now(UTC):
            raise DemasiadasPeticiones(
                "Demasiados intentos fallidos. Prueba dentro de unos minutos."
            )
        usuario.bloqueado_hasta = None
        usuario.intentos_fallidos = 0

    # Se comprueba **siempre**, exista o no la cuenta: con un señuelo cuando no
    # existe, para que el tiempo de respuesta no delate qué correos hay.
    if not comprobar_contrasena(usuario.contrasena_hash if usuario else None, datos.contrasena):
        if usuario is not None:
            await _anotar_fallo(usuario.id)
        raise NoAutenticado(_CREDENCIALES_MAL)

    assert usuario is not None  # noqa: S101 — lo garantiza `comprobar_contrasena`
    usuario.intentos_fallidos = 0
    usuario.bloqueado_hasta = None
    usuario.ultimo_acceso = datetime.now(UTC)
    if hay_que_recifrar(usuario.contrasena_hash):
        usuario.contrasena_hash = cifrar_contrasena(datos.contrasena)
    return await _abrir_sesion(s, usuario)


@rutas.post("/refrescar")
async def refrescar(datos: PeticionRefresco, s: AsyncSession = Depends(sesion)) -> Sesion:
    """Canjea un refresco por otro. **El anterior deja de valer.**

    Si llega uno ya usado, hay dos poseedores del mismo token y uno de ellos no
    debería tenerlo: se revoca **la familia entera** y los dos vuelven a entrar.
    Es la única respuesta segura, y es la razón de que la familia exista.
    """
    guardado = await s.scalar(
        select(Refresco).where(Refresco.token_hash == huella_refresco(datos.refresco))
    )
    if guardado is None:
        raise NoAutenticado("La sesión ya no vale. Vuelve a entrar.")

    if guardado.usado or guardado.revocado:
        await _revocar_familia(guardado.usuario_id, guardado.familia)
        raise NoAutenticado("La sesión se ha cerrado por seguridad. Vuelve a entrar.")

    if guardado.caduca <= datetime.now(UTC):
        raise NoAutenticado("La sesión ha caducado. Vuelve a entrar.")

    usuario = await s.get(Usuario, guardado.usuario_id)
    if usuario is None:
        raise NoAutenticado("La cuenta ya no existe.")

    guardado.usado = True
    return await _abrir_sesion(s, usuario, familia=guardado.familia)


@rutas.post("/salir", status_code=status.HTTP_204_NO_CONTENT)
async def salir(datos: PeticionRefresco, s: AsyncSession = Depends(sesion)) -> Response:
    """Cierra **esta** sesión y solo esta.

    Salir en el móvil no puede cerrar la de la tableta: K3 dice «un usuario, N
    dispositivos». Y no da error si el refresco no existe: contestar distinto
    diría si un token es válido.
    """
    await s.execute(
        update(Refresco)
        .where(Refresco.token_hash == huella_refresco(datos.refresco))
        .values(revocado=True)
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@rutas.delete("/cuenta", status_code=status.HTTP_204_NO_CONTENT)
async def borrar_cuenta(
    usuario: Usuario = Depends(usuario_actual), s: AsyncSession = Depends(sesion)
) -> Response:
    """Borra la cuenta y sus datos. **Los del móvil no se tocan.**

    A quien se borra es a quien trae el token; no hay forma de nombrar a otro. Las
    filas, el reloj y los refrescos se van con el usuario por el `ON DELETE
    CASCADE`, en la misma transacción: no queda nada a medias.
    """
    await s.execute(delete(Usuario).where(Usuario.id == usuario.id))
    return Response(status_code=status.HTTP_204_NO_CONTENT)
