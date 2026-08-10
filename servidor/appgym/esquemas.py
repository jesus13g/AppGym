"""Los DTO de la API.

Los nombres de campo son **los mismos que usa el cliente** (`correo`, `filas`,
`tabla`, `clave`, `datos`, `sellos`, `cursor`, `cursorPrevio`), de modo que el
adaptador del móvil cambia de transporte pero no de vocabulario. El único
`camelCase` es `cursorPrevio`, y es a propósito: es el nombre que el motor de
reconciliación ya usa y renombrarlo aquí solo añadiría una traducción.
"""

import uuid

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator

# Diez caracteres, que es el mínimo que recomienda cualquiera hoy, y sin reglas de
# «una mayúscula y un símbolo»: obligan a contraseñas peores y más difíciles de
# recordar. La longitud es lo que importa.
LARGO_MINIMO_CONTRASENA = 10


class Credenciales(BaseModel):
    correo: EmailStr
    contrasena: str = Field(min_length=1, max_length=256)

    @field_validator("correo")
    @classmethod
    def _normalizar(cls, valor: str) -> str:
        return valor.strip().lower()


class Registro(Credenciales):
    contrasena: str = Field(min_length=LARGO_MINIMO_CONTRASENA, max_length=256)


class UsuarioPublico(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    correo: str


class Sesion(BaseModel):
    """Lo que devuelve entrar, registrarse y renovar.

    `expira_en` va en segundos, como en OAuth, porque es lo que el cliente
    necesita para saber cuándo renovar sin depender de que su reloj coincida con
    el del servidor.
    """

    acceso: str
    refresco: str
    expira_en: int
    usuario: UsuarioPublico


class PeticionRefresco(BaseModel):
    refresco: str = Field(min_length=1, max_length=512)


class FilaEntrante(BaseModel):
    """Una fila que sube el cliente.

    **No trae `actualizado`.** El sello lo pone el servidor, y que sea
    estructuralmente imposible que el reloj del móvil influya es mejor que
    ignorarlo por convenio: un móvil con la hora adelantada dos años no puede
    ganar todos los conflictos para siempre.
    """

    tabla: str = Field(min_length=1, max_length=64)
    clave: str = Field(min_length=1, max_length=128)
    datos: dict | None = None


class Subida(BaseModel):
    filas: list[FilaEntrante]


class RespuestaSubida(BaseModel):
    # `tabla/clave` → el sello que le tocó.
    sellos: dict[str, int]
    cursor: int
    cursorPrevio: int  # noqa: N815 — el nombre que ya usa el motor del cliente


class FilaSaliente(BaseModel):
    tabla: str
    clave: str
    actualizado: int
    datos: dict | None


class Paquete(BaseModel):
    cursor: int
    filas: list[FilaSaliente]


class Cifras(BaseModel):
    """Las dos cifras del primer enlace: «En la cuenta: 2 rutinas, 180 sesiones»."""

    rutinas: int
    sesiones: int
