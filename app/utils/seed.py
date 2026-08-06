"""Carga el catálogo de ejercicios desde el JSON a la tabla `ejercicio_catalogo`.

El JSON (`app/data/ejercicios.es.json`) es un recorte de
https://github.com/hasaneyldrm/exercises-dataset (datos bajo licencia MIT) con
los 1.324 ejercicios, sus metadatos y las instrucciones en español.
"""

import json
from pathlib import Path

from app.utils.i18n import body_part, equipment, musculo, musculos, normalizar
from app.utils.modelo import EjercicioCatalogo

RUTA_JSON = Path(__file__).resolve().parent.parent / "data" / "ejercicios.es.json"


def cargar_json():
    """Lee el JSON del catálogo. Devuelve una lista vacía si no está disponible."""
    try:
        with open(RUTA_JSON, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        print(f"No se encontró el catálogo en {RUTA_JSON}")
    except json.JSONDecodeError as e:
        print(f"El catálogo está corrupto: {e}")
    return []


def _texto_busqueda(ejercicio):
    """Construye el índice de búsqueda: nombre en inglés + todas las traducciones.

    Así "mancuerna", "pecho" o "bench press" encuentran el mismo ejercicio, y como
    se guarda normalizado (minúsculas, sin acentos) "biceps" encuentra "bíceps".
    """
    partes = [
        ejercicio["nombre"],
        ejercicio["body_part"],
        ejercicio["equipment"],
        ejercicio["target"],
        ejercicio["muscle_group"],
        body_part(ejercicio["body_part"]),
        equipment(ejercicio["equipment"]),
        musculo(ejercicio["target"]),
        musculo(ejercicio["muscle_group"]),
    ]
    partes.extend(ejercicio.get("secondary_muscles") or [])
    partes.extend(musculos(ejercicio.get("secondary_muscles")))
    return normalizar(" ".join(str(p) for p in partes if p))


def seed_catalogo(conexion, forzar=False):
    """Siembra el catálogo si hace falta. Es idempotente y barato de llamar.

    :param conexion: instancia de ConexionBD
    :param forzar: vuelve a sembrar aunque el recuento ya coincida
    :return: número de ejercicios en el catálogo tras la operación
    """
    datos = cargar_json()
    if not datos:
        return conexion.count_catalogo()

    if not forzar and conexion.count_catalogo() == len(datos):
        return len(datos)

    filas = []
    for ejercicio in datos:
        filas.append({
            "id": ejercicio["id"],
            "nombre": ejercicio["nombre"],
            "body_part": ejercicio["body_part"],
            "equipment": ejercicio["equipment"],
            "target": ejercicio["target"],
            "muscle_group": ejercicio["muscle_group"],
            "secondary_muscles": json.dumps(ejercicio.get("secondary_muscles") or [], ensure_ascii=False),
            "instrucciones": json.dumps(ejercicio.get("pasos") or [], ensure_ascii=False),
            "image": ejercicio["image"],
            "gif": ejercicio["gif"],
            "busqueda": _texto_busqueda(ejercicio),
        })

    sesion = conexion.get_sesion()
    try:
        sesion.query(EjercicioCatalogo).delete()
        sesion.bulk_insert_mappings(EjercicioCatalogo, filas)
        sesion.commit()
        print(f"Catálogo sembrado: {len(filas)} ejercicios.")
    except Exception as e:
        sesion.rollback()
        print(f"Error al sembrar el catálogo: {e}")
    finally:
        conexion.close_sesion(sesion)

    return conexion.count_catalogo()
