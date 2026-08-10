"""Los fallos que el servidor sabe contar, y cómo salen por la API.

**Todos contestan con `{"mensaje": "..."}`**, y no con el `{"detail": ...}` de
fábrica de FastAPI. El cliente lee `mensaje` y lo enseña tal cual cuando el fallo
es cosa del usuario —una contraseña que no coincide—, así que la frase que se
escriba aquí es la frase que se lee en el móvil. En español, y sin jerga.
"""


class ErrorApi(Exception):
    """Un fallo con su código HTTP y su frase."""

    estado = 400

    def __init__(self, mensaje: str) -> None:
        super().__init__(mensaje)
        self.mensaje = mensaje


class Rechazado(ErrorApi):
    """La petición no vale y repetirla igual tampoco valdrá."""

    estado = 400


class NoAutenticado(ErrorApi):
    """No hay credencial, o ya no sirve. El cliente vuelve a entrar."""

    estado = 401


class SinPermiso(ErrorApi):
    estado = 403


class NoExiste(ErrorApi):
    estado = 404


class Conflicto(ErrorApi):
    """Ya existe algo que impide seguir. Hoy solo: ese correo ya tiene cuenta."""

    estado = 409


class DemasiadasPeticiones(ErrorApi):
    """Se ha pasado del límite. El cliente lo trata como temporal y reintenta."""

    estado = 429
