/// Opciones de un ejercicio dentro de una rutina: descanso y progresión.
///
/// El descanso propio ya se elegía antes de esto, desde una pulsación larga
/// sobre el temporizador de la tarjeta; lo que no había era ningún sitio donde
/// poner **lo demás** que es propio del ejercicio y no de la sesión. Con la
/// progresión configurable por ejercicio hacían falta cuatro filas más, así que
/// el selector suelto pasa a ser la primera fila de una hoja.
///
/// Vive aparte porque la abren la pantalla de entrenar y el detalle de la
/// rutina, y meterla en cualquiera de las dos obligaría a la otra a importarla
/// entera.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/ajustes.dart' show descansos, pasosPeso;
import '../datos/bd.dart';
import '../datos/formato.dart';
import '../datos/progresion.dart' as progresion;
import '../estado/providers.dart';
import '../tema/tokens.dart';
import '../tema/tokens.dart' as t;
import '../tema/ui.dart' as ui;

/// Abre las opciones de un ejercicio. Devuelve `true` si algo cambió.
Future<bool> abrirOpcionesEjercicio(
  BuildContext context,
  int idRutina,
  int idEjercicio,
) async {
  final cambiado = await showCupertinoModalPopup<bool>(
    context: context,
    builder: (_) => _HojaOpciones(idRutina: idRutina, idEjercicio: idEjercicio),
  );
  return cambiado ?? false;
}

class _HojaOpciones extends ConsumerStatefulWidget {
  const _HojaOpciones({required this.idRutina, required this.idEjercicio});

  final int idRutina;
  final int idEjercicio;

  @override
  ConsumerState<_HojaOpciones> createState() => _HojaOpcionesState();
}

class _HojaOpcionesState extends ConsumerState<_HojaOpciones> {
  /// Si se ha tocado algo: es lo que decide si la pantalla de origen recarga.
  bool _cambiado = false;

  Future<void> _escribir(Future<void> Function(AppBD bd) accion) async {
    await accion(ref.read(bdProvider));
    if (!mounted) return;
    invalidarRutina(ref, widget.idRutina);
    setState(() => _cambiado = true);
  }

  @override
  Widget build(BuildContext context) {
    final ejercicio = ref.watch(ejercicioProvider(widget.idEjercicio)).value;
    final f = formatoDe(context, ref);
    final historial = ref
        .watch(
          resumenSesionesEjercicioProvider((
            idRutina: widget.idRutina,
            idEjercicio: widget.idEjercicio,
          )),
        )
        .value;

    if (ejercicio == null) {
      return Container(
        height: 200,
        color: context.fondo,
        child: const ui.Cargando(),
      );
    }

    final fila = ejercicio.ejercicio;
    final config = progresion.ConfiguracionProgresion.resolver(
      ejercicio,
      f.ajustes,
    );
    final observado = historial == null
        ? null
        : progresion.rangoObservado(historial, config);

    return Container(
      decoration: BoxDecoration(
        color: context.fondo,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(t.radioL),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(t.l, t.l, t.l, 0),
              child: Text(
                ejercicio.nombre,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: ui.estilo(context, size: t.headline, weight: t.semibold),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ui.Grupo(
                    filas: [
                      _fila(
                        titulo: 'Descanso',
                        valor: f.descanso(
                          fila.descansoSeg ?? f.ajustes.descansoSeg,
                        ),
                        propio: fila.descansoSeg != null,
                        onTap: () => _elegirDescanso(fila, f),
                      ),
                    ],
                  ),
                  ui.Grupo(
                    cabecera: 'Progresión',
                    pie: _pie(config, observado),
                    filas: [
                      _fila(
                        titulo: 'Estrategia',
                        valor: _estrategia(config.estrategia),
                        propio: fila.estrategia != null,
                        onTap: _elegirEstrategia,
                      ),
                      _fila(
                        titulo: 'Rango de repeticiones',
                        valor: '${config.repMin} – ${config.repMax}',
                        propio: fila.repMin != null || fila.repMax != null,
                        onTap: () => _elegirRango(config, observado),
                      ),
                      _fila(
                        titulo: 'Escalón de peso',
                        valor: f.peso(config.incrementoKg),
                        propio: fila.incrementoKg != null,
                        onTap: () => _elegirEscalon(fila, f),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(t.l, t.s, t.l, t.l),
                    child: ui.BotonPrincipal(
                      'Listo',
                      onPressed: () => Navigator.pop(context, _cambiado),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// El pie explica de dónde sale el rango cuando el historial dice otra cosa.
  String? _pie(
    progresion.ConfiguracionProgresion config,
    (int, int)? observado,
  ) {
    if (config.estrategia == progresion.Estrategia.desactivada) {
      return 'Este ejercicio no recibe sugerencias.';
    }
    if (observado != null) {
      return 'En las últimas sesiones has hecho más bien '
          '${observado.$1}–${observado.$2} repeticiones; toca el rango para '
          'ajustarlo.';
    }
    return null;
  }

  /// Fila con el valor **efectivo** a la derecha y su procedencia debajo.
  ///
  /// El valor va siempre corto —«8 – 12», «2,5 kg»— y de dónde sale se dice en
  /// el subtítulo. Meterlo todo en la derecha, como «Como el global (8 – 12)»,
  /// desbordaba la fila a 375 px; hay un test que lo fija.
  Widget _fila({
    required String titulo,
    required String valor,
    required bool propio,
    required VoidCallback onTap,
  }) => CupertinoListTile(
    backgroundColor: context.tarjeta,
    title: Text(titulo, style: ui.estilo(context)),
    subtitle: propio
        ? null
        : Text(
            'Como el global',
            style: ui.estilo(
              context,
              size: t.footnote,
              color: context.textoSec,
            ),
          ),
    additionalInfo: Text(
      valor,
      style: ui.estilo(
        context,
        color: propio ? context.acento : context.textoSec,
      ),
    ),
    trailing: const CupertinoListTileChevron(),
    onTap: onTap,
  );

  static String _estrategia(progresion.Estrategia estrategia) =>
      switch (estrategia) {
        progresion.Estrategia.desactivada => 'Desactivada',
        progresion.Estrategia.dobleProgresion => 'Doble progresión',
        progresion.Estrategia.soloRepeticiones => 'Solo repeticiones',
      };

  Future<void> _elegirDescanso(Ejercicio fila, Formato f) async {
    final elegido = await ui.elegirEnHoja<int?>(
      context,
      titulo: 'Descanso',
      mensaje:
          'Los descansos de una sentadilla y de un curl no son iguales; aquí '
          'se separa uno del otro.',
      actual: fila.descansoSeg,
      opciones: [
        (null, 'Como el global (${f.descanso(f.ajustes.descansoSeg)})'),
        for (final segundos in descansos) (segundos, f.descanso(segundos)),
      ],
    );
    if (elegido == null) return;
    await _escribir((bd) => bd.fijarDescansoEjercicio(fila.id, elegido.$1));
  }

  Future<void> _elegirEstrategia() async {
    final elegida = await ui.elegirEnHoja<int?>(
      context,
      titulo: 'Estrategia',
      mensaje:
          'La doble progresión sube repeticiones dentro del rango y, al '
          'completarlo, el peso. En peso corporal no hay peso que subir.',
      opciones: [
        (null, 'Como el global'),
        for (final e in progresion.Estrategia.values) (e.index, _estrategia(e)),
      ],
    );
    if (elegida == null) return;
    await _escribir(
      (bd) => bd.fijarProgresionEjercicio(
        widget.idEjercicio,
        estrategia: Value(elegida.$1),
      ),
    );
  }

  /// El rango observado va **el primero** y anotado, que es la propuesta.
  Future<void> _elegirRango(
    progresion.ConfiguracionProgresion config,
    (int, int)? observado,
  ) async {
    final opciones = <((int, int)?, String)>[
      if (observado != null)
        (observado, '${observado.$1} – ${observado.$2}  (lo que haces)'),
      (null, 'Como el global'),
      for (final rango in progresion.rangosRepeticiones)
        if (rango != observado) (rango, '${rango.$1} – ${rango.$2}'),
    ];

    final elegido = await ui.elegirEnHoja<(int, int)?>(
      context,
      titulo: 'Rango de repeticiones',
      mensaje:
          '8–12 va bien en accesorios y se queda corto en un peso muerto '
          'pesado o en gemelos.',
      opciones: opciones,
    );
    if (elegido == null) return;

    await _escribir(
      (bd) => bd.fijarProgresionEjercicio(
        widget.idEjercicio,
        repMin: Value(elegido.$1?.$1),
        repMax: Value(elegido.$1?.$2),
      ),
    );
  }

  Future<void> _elegirEscalon(Ejercicio fila, Formato f) async {
    // Los pasos están en la unidad activa y la columna en kilos, así que se
    // ofrecen los mismos que el selector de peso y se guardan convertidos.
    final elegido = await ui.elegirEnHoja<double?>(
      context,
      titulo: 'Escalón de peso',
      mensaje: 'Cuánto sube la sugerencia al completar el rango.',
      opciones: [
        (
          null,
          'Como el global (${f.peso(f.ajustes.aKilos(f.ajustes.pasoPeso))})',
        ),
        for (final paso in pasosPeso)
          (f.ajustes.aKilos(paso), f.peso(f.ajustes.aKilos(paso))),
      ],
    );
    if (elegido == null) return;
    await _escribir(
      (bd) =>
          bd.fijarProgresionEjercicio(fila.id, incrementoKg: Value(elegido.$1)),
    );
  }
}
