/// Detalle de una rutina: sus ejercicios y el acceso a registrar entrenamiento.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/bd.dart';
import '../datos/formato.dart' as formato;
import '../estado/providers.dart';
import '../tema/tokens.dart';
import '../tema/tokens.dart' as t;
import '../tema/ui.dart' as ui;
import 'catalogo.dart';
import 'entrenar.dart';
import 'ficha.dart';
import 'historial.dart';

Future<void> abrirRutina(BuildContext context, int idRutina) =>
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        title: 'Rutinas',
        builder: (_) => PantallaRutina(idRutina: idRutina),
      ),
    );

class PantallaRutina extends ConsumerStatefulWidget {
  const PantallaRutina({super.key, required this.idRutina});

  final int idRutina;

  @override
  ConsumerState<PantallaRutina> createState() => _PantallaRutinaState();
}

class _PantallaRutinaState extends ConsumerState<PantallaRutina> {
  /// En modo edición salen las asas de arrastre y desaparece el chevron.
  bool _editando = false;

  /// Orden mientras se arrastra, para que la lista siga al dedo sin esperar a
  /// que la escritura vuelva de la base de datos.
  List<int>? _ordenLocal;

  int get idRutina => widget.idRutina;

  Future<void> _renombrar(
    BuildContext context,
    WidgetRef ref,
    String actual,
  ) async {
    final nombre = await ui.dialogoTexto(
      context,
      titulo: 'Renombrar rutina',
      marcador: 'Nombre de la rutina',
      valor: actual,
    );
    if (nombre == null || !context.mounted) return;

    final bien = await ref.read(bdProvider).renombrarRutina(idRutina, nombre);
    if (!context.mounted) return;

    if (!bien) {
      ui.aviso(context, 'Ya existe una rutina llamada «$nombre»');
      return;
    }
    invalidarRutina(ref, idRutina);
  }

  Future<void> _borrarEjercicio(WidgetRef ref, int idEjercicio) async {
    await ref.read(bdProvider).borrarEjercicio(idRutina, idEjercicio);
    invalidarRutina(ref, idRutina);
  }

  /// Aplica el arrastre y lo guarda.
  Future<void> _reordenar(
    List<EjercicioConFicha> lista,
    int desde,
    int hasta,
  ) async {
    final ids = [for (final e in lista) e.id];
    ids.insert(hasta, ids.removeAt(desde));

    setState(() => _ordenLocal = ids);
    await ref.read(bdProvider).reordenarEjercicios(idRutina, ids);
    if (mounted) invalidarRutina(ref, idRutina);
  }

  /// Mueve un ejercicio a otra rutina, con su histórico.
  Future<void> _mover(BuildContext context, EjercicioConFicha ejercicio) async {
    final rutinas = await ref.read(bdProvider).todasLasRutinas();
    final destinos = [
      for (final r in rutinas)
        if (r.id != idRutina) r,
    ];
    if (!context.mounted) return;

    if (destinos.isEmpty) {
      ui.aviso(context, 'No hay otra rutina a la que moverlo');
      return;
    }

    final destino = await showCupertinoModalPopup<int>(
      context: context,
      builder: (hoja) => CupertinoActionSheet(
        title: Text('Mover «${ejercicio.nombre}»'),
        message: const Text(
          'Se lleva su histórico: las series ya registradas siguen '
          'colgando de las sesiones en las que se hicieron.',
        ),
        actions: [
          for (final r in destinos)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(hoja, r.id),
              child: Text(r.nombre),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(hoja),
          child: const Text('Cancelar'),
        ),
      ),
    );
    if (destino == null || !context.mounted) return;

    final bien = await ref
        .read(bdProvider)
        .moverEjercicio(ejercicio.id, destino);
    if (!context.mounted) return;

    if (!bien) {
      ui.aviso(context, 'Esa rutina ya tiene «${ejercicio.nombre}»');
      return;
    }
    invalidarRutina(ref, idRutina);
    invalidarRutina(ref, destino);
  }

  /// La lista tal y como hay que pintarla, con el arrastre en curso aplicado.
  List<EjercicioConFicha> _ordenar(List<EjercicioConFicha> lista) {
    final orden = _ordenLocal;
    if (orden == null) return lista;
    final porId = {for (final e in lista) e.id: e};
    return [
      for (final id in orden) ?porId.remove(id),
      // Lo que llegue nuevo mientras se reordena va al final, no se pierde.
      ...porId.values,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final rutina = ref.watch(rutinaProvider(idRutina));
    final ejercicios = ref.watch(ejerciciosRutinaProvider(idRutina));
    final estadisticas = ref.watch(estadisticasRutinaProvider(idRutina));

    final nombre = rutina.value?.nombre ?? 'Rutina';

    if (rutina.hasValue && rutina.value == null) {
      return CupertinoPageScaffold(
        backgroundColor: context.fondo,
        navigationBar: ui.barra(context, titulo: 'Rutina'),
        child: const ui.EstadoVacio(
          icono: CupertinoIcons.exclamationmark_triangle,
          titulo: 'Esta rutina ya no existe',
        ),
      );
    }

    final lista = _ordenar(ejercicios.value ?? const <EjercicioConFicha>[]);

    return CupertinoPageScaffold(
      backgroundColor: context.fondo,
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: Text(nombre),
            previousPageTitle: 'Rutinas',
            backgroundColor: context.barra,
            trailing: _editando
                ? CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    onPressed: () => setState(() {
                      _editando = false;
                      _ordenLocal = null;
                    }),
                    child: Text(
                      'Listo',
                      style: ui.estilo(
                        context,
                        weight: t.semibold,
                        color: context.acento,
                      ),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        onPressed: () => _renombrar(context, ref, nombre),
                        child: const Icon(CupertinoIcons.pencil, size: 20),
                      ),
                      const SizedBox(width: t.m),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        onPressed: lista.length < 2
                            ? null
                            : () => setState(() => _editando = true),
                        child: const Icon(
                          CupertinoIcons.arrow_up_arrow_down,
                          size: 19,
                        ),
                      ),
                      const SizedBox(width: t.m),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        onPressed: () =>
                            abrirAnadirEjercicio(context, idRutina),
                        child: const Icon(CupertinoIcons.add, size: 22),
                      ),
                    ],
                  ),
          ),
          SliverToBoxAdapter(
            child: _Estadisticas(
              datos: estadisticas.value,
              nEjercicios: lista.length,
              onSesiones: () => abrirHistorial(context, idRutina),
            ),
          ),
          if (_editando)
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: t.l,
                vertical: t.s,
              ),
              // `ReorderableListView` es de Material; el equivalente de
              // `widgets.dart` da el mismo arrastre sin traerse su tema.
              sliver: SliverReorderableList(
                itemCount: lista.length,
                // `onReorderItem` en vez del `onReorder` obsoleto: ya trae el
                // índice de destino ajustado.
                onReorderItem: (desde, hasta) =>
                    _reordenar(lista, desde, hasta),
                itemBuilder: (context, indice) => _FilaOrden(
                  key: ValueKey(lista[indice].id),
                  ejercicio: lista[indice],
                  indice: indice,
                  onMover: () => _mover(context, lista[indice]),
                ),
              ),
            )
          else
            SliverToBoxAdapter(
              child: lista.isEmpty
                  ? ui.Grupo(
                      cabecera: 'Ejercicios',
                      pie:
                          'Esta rutina todavía está vacía. Añade ejercicios '
                          'para poder registrar un entrenamiento.',
                      filas: [
                        CupertinoListTile(
                          backgroundColor: context.tarjeta,
                          leading: Icon(
                            CupertinoIcons.add_circled,
                            color: context.acento,
                            size: 26,
                          ),
                          title: Text(
                            'Añadir ejercicios',
                            style: ui.estilo(context),
                          ),
                          subtitle: Text(
                            'Elige del catálogo de 1.324 ejercicios',
                            style: ui.estilo(
                              context,
                              size: t.footnote,
                              color: context.textoSec,
                            ),
                          ),
                          trailing: const CupertinoListTileChevron(),
                          onTap: () => abrirAnadirEjercicio(context, idRutina),
                        ),
                      ],
                    )
                  : ui.Grupo(
                      cabecera: 'Ejercicios',
                      filas: [
                        for (final e in lista)
                          ui.DeslizarParaBorrar(
                            llave: ValueKey(e.id),
                            onBorrar: () => _borrarEjercicio(ref, e.id),
                            titulo: '¿Quitar «${e.nombre}»?',
                            mensaje:
                                'Se eliminarán también las series '
                                'registradas de este ejercicio en esta rutina.',
                            child: CupertinoListTile(
                              backgroundColor: context.tarjeta,
                              leading: ui.Miniatura(formato.imagenEjercicio(e)),
                              leadingSize: 48,
                              title: Text(e.nombre, style: ui.estilo(context)),
                              subtitle: Text(
                                formato.subtituloEjercicio(e),
                                style: ui.estilo(
                                  context,
                                  size: t.footnote,
                                  color: context.textoSec,
                                ),
                              ),
                              trailing: e.ficha == null
                                  ? null
                                  : const CupertinoListTileChevron(),
                              onTap: e.ficha == null
                                  ? null
                                  : () => abrirFicha(context, e.ficha!.id),
                            ),
                          ),
                      ],
                    ),
            ),
          if (!_editando)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(t.l),
                child: ui.BotonPrincipal(
                  'Empezar entrenamiento',
                  icono: CupertinoIcons.play_fill,
                  onPressed: lista.isEmpty
                      ? null
                      : () => abrirEntrenar(context, idRutina),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: t.xxl)),
        ],
      ),
    );
  }
}

/// Fila del modo edición: asa de arrastre, nombre y mover a otra rutina.
class _FilaOrden extends StatelessWidget {
  const _FilaOrden({
    super.key,
    required this.ejercicio,
    required this.indice,
    required this.onMover,
  });

  final EjercicioConFicha ejercicio;
  final int indice;
  final VoidCallback onMover;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: t.s),
    child: Container(
      decoration: BoxDecoration(
        color: context.tarjeta,
        borderRadius: BorderRadius.circular(t.radioM),
      ),
      padding: const EdgeInsets.symmetric(horizontal: t.m, vertical: t.s),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: indice,
            child: Padding(
              padding: const EdgeInsets.only(right: t.m),
              child: Icon(
                CupertinoIcons.line_horizontal_3,
                size: 20,
                color: context.textoTer,
              ),
            ),
          ),
          ui.Miniatura(formato.imagenEjercicio(ejercicio), tamano: 36),
          const SizedBox(width: t.m),
          Expanded(
            child: Text(
              ejercicio.nombre,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: ui.estilo(context, size: t.subhead),
            ),
          ),
          CupertinoButton(
            onPressed: onMover,
            padding: const EdgeInsets.symmetric(horizontal: t.s),
            minimumSize: Size.zero,
            child: Icon(
              CupertinoIcons.arrow_right_arrow_left,
              size: 18,
              color: context.acento,
            ),
          ),
        ],
      ),
    ),
  );
}

class _Estadisticas extends StatelessWidget {
  const _Estadisticas({
    required this.datos,
    required this.nEjercicios,
    required this.onSesiones,
  });

  final EstadisticasRutina? datos;
  final int nEjercicios;

  /// «Sesiones» lleva al historial, que es desde donde se corrigen y borran.
  final VoidCallback onSesiones;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: t.l, vertical: t.s),
    padding: const EdgeInsets.symmetric(vertical: t.l),
    decoration: BoxDecoration(
      color: context.tarjeta,
      borderRadius: BorderRadius.circular(t.radioL),
    ),
    // Cada cifra en su tercio: «Sin entrenar» a tamaño de título no cabe en un
    // móvil estrecho si las columnas se dimensionan por su contenido.
    child: Row(
      children: [
        Expanded(child: _Dato('$nEjercicios', 'Ejercicios')),
        Expanded(
          child: _Dato(
            '${datos?.nEntrenamientos ?? 0}',
            'Sesiones',
            onTap: (datos?.nEntrenamientos ?? 0) == 0 ? null : onSesiones,
          ),
        ),
        Expanded(child: _Dato(formato.hace(datos?.ultima), 'Última')),
      ],
    ),
  );
}

class _Dato extends StatelessWidget {
  const _Dato(this.valor, this.etiqueta, {this.onTap});

  final String valor;
  final String etiqueta;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final columna = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          valor,
          textAlign: TextAlign.center,
          style: ui.estilo(
            context,
            size: t.title3,
            weight: t.semibold,
            color: onTap == null ? null : context.acento,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          etiqueta,
          textAlign: TextAlign.center,
          style: ui.estilo(context, size: t.caption, color: context.textoSec),
        ),
      ],
    );

    if (onTap == null) return columna;
    return CupertinoButton(
      onPressed: onTap,
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      child: columna,
    );
  }
}
