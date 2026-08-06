/// Tokens de diseño: colores, espaciados, radios y tipografía estilo iOS.
///
/// Los colores son los semánticos de Cupertino. En Flutter son
/// `CupertinoDynamicColor`, es decir, **no valen tal cual**: hay que resolverlos
/// contra el contexto para que den el tono de claro o de oscuro. Ese es el error
/// clásico al usarlos, así que aquí se envuelven en la extensión [Paleta] y las
/// pantallas escriben `context.texto` en vez de tocar `CupertinoColors`.
library;

import 'package:flutter/cupertino.dart';

// ── Colores ──────────────────────────────────────────────────────────────────

/// Colores del tema, ya resueltos para el brillo actual.
extension Paleta on BuildContext {
  /// Fondo de pantalla.
  Color get fondo => CupertinoColors.systemGroupedBackground.resolveFrom(this);

  /// Fondo de las listas y tarjetas.
  Color get tarjeta =>
      CupertinoColors.secondarySystemGroupedBackground.resolveFrom(this);

  /// Fondo de la barra de navegación y la de pestañas.
  Color get barra => CupertinoColors.systemBackground.resolveFrom(this);

  Color get texto => CupertinoColors.label.resolveFrom(this);
  Color get textoSec => CupertinoColors.secondaryLabel.resolveFrom(this);
  Color get textoTer => CupertinoColors.tertiaryLabel.resolveFrom(this);
  Color get marcador => CupertinoColors.placeholderText.resolveFrom(this);

  Color get separador => CupertinoColors.separator.resolveFrom(this);

  /// Fondo de campos y píldoras.
  Color get relleno => CupertinoColors.tertiarySystemFill.resolveFrom(this);

  Color get acento => CupertinoColors.systemBlue.resolveFrom(this);
  Color get destructivo => CupertinoColors.systemRed.resolveFrom(this);
  Color get exito => CupertinoColors.systemGreen.resolveFrom(this);
}

/// Convierte un color de [coloresRutina] ('#0A84FF') en un [Color].
///
/// Es la única familia de colores literales de la app: identifica cada rutina en
/// el calendario y tiene que ser la misma en claro y en oscuro.
Color colorDesdeHex(String? hex, Color porDefecto) {
  if (hex == null || hex.length != 7 || !hex.startsWith('#')) return porDefecto;
  final valor = int.tryParse(hex.substring(1), radix: 16);
  return valor == null ? porDefecto : Color(0xFF000000 | valor);
}

// ── Espaciado ────────────────────────────────────────────────────────────────

const double xs = 4;
const double s = 8;
const double m = 12;
const double l = 16;
const double xl = 20;
const double xxl = 28;

// ── Radios ───────────────────────────────────────────────────────────────────

const double radioS = 8;
const double radioM = 10;
const double radioL = 14;
const double radioXl = 22;

// ── Tipografía (escala de iOS) ───────────────────────────────────────────────

const double largeTitle = 34;
const double title1 = 28;
const double title2 = 22;
const double title3 = 20;
const double headline = 17;
const double body = 17;
const double callout = 16;
const double subhead = 15;
const double footnote = 13;
const double caption = 12;

const FontWeight semibold = FontWeight.w600;
const FontWeight bold = FontWeight.w700;

/// Alto mínimo de una fila táctil, según las guías de Apple.
const double altoFila = 44;
