/// Detalle de una rutina: sus ejercicios y el acceso a registrar entrenamiento.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/bd.dart';
import '../datos/formato.dart';
import '../estado/providers.dart';
import '../l10n/textos.dart';
import '../tema/tokens.dart';
import '../tema/tokens.dart' as t;
import '../tema/ui.dart' as ui;
import 'catalogo.dart';
import 'entrenar.dart';
import 'ficha.dart';
import 'historial.dart';
import 'opciones_ejercicio.dart';

Future<void> abrirRutina(BuildContext context, int idRutina) =>
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        title: context.t.raizRutinas,
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
      titulo: context.t.rutinaRenombrarTitulo,
      marcador: context.t.rutinasNombreMarcador,
      valor: actual,
      etiquetaAceptar: context.t.comunGuardar,
      etiquetaCancelar: context.t.comunCancelar,
    );
    if (nombre == null || !context.mounted) return;

    final bien = await ref.read(bdProvider).renombrarRutina(idRutina, nombre);
    if (!context.mounted) return;

    if (!bien) {
      ui.aviso(context, context.t.rutinaNombreRepetido(nombre));
      return;
    }
    invalidarRutina(ref, idRutina);
  }

  /// Menú de la rutina: renombrar y duplicar.
  Future<void> _menu(BuildContext context, String nombre) async {
    final accion = await showCupertinoModalPopup<String>(
      context: context,
      builder: (hoja) => CupertinoActionSheet(
        title: Text(nombre),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(hoja, 'renombrar'),
            child: Text(hoja.t.rutinaRenombrar),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(hoja, 'duplicar'),
            child: Text(hoja.t.rutinaDuplicar),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(hoja),
          child: Text(hoja.t.comunCancelar),
        ),
      ),
    );
    if (accion == null || !context.mounted) return;

    if (accion == 'renombrar') {
      await _renombrar(context, ref, nombre);
    } else {
      await _duplicar(context, nombre);
    }
  }

  /// Copia la rutina con sus ejercicios, sin el histórico.
  Future<void> _duplicar(BuildContext context, String nombre) async {
    final propuesto = await ui.dialogoTexto(
      context,
      titulo: context.t.rutinaDuplicar,
      marcador: context.t.rutinaCopiaMarcador,
      mensaje: context.t.rutinaCopiaMensaje,
      valor: context.t.rutinaCopiaSufijo(nombre),
      etiquetaAceptar: context.t.rutinaDuplicarBoton,
      etiquetaCancelar: context.t.comunCancelar,
    );
    if (propuesto == null || !context.mounted) return;

    final copia = await ref
        .read(bdProvider)
        .duplicarRutina(idRutina, nuevoNombre: propuesto);
    if (!context.mounted) return;

    if (copia == null) {
      ui.aviso(context, context.t.rutinaNombreRepetido(propuesto));
      return;
    }
    invalidarRutinas(ref);
    await abrirRutina(context, copia);
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
      ui.aviso(context, context.t.rutinaSinDestino);
      return;
    }

    final destino = await showCupertinoModalPopup<int>(
      context: context,
      builder: (hoja) => CupertinoActionSheet(
        title: Text(hoja.t.rutinaMoverTitulo(ejercicio.nombre)),
        message: Text(hoja.t.rutinaMoverMensaje),
        actions: [
          for (final r in destinos)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(hoja, r.id),
              child: Text(r.nombre),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(hoja),
          child: Text(hoja.t.comunCancelar),
        ),
      ),
    );
    if (destino == null || !context.mounted) return;

    final bien = await ref
        .read(bdProvider)
        .moverEjercicio(ejercicio.id, destino);
    if (!context.mounted) return;

    if (!bien) {
      ui.aviso(context, context.t.rutinaMoverRepetido(ejercicio.nombre));
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
    final f = formatoDe(context, ref);

    final nombre = rutina.value?.nombre ?? context.t.rutinaTitulo;

    if (rutina.hasValue && rutina.value == null) {
      return CupertinoPageScaffold(
        backgroundColor: context.fondo,
        navigationBar: ui.barra(context, titulo: context.t.rutinaTitulo),
        child: ui.EstadoVacio(
          icono: CupertinoIcons.exclamationmark_triangle,
          titulo: context.t.resultadosRutinaBorrada,
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
            previousPageTitle: context.t.raizRutinas,
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
                      context.t.comunListo,
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
                        onPressed: () => _menu(context, nombre),
                        child: const Icon(CupertinoIcons.ellipsis, size: 20),
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
              formato: f,
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
                      cabecera: context.t.comunEjerciciosCabecera,
                      pie: context.t.rutinaVaciaDetalle,
                      filas: [
                        CupertinoListTile(
                          backgroundColor: context.tarjeta,
                          leading: Icon(
                            CupertinoIcons.add_circled,
                            color: context.acento,
                            size: 26,
                          ),
                          title: Text(
                            context.t.rutinaAnadirEjercicios,
                            style: ui.estilo(context),
                          ),
                          subtitle: Text(
                            context.t.rutinaAnadirDetalle,
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
                      cabecera: context.t.comunEjerciciosCabecera,
                      filas: [
                        for (final e in lista)
                          ui.DeslizarParaBorrar(
                            llave: ValueKey(e.id),
                            onBorrar: () => _borrarEjercicio(ref, e.id),
                            titulo: context.t.rutinaQuitarTitulo(e.nombre),
                            mensaje: context.t.rutinaQuitarMensaje,
                            etiquetaEliminar: context.t.comunEliminar,
                            etiquetaCancelar: context.t.comunCancelar,
                            // Mantener pulsado abre las opciones propias del
                            // ejercicio —descanso y progresión—, que es donde
                            // se configuran sin estar entrenando.
                            child: GestureDetector(
                              onLongPress: () => abrirOpcionesEjercicio(
                                context,
                                idRutina,
                                e.id,
                              ),
                              child: CupertinoListTile(
                                backgroundColor: context.tarjeta,
                                leading: ui.Miniatura(imagenEjercicio(e)),
                                leadingSize: 48,
                                title: Text(
                                  e.nombre,
                                  style: ui.estilo(context),
                                ),
                                subtitle: Text(
                                  f.subtituloEjercicio(e),
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
                          ),
                      ],
                    ),
            ),
          if (!_editando)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(t.l),
                child: Column(
                  children: [
                    ui.BotonPrincipal(
                      context.t.rutinaEmpezar,
                      icono: CupertinoIcons.play_fill,
                      onPressed: lista.isEmpty
                          ? null
                          : () => abrirEntrenar(context, idRutina),
                    ),
                    // El formulario de siempre, para el día que uno se acuerda
                    // de la app al día siguiente. Va debajo y sin relleno
                    // porque es la salida secundaria, no la principal.
                    CupertinoButton(
                      onPressed: lista.isEmpty
                          ? null
                          : () => abrirRegistrarAnterior(context, idRutina),
                      child: Text(
                        context.t.rutinaRegistrarAnterior,
                        style: ui.estilo(
                          context,
                          size: t.subhead,
                          color: context.acento,
                        ),
                      ),
                    ),
                  ],
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
          ui.Miniatura(imagenEjercicio(ejercicio), tamano: 36),
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
    required this.formato,
    required this.nEjercicios,
    required this.onSesiones,
  });

  final EstadisticasRutina? datos;
  final Formato formato;
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
        Expanded(
          child: _Dato('$nEjercicios', context.t.comunEjerciciosCabecera),
        ),
        Expanded(
          child: _Dato(
            '${datos?.nEntrenamientos ?? 0}',
            context.t.rutinaSesiones,
            onTap: (datos?.nEntrenamientos ?? 0) == 0 ? null : onSesiones,
          ),
        ),
        Expanded(
          child: _Dato(formato.hace(datos?.ultima), context.t.rutinaUltima),
        ),
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
