/// Punto de entrada de AppGym.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pantallas/raiz.dart';

void main() {
  runApp(const ProviderScope(child: AppGym()));
}

class AppGym extends StatelessWidget {
  const AppGym({super.key});

  @override
  Widget build(BuildContext context) => const CupertinoApp(
    title: 'AppGym',
    debugShowCheckedModeBanner: false,
    // Sin `brightness`, Cupertino sigue el tema del sistema, que es lo que
    // hace que los colores semánticos cambien solos entre claro y oscuro.
    theme: CupertinoThemeData(),
    locale: Locale('es'),
    supportedLocales: [Locale('es'), Locale('en')],
    localizationsDelegates: [
      GlobalCupertinoLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    home: Raiz(),
  );
}
