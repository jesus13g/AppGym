"""Las cuatro tablas del servidor.

Las dos primeras son la cuenta; las dos últimas son **el buzón con reloj**, y son
la traducción a SQLAlchemy del esquema que la fase 8c tenía escrito en SQL.

── Qué es el buzón ────────────────────────────────────────────────────────────

El servidor **no sabe qué es una rutina**: guarda lo que el cliente transporta
(tabla, clave, sello y datos) y lo único que decide es el sello. Que la carga
útil vaya en `jsonb` y no en seis tablas espejo es deliberado: el APK se instala
a mano desde una release, así que conviven versiones arbitrarias del cliente, y
con tablas espejo añadir una columna en el móvil exigiría desplegar aquí
**antes**. Con `jsonb` el servidor no se entera.
"""

import uuid
from datetime import datetime

from sqlalchemy import (
    BigInteger,
    Boolean,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    pass


class Usuario(Base):
    __tablename__ = "usuarios"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)

    # Normalizado a minúsculas y sin espacios **antes** de llegar aquí, para que
    # el índice único signifique de verdad «una cuenta por correo».
    correo: Mapped[str] = mapped_column(String(320), unique=True, nullable=False)

    # Argon2id. Nunca la contraseña, obviamente, y nunca un hash rápido: el coste
    # es lo único que protege una contraseña floja si algún día se filtra la base.
    contrasena_hash: Mapped[str] = mapped_column(Text, nullable=False)

    creado: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    ultimo_acceso: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    # El bloqueo por intentos fallidos vive aquí y no en memoria: reiniciar el
    # proceso no puede ser la forma de saltárselo.
    intentos_fallidos: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    bloqueado_hasta: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class Refresco(Base):
    """Un *refresh token* vivo. Rotatorio, y guardado **solo como hash**.

    Si se guardara en claro, quien leyera la base tendría la sesión de todos. Se
    guarda el SHA-256 —no Argon2— porque es un secreto de 32 bytes aleatorios y no
    una contraseña: no hay diccionario que probar contra él, y la comprobación
    tiene que ser barata porque ocurre en cada renovación.

    `familia` es lo que permite detectar un robo: cada cadena de rotaciones
    comparte familia, y si un refresco **ya usado** vuelve a aparecer es que hay
    dos poseedores. Entonces se revoca la familia entera y los dos vuelven a
    entrar, que es la única respuesta segura.
    """

    __tablename__ = "refrescos"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    usuario_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("usuarios.id", ondelete="CASCADE"), nullable=False
    )
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    familia: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)

    creado: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    caduca: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    usado: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    revocado: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)


Index("refrescos_familia", Refresco.usuario_id, Refresco.familia)


class Fila(Base):
    """Una fila del usuario, tal y como la transporta el cliente.

    `datos` a `NULL` es **una lápida**, igual que `FilaRemota.datos == null` en el
    móvil. Ojo con la distinción: el JSON `null` y el `NULL` de SQL no son lo
    mismo, y por eso la columna se declara con `none_as_null=True` — sin eso,
    SQLAlchemy guardaría el JSON `'null'` y ninguna lápida lo sería.
    """

    __tablename__ = "filas"

    usuario_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("usuarios.id", ondelete="CASCADE"), primary_key=True
    )
    tabla: Mapped[str] = mapped_column(String(64), primary_key=True)
    clave: Mapped[str] = mapped_column(String(128), primary_key=True)

    # El sello que puso este servidor. Estrictamente creciente por usuario.
    actualizado: Mapped[int] = mapped_column(BigInteger, nullable=False)

    datos: Mapped[dict | None] = mapped_column(JSONB(none_as_null=True))


# El índice del delta: `bajar` es exactamente esta consulta.
Index("filas_delta", Fila.usuario_id, Fila.actualizado)


class Reloj(Base):
    """El reloj de un usuario. Una fila, un contador.

    **Se siembra con la hora de época en milisegundos** y a partir de ahí solo
    sube +1 por cada fila aceptada. Las dos mitades importan y cada una tapa un
    fallo distinto:

      · **Sembrarlo alto.** El móvil sella sus cambios con
        `identidad.selloLocal()`, que son milisegundos de época, y sube todo lo
        que tenga `actualizado > cursorSubida`. Un servidor que empezara en 0
        dejaría ese cursor en un número de dos cifras, por debajo de todos los
        sellos locales, y **cada pasada resubiría el histórico entero, para
        siempre**.

      · **No volver a mirar la hora de pared después.** `bajar` devuelve este
        sello tal cual y `subir` devuelve el valor previo como `cursorPrevio`. El
        cliente compara ese `cursorPrevio` con su propio cursor de bajada para
        saber si lo que hay entre medias lo escribió él mismo; si `subir`
        adelantara el reloj a la hora actual, esa comparación no casaría nunca y
        cada móvil se descargaría su propio eco en cada pasada.

    Que el sello se aleje de la hora de pared no le importa a nadie: es un
    contador, no una fecha, y en ningún sitio se enseña.
    """

    __tablename__ = "relojes"

    usuario_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("usuarios.id", ondelete="CASCADE"), primary_key=True
    )
    sello: Mapped[int] = mapped_column(BigInteger, nullable=False)
