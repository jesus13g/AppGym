/// Punto de entrada de AppGym.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'datos/bd.dart';
import 'estado/providers.dart';
import 'pantallas/raiz.dart';

void main() {
  runApp(const ProviderScope(child: AppGym()));
}

class AppGym extends ConsumerWidget {
  const AppGym({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Mientras las preferencias cargan no hay `brightness`, que es exactamente
    // lo que se quiere: seguir al sistema. Así el primer frame no parpadea en
    // el caso de largo el más común.
    final tema = ref.watch(ajustesProvider).value?.tema ?? Tema.sistema;

    return CupertinoApp(
      title: 'AppGym',
      debugShowCheckedModeBanner: false,
      // Sin `brightness`, Cupertino sigue el tema del sistema, que es lo que
      // hace que los colores semánticos cambien solos entre claro y oscuro.
      // Forzarlo aquí, en la raíz, es lo que hace que la extensión `Paleta` lo
      // resuelva igual en toda la app: los diálogos incluidos, porque cuelgan
      // de este mismo `CupertinoApp`.
      theme: CupertinoThemeData(
        brightness: switch (tema) {
          Tema.sistema => null,
          Tema.claro => Brightness.light,
          Tema.oscuro => Brightness.dark,
        },
      ),
      locale: const Locale('es'),
      supportedLocales: const [Locale('es'), Locale('en')],
      localizationsDelegates: const [
        GlobalCupertinoLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      home: const Raiz(),
    );
  }
}
