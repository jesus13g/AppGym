/// Traducción del vocabulario del catálogo de ejercicios.
///
/// Los cuatro vocabularios del dataset (`bodyPart`, `equipment`, `target` y los
/// músculos) son cerrados y pequeños, así que se traducen con una tabla por
/// idioma: `i18n_es.dart` e `i18n_en.dart`. Los **nombres de ejercicio no se
/// traducen** en ningún idioma (ver la cabecera de `i18n_es.dart`).
///
/// Estas traducciones no son solo presentación: alimentan la columna `busqueda`
/// de `catalogo_ejercicios`, que es el índice del buscador. Y ahí entran **los
/// términos de todos los idiomas a la vez**, no solo los del activo: así el
/// índice se construye una vez, cambiar de idioma no toca la base, y un usuario
/// inglés que aprendió los nombres en español los sigue encontrando.
///
/// **Si tocas las tablas hay que subir `versionIndice`** (ver `semilla.dart`).
library;

import 'i18n_en.dart';
import 'i18n_es.dart';

/// Los idiomas con vocabulario propio, en el mismo orden que
/// `idiomasSoportados`. Un idioma sin tabla cae al español.
const idiomasCatalogo = <String>['es', 'en'];

const _zonasCuerpo = <String, Map<String, String>>{
  'es': zonasCuerpoEs,
  'en': zonasCuerpoEn,
};

const _equipamientos = <String, Map<String, String>>{
  'es': equipamientosEs,
  'en': equipamientosEn,
};

const _musculos = <String, Map<String, String>>{
  'es': musculosEs,
  'en': musculosEn,
};

String _traducir(
  String? valor,
  Map<String, Map<String, String>> tablas,
  String idioma,
) {
  if (valor == null || valor.isEmpty) return '';
  final clave = valor.toLowerCase().trim();
  final tabla = tablas[idioma] ?? tablas['es']!;
  final traducido = tabla[clave];
  if (traducido != null) return traducido;
  // Sin traducción, se muestra capitalizado en vez de en crudo.
  return clave.isEmpty ? '' : clave[0].toUpperCase() + clave.substring(1);
}

/// Traduce una zona del cuerpo ('chest' -> 'Pecho').
String zonaCuerpo(String? valor, String idioma) =>
    _traducir(valor, _zonasCuerpo, idioma);

/// Traduce un equipamiento ('dumbbell' -> 'Mancuerna').
String equipamiento(String? valor, String idioma) =>
    _traducir(valor, _equipamientos, idioma);

/// Traduce un músculo ('lats' -> 'Dorsales').
String musculo(String? valor, String idioma) =>
    _traducir(valor, _musculos, idioma);

/// Traduce una lista de músculos, sin repetir traducciones.
List<String> musculos(Iterable<String>? valores, String idioma) {
  final vistos = <String>[];
  for (final v in valores ?? const <String>[]) {
    final t = musculo(v, idioma);
    if (t.isNotEmpty && !vistos.contains(t)) vistos.add(t);
  }
  return vistos;
}

/// Cómo se dice un término en **todos** los idiomas, para el índice de
/// búsqueda. Se usa desde `semilla.dart` y de ahí sale el índice multilingüe.
Iterable<String> enTodosLosIdiomas(
  String? valor,
  String Function(String? valor, String idioma) traducir,
) => {for (final idioma in idiomasCatalogo) traducir(valor, idioma)};

/// Marcas diacríticas de la descomposición Unicode NFD.
final _diacriticos = RegExp('[̀-ͯ]');

/// Mapa de los caracteres acentuados que usa el español a su letra base.
///
/// Dart no trae normalización Unicode en su biblioteca estándar, así que en vez
/// de descomponer se sustituye directamente. Cubre lo que aparece en las
/// traducciones de este fichero y lo que un usuario puede teclear.
const _equivalencias = <String, String>{
  'á': 'a',
  'à': 'a',
  'ä': 'a',
  'â': 'a',
  'ã': 'a',
  'å': 'a',
  'é': 'e',
  'è': 'e',
  'ë': 'e',
  'ê': 'e',
  'í': 'i',
  'ì': 'i',
  'ï': 'i',
  'î': 'i',
  'ó': 'o',
  'ò': 'o',
  'ö': 'o',
  'ô': 'o',
  'õ': 'o',
  'ú': 'u',
  'ù': 'u',
  'ü': 'u',
  'û': 'u',
  'ñ': 'n',
  'ç': 'c',
  'ý': 'y',
};

/// Pasa a minúsculas y quita acentos, para búsquedas insensibles a tildes.
///
/// Es lo que hace que «biceps» encuentre «bíceps».
String normalizar(String? texto) {
  if (texto == null || texto.isEmpty) return '';
  final buffer = StringBuffer();
  for (final caracter
      in texto.toLowerCase().replaceAll(_diacriticos, '').split('')) {
    buffer.write(_equivalencias[caracter] ?? caracter);
  }
  return buffer.toString().trim();
}
