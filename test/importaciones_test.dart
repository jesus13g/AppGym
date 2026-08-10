/// Qué puede importar cada parte de `lib/`.
///
/// K12 pedía que «`lib/datos/sincro/` sea el único directorio que importa el SDK
/// del proveedor, con un test que lo fije, como el que fija que no se importa
/// `material.dart`». Dos correcciones al enunciado, y este fichero es las dos:
///
///   - **No hay SDK.** Supabase se habla REST con el `http` que ya estaba, así
///     que el criterio se replantea a lo que de verdad significaba: que hablar
///     con la red esté aislado, que la costura siga sin saber de Flutter ni de
///     drift, y que el nombre del proveedor no se filtre fuera de su adaptador.
///   - **El test de `material.dart` no existía.** `CLAUDE.md` lo daba por
///     escrito y no lo estaba. Aquí queda saldado.
///
/// Se comprueban las **líneas de import**, no el texto suelto: `supabase.dart`
/// menciona `flutter_secure_storage` en un comentario y eso no es importarlo.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Todos los `.dart` de `lib/`, por su ruta relativa y con barras normales.
///
/// `lib/l10n/generado/` queda fuera: no se versiona, lo escribe `gen-l10n` y no
/// es código de este proyecto.
Map<String, String> _fuentes() {
  final fuentes = <String, String>{};
  for (final entrada in Directory('lib').listSync(recursive: true)) {
    if (entrada is! File || !entrada.path.endsWith('.dart')) continue;
    final ruta = entrada.path.replaceAll(r'\', '/');
    if (ruta.contains('/l10n/generado/')) continue;
    fuentes[ruta] = entrada.readAsStringSync();
  }
  return fuentes;
}

/// Lo que importa un fichero, tal y como está escrito en su `import`.
final _import = RegExp(r"^\s*(?:import|export)\s+'([^']+)'", multiLine: true);

Set<String> _importaciones(String fuente) => {
  for (final coincidencia in _import.allMatches(fuente)) coincidencia.group(1)!,
};

void main() {
  final fuentes = _fuentes();

  test('hay fuentes que mirar', () {
    // Si el patrón de búsqueda o el directorio de trabajo cambiaran, el resto
    // de este fichero pasaría en verde sin comprobar nada.
    expect(fuentes.length, greaterThan(40));
    expect(fuentes, contains('lib/datos/sincro/supabase.dart'));
  });

  test('no se importa material.dart en ningún sitio', () {
    // La interfaz es solo Cupertino. Lo que Material trae y Flutter no, se
    // compone en `tema/ui.dart` — así nació `BarraProgreso`, sustituyendo a
    // `LinearProgressIndicator`.
    for (final MapEntry(key: ruta, value: fuente) in fuentes.entries) {
      expect(
        _importaciones(fuente),
        isNot(contains('package:flutter/material.dart')),
        reason: ruta,
      );
    }
  });

  test('hablar con la red está aislado en tres ficheros', () {
    // `media.dart` descarga las imágenes del catálogo, `drive.dart` es la copia
    // automática y `supabase.dart` la sincronización. Nadie más tiene por qué
    // abrir una conexión, y menos una pantalla.
    const permitidos = {
      'lib/datos/media.dart',
      'lib/datos/nube/drive.dart',
      'lib/datos/sincro/supabase.dart',
    };
    for (final MapEntry(key: ruta, value: fuente) in fuentes.entries) {
      if (permitidos.contains(ruta)) continue;
      expect(
        _importaciones(fuente).where((i) => i.startsWith('package:http')),
        isEmpty,
        reason: ruta,
      );
    }
  });

  test('el almacén seguro se toca en un solo fichero', () {
    // Las credenciales de las dos funcionalidades viven bajo dos claves del
    // mismo almacén, y la configuración que las respalda con el Keystore está
    // escrita una sola vez.
    for (final MapEntry(key: ruta, value: fuente) in fuentes.entries) {
      if (ruta == 'lib/datos/nube/token.dart') continue;
      expect(
        _importaciones(
          fuente,
        ).where((i) => i.contains('flutter_secure_storage')),
        isEmpty,
        reason: ruta,
      );
    }
  });

  test('la costura no sabe de Flutter, ni de drift, ni de la base', () {
    // `transporte.dart` son datos y una interfaz, y nada más. Es lo que permite
    // que el motor se pruebe entero sin red, sin cuenta y sin proveedor.
    expect(
      _importaciones(fuentes['lib/datos/sincro/transporte.dart']!),
      isEmpty,
    );
  });

  test('el adaptador no sabe de Flutter, ni de drift, ni de la base', () {
    // Habla con la costura y con el almacén, y punto. Si algún día necesitara
    // `bd.dart`, sería que la reconciliación se le está colando dentro.
    final suyos = _importaciones(fuentes['lib/datos/sincro/supabase.dart']!);
    for (final prohibido in ['package:flutter/', 'package:drift/', 'bd.dart']) {
      expect(
        suyos.where((i) => i.contains(prohibido)),
        isEmpty,
        reason: prohibido,
      );
    }
  });

  test('el motor de reconciliación no importa el adaptador de nadie', () {
    // `motor.dart` y `enlace.dart` sí importan `bd.dart` —reconcilian contra la
    // base, es su trabajo—, pero no pueden saber qué proveedor hay detrás.
    for (final ruta in [
      'lib/datos/sincro/motor.dart',
      'lib/datos/sincro/enlace.dart',
    ]) {
      final suyos = _importaciones(fuentes[ruta]!);
      expect(suyos, isNot(contains('supabase.dart')), reason: ruta);
      expect(
        suyos.where((i) => i.startsWith('package:flutter/')),
        isEmpty,
        reason: ruta,
      );
    }
  });

  test('solo el adaptador sabe cómo se habla con el proveedor', () {
    // Este es el criterio de K12 tal cual, adaptado a que no hay SDK: la URL,
    // la clave y las rutas REST son suyas. `providers.dart` lo instancia —
    // alguien tiene que hacerlo— pero no conoce ni un endpoint.
    const marcas = [
      'SUPABASE_URL',
      'SUPABASE_ANON_KEY',
      '/auth/v1',
      '/rest/v1',
    ];
    for (final MapEntry(key: ruta, value: fuente) in fuentes.entries) {
      if (ruta == 'lib/datos/sincro/supabase.dart') continue;
      for (final marca in marcas) {
        expect(fuente, isNot(contains(marca)), reason: '$ruta: $marca');
      }
    }
  });
}
