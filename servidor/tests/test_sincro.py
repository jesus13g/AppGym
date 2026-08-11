"""El buzón con reloj.

Es el fichero que cubre lo que antes no se podía probar: el reloj, sus tres
invariantes, las lápidas y el resumen. Cada caso de aquí se corresponde con una
línea del contrato que el cliente implementa en `test/sincro_falso.dart`, que es
la especificación ejecutable del transporte.
"""

from httpx import AsyncClient

from .conftest import cabeceras, registrar


def _fila(tabla: str, clave: str, datos: dict | None) -> dict:
    return {"tabla": tabla, "clave": clave, "datos": datos}


async def _subir(cliente: AsyncClient, sesion: dict, filas: list[dict]) -> dict:
    respuesta = await cliente.post(
        "/sincro/subir", json={"filas": filas}, headers=cabeceras(sesion)
    )
    assert respuesta.status_code == 200, respuesta.text
    return respuesta.json()


async def _bajar(cliente: AsyncClient, sesion: dict, cursor: int = 0) -> dict:
    respuesta = await cliente.get(
        "/sincro/bajar", params={"cursor": cursor}, headers=cabeceras(sesion)
    )
    assert respuesta.status_code == 200, respuesta.text
    return respuesta.json()


# ── El reloj ──────────────────────────────────────────────────────────────────


async def test_el_reloj_arranca_en_milisegundos_de_epoca(cliente: AsyncClient, correo: str):
    """Si arrancara en cero, el móvil resubiría su histórico entero en cada pasada.

    El fallo no se vería hasta que el usuario tuviera datos, así que esta cifra es
    el test más importante del fichero.
    """
    sesion = await registrar(cliente, correo)
    respuesta = await _subir(cliente, sesion, [_fila("rutinas", "r1", {"nombre": "Empuje"})])

    assert respuesta["cursorPrevio"] > 1_700_000_000_000
    assert respuesta["cursor"] > respuesta["cursorPrevio"]


async def test_los_sellos_crecen_de_uno_en_uno_y_en_orden(cliente: AsyncClient, correo: str):
    sesion = await registrar(cliente, correo)
    respuesta = await _subir(
        cliente,
        sesion,
        [
            _fila("rutinas", "r1", {"nombre": "Empuje"}),
            _fila("rutinas", "r2", {"nombre": "Tirón"}),
            _fila("entrenamientos", "e1", {"fecha": "2026-08-10"}),
        ],
    )

    sellos = respuesta["sellos"]
    previo = respuesta["cursorPrevio"]
    assert sellos["rutinas/r1"] == previo + 1
    assert sellos["rutinas/r2"] == previo + 2
    assert sellos["entrenamientos/e1"] == previo + 3
    assert respuesta["cursor"] == previo + 3


async def test_el_cursor_previo_es_el_cursor_de_la_subida_anterior(
    cliente: AsyncClient, correo: str
):
    """Es lo que permite al motor saber que lo que hay en medio lo escribió él.

    Si `subir` mirara la hora de pared, esta igualdad no se daría nunca y cada
    móvil se descargaría su propio eco en cada pasada.
    """
    sesion = await registrar(cliente, correo)
    primera = await _subir(cliente, sesion, [_fila("rutinas", "r1", {"nombre": "Empuje"})])
    segunda = await _subir(cliente, sesion, [_fila("rutinas", "r2", {"nombre": "Tirón"})])

    assert segunda["cursorPrevio"] == primera["cursor"]


async def test_el_sello_que_manda_el_cliente_no_se_mira(cliente: AsyncClient, correo: str):
    """Un móvil con la hora adelantada dos años no puede ganar todos los conflictos."""
    sesion = await registrar(cliente, correo)
    respuesta = await cliente.post(
        "/sincro/subir",
        json={
            "filas": [
                {
                    "tabla": "rutinas",
                    "clave": "r1",
                    "datos": {"nombre": "Empuje"},
                    "actualizado": 9_999_999_999_999,
                }
            ]
        },
        headers=cabeceras(sesion),
    )
    assert respuesta.status_code == 200
    assert respuesta.json()["sellos"]["rutinas/r1"] < 9_999_999_999_999


async def test_reescribir_una_fila_le_da_un_sello_nuevo(cliente: AsyncClient, correo: str):
    sesion = await registrar(cliente, correo)
    primera = await _subir(cliente, sesion, [_fila("rutinas", "r1", {"nombre": "Empuje"})])
    segunda = await _subir(cliente, sesion, [_fila("rutinas", "r1", {"nombre": "Empuje A"})])

    assert segunda["sellos"]["rutinas/r1"] > primera["sellos"]["rutinas/r1"]
    paquete = await _bajar(cliente, sesion)
    assert len(paquete["filas"]) == 1
    assert paquete["filas"][0]["datos"] == {"nombre": "Empuje A"}


async def test_la_misma_clave_dos_veces_en_un_envio_se_queda_con_la_ultima(
    cliente: AsyncClient, correo: str
):
    """`on conflict do update` no puede tocar dos veces la misma fila en una
    sentencia, así que el envío se deduplica antes de escribir."""
    sesion = await registrar(cliente, correo)
    respuesta = await _subir(
        cliente,
        sesion,
        [
            _fila("rutinas", "r1", {"nombre": "Vieja"}),
            _fila("rutinas", "r1", {"nombre": "Nueva"}),
        ],
    )
    assert len(respuesta["sellos"]) == 1

    paquete = await _bajar(cliente, sesion)
    assert paquete["filas"][0]["datos"] == {"nombre": "Nueva"}


async def test_un_envio_vacio_deja_el_reloj_quieto(cliente: AsyncClient, correo: str):
    sesion = await registrar(cliente, correo)
    await _subir(cliente, sesion, [_fila("rutinas", "r1", {"nombre": "Empuje"})])
    respuesta = await _subir(cliente, sesion, [])

    assert respuesta["sellos"] == {}
    assert respuesta["cursor"] == respuesta["cursorPrevio"]


# ── Bajar ─────────────────────────────────────────────────────────────────────


async def test_bajar_desde_cero_lo_trae_todo_en_orden(cliente: AsyncClient, correo: str):
    sesion = await registrar(cliente, correo)
    await _subir(
        cliente,
        sesion,
        [_fila("rutinas", "r1", {"nombre": "Empuje"}), _fila("rutinas", "r2", {"nombre": "Tirón"})],
    )

    paquete = await _bajar(cliente, sesion)
    sellos = [f["actualizado"] for f in paquete["filas"]]
    assert len(paquete["filas"]) == 2
    assert sellos == sorted(sellos)
    assert paquete["cursor"] == max(sellos)


async def test_bajar_desde_el_cursor_no_trae_nada_pero_devuelve_el_cursor(
    cliente: AsyncClient, correo: str
):
    """El cliente tiene que poder avanzar su cursor aunque el paquete venga vacío."""
    sesion = await registrar(cliente, correo)
    subida = await _subir(cliente, sesion, [_fila("rutinas", "r1", {"nombre": "Empuje"})])

    paquete = await _bajar(cliente, sesion, cursor=subida["cursor"])
    assert paquete["filas"] == []
    assert paquete["cursor"] == subida["cursor"]


async def test_bajar_de_una_cuenta_sin_reloj_devuelve_cursor_cero(
    cliente: AsyncClient, correo: str
):
    sesion = await registrar(cliente, correo)
    paquete = await _bajar(cliente, sesion)
    assert paquete == {"cursor": 0, "filas": []}


# ── Lápidas ───────────────────────────────────────────────────────────────────


async def test_una_lapida_viaja_como_datos_nulos(cliente: AsyncClient, correo: str):
    """`datos: null` es la lápida en las dos direcciones y sin caso especial.

    Es también el sitio donde `JSONB(none_as_null=True)` importa: sin eso se
    guardaría el JSON `'null'`, que **no** es una lápida.
    """
    sesion = await registrar(cliente, correo)
    await _subir(cliente, sesion, [_fila("rutinas", "r1", {"nombre": "Empuje"})])
    await _subir(cliente, sesion, [_fila("rutinas", "r1", None)])

    paquete = await _bajar(cliente, sesion)
    assert len(paquete["filas"]) == 1
    assert paquete["filas"][0]["datos"] is None


# ── Resumen y vaciar ──────────────────────────────────────────────────────────


async def test_el_resumen_cuenta_rutinas_y_sesiones_y_no_las_lapidas(
    cliente: AsyncClient, correo: str
):
    sesion = await registrar(cliente, correo)
    await _subir(
        cliente,
        sesion,
        [
            _fila("rutinas", "r1", {"nombre": "Empuje"}),
            _fila("rutinas", "r2", {"nombre": "Tirón"}),
            _fila("entrenamientos", "e1", {"fecha": "2026-08-10"}),
            _fila("medidas", "peso|2026-08-10", {"valor": 80}),
        ],
    )
    await _subir(cliente, sesion, [_fila("rutinas", "r2", None)])

    respuesta = await cliente.get("/sincro/resumen", headers=cabeceras(sesion))
    assert respuesta.json() == {"rutinas": 1, "sesiones": 1}


async def test_vaciar_borra_las_filas_y_no_reinicia_el_reloj(cliente: AsyncClient, correo: str):
    """Si el reloj se reiniciara, repartiría otra vez sellos ya usados y un
    dispositivo con el cursor por encima no volvería a ver nada nunca."""
    sesion = await registrar(cliente, correo)
    antes = await _subir(cliente, sesion, [_fila("rutinas", "r1", {"nombre": "Empuje"})])

    assert (await cliente.post("/sincro/vaciar", headers=cabeceras(sesion))).status_code == 204

    respuesta = await cliente.get("/sincro/resumen", headers=cabeceras(sesion))
    assert respuesta.json() == {"rutinas": 0, "sesiones": 0}

    despues = await _subir(cliente, sesion, [_fila("rutinas", "r2", {"nombre": "Tirón"})])
    assert despues["cursorPrevio"] == antes["cursor"]


# ── Tamaño ────────────────────────────────────────────────────────────────────


async def test_un_envio_gigante_se_rechaza(cliente: AsyncClient, correo: str):
    sesion = await registrar(cliente, correo)
    filas = [_fila("rutinas", f"r{i}", {"nombre": f"R{i}"}) for i in range(501)]
    respuesta = await cliente.post(
        "/sincro/subir", json={"filas": filas}, headers=cabeceras(sesion)
    )
    assert respuesta.status_code == 400
    assert "lotes" in respuesta.json()["mensaje"]
