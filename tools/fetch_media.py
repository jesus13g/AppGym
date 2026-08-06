#!/usr/bin/env python3
"""Descarga las imágenes y GIFs de los ejercicios sin abrir la app.

Uso, desde la raíz del proyecto:

    python tools/fetch_media.py

Es reanudable: si se corta, vuelve a lanzarlo y solo baja lo que falte.
La media es © Gym visual — https://gymvisual.com/
"""

import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.utils import media  # noqa: E402
from app.utils.seed import cargar_json  # noqa: E402


def main():
    ejercicios = cargar_json()
    if not ejercicios:
        print("No se pudo leer el catálogo de ejercicios.")
        return 1

    pendientes = len(media.rutas_pendientes(ejercicios))
    if pendientes == 0:
        print("La media ya está descargada.")
        return 0

    print(f"Descargando {pendientes} ficheros en {media.DIRECTORIO} …")
    inicio = time.monotonic()

    def progreso(hechos, total, fallos):
        pct = hechos * 100 // total if total else 100
        sufijo = f"  ({fallos} fallidos)" if fallos else ""
        print(f"\r  {pct:3d}%  {hechos}/{total}{sufijo}", end="", flush=True)

    hechos, total, fallos = media.descargar_todo(ejercicios, al_progresar=progreso)
    print()

    segundos = time.monotonic() - inicio
    print(f"Terminado: {hechos - fallos}/{total} en {segundos:.0f}s.")
    if fallos:
        print(f"{fallos} ficheros fallaron. Vuelve a ejecutar el script para reintentarlos.")
        return 1
    print(f"Media disponible. {media.ATRIBUCION}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
