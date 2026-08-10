"""Que cada usuario vea lo suyo y nada más.

Es el test que K9 exigía y que en la versión anterior **necesitaba red**, porque
el aislamiento lo daba la RLS del proveedor. Ahora el cliente no habla con
Postgres, solo con esta API, y el aislamiento es que **toda** consulta filtra por
el usuario del token. Eso sí se puede probar aquí.
"""

from httpx import AsyncClient

from .conftest import cabeceras, registrar


async def _dos_cuentas(cliente: AsyncClient) -> tuple[dict, dict]:
    ana = await registrar(cliente, "ana@ejemplo.com")
    bruno = await registrar(cliente, "bruno@ejemplo.com")
    return ana, bruno


async def _subir(cliente: AsyncClient, sesion: dict, clave: str, nombre: str) -> dict:
    respuesta = await cliente.post(
        "/sincro/subir",
        json={"filas": [{"tabla": "rutinas", "clave": clave, "datos": {"nombre": nombre}}]},
        headers=cabeceras(sesion),
    )
    assert respuesta.status_code == 200, respuesta.text
    return respuesta.json()


async def test_bajar_no_trae_las_filas_de_otro(cliente: AsyncClient):
    ana, bruno = await _dos_cuentas(cliente)
    await _subir(cliente, ana, "r1", "Empuje de Ana")

    paquete = await cliente.get("/sincro/bajar", params={"cursor": 0}, headers=cabeceras(bruno))
    assert paquete.json() == {"cursor": 0, "filas": []}


async def test_el_resumen_es_el_de_cada_uno(cliente: AsyncClient):
    ana, bruno = await _dos_cuentas(cliente)
    await _subir(cliente, ana, "r1", "Empuje de Ana")

    assert (await cliente.get("/sincro/resumen", headers=cabeceras(ana))).json() == {
        "rutinas": 1,
        "sesiones": 0,
    }
    assert (await cliente.get("/sincro/resumen", headers=cabeceras(bruno))).json() == {
        "rutinas": 0,
        "sesiones": 0,
    }


async def test_la_misma_clave_en_dos_cuentas_son_dos_filas(cliente: AsyncClient):
    """La clave primaria lleva el usuario delante: `r1` de Ana no es `r1` de Bruno."""
    ana, bruno = await _dos_cuentas(cliente)
    await _subir(cliente, ana, "r1", "Empuje de Ana")
    await _subir(cliente, bruno, "r1", "Empuje de Bruno")

    de_ana = (await cliente.get("/sincro/bajar", headers=cabeceras(ana))).json()
    de_bruno = (await cliente.get("/sincro/bajar", headers=cabeceras(bruno))).json()

    assert de_ana["filas"][0]["datos"] == {"nombre": "Empuje de Ana"}
    assert de_bruno["filas"][0]["datos"] == {"nombre": "Empuje de Bruno"}


async def test_vaciar_no_toca_los_datos_del_otro(cliente: AsyncClient):
    ana, bruno = await _dos_cuentas(cliente)
    await _subir(cliente, ana, "r1", "Empuje de Ana")
    await _subir(cliente, bruno, "r1", "Empuje de Bruno")

    assert (await cliente.post("/sincro/vaciar", headers=cabeceras(bruno))).status_code == 204

    assert (await cliente.get("/sincro/resumen", headers=cabeceras(ana))).json()["rutinas"] == 1


async def test_borrar_una_cuenta_no_toca_la_otra(cliente: AsyncClient):
    ana, bruno = await _dos_cuentas(cliente)
    await _subir(cliente, ana, "r1", "Empuje de Ana")

    assert (await cliente.delete("/auth/cuenta", headers=cabeceras(bruno))).status_code == 204

    assert (await cliente.get("/sincro/resumen", headers=cabeceras(ana))).json()["rutinas"] == 1


async def test_el_reloj_de_cada_uno_va_por_su_cuenta(cliente: AsyncClient):
    """Que Bruno suba treinta filas no puede adelantar el cursor de Ana."""
    ana, bruno = await _dos_cuentas(cliente)
    primera_de_ana = await _subir(cliente, ana, "r1", "Empuje de Ana")

    for i in range(5):
        await _subir(cliente, bruno, f"r{i}", f"Rutina {i}")

    segunda_de_ana = await _subir(cliente, ana, "r2", "Tirón de Ana")
    assert segunda_de_ana["cursorPrevio"] == primera_de_ana["cursor"]
