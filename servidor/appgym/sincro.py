"""El buzón con reloj: subir, bajar, resumen y vaciar.

La lógica va aquí y no en las rutas porque es lo único del servidor que **no se
puede tocar sin pensar**: son cuatro funciones con tres invariantes, y cada
invariante tapa un fallo que no se ve hasta que el usuario tiene datos. Las rutas
son la capa fina de encima.
"""

import uuid

from sqlalchemy import BigInteger, cast, delete, func, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from .esquemas import Cifras, FilaEntrante, FilaSaliente, Paquete, RespuestaSubida
from .modelos import Fila, Reloj


async def _sembrar_reloj(s: AsyncSession, usuario_id: uuid.UUID) -> None:
    """La primera subida de una cuenta siembra su reloj con la hora de época.

    En milisegundos, y no en cero: ver la nota larga de `modelos.Reloj`. Es la
    invariante que, incumplida, hace que cada pasada resuba el histórico entero.
    """
    await s.execute(
        pg_insert(Reloj)
        .values(
            usuario_id=usuario_id,
            sello=cast(func.extract("epoch", func.clock_timestamp()) * 1000, BigInteger),
        )
        .on_conflict_do_nothing(index_elements=[Reloj.usuario_id])
    )


async def subir(
    s: AsyncSession, usuario_id: uuid.UUID, filas: list[FilaEntrante]
) -> RespuestaSubida:
    """Escribe las filas y devuelve el sello que le tocó a cada una.

    Bloquea el reloj del usuario (`FOR UPDATE`), reparte sellos estrictamente
    crecientes **en el orden en que llegaron**, escribe y actualiza el reloj. Todo
    dentro de la transacción de la petición: dos móviles subiendo a la vez se
    ordenan en el bloqueo, que es lo que hace que «gana quien llega el último»
    signifique algo.

    **No mira la hora de pared.** El reloj solo avanza +1 por fila aceptada; si
    aquí se pusiera la hora actual, `cursorPrevio` no volvería a casar con el
    cursor del cliente y cada móvil se descargaría su propio eco.
    """
    await _sembrar_reloj(s, usuario_id)

    previo = await s.scalar(
        select(Reloj.sello).where(Reloj.usuario_id == usuario_id).with_for_update()
    )
    previo = int(previo or 0)

    # Deduplicado: dos filas con la misma (tabla, clave) en el mismo envío no
    # pueden escribirse dos veces en una sentencia. Se queda **la última enviada**,
    # que es la fresca, y ocupa su sitio al final para que el sello siga el orden
    # de llegada.
    limpias: dict[tuple[str, str], FilaEntrante] = {}
    for fila in filas:
        clave = (fila.tabla, fila.clave)
        limpias.pop(clave, None)
        limpias[clave] = fila

    if not limpias:
        # El cliente no llega aquí con el paquete vacío, pero devolver el reloj
        # quieto es lo honesto: no se ha sellado nada.
        return RespuestaSubida(sellos={}, cursor=previo, cursorPrevio=previo)

    sellos: dict[str, int] = {}
    valores = []
    for numero, ((tabla, clave), fila) in enumerate(limpias.items(), start=1):
        sello = previo + numero
        sellos[f"{tabla}/{clave}"] = sello
        valores.append(
            {
                "usuario_id": usuario_id,
                "tabla": tabla,
                "clave": clave,
                "actualizado": sello,
                "datos": fila.datos,
            }
        )

    sentencia = pg_insert(Fila).values(valores)
    await s.execute(
        sentencia.on_conflict_do_update(
            index_elements=[Fila.usuario_id, Fila.tabla, Fila.clave],
            set_={
                "actualizado": sentencia.excluded.actualizado,
                "datos": sentencia.excluded.datos,
            },
        )
    )

    cursor = previo + len(limpias)
    await s.execute(
        Reloj.__table__.update().where(Reloj.usuario_id == usuario_id).values(sello=cursor)
    )
    return RespuestaSubida(sellos=sellos, cursor=cursor, cursorPrevio=previo)


async def bajar(s: AsyncSession, usuario_id: uuid.UUID, cursor: int) -> Paquete:
    """Lo que haya con sello posterior a [cursor].

    **El reloj se lee ANTES que las filas, y las filas se acotan por arriba con
    él.** Al revés —filas primero, reloj después— una subida de otro dispositivo
    que se colara en medio adelantaría el cursor por encima de filas que este
    cliente no ha recibido, y esas filas no se bajarían jamás. Es la única forma
    de perder datos que hay en todo el servidor, así que el orden de estas dos
    consultas no es estético.

    Devuelve el cursor también cuando no hay nada: el cliente tiene que avanzarlo
    igual.
    """
    tope = await s.scalar(select(Reloj.sello).where(Reloj.usuario_id == usuario_id))
    tope = int(tope or 0)
    desde = max(int(cursor or 0), 0)

    resultado = await s.execute(
        select(Fila.tabla, Fila.clave, Fila.actualizado, Fila.datos)
        .where(
            Fila.usuario_id == usuario_id,
            Fila.actualizado > desde,
            Fila.actualizado <= tope,
        )
        .order_by(Fila.actualizado)
    )
    return Paquete(
        cursor=tope,
        filas=[
            FilaSaliente(tabla=f.tabla, clave=f.clave, actualizado=f.actualizado, datos=f.datos)
            for f in resultado
        ],
    )


async def resumen(s: AsyncSession, usuario_id: uuid.UUID) -> Cifras:
    """Las dos cifras del primer enlace. **Las lápidas no cuentan.**"""
    resultado = await s.execute(
        select(
            func.count().filter(Fila.tabla == "rutinas", Fila.datos.is_not(None)),
            func.count().filter(Fila.tabla == "entrenamientos", Fila.datos.is_not(None)),
        ).where(Fila.usuario_id == usuario_id)
    )
    rutinas, sesiones = resultado.one()
    return Cifras(rutinas=rutinas or 0, sesiones=sesiones or 0)


async def vaciar(s: AsyncSession, usuario_id: uuid.UUID) -> None:
    """Borra los datos y **conserva la cuenta y el reloj**.

    Lo usa «este dispositivo manda» del primer enlace.

    Que el reloj no se reinicie es deliberado: repartiría otra vez sellos ya
    usados, y un dispositivo cuyo cursor estuviera por encima no volvería a ver
    nunca lo que se subiera después.

    **Limitación conocida.** Es un borrado duro, sin lápidas. Un tercer
    dispositivo ya enlazado no se entera —no hay nada que bajar— y conserva sus
    datos locales; tampoco los resucita, porque no están pendientes. La
    alternativa —enterrarlo todo en vez de borrarlo— propagaría el borrado a los
    datos locales de ese tercer móvil, que es peor y contradice «desactivar la
    sincronización deja los datos locales intactos».
    """
    await s.execute(delete(Fila).where(Fila.usuario_id == usuario_id))
