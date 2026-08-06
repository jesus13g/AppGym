"""Traducciones al español del vocabulario del catálogo de ejercicios.

Los nombres de los ejercicios vienen solo en inglés en el dataset original y se
muestran tal cual, pero las categorías sí son vocabularios cerrados y pequeños,
así que se traducen aquí. Estas traducciones también alimentan el índice de
búsqueda (`app/utils/seed.py`), de forma que buscar "mancuerna" encuentra los
ejercicios cuyo equipamiento es "dumbbell".
"""

import unicodedata

BODY_PARTS = {
    "back": "Espalda",
    "cardio": "Cardio",
    "chest": "Pecho",
    "lower arms": "Antebrazos",
    "lower legs": "Piernas (inferior)",
    "neck": "Cuello",
    "shoulders": "Hombros",
    "upper arms": "Brazos",
    "upper legs": "Piernas",
    "waist": "Core",
}

EQUIPMENT = {
    "assisted": "Asistido",
    "band": "Banda",
    "barbell": "Barra",
    "body weight": "Peso corporal",
    "bosu ball": "Bosu",
    "cable": "Polea",
    "dumbbell": "Mancuerna",
    "elliptical machine": "Elíptica",
    "ez barbell": "Barra Z",
    "hammer": "Martillo",
    "kettlebell": "Kettlebell",
    "leverage machine": "Máquina",
    "medicine ball": "Balón medicinal",
    "olympic barbell": "Barra olímpica",
    "resistance band": "Banda elástica",
    "roller": "Rodillo",
    "rope": "Cuerda",
    "skierg machine": "SkiErg",
    "sled machine": "Trineo",
    "smith machine": "Multipower",
    "stability ball": "Fitball",
    "stationary bike": "Bicicleta estática",
    "stepmill machine": "Escaladora",
    "tire": "Neumático",
    "trap bar": "Barra hexagonal",
    "upper body ergometer": "Ergómetro de brazos",
    "weighted": "Lastrado",
    "wheel roller": "Rueda abdominal",
}

MUSCLES = {
    "abdominals": "Abdominales",
    "abductors": "Abductores",
    "abs": "Abdominales",
    "adductors": "Aductores",
    "ankle stabilizers": "Estabilizadores del tobillo",
    "ankles": "Tobillos",
    "back": "Espalda",
    "biceps": "Bíceps",
    "brachialis": "Braquial",
    "calves": "Gemelos",
    "cardiovascular system": "Sistema cardiovascular",
    "chest": "Pecho",
    "core": "Core",
    "deltoids": "Deltoides",
    "delts": "Deltoides",
    "feet": "Pies",
    "forearms": "Antebrazos",
    "glutes": "Glúteos",
    "grip muscles": "Agarre",
    "groin": "Ingle",
    "hamstrings": "Isquiotibiales",
    "hands": "Manos",
    "hip flexors": "Flexores de cadera",
    "inner thighs": "Cara interna del muslo",
    "latissimus dorsi": "Dorsal ancho",
    "lats": "Dorsales",
    "levator scapulae": "Elevador de la escápula",
    "lower abs": "Abdomen inferior",
    "lower back": "Lumbares",
    "obliques": "Oblicuos",
    "pectorals": "Pectorales",
    "quadriceps": "Cuádriceps",
    "quads": "Cuádriceps",
    "rear deltoids": "Deltoides posterior",
    "rhomboids": "Romboides",
    "rotator cuff": "Manguito rotador",
    "serratus anterior": "Serrato anterior",
    "shins": "Espinillas",
    "shoulders": "Hombros",
    "soleus": "Sóleo",
    "spine": "Columna",
    "sternocleidomastoid": "Esternocleidomastoideo",
    "traps": "Trapecios",
    "trapezius": "Trapecios",
    "triceps": "Tríceps",
    "upper back": "Espalda alta",
    "upper chest": "Pecho superior",
    "wrist extensors": "Extensores de muñeca",
    "wrist flexors": "Flexores de muñeca",
    "wrists": "Muñecas",
}


def _traducir(valor, tabla):
    if not valor:
        return ""
    return tabla.get(valor.lower().strip(), valor.capitalize())


def body_part(valor):
    """Traduce una zona del cuerpo ('chest' -> 'Pecho')."""
    return _traducir(valor, BODY_PARTS)


def equipment(valor):
    """Traduce un equipamiento ('dumbbell' -> 'Mancuerna')."""
    return _traducir(valor, EQUIPMENT)


def musculo(valor):
    """Traduce un músculo ('lats' -> 'Dorsales')."""
    return _traducir(valor, MUSCLES)


def musculos(valores):
    """Traduce una lista de músculos, sin repetir traducciones."""
    vistos = []
    for v in valores or []:
        t = musculo(v)
        if t not in vistos:
            vistos.append(t)
    return vistos


def normalizar(texto):
    """Pasa a minúsculas y quita acentos, para búsquedas insensibles a tildes."""
    if not texto:
        return ""
    descompuesto = unicodedata.normalize("NFKD", str(texto))
    sin_acentos = "".join(c for c in descompuesto if not unicodedata.combining(c))
    return sin_acentos.lower().strip()
