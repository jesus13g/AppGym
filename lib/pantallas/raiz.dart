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
import '../estado/copia_automatica.dart';
import '../estado/providers.dart';
import '../estado/sincro.dart';
import '../l10n/textos.dart';
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
        loading: () => ui.Cargando(mensaje: context.t.raizPreparando),
        error: (e, _) => ui.EstadoVacio(
          icono: CupertinoIcons.exclamationmark_triangle,
          titulo: context.t.raizErrorCatalogo,
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

class _PestanasState extends ConsumerState<Pestanas>
    with WidgetsBindingObserver {
  /// Solo se pregunta una vez por arranque, se conteste lo que se conteste.
  bool _preguntado = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Tras el primer frame: mientras se construye el árbol no se puede navegar
    // ni abrir un diálogo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ofrecerContinuar();
      // La copia automática, si toca. Va después del primer frame y no se
      // espera: la app no puede quedarse en blanco por una copia, y su fallo
      // no es visible en la ruta de entrenar.
      _copiar(Disparador.arranque);
      _sincronizar(DisparadorSincro.arranque);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Al volver del segundo plano. El motor pone el mínimo de cinco minutos
  /// entre intentos, así que alternar de app no dispara nada.
  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado != AppLifecycleState.resumed) return;
    _copiar(Disparador.vuelta);
    _sincronizar(DisparadorSincro.vuelta);
  }

  void _copiar(Disparador disparador) {
    if (!mounted) return;
    ref.read(motorCopiaProvider.notifier).intentar(disparador);
  }

  void _sincronizar(DisparadorSincro disparador) {
    if (!mounted) return;
    ref.read(sincronizacionProvider.notifier).intentar(disparador);
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
        title: Text(context.t.raizContinuarTitulo),
        content: Padding(
          padding: const EdgeInsets.only(top: t.s),
          child: Text(
            context.t.raizContinuarMensaje(
              rutina.nombre,
              leerFormato(context, ref).desde(borrador.inicio),
            ),
            textAlign: TextAlign.center,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(dialogo, false),
            child: Text(context.t.raizDescartar),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(dialogo, true),
            child: Text(context.t.raizContinuar),
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
  Widget build(BuildContext context) {
    // Cuando una pasada de sincronización trae algo, la base ha cambiado por
    // debajo de la interfaz y hay que repintarlo todo.
    //
    // Se escucha aquí, en la raíz, porque es el único widget que está siempre
    // montado: el motor tiene un `Ref` y no un `WidgetRef`, así que no puede
    // invalidar nada por su cuenta. `cambios` solo sube, de modo que comparar
    // con el valor anterior basta para no repintar de más.
    ref.listen(sincronizacionProvider, (antes, ahora) {
      if (ahora.cambios > (antes?.cambios ?? 0)) invalidarTodo(ref);
    });

    return _pestanas(context);
  }

  Widget _pestanas(BuildContext context) => CupertinoTabScaffold(
    tabBar: CupertinoTabBar(
      backgroundColor: context.barra,
      activeColor: context.acento,
      inactiveColor: context.textoSec,
      border: Border(top: BorderSide(color: context.separador, width: 0.5)),
      items: [
        BottomNavigationBarItem(
          icon: const Icon(CupertinoIcons.list_bullet),
          label: context.t.raizRutinas,
        ),
        BottomNavigationBarItem(
          icon: const Icon(CupertinoIcons.search),
          label: context.t.comunEjerciciosCabecera,
        ),
        BottomNavigationBarItem(
          icon: const Icon(CupertinoIcons.chart_bar_alt_fill),
          label: context.t.comunProgreso,
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
