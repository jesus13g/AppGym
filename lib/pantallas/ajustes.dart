/// Ajustes de la app.
///
/// De momento solo el esfuerzo percibido, que es lo que A5 necesita poder
/// activar. La pantalla de ajustes completa —unidades, copia de seguridad,
/// descanso— es B9; esto es su primer trozo, no un sustituto.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/bd.dart';
import '../estado/providers.dart';
import '../tema/tokens.dart';
import '../tema/tokens.dart' as t;
import '../tema/ui.dart' as ui;

Future<void> abrirAjustes(BuildContext context) => Navigator.of(
  context,
).push(CupertinoPageRoute<void>(builder: (_) => const PantallaAjustes()));

class PantallaAjustes extends ConsumerWidget {
  const PantallaAjustes({super.key});

  Future<void> _fijar(WidgetRef ref, String clave, String valor) async {
    await ref.read(bdProvider).fijarAjuste(clave, valor);
    invalidarAjustes(ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ajustes = ref.watch(ajustesProvider).value ?? const Ajustes();

    return CupertinoPageScaffold(
      backgroundColor: context.fondo,
      navigationBar: ui.barra(
        context,
        titulo: 'Ajustes',
        tituloAnterior: 'Rutinas',
      ),
      child: SafeArea(
        child: ListView(
          children: [
            ui.Grupo(
              cabecera: 'Registro',
              pie:
                  'El esfuerzo percibido de cada serie. Desactivado, el '
                  'registro queda igual que si no existiera.',
              filas: [
                CupertinoListTile(
                  backgroundColor: context.tarjeta,
                  title: Text('Anotar el esfuerzo', style: ui.estilo(context)),
                  trailing: CupertinoSwitch(
                    value: ajustes.esfuerzoActivo,
                    onChanged: (valor) => _fijar(
                      ref,
                      AppBD.claveEsfuerzoActivo,
                      valor ? '1' : '0',
                    ),
                  ),
                ),
              ],
            ),
            if (ajustes.esfuerzoActivo)
              ui.Grupo(
                cabecera: 'Escala',
                pie:
                    'RPE va de 6 a 10, donde 10 es el fallo. RIR cuenta las '
                    'repeticiones que quedaban en recámara, así que 0 es el '
                    'fallo. Se guarda siempre lo mismo: cambiar de escala solo '
                    'cambia cómo se lee.',
                filas: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: t.l,
                      vertical: t.m,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: CupertinoSlidingSegmentedControl<EscalaEsfuerzo>(
                        groupValue: ajustes.escala,
                        onValueChanged: (valor) => _fijar(
                          ref,
                          AppBD.claveEsfuerzoEscala,
                          valor == EscalaEsfuerzo.rir ? 'rir' : 'rpe',
                        ),
                        children: const {
                          EscalaEsfuerzo.rpe: Padding(
                            padding: EdgeInsets.symmetric(vertical: t.xs),
                            child: Text('RPE'),
                          ),
                          EscalaEsfuerzo.rir: Padding(
                            padding: EdgeInsets.symmetric(vertical: t.xs),
                            child: Text('RIR'),
                          ),
                        },
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
}
