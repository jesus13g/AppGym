"""El límite de peticiones por IP.

Una ventana deslizante en memoria. **A propósito no hay Redis**: este servidor es
una instancia para un puñado de usuarios, y meter otro servicio en el compose
—con su memoria, su persistencia y su modo de fallo— para contar peticiones sería
exactamente el tipo de infraestructura que este proyecto evita. Si algún día hay
varias instancias, se sustituye la clase y no cambia nada más.

Lo que **no** vive aquí es el bloqueo por intentos fallidos de una cuenta: ese va
en la base (`usuarios.bloqueado_hasta`), porque reiniciar el proceso no puede ser
la forma de saltárselo.
"""

import time
from collections import defaultdict, deque

from fastapi import Request

from .config import ajustes
from .errores import DemasiadasPeticiones


class Limitador:
    def __init__(self, ventana_segundos: int = 60) -> None:
        self._ventana = ventana_segundos
        self._visitas: dict[str, deque[float]] = defaultdict(deque)

    def comprobar(self, clave: str, maximo: int) -> None:
        ahora = time.monotonic()
        visitas = self._visitas[clave]
        while visitas and ahora - visitas[0] > self._ventana:
            visitas.popleft()
        if len(visitas) >= maximo:
            raise DemasiadasPeticiones("Demasiadas peticiones seguidas. Espera un momento.")
        visitas.append(ahora)

    def olvidar(self) -> None:
        """Para los tests, que no pueden heredar las cuentas del anterior."""
        self._visitas.clear()


limitador = Limitador()


def _de_donde(peticion: Request) -> str:
    """La IP del cliente, contando con que Caddy va delante.

    Se lee la **primera** entrada de `X-Forwarded-For`, que es la del cliente; las
    siguientes las añaden los intermedios. Es fiable porque el único que puede
    poner esa cabecera aquí es el proxy: el contenedor de la API no está expuesto.
    """
    reenviada = peticion.headers.get("X-Forwarded-For")
    if reenviada:
        return reenviada.split(",")[0].strip()
    return peticion.client.host if peticion.client else "desconocida"


async def limite_auth(peticion: Request) -> None:
    limitador.comprobar(f"auth:{_de_donde(peticion)}", ajustes().limite_auth_minuto)


async def limite_datos(peticion: Request) -> None:
    limitador.comprobar(f"datos:{_de_donde(peticion)}", ajustes().limite_datos_minuto)
