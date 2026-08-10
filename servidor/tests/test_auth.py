"""La cuenta: registro, entrada, rotación del refresco y borrado.

El caso que más importa es `test_reutilizar_un_refresco_mata_la_familia`: es la
diferencia entre «un refresco robado sirve dos meses» y «un refresco robado se
detecta la primera vez que se usa».
"""

from datetime import UTC, datetime, timedelta

import jwt
import pytest
from httpx import AsyncClient

from appgym.config import ajustes

from .conftest import CONTRASENA, cabeceras, registrar

# ── Registro ──────────────────────────────────────────────────────────────────


async def test_registrarse_devuelve_sesion_utilizable(cliente: AsyncClient, correo: str):
    sesion = await registrar(cliente, correo)

    assert sesion["usuario"]["correo"] == correo
    assert sesion["expira_en"] == ajustes().acceso_minutos * 60
    assert sesion["acceso"] and sesion["refresco"]

    respuesta = await cliente.get("/sincro/resumen", headers=cabeceras(sesion))
    assert respuesta.status_code == 200


async def test_el_correo_se_normaliza(cliente: AsyncClient, correo: str):
    """Dos correos que solo se diferencian en mayúsculas son la misma cuenta."""
    await registrar(cliente, f"  {correo.upper()}  ")

    respuesta = await cliente.post(
        "/auth/entrar", json={"correo": correo, "contrasena": CONTRASENA}
    )
    assert respuesta.status_code == 200


async def test_registrarse_dos_veces_con_el_mismo_correo(cliente: AsyncClient, correo: str):
    await registrar(cliente, correo)
    respuesta = await cliente.post(
        "/auth/registro", json={"correo": correo, "contrasena": CONTRASENA}
    )

    assert respuesta.status_code == 409
    assert "ya tiene una cuenta" in respuesta.json()["mensaje"]


async def test_una_contrasena_corta_no_vale(cliente: AsyncClient, correo: str):
    respuesta = await cliente.post("/auth/registro", json={"correo": correo, "contrasena": "corta"})

    assert respuesta.status_code == 400
    assert "mensaje" in respuesta.json()


async def test_con_el_registro_cerrado_no_se_crean_cuentas(
    cliente: AsyncClient, correo: str, monkeypatch: pytest.MonkeyPatch
):
    """Es lo que hace que un servidor personal siga siendo personal."""
    monkeypatch.setenv("APPGYM_REGISTRO_ABIERTO", "false")
    ajustes.cache_clear()

    respuesta = await cliente.post(
        "/auth/registro", json={"correo": correo, "contrasena": CONTRASENA}
    )
    assert respuesta.status_code == 403

    ajustes.cache_clear()


# ── Entrar ────────────────────────────────────────────────────────────────────


async def test_la_contrasena_incorrecta_y_el_correo_inexistente_dicen_lo_mismo(
    cliente: AsyncClient, correo: str
):
    """Si dijeran cosas distintas, se podría averiguar qué correos tienen cuenta."""
    await registrar(cliente, correo)

    mala = await cliente.post("/auth/entrar", json={"correo": correo, "contrasena": "otraCosa123"})
    inexistente = await cliente.post(
        "/auth/entrar", json={"correo": "nadie@ejemplo.com", "contrasena": CONTRASENA}
    )

    assert mala.status_code == inexistente.status_code == 401
    assert mala.json()["mensaje"] == inexistente.json()["mensaje"]


async def test_cinco_fallos_bloquean_la_cuenta_un_rato(cliente: AsyncClient, correo: str):
    await registrar(cliente, correo)

    for _ in range(ajustes().intentos_maximos):
        respuesta = await cliente.post(
            "/auth/entrar", json={"correo": correo, "contrasena": "loQueSea123"}
        )
        assert respuesta.status_code == 401

    # Y ahora ni siquiera con la buena.
    respuesta = await cliente.post(
        "/auth/entrar", json={"correo": correo, "contrasena": CONTRASENA}
    )
    assert respuesta.status_code == 429
    assert "unos minutos" in respuesta.json()["mensaje"]


async def test_entrar_bien_borra_los_intentos_fallidos(cliente: AsyncClient, correo: str):
    await registrar(cliente, correo)
    await cliente.post("/auth/entrar", json={"correo": correo, "contrasena": "mal123456789"})
    await cliente.post("/auth/entrar", json={"correo": correo, "contrasena": CONTRASENA})

    for _ in range(ajustes().intentos_maximos - 1):
        await cliente.post("/auth/entrar", json={"correo": correo, "contrasena": "mal123456789"})

    respuesta = await cliente.post(
        "/auth/entrar", json={"correo": correo, "contrasena": CONTRASENA}
    )
    assert respuesta.status_code == 200


# ── El acceso ─────────────────────────────────────────────────────────────────


async def test_sin_credencial_no_se_entra(cliente: AsyncClient):
    assert (await cliente.get("/sincro/resumen")).status_code == 401


async def test_un_acceso_caducado_no_vale(cliente: AsyncClient, correo: str):
    sesion = await registrar(cliente, correo)
    a = ajustes()
    ayer = datetime.now(UTC) - timedelta(days=1)
    caducado = jwt.encode(
        {
            "sub": sesion["usuario"]["id"],
            "iss": a.jwt_emisor,
            "aud": a.jwt_audiencia,
            "iat": int(ayer.timestamp()),
            "exp": int((ayer + timedelta(minutes=15)).timestamp()),
        },
        a.jwt_secreto,
        algorithm="HS256",
    )

    respuesta = await cliente.get(
        "/sincro/resumen", headers={"Authorization": f"Bearer {caducado}"}
    )
    assert respuesta.status_code == 401


async def test_un_acceso_de_otra_audiencia_no_vale(cliente: AsyncClient, correo: str):
    """Un token firmado con el mismo secreto para otra cosa no sirve aquí."""
    sesion = await registrar(cliente, correo)
    a = ajustes()
    ahora = datetime.now(UTC)
    ajeno = jwt.encode(
        {
            "sub": sesion["usuario"]["id"],
            "iss": a.jwt_emisor,
            "aud": "otra-app",
            "iat": int(ahora.timestamp()),
            "exp": int((ahora + timedelta(minutes=15)).timestamp()),
        },
        a.jwt_secreto,
        algorithm="HS256",
    )

    respuesta = await cliente.get("/sincro/resumen", headers={"Authorization": f"Bearer {ajeno}"})
    assert respuesta.status_code == 401


async def test_un_acceso_firmado_con_otro_secreto_no_vale(cliente: AsyncClient, correo: str):
    sesion = await registrar(cliente, correo)
    ahora = datetime.now(UTC)
    falso = jwt.encode(
        {
            "sub": sesion["usuario"]["id"],
            "iss": ajustes().jwt_emisor,
            "aud": ajustes().jwt_audiencia,
            "iat": int(ahora.timestamp()),
            "exp": int((ahora + timedelta(minutes=15)).timestamp()),
        },
        "otro-secreto-cualquiera-de-la-calle",
        algorithm="HS256",
    )

    respuesta = await cliente.get("/sincro/resumen", headers={"Authorization": f"Bearer {falso}"})
    assert respuesta.status_code == 401


# ── El refresco ───────────────────────────────────────────────────────────────


async def test_refrescar_rota_el_token(cliente: AsyncClient, correo: str):
    sesion = await registrar(cliente, correo)

    respuesta = await cliente.post("/auth/refrescar", json={"refresco": sesion["refresco"]})
    assert respuesta.status_code == 200
    nueva = respuesta.json()
    assert nueva["refresco"] != sesion["refresco"]

    # Y el nuevo sirve para renovar otra vez.
    otra = await cliente.post("/auth/refrescar", json={"refresco": nueva["refresco"]})
    assert otra.status_code == 200


async def test_reutilizar_un_refresco_mata_la_familia(cliente: AsyncClient, correo: str):
    """El robo se detecta la primera vez que se usa el token robado.

    Quien lo tenga —el ladrón o el dueño— se queda fuera y vuelve a entrar, que es
    la única respuesta segura: el servidor no puede saber cuál de los dos es cuál.
    """
    sesion = await registrar(cliente, correo)
    primera = (await cliente.post("/auth/refrescar", json={"refresco": sesion["refresco"]})).json()

    repetida = await cliente.post("/auth/refrescar", json={"refresco": sesion["refresco"]})
    assert repetida.status_code == 401

    # Y el que había salido de esa cadena también queda revocado.
    despues = await cliente.post("/auth/refrescar", json={"refresco": primera["refresco"]})
    assert despues.status_code == 401


async def test_un_refresco_inventado_no_vale(cliente: AsyncClient):
    respuesta = await cliente.post("/auth/refrescar", json={"refresco": "esto-no-existe"})
    assert respuesta.status_code == 401


# ── Salir ─────────────────────────────────────────────────────────────────────


async def test_salir_cierra_solo_este_dispositivo(cliente: AsyncClient, correo: str):
    """«Un usuario, N dispositivos»: salir en el móvil no cierra la tableta."""
    movil = await registrar(cliente, correo)
    tableta = (
        await cliente.post("/auth/entrar", json={"correo": correo, "contrasena": CONTRASENA})
    ).json()

    assert (
        await cliente.post("/auth/salir", json={"refresco": movil["refresco"]})
    ).status_code == 204

    assert (
        await cliente.post("/auth/refrescar", json={"refresco": movil["refresco"]})
    ).status_code == 401
    assert (
        await cliente.post("/auth/refrescar", json={"refresco": tableta["refresco"]})
    ).status_code == 200


async def test_salir_con_un_refresco_desconocido_no_dice_nada(cliente: AsyncClient):
    """Contestar distinto diría si un token es válido."""
    respuesta = await cliente.post("/auth/salir", json={"refresco": "no-existe"})
    assert respuesta.status_code == 204


# ── Borrar la cuenta ──────────────────────────────────────────────────────────


async def test_borrar_la_cuenta_se_lleva_los_datos_y_la_sesion(cliente: AsyncClient, correo: str):
    sesion = await registrar(cliente, correo)
    await cliente.post(
        "/sincro/subir",
        json={"filas": [{"tabla": "rutinas", "clave": "r1", "datos": {"nombre": "Empuje"}}]},
        headers=cabeceras(sesion),
    )

    assert (await cliente.delete("/auth/cuenta", headers=cabeceras(sesion))).status_code == 204

    # El acceso todavía no ha caducado y aun así no vale: `usuario_actual` carga
    # al usuario de la base.
    assert (await cliente.get("/sincro/resumen", headers=cabeceras(sesion))).status_code == 401
    assert (
        await cliente.post("/auth/refrescar", json={"refresco": sesion["refresco"]})
    ).status_code == 401
    assert (
        await cliente.post("/auth/entrar", json={"correo": correo, "contrasena": CONTRASENA})
    ).status_code == 401


async def test_el_correo_queda_libre_tras_borrar_la_cuenta(cliente: AsyncClient, correo: str):
    sesion = await registrar(cliente, correo)
    await cliente.delete("/auth/cuenta", headers=cabeceras(sesion))

    respuesta = await cliente.post(
        "/auth/registro", json={"correo": correo, "contrasena": CONTRASENA}
    )
    assert respuesta.status_code == 201
