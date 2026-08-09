/// Utilidades que comparten los tests.
///
/// Los textos traducidos se piden a la clase generada sin montar un widget:
/// `lookupTextos` es una función normal, así que un test de datos puede
/// construir un [Formato] sin `pumpWidget`.
library;

import 'package:appgym/datos/ajustes.dart';
import 'package:appgym/datos/formato.dart';
import 'package:appgym/l10n/textos.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Un [Formato] listo para usar en un test, en el idioma que se pida.
///
/// La llamada a `initializeDateFormatting` es lo que en la app hace
/// `flutter_localizations` al cargar sus delegates: sin ella `DateFormat` no
/// tiene los símbolos del idioma. Es idempotente, así que se puede llamar en
/// cada test sin llevar la cuenta.
Formato formatoDePrueba({
  String idioma = 'es',
  Ajustes ajustes = const Ajustes(),
}) {
  initializeDateFormatting();
  return Formato(
    locale: idioma,
    textos: lookupTextos(Locale(idioma)),
    ajustes: ajustes,
  );
}

/// Los textos traducidos de un idioma, sin montar un widget.
Textos textosDePrueba({String idioma = 'es'}) => lookupTextos(Locale(idioma));
