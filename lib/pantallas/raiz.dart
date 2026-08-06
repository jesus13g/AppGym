/// Raíz de la app: arranque, onboarding y barra de pestañas.
///
/// Cada pestaña vive en su propio `CupertinoTabView`, que trae su pila de
/// navegación independiente. De ahí salen gratis el botón atrás, las
/// transiciones de empuje y el gesto de volver deslizando, que en el router de
/// Flet había que montar a mano.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/media.dart' as media;
import '../estado/providers.dart';
import '../tema/tokens.dart';
import '../tema/ui.dart' as ui;
import 'catalogo.dart';
import 'progreso.dart';
import 'rutinas.dart';
import 'setup.dart';

class Raiz extends ConsumerStatefulWidget {
  const Raiz({super.key});

  @override
  ConsumerState<Raiz> createState() => _RaizState();
}

class _RaizState extends ConsumerState<Raiz> {
  /// Se pone a true al salir del onboarding, ya sea descargando u omitiendo.
  bool _entrado = false;

  @override
  Widget build(BuildContext context) {
    final arranque = ref.watch(arranqueProvider);

    return CupertinoPageScaffold(
      backgroundColor: context.fondo,
      child: arranque.when(
        loading: () => const ui.Cargando(mensaje: 'Preparando el catálogo…'),
        error: (e, _) => ui.EstadoVacio(
          icono: CupertinoIcons.exclamationmark_triangle,
          titulo: 'No se pudo cargar el catálogo',
          subtitulo: '$e',
        ),
        data: (catalogo) {
          if (_entrado || media.descargaCompleta) return const Pestanas();
          return PantallaSetup(
            catalogo: catalogo,
            onEntrar: () => setState(() => _entrado = true),
          );
        },
      ),
    );
  }
}

class Pestanas extends StatelessWidget {
  const Pestanas({super.key});

  @override
  Widget build(BuildContext context) => CupertinoTabScaffold(
    tabBar: CupertinoTabBar(
      backgroundColor: context.barra,
      activeColor: context.acento,
      inactiveColor: context.textoSec,
      border: Border(top: BorderSide(color: context.separador, width: 0.5)),
      items: const [
        BottomNavigationBarItem(
          icon: Icon(CupertinoIcons.list_bullet),
          label: 'Rutinas',
        ),
        BottomNavigationBarItem(
          icon: Icon(CupertinoIcons.search),
          label: 'Ejercicios',
        ),
        BottomNavigationBarItem(
          icon: Icon(CupertinoIcons.chart_bar_alt_fill),
          label: 'Progreso',
        ),
      ],
    ),
    tabBuilder: (context, indice) => CupertinoTabView(
      builder: (context) => switch (indice) {
        0 => const PantallaRutinas(),
        1 => const PantallaCatalogo(),
        _ => const PantallaProgreso(),
      },
    ),
  );
}
