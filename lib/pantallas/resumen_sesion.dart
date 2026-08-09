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
import '../datos/formato.dart';
import '../estado/providers.dart';
import '../l10n/textos.dart';
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
    final f = formatoDe(context, ref);

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
            formato: f,
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
    required this.formato,
  });

  final SesionCompleta sesion;
  final List<RecordSesion> records;
  final Formato formato;

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
              Expanded(child: _Dato(formato.peso(sesion.volumen), 'Volumen')),
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
                    _detalle(r, formato),
                    style: ui.estilo(
                      context,
                      size: t.footnote,
                      color: context.textoSec,
                    ),
                  ),
                  additionalInfo: Text(
                    _cifra(r, formato),
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
                leading: ui.Miniatura(imagenEjercicio(e.ejercicio), tamano: 40),
                leadingSize: 40,
                title: Text(e.ejercicio.nombre, style: ui.estilo(context)),
                subtitle: Text(
                  '${context.t.comunSeries(e.series.length)} · '
                  '${formato.peso(e.volumen)}',
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

/// Qué récord se ha batido y contra qué, para el subtítulo de la fila.
///
/// Se baten los tres a la vez con más frecuencia de la que parece —subir el
/// peso suele subir también el 1RM y el volumen—, así que se enumeran en vez de
/// quedarse solo con el primero.
String _detalle(RecordSesion record, Formato formato) {
  String contra(double? anterior) =>
      anterior == null ? 'primera vez' : 'antes ${formato.peso(anterior)}';

  final partes = [
    for (final tipo in record.batidos)
      switch (tipo) {
        TipoRecord.peso => 'Peso (${contra(record.pesoAnterior)})',
        TipoRecord.unoRm => '1RM (${contra(record.unoRmAnterior)})',
        TipoRecord.volumen => 'Volumen (${contra(record.volumenAnterior)})',
      },
  ];
  return partes.join(' · ');
}

/// La cifra que se enseña a la derecha: la del récord más significativo de los
/// batidos, en el orden peso → 1RM → volumen.
String _cifra(RecordSesion record, Formato formato) {
  final batidos = record.batidos;
  if (batidos.contains(TipoRecord.peso)) {
    return formato.peso(record.pesoMaximo);
  }
  if (batidos.contains(TipoRecord.unoRm) && record.mejor1RM != null) {
    return formato.peso(record.mejor1RM!);
  }
  return formato.peso(record.volumen);
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
