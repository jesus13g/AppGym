/// Traducciones al español del vocabulario del catálogo de ejercicios.
///
/// Los nombres de los ejercicios vienen solo en inglés en el dataset original y
/// se muestran tal cual, pero las categorías sí son vocabularios cerrados y
/// pequeños, así que se traducen aquí. Estas traducciones también alimentan el
/// índice de búsqueda (ver `semilla.dart`), de forma que buscar «mancuerna»
/// encuentra los ejercicios cuyo equipamiento es «dumbbell».
///
/// **Si tocas este fichero hay que volver a sembrar el catálogo**, porque la
/// columna `busqueda` se construye a partir de estas tablas.
library;

const zonasCuerpo = <String, String>{
  'back': 'Espalda',
  'cardio': 'Cardio',
  'chest': 'Pecho',
  'lower arms': 'Antebrazos',
  'lower legs': 'Piernas (inferior)',
  'neck': 'Cuello',
  'shoulders': 'Hombros',
  'upper arms': 'Brazos',
  'upper legs': 'Piernas',
  'waist': 'Core',
};

const equipamientos = <String, String>{
  'assisted': 'Asistido',
  'band': 'Banda',
  'barbell': 'Barra',
  'body weight': 'Peso corporal',
  'bosu ball': 'Bosu',
  'cable': 'Polea',
  'dumbbell': 'Mancuerna',
  'elliptical machine': 'Elíptica',
  'ez barbell': 'Barra Z',
  'hammer': 'Martillo',
  'kettlebell': 'Kettlebell',
  'leverage machine': 'Máquina',
  'medicine ball': 'Balón medicinal',
  'olympic barbell': 'Barra olímpica',
  'resistance band': 'Banda elástica',
  'roller': 'Rodillo',
  'rope': 'Cuerda',
  'skierg machine': 'SkiErg',
  'sled machine': 'Trineo',
  'smith machine': 'Multipower',
  'stability ball': 'Fitball',
  'stationary bike': 'Bicicleta estática',
  'stepmill machine': 'Escaladora',
  'tire': 'Neumático',
  'trap bar': 'Barra hexagonal',
  'upper body ergometer': 'Ergómetro de brazos',
  'weighted': 'Lastrado',
  'wheel roller': 'Rueda abdominal',
};

const musculosTabla = <String, String>{
  'abdominals': 'Abdominales',
  'abductors': 'Abductores',
  'abs': 'Abdominales',
  'adductors': 'Aductores',
  'ankle stabilizers': 'Estabilizadores del tobillo',
  'ankles': 'Tobillos',
  'back': 'Espalda',
  'biceps': 'Bíceps',
  'brachialis': 'Braquial',
  'calves': 'Gemelos',
  'cardiovascular system': 'Sistema cardiovascular',
  'chest': 'Pecho',
  'core': 'Core',
  'deltoids': 'Deltoides',
  'delts': 'Deltoides',
  'feet': 'Pies',
  'forearms': 'Antebrazos',
  'glutes': 'Glúteos',
  'grip muscles': 'Agarre',
  'groin': 'Ingle',
  'hamstrings': 'Isquiotibiales',
  'hands': 'Manos',
  'hip flexors': 'Flexores de cadera',
  'inner thighs': 'Cara interna del muslo',
  'latissimus dorsi': 'Dorsal ancho',
  'lats': 'Dorsales',
  'levator scapulae': 'Elevador de la escápula',
  'lower abs': 'Abdomen inferior',
  'lower back': 'Lumbares',
  'obliques': 'Oblicuos',
  'pectorals': 'Pectorales',
  'quadriceps': 'Cuádriceps',
  'quads': 'Cuádriceps',
  'rear deltoids': 'Deltoides posterior',
  'rhomboids': 'Romboides',
  'rotator cuff': 'Manguito rotador',
  'serratus anterior': 'Serrato anterior',
  'shins': 'Espinillas',
  'shoulders': 'Hombros',
  'soleus': 'Sóleo',
  'spine': 'Columna',
  'sternocleidomastoid': 'Esternocleidomastoideo',
  'traps': 'Trapecios',
  'trapezius': 'Trapecios',
  'triceps': 'Tríceps',
  'upper back': 'Espalda alta',
  'upper chest': 'Pecho superior',
  'wrist extensors': 'Extensores de muñeca',
  'wrist flexors': 'Flexores de muñeca',
  'wrists': 'Muñecas',
};

String _traducir(String? valor, Map<String, String> tabla) {
  if (valor == null || valor.isEmpty) return '';
  final clave = valor.toLowerCase().trim();
  final traducido = tabla[clave];
  if (traducido != null) return traducido;
  // Sin traducción, se muestra capitalizado en vez de en crudo.
  return clave.isEmpty ? '' : clave[0].toUpperCase() + clave.substring(1);
}

/// Traduce una zona del cuerpo ('chest' -> 'Pecho').
String zonaCuerpo(String? valor) => _traducir(valor, zonasCuerpo);

/// Traduce un equipamiento ('dumbbell' -> 'Mancuerna').
String equipamiento(String? valor) => _traducir(valor, equipamientos);

/// Traduce un músculo ('lats' -> 'Dorsales').
String musculo(String? valor) => _traducir(valor, musculosTabla);

/// Traduce una lista de músculos, sin repetir traducciones.
List<String> musculos(Iterable<String>? valores) {
  final vistos = <String>[];
  for (final v in valores ?? const <String>[]) {
    final t = musculo(v);
    if (t.isNotEmpty && !vistos.contains(t)) vistos.add(t);
  }
  return vistos;
}

/// Marcas diacríticas de la descomposición Unicode NFD.
final _diacriticos = RegExp('[̀-ͯ]');

/// Mapa de los caracteres acentuados que usa el español a su letra base.
///
/// Dart no trae normalización Unicode en su biblioteca estándar, así que en vez
/// de descomponer se sustituye directamente. Cubre lo que aparece en las
/// traducciones de este fichero y lo que un usuario puede teclear.
const _equivalencias = <String, String>{
  'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'ã': 'a', 'å': 'a',
  'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
  'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
  'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', 'õ': 'o',
  'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
  'ñ': 'n', 'ç': 'c', 'ý': 'y',
};

/// Pasa a minúsculas y quita acentos, para búsquedas insensibles a tildes.
///
/// Es lo que hace que «biceps» encuentre «bíceps».
String normalizar(String? texto) {
  if (texto == null || texto.isEmpty) return '';
  final buffer = StringBuffer();
  for (final caracter in texto.toLowerCase().replaceAll(_diacriticos, '').split('')) {
    buffer.write(_equivalencias[caracter] ?? caracter);
  }
  return buffer.toString().trim();
}
