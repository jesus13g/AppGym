"""Dónde guarda la app sus datos.

En desarrollo (`python main.py`) todo vive junto al proyecto, que es lo cómodo.
Pero en una app empaquetada —sobre todo en Android e iOS— el directorio de
trabajo no es escribible, así que hay que usar el almacenamiento privado que el
sistema asigna a la app. Flet lo expone en `FLET_APP_STORAGE_DATA`.
"""

import os
from pathlib import Path


def directorio_datos():
    """Directorio escribible donde guardar la base de datos y la media."""
    ruta = os.getenv("FLET_APP_STORAGE_DATA")
    base = Path(ruta) if ruta else Path.cwd()
    base.mkdir(parents=True, exist_ok=True)
    return base


def ruta_base_datos():
    """URL SQLAlchemy de la base de datos."""
    fichero = directorio_datos() / "DataBase.db"
    return f"sqlite:///{fichero}"


def directorio_media():
    """Carpeta con las imágenes y GIFs de los ejercicios."""
    return directorio_datos() / "media"
