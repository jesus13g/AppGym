/// La pantalla de «Última vez»: qué subió, qué bajó y qué no se pudo resolver.
///
/// Es donde acaban los avisos de K5. **Un diálogo modal de resolución de
/// conflictos es exactamente lo que no hay que construir**: interrumpe, obliga a
/// decidir sobre algo que no se recuerda y se dispara siempre en el peor
/// momento. Aquí se leen cuando el usuario quiere, con su fecha.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/sincro/motor.dart';
import '../estado/providers.dart';
import '../l10n/textos.dart';
import '../tema/tokens.dart';
import '../tema/tokens.dart' as t;
import '../tema/ui.dart' as ui;

Future<void> abrirSincroDetalle(BuildContext context) => Navigator.of(context)
    .push(CupertinoPageRoute<void>(builder: (_) => const PantallaSincroDetalle()));

/// La frase de cada aviso.
///
/// Un `switch` exhaustivo y no un mapa: el motivo viaja como enumerado y no como
/// texto —igual que en `progresion.dart`—, así que añadir uno rompe la
/// compilación justo aquí, que es donde falta la traducción.
String fraseAviso(BuildContext context, WidgetRef ref, AvisoSincro aviso) =>
    switch (aviso.motivo) {
      MotivoAviso.rutinaRenombrada => context.t.sincroAvisoRenombrada(
        aviso.detalle,
      ),
      MotivoAviso.sinPadre => context.t.sincroAvisoSinPadre(aviso.detalle),
      // El detalle es la fecha de la sesión, en ISO. `tryParse` porque una
      // contabilidad malformada no puede impedir que la pantalla se pinte.
      MotivoAviso.seriesPerdidas => context.t.sincroAvisoSeriesPerdidas(
        switch (DateTime.tryParse(aviso.detalle)) {
          final fecha? => formatoDe(context, ref).fechaCorta(fecha),
          null => aviso.detalle,
        },
      ),
    };

class PantallaSincroDetalle extends ConsumerWidget {
  const PantallaSincroDetalle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vista = ref.watch(sincronizacionProvider);
    final formato = formatoDe(context, ref);
    final estado = vista.estado;

    return CupertinoPageScaffold(
      backgroundColor: context.fondo,
      navigationBar: ui.barra(
        context,
        titulo: context.t.sincroDetalleTitulo,
        tituloAnterior: context.t.ajustesTitulo,
      ),
      child: SafeArea(
        child: ListView(
          children: [
            ui.Grupo(
              cabecera: context.t.sincroUltimaPasada,
              pie: estado.ultimoError != null
                  ? context.t.sincroUltimoError(estado.ultimoError!)
                  : null,
              filas: [
                _fila(
                  context,
                  titulo: context.t.cuentaUltimaVez,
                  valor: estado.ultimaSincro == null
                      ? context.t.cuentaNunca
                      : formato.desde(estado.ultimaSincro!),
                ),
                _fila(
                  context,
                  titulo: context.t.sincroSubidas,
                  valor: context.t.sincroFilas(estado.subidas),
                ),
                _fila(
                  context,
                  titulo: context.t.sincroBajadas,
                  valor: context.t.sincroFilas(estado.bajadas),
                ),
              ],
            ),
            if (vista.avisos.isEmpty)
              ui.Grupo(
                cabecera: context.t.sincroAvisos,
                filas: [
                  CupertinoListTile(
                    backgroundColor: context.tarjeta,
                    title: Text(
                      context.t.sincroSinAvisos,
                      style: ui.estilo(context, color: context.textoSec),
                    ),
                  ),
                ],
              )
            else
              ui.Grupo(
                cabecera: context.t.sincroAvisos,
                pie: context.t.sincroAvisosPie,
                filas: [
                  for (final aviso in vista.avisos)
                    CupertinoListTile(
                      backgroundColor: context.tarjeta,
                      title: Text(
                        fraseAviso(context, ref, aviso),
                        style: ui.estilo(context),
                      ),
                      subtitle: Text(
                        formato.fechaCorta(aviso.cuando),
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
        ),
      ),
    );
  }

  Widget _fila(
    BuildContext context, {
    required String titulo,
    required String valor,
  }) => CupertinoListTile(
    backgroundColor: context.tarjeta,
    title: Text(titulo, style: ui.estilo(context)),
    additionalInfo: Flexible(
      child: Text(
        valor,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: ui.estilo(context, color: context.textoSec),
      ),
    ),
  );
}
