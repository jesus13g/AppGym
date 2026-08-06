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

class PantallaRutina extends ConsumerWidget {
  const PantallaRutina({super.key, required this.idRutina});

  final int idRutina;

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    final lista = ejercicios.value ?? const <EjercicioConFicha>[];

    return CupertinoPageScaffold(
      backgroundColor: context.fondo,
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: Text(nombre),
            previousPageTitle: 'Rutinas',
            backgroundColor: context.barra,
            trailing: Row(
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
                  onPressed: () => abrirAnadirEjercicio(context, idRutina),
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
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _Dato('$nEjercicios', 'Ejercicios'),
        _Dato(
          '${datos?.nEntrenamientos ?? 0}',
          'Sesiones',
          onTap: (datos?.nEntrenamientos ?? 0) == 0 ? null : onSesiones,
        ),
        _Dato(formato.hace(datos?.ultima), 'Última'),
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
