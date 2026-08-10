"""Los ajustes del servidor, todos por variable de entorno.

Nada de valores por defecto para lo que es un secreto: `APPGYM_JWT_SECRETO` no
tiene valor de fábrica **a propósito**, para que un despliegue sin configurar no
arranque en vez de arrancar firmando con una cadena conocida.
"""

from functools import lru_cache

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Ajustes(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="APPGYM_", env_file=".env", env_file_encoding="utf-8", extra="ignore"
    )

    # ── La base de datos ──────────────────────────────────────────────────────
    bd_url: str = "postgresql+asyncpg://appgym:appgym@localhost:5432/appgym"

    # ── Las llaves ────────────────────────────────────────────────────────────
    #
    # 32 bytes como mínimo. Se genera con `python -c "import secrets;
    # print(secrets.token_urlsafe(48))"`, va en el `.env` del servidor y no se
    # escribe en ningún sitio más. Cambiarlo invalida todos los accesos vivos —no
    # los refrescos, que se guardan en la base—, así que rotarlo cuesta que cada
    # móvil renueve una vez.
    jwt_secreto: str = Field(min_length=32)
    jwt_emisor: str = "appgym"
    jwt_audiencia: str = "appgym-app"

    # Corto a propósito: un acceso robado sirve quince minutos. Lo que dura es el
    # refresco, que es revocable y está en la base.
    acceso_minutos: int = 15
    refresco_dias: int = 60

    # ── La puerta ─────────────────────────────────────────────────────────────
    #
    # Con esto en `false` no se pueden crear cuentas nuevas. Es lo que hace que un
    # servidor personal siga siendo personal aunque alguien saque la URL del APK.
    registro_abierto: bool = True

    # Bloqueo por intentos fallidos, por cuenta. Cinco fallos y quince minutos de
    # espera: molesta a quien prueba contraseñas y no a quien se equivoca.
    intentos_maximos: int = 5
    bloqueo_minutos: int = 15

    # Límite de peticiones por IP y minuto, para las rutas de autenticación y para
    # el resto. Es un cortafuegos de andar por casa —vive en memoria y no
    # sobrevive a un reinicio—, pensado para una sola instancia. Si algún día hay
    # varias, esto se sustituye por Redis y no cambia nada más.
    limite_auth_minuto: int = 10
    limite_datos_minuto: int = 120

    # Cuántas filas admite una subida. El cliente manda en lotes de 200; el margen
    # es para no rechazar a un cliente algo más viejo o algo más nuevo.
    filas_maximas: int = 500

    @field_validator("jwt_secreto")
    @classmethod
    def _no_es_el_de_ejemplo(cls, valor: str) -> str:
        if valor.strip().lower() in {"cambiame", "secreto", "changeme"}:
            raise ValueError("APPGYM_JWT_SECRETO sigue siendo el del ejemplo")
        return valor


@lru_cache
def ajustes() -> Ajustes:
    """Los ajustes, leídos una sola vez.

    Va cacheado para poder sobrescribirlo en los tests con
    `ajustes.cache_clear()` sin tener que pasarlo por parámetro a media docena de
    funciones.
    """
    return Ajustes()  # type: ignore[call-arg]
