/// Detalle de una sesión: lo que se hizo aquel día, en solo lectura.
///
/// Desde aquí se corrige (reabre el registro con los datos cargados) o se
/// elimina.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/bd.dart';
import '../datos/formato.dart' as formato;
import '../estado/providers.dart';
import '../tema/tokens.dart';
import '../tema/tokens.dart' as t;
import '../tema/ui.dart' as ui;
import 'entrenar.dart';

Future<void> abrirSesion(BuildContext context, int idEntrenamiento) =>
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => PantallaSesion(idEntrenamiento: idEntrenamiento),
      ),
    );

class PantallaSesion extends ConsumerWidget {
  const PantallaSesion({super.key, required this.idEntrenamiento});

  final int idEntrenamiento;

  Future<void> _eliminar(
    BuildContext context,
    WidgetRef ref,
    SesionCompleta sesion,
  ) async {
    final confirmado = await ui.dialogoConfirmar(
      context,
      titulo: '¿Eliminar la sesión?',
      mensaje:
          'Se borrarán sus series y dejará de contar en el calendario y en '
          'las estadísticas. No se puede deshacer.',
    );
    if (!confirmado || !context.mounted) return;

    await ref.read(bdProvider).borrarEntrenamiento(sesion.id);
    invalidarEntrenamientos(ref, sesion.idRutina);
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(sesionProvider(idEntrenamiento));

    return CupertinoPageScaffold(
      backgroundColor: context.fondo,
      navigationBar: ui.barra(
        context,
        titulo: 'Sesión',
        tituloAnterior: 'Sesiones',
        derecha: switch (sesion.value) {
          final datos? => CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            onPressed: () =>
                abrirEditarEntrenamiento(context, datos.idRutina, datos.id),
            child: const Text('Editar'),
          ),
          _ => null,
        },
      ),
      child: SafeArea(
        child: sesion.when(
          loading: () => const ui.Cargando(),
          error: (e, _) => ui.EstadoVacio(
            icono: CupertinoIcons.exclamationmark_triangle,
            titulo: 'No se pudo cargar la sesión',
            subtitulo: '$e',
          ),
          data: (datos) => datos == null
              ? const ui.EstadoVacio(
                  icono: CupertinoIcons.exclamationmark_triangle,
                  titulo: 'Esta sesión ya no existe',
                )
              : _Contenido(
                  sesion: datos,
                  onEliminar: () => _eliminar(context, ref, datos),
                ),
        ),
      ),
    );
  }
}

class _Contenido extends StatelessWidget {
  const _Contenido({required this.sesion, required this.onEliminar});

  final SesionCompleta sesion;
  final VoidCallback onEliminar;

  @override
  Widget build(BuildContext context) {
    final nSeries = sesion.ejercicios.fold<int>(
      0,
      (suma, e) => suma + e.series.length,
    );

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: t.l,
            right: t.l,
            top: t.m,
            bottom: t.s,
          ),
          child: Text(
            formato.fechaLarga(sesion.fecha),
            style: ui.estilo(context, size: t.title2, weight: t.bold),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: t.l, vertical: t.s),
          padding: const EdgeInsets.symmetric(vertical: t.l),
          decoration: BoxDecoration(
            color: context.tarjeta,
            borderRadius: BorderRadius.circular(t.radioL),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _Dato('${sesion.ejercicios.length}', 'Ejercicios'),
              _Dato('$nSeries', 'Series'),
              _Dato('${formato.numero(sesion.volumen)} kg', 'Volumen'),
            ],
          ),
        ),
        for (final ejercicio in sesion.ejercicios)
          ui.Grupo(
            cabecera: ejercicio.ejercicio.nombre,
            filas: [
              for (final (indice, serie) in ejercicio.series.indexed)
                CupertinoListTile(
                  backgroundColor: context.tarjeta,
                  leading: serie.calentamiento
                      ? Icon(
                          CupertinoIcons.flame,
                          size: 18,
                          color: context.textoTer,
                        )
                      : Text(
                          '${indice + 1}',
                          style: ui.estilo(
                            context,
                            size: t.subhead,
                            color: context.textoSec,
                          ),
                        ),
                  leadingSize: 22,
                  title: Text(
                    '${serie.repeticiones} repeticiones',
                    style: ui.estilo(context),
                  ),
                  additionalInfo: Text(
                    '${formato.numero(serie.peso)} kg',
                    style: ui.estilo(context, color: context.textoSec),
                  ),
                ),
            ],
          ),
        Padding(
          padding: const EdgeInsets.all(t.l),
          child: ui.BotonPrincipal(
            'Eliminar sesión',
            icono: CupertinoIcons.delete,
            color: context.destructivo,
            onPressed: onEliminar,
          ),
        ),
        const SizedBox(height: t.xxl),
      ],
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato(this.valor, this.etiqueta);

  final String valor;
  final String etiqueta;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        valor,
        textAlign: TextAlign.center,
        style: ui.estilo(context, size: t.title3, weight: t.semibold),
      ),
      const SizedBox(height: 2),
      Text(
        etiqueta,
        textAlign: TextAlign.center,
        style: ui.estilo(context, size: t.caption, color: context.textoSec),
      ),
    ],
  );
}
