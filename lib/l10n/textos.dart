/// Punto de entrada a los textos traducidos.
///
/// Todo el mundo importa **este** fichero y nunca `generado/`, que no se
/// versiona (ver `.gitignore`) y podría cambiar de nombre o de ruta. Aquí viven
/// además las dos cosas que lo generado no puede dar: el atajo `context.t` y el
/// orden de los idiomas.
///
/// El texto se escribe en `app_es.arb` (la plantilla, con las descripciones) y
/// en `app_en.arb`. **Cada texto nuevo son dos ediciones**; hay un test que
/// compara los dos conjuntos de claves y no deja saltarse ninguna.
library;

import 'package:flutter/widgets.dart';

import 'generado/textos.dart';

export 'generado/textos.dart';

/// Los idiomas que la app admite, **con el español primero**.
///
/// No se usa `Textos.supportedLocales`, que sale ordenada alfabéticamente y
/// pondría el inglés delante: con `locale: null` (la opción «Automático»)
/// Flutter cae al **primero** de la lista cuando el idioma del sistema no está,
/// y esta app es española antes que inglesa. Hay un test que comprueba que esta
/// lista y la generada tienen los mismos idiomas.
const idiomasSoportados = <Locale>[Locale('es'), Locale('en')];

/// Acceso corto a los textos, coherente con `context.texto` y `context.acento`
/// de la paleta.
///
/// Vive aquí y no en `tema/ui.dart` a propósito: los componentes compartidos de
/// `ui.dart` no deben saber en qué idioma está la app —reciben el texto ya
/// resuelto—, así que ese fichero no importa `Textos`.
extension Traducciones on BuildContext {
  Textos get t => Textos.of(this);
}
