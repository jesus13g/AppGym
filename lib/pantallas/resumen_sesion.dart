/// Resumen de cierre de un entrenamiento recién terminado.
///
/// Es la respuesta a «¿ha servido de algo lo de hoy?»: volumen, series,
/// duración y los ejercicios en los que se ha batido el peso máximo. Sale una
/// sola vez, justo al terminar la sesión viva; para repasarla más tarde está el
/// detalle de sesión del historial.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/bd.dart';
import '../datos/formato.dart' as formato;
import '../estado/providers.dart';
import '../tema/tokens.dart';
import '../tema/tokens.dart' as t;
import '../tema/ui.dart' as ui;

Future<void> abrirResumenSesion(BuildContext context, int idEntrenamiento) =>
    Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => PantallaResumenSesion(idEntrenamiento: idEntrenamiento),
      ),
    );

class PantallaResumenSesion extends ConsumerWidget {
  const PantallaResumenSesion({super.key, required this.idEntrenamiento});

  final int idEntrenamiento;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(sesionProvider(idEntrenamiento));
    final records = ref.watch(recordsSesionProvider(idEntrenamiento));
    final ajustes = ref.watch(ajustesProvider).value ?? const Ajustes();

    return CupertinoPageScaffold(
      backgroundColor: context.fondo,
      navigationBar: ui.barra(
        context,
        titulo: 'Entrenamiento terminado',
        derecha: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Listo',
            style: ui.estilo(
              context,
              weight: t.semibold,
              color: context.acento,
            ),
          ),
        ),
      ),
      child: SafeArea(
        child: switch (sesion.value) {
          null => const ui.Cargando(),
          final datos => _Contenido(
            sesion: datos,
            records: records.value ?? const [],
            ajustes: ajustes,
          ),
        },
      ),
    );
  }
}

class _Contenido extends StatelessWidget {
  const _Contenido({
    required this.sesion,
    required this.records,
    required this.ajustes,
  });

  final SesionCompleta sesion;
  final List<RecordSesion> records;
  final Ajustes ajustes;

  @override
  Widget build(BuildContext context) {
    final nSeries = sesion.ejercicios.fold<int>(
      0,
      (suma, e) => suma + e.series.length,
    );
    final duracion = sesion.entrenamiento.duracionSeg;

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: t.l, vertical: t.xl),
          child: Column(
            children: [
              Icon(
                CupertinoIcons.checkmark_seal_fill,
                size: 56,
                color: context.exito,
              ),
              const SizedBox(height: t.m),
              Text(
                '¡Sesión guardada!',
                style: ui.estilo(context, size: t.title2, weight: t.bold),
              ),
              const SizedBox(height: t.xs),
              Text(
                formato.fechaLarga(sesion.fecha),
                style: ui.estilo(
                  context,
                  size: t.subhead,
                  color: context.textoSec,
                ),
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: t.l),
          padding: const EdgeInsets.symmetric(vertical: t.l),
          decoration: BoxDecoration(
            color: context.tarjeta,
            borderRadius: BorderRadius.circular(t.radioL),
          ),
          child: Row(
            children: [
              Expanded(child: _Dato('$nSeries', 'Series')),
              Expanded(
                child: _Dato(formato.peso(sesion.volumen, ajustes), 'Volumen'),
              ),
              Expanded(
                child: _Dato(
                  duracion == null ? '—' : formato.duracion(duracion),
                  'Duración',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: t.s),
        if (records.isNotEmpty)
          ui.Grupo(
            cabecera: 'Récords',
            pie:
                'Comparado con lo que habías levantado antes de hoy en esta '
                'misma rutina.',
            filas: [
              for (final r in records)
                CupertinoListTile(
                  backgroundColor: context.tarjeta,
                  leading: Icon(
                    CupertinoIcons.flame_fill,
                    size: 20,
                    color: context.acento,
                  ),
                  leadingSize: 24,
                  title: Text(r.nombre, style: ui.estilo(context)),
                  subtitle: Text(
                    switch (r.pesoAnterior) {
                      null => 'Primera vez que lo registras',
                      final anterior =>
                        'Antes: ${formato.peso(anterior, ajustes)}',
                    },
                    style: ui.estilo(
                      context,
                      size: t.footnote,
                      color: context.textoSec,
                    ),
                  ),
                  additionalInfo: Text(
                    formato.peso(r.pesoMaximo, ajustes),
                    style: ui.estilo(context, weight: t.semibold),
                  ),
                ),
            ],
          ),
        ui.Grupo(
          cabecera: 'Lo que has hecho',
          filas: [
            for (final e in sesion.ejercicios)
              CupertinoListTile(
                backgroundColor: context.tarjeta,
                leading: ui.Miniatura(
                  formato.imagenEjercicio(e.ejercicio),
                  tamano: 40,
                ),
                leadingSize: 40,
                title: Text(e.ejercicio.nombre, style: ui.estilo(context)),
                subtitle: Text(
                  '${formato.plural(e.series.length, 'serie', 'series')} · '
                  '${formato.peso(e.volumen, ajustes)}',
                  style: ui.estilo(
                    context,
                    size: t.footnote,
                    color: context.textoSec,
                  ),
                ),
              ),
          ],
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
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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
