/// Cobertura de los dos ARB.
///
/// El modo de fallo típico de este mecanismo es silencioso: se añade una clave
/// al español, se olvida el inglés y `gen-l10n` rellena el hueco con el texto
/// español, de modo que la app en inglés enseña una frase en español y nadie se
/// entera hasta verla en el móvil. Esto lo convierte en un test rojo.
library;

import 'dart:convert';
import 'dart:io';

import 'package:appgym/l10n/textos.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _arb(String idioma) =>
    jsonDecode(File('lib/l10n/app_$idioma.arb').readAsStringSync())
        as Map<String, dynamic>;

/// Las claves de verdad, sin los metadatos `@clave` ni `@@locale`.
Set<String> _claves(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).toSet();

void main() {
  final es = _arb('es');
  final en = _arb('en');

  test('los dos idiomas tienen exactamente las mismas claves', () {
    final soloEs = _claves(es).difference(_claves(en));
    final soloEn = _claves(en).difference(_claves(es));
    expect(soloEs, isEmpty, reason: 'sin traducir al inglés');
    expect(soloEn, isEmpty, reason: 'sobran en el inglés');
  });

  test('hay un ARB por cada idioma soportado', () {
    // Si mañana entra un tercero, esto obliga a añadir su fichero antes de
    // declararlo, y no al revés.
    for (final locale in idiomasSoportados) {
      expect(
        File('lib/l10n/app_${locale.languageCode}.arb').existsSync(),
        isTrue,
        reason: locale.languageCode,
      );
    }
  });

  test('el español va primero en los idiomas soportados', () {
    // Con «Automático» se pasa `locale: null` y Flutter cae al **primero** de
    // la lista cuando el móvil está en un idioma que no tenemos: con el móvil
    // en francés, la app sale en español y no en inglés ni vacía.
    expect(idiomasSoportados.first.languageCode, 'es');
    expect(
      idiomasSoportados.map((l) => l.languageCode).toSet(),
      Textos.supportedLocales.map((l) => l.languageCode).toSet(),
    );
  });

  test('ninguna traducción se ha quedado en blanco', () {
    for (final (idioma, arb) in [('es', es), ('en', en)]) {
      for (final clave in _claves(arb)) {
        expect(
          (arb[clave] as String).trim(),
          isNotEmpty,
          reason: '$idioma: $clave',
        );
      }
    }
  });

  test('todo parámetro declarado aparece en los dos idiomas', () {
    // Un `{nombre}` que falte en un idioma no rompe la generación, pero deja la
    // frase coja justo en el dato que importa. Se comparan los declarados en la
    // plantilla, no los que parezcan llaves: la sintaxis ICU de plural también
    // usa llaves para sus ramas.
    for (final clave in _claves(es)) {
      final meta = es['@$clave'] as Map<String, dynamic>?;
      final declarados =
          (meta?['placeholders'] as Map<String, dynamic>?)?.keys ??
          const <String>[];
      for (final parametro in declarados) {
        expect(
          en[clave] as String,
          contains('{$parametro'),
          reason: '$clave: falta {$parametro} en el inglés',
        );
        expect(es[clave] as String, contains('{$parametro'), reason: clave);
      }
    }
  });

  test('la plantilla española documenta lo que lleva parámetros', () {
    // La descripción es lo único que ve quien traduzca desde fuera: sin ella,
    // un `{cuando}` no dice si es una fecha, una hora o «hace dos días».
    final conParametros = _claves(
      es,
    ).where((k) => (es[k] as String).contains('{'));
    for (final clave in conParametros) {
      final meta = es['@$clave'] as Map<String, dynamic>?;
      expect(meta, isNotNull, reason: '$clave sin metadatos');
      expect(meta!['description'], isNotNull, reason: '$clave sin descripción');
      expect(
        meta['placeholders'],
        isNotNull,
        reason: '$clave sin placeholders',
      );
    }
  });
}
