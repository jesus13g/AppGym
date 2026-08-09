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
import '../tema/tokens.dart' as t;
import '../tema/ui.dart' as ui;
import 'catalogo.dart';
import 'entrenar.dart';
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

/// Las pestañas, más el ofrecimiento de retomar un entrenamiento a medias.
///
/// La pregunta va aquí y no en la lista de rutinas porque este es el punto en
/// el que la app ya tiene datos y todavía no ha enseñado nada: preguntarlo
/// antes sería preguntarlo sobre una pantalla de carga.
class Pestanas extends ConsumerStatefulWidget {
  const Pestanas({super.key});

  @override
  ConsumerState<Pestanas> createState() => _PestanasState();
}

class _PestanasState extends ConsumerState<Pestanas> {
  /// Solo se pregunta una vez por arranque, se conteste lo que se conteste.
  bool _preguntado = false;

  @override
  void initState() {
    super.initState();
    // Tras el primer frame: mientras se construye el árbol no se puede navegar
    // ni abrir un diálogo.
    WidgetsBinding.instance.addPostFrameCallback((_) => _ofrecerContinuar());
  }

  Future<void> _ofrecerContinuar() async {
    if (_preguntado) return;
    _preguntado = true;

    final bd = ref.read(bdProvider);
    final borrador = await bd.sesionActiva();
    if (borrador == null || !mounted) return;

    final rutina = await bd.rutina(borrador.idRutina);
    if (rutina == null || !mounted) {
      // La rutina se borró con la sesión a medias: el borrador ya no lleva a
      // ninguna parte.
      await bd.descartarSesionActiva();
      return;
    }

    final continuar = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogo) => CupertinoAlertDialog(
        title: const Text('Tienes un entrenamiento empezado'),
        content: Padding(
          padding: const EdgeInsets.only(top: t.s),
          child: Text(
            '«${rutina.nombre}», empezado '
            '${leerFormato(context, ref).desde(borrador.inicio)}.',
            textAlign: TextAlign.center,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(dialogo, false),
            child: const Text('Descartar'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(dialogo, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (continuar == null || !mounted) return;

    if (!continuar) {
      await bd.descartarSesionActiva();
      if (mounted) ref.invalidate(sesionActivaProvider);
      return;
    }
    if (!mounted) return;
    await abrirEntrenar(context, borrador.idRutina, borrador: borrador);
  }

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
