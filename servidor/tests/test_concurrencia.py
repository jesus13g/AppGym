"""Dos dispositivos subiendo a la vez.

Es el escenario para el que existe el `FOR UPDATE` de `sincro.subir`. Sin él, dos
subidas simultáneas leerían el mismo `previo` y repartirían **los mismos sellos**
a filas distintas: dos filas con el mismo sello, y un cliente que baje se dejaría
una de las dos fuera para siempre.
"""

import asyncio

from httpx import AsyncClient

from .conftest import cabeceras, registrar


async def test_dos_subidas_a_la_vez_no_repiten_sellos(cliente: AsyncClient, correo: str):
    sesion = await registrar(cliente, correo)

    async def subir(prefijo: str) -> dict:
        respuesta = await cliente.post(
            "/sincro/subir",
            json={
                "filas": [
                    {"tabla": "rutinas", "clave": f"{prefijo}{i}", "datos": {"nombre": prefijo}}
                    for i in range(10)
                ]
            },
            headers=cabeceras(sesion),
        )
        assert respuesta.status_code == 200, respuesta.text
        return respuesta.json()

    movil, tableta = await asyncio.gather(subir("m"), subir("t"))

    sellos = list(movil["sellos"].values()) + list(tableta["sellos"].values())
    assert len(sellos) == 20
    assert len(set(sellos)) == 20, "dos filas se han llevado el mismo sello"

    # Y el que llegó segundo arranca donde acabó el primero: los dos huecos son
    # contiguos y no se solapan.
    primero, segundo = sorted([movil, tableta], key=lambda r: r["cursorPrevio"])
    assert segundo["cursorPrevio"] == primero["cursor"]

    # Bajar desde cero las trae todas: ninguna se ha quedado por debajo del cursor.
    paquete = await cliente.get("/sincro/bajar", headers=cabeceras(sesion))
    assert len(paquete.json()["filas"]) == 20
