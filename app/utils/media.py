"""Descarga y resolución de las imágenes y GIFs de los ejercicios.

La media (miniaturas 180x180 y GIFs animados) es propiedad de **Gym visual** y no
se distribuye con este repositorio: se descarga desde el dataset original al
directorio `media/`, que está en el .gitignore.

Condiciones de uso de la media, según el NOTICE del dataset:
  - se distribuye únicamente a 180x180
  - hay que mantener visible la atribución `© Gym visual — https://gymvisual.com/`
Ver https://gymvisual.com/content/3-terms-and-conditions-of-use
"""

import os
from concurrent.futures import ThreadPoolExecutor, as_completed

import requests

from app.utils import almacenamiento

BASE_REMOTA = "https://raw.githubusercontent.com/hasaneyldrm/exercises-dataset/main/"
ATRIBUCION = "© Gym visual — https://gymvisual.com/"

DIRECTORIO = almacenamiento.directorio_media()
MARCA_COMPLETA = DIRECTORIO / ".complete"

_TIEMPO_ESPERA = 30
_HILOS = 16


def url_remota(ruta_relativa):
    """URL en el repositorio original para una ruta como 'images/0001-2gPfomN.jpg'."""
    return BASE_REMOTA + ruta_relativa.lstrip("/")


def ruta_local(ruta_relativa):
    """Ruta en disco donde vive (o vivirá) esa media."""
    return DIRECTORIO / ruta_relativa.lstrip("/")


def resolver(ruta_relativa):
    """Devuelve la ruta local si el fichero ya está descargado, o la URL remota.

    `ft.Image(src=...)` acepta ambas, así que la app funciona igual durante la
    descarga, si el usuario la omite, o si falló a medias.
    """
    if not ruta_relativa:
        return None
    local = ruta_local(ruta_relativa)
    if local.exists() and local.stat().st_size > 0:
        return str(local)
    return url_remota(ruta_relativa)


def descarga_completa():
    """True si ya se descargó todo el paquete de media."""
    return MARCA_COMPLETA.exists()


def _descargar_uno(ruta_relativa, sesion):
    """Descarga un fichero si falta. Devuelve True si el fichero está disponible."""
    destino = ruta_local(ruta_relativa)
    if destino.exists() and destino.stat().st_size > 0:
        return True

    destino.parent.mkdir(parents=True, exist_ok=True)
    # Se escribe a .part y se renombra al final para que un corte de red no deje
    # ficheros truncados que luego se den por buenos.
    parcial = destino.with_suffix(destino.suffix + ".part")
    try:
        respuesta = sesion.get(url_remota(ruta_relativa), timeout=_TIEMPO_ESPERA, stream=True)
        respuesta.raise_for_status()
        with open(parcial, "wb") as f:
            for trozo in respuesta.iter_content(chunk_size=65536):
                if trozo:
                    f.write(trozo)
        os.replace(parcial, destino)
        return True
    except Exception:
        parcial.unlink(missing_ok=True)
        return False


def rutas_pendientes(ejercicios):
    """Rutas de media que aún no están en disco, dada la lista del catálogo."""
    todas = []
    for ejercicio in ejercicios:
        for ruta in (ejercicio.get("image"), ejercicio.get("gif")):
            if ruta:
                todas.append(ruta)
    return [r for r in todas if not (ruta_local(r).exists() and ruta_local(r).stat().st_size > 0)]


def descargar_todo(ejercicios, al_progresar=None, cancelado=None):
    """Descarga toda la media que falte, en paralelo y de forma reanudable.

    :param ejercicios: lista de dicts del catálogo (con claves 'image' y 'gif')
    :param al_progresar: callback(hechos, total, fallos) llamado periódicamente
    :param cancelado: callable que devuelve True para abortar la descarga
    :return: (hechos, total, fallos)
    """
    pendientes = rutas_pendientes(ejercicios)
    total = len(pendientes)
    if total == 0:
        MARCA_COMPLETA.parent.mkdir(parents=True, exist_ok=True)
        MARCA_COMPLETA.touch()
        if al_progresar:
            al_progresar(0, 0, 0)
        return 0, 0, 0

    hechos = 0
    fallos = 0
    sesion = requests.Session()

    with ThreadPoolExecutor(max_workers=_HILOS) as pool:
        futuros = [pool.submit(_descargar_uno, ruta, sesion) for ruta in pendientes]
        for futuro in as_completed(futuros):
            hechos += 1
            if not futuro.result():
                fallos += 1
            if al_progresar and (hechos % 10 == 0 or hechos == total):
                al_progresar(hechos, total, fallos)
            if cancelado and cancelado():
                # cancel() solo funciona en los que aún no han arrancado, que es
                # justo lo que interesa: los 16 en vuelo terminan y se acabó.
                for pendiente in futuros:
                    pendiente.cancel()
                break

    sesion.close()

    if fallos == 0 and hechos == total:
        MARCA_COMPLETA.parent.mkdir(parents=True, exist_ok=True)
        MARCA_COMPLETA.touch()

    return hechos, total, fallos
