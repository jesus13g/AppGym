"""Formateo de textos que comparten varias pantallas."""

import json
from datetime import date, datetime

from app.utils import i18n, media

MESES = ["Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio",
         "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"]

DIAS_SEMANA = ["L", "M", "X", "J", "V", "S", "D"]


def mes(numero):
    """Nombre del mes (1-12)."""
    return MESES[numero - 1]


def fecha_corta(valor):
    """'12 mar' a partir de un datetime o date."""
    if valor is None:
        return ""
    return f"{valor.day} {MESES[valor.month - 1][:3].lower()}"


def fecha_larga(valor):
    """'12 de marzo de 2026'."""
    if valor is None:
        return ""
    return f"{valor.day} de {MESES[valor.month - 1].lower()} de {valor.year}"


def hace(valor):
    """Distancia en lenguaje natural hasta hoy: 'hoy', 'ayer', 'hace 5 días'…"""
    if valor is None:
        return "Sin entrenar"
    dia = valor.date() if isinstance(valor, datetime) else valor
    dias = (date.today() - dia).days
    if dias <= 0:
        return "Hoy"
    if dias == 1:
        return "Ayer"
    if dias < 7:
        return f"Hace {dias} días"
    if dias < 30:
        semanas = dias // 7
        return f"Hace {semanas} semana{'s' if semanas > 1 else ''}"
    meses = dias // 30
    return f"Hace {meses} mes{'es' if meses > 1 else ''}"


def plural(cantidad, singular, plural_):
    return f"{cantidad} {singular if cantidad == 1 else plural_}"


def lista_json(valor):
    """Deserializa una columna de texto que guarda una lista JSON."""
    if not valor:
        return []
    try:
        cargado = json.loads(valor)
        return cargado if isinstance(cargado, list) else []
    except (json.JSONDecodeError, TypeError):
        return []


# ── Ejercicios ───────────────────────────────────────────────────────────────

def subtitulo_catalogo(ficha):
    """'Pectorales · Mancuerna' para una ficha del catálogo."""
    if ficha is None:
        return ""
    partes = [i18n.musculo(ficha.target), i18n.equipment(ficha.equipment)]
    return " · ".join(p for p in partes if p)


def subtitulo_ejercicio(ejercicio):
    """Subtítulo de un ejercicio de rutina: del catálogo o su descripción."""
    if ejercicio.catalogo is not None:
        return subtitulo_catalogo(ejercicio.catalogo)
    return (ejercicio.descripcion or "Ejercicio personalizado").strip()


def imagen_ejercicio(ejercicio):
    """Miniatura de un ejercicio de rutina, o None si es personalizado."""
    if getattr(ejercicio, "catalogo", None) is None:
        return None
    return media.resolver(ejercicio.catalogo.image)


def animacion_catalogo(ficha):
    """GIF animado de una ficha del catálogo."""
    if ficha is None:
        return None
    return media.resolver(ficha.gif)
