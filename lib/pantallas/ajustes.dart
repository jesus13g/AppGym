/// Ajustes de la app.
///
/// Hasta ahora había valores razonables pero clavados en el código: el paso del
/// peso a 2,5, el `4 × 10 × 20 kg` de partida y el kilogramo escrito a mano en
/// media docena de pantallas. Aquí se tocan todos, y también lo que necesitan
/// el temporizador de descanso, el esfuerzo percibido y la copia de seguridad.
///
/// Se llega por el engranaje de la pestaña **Rutinas**, no por una cuarta
/// pestaña: tres es el equilibrio del `CupertinoTabScaffold` y esto no es una
/// zona de uso frecuente.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/ajustes.dart';
import '../datos/media.dart' as media;
import '../datos/progresion.dart' show rangosRepeticiones;
import '../estado/providers.dart';
import '../l10n/textos.dart';
import '../tema/tokens.dart';
import '../tema/tokens.dart' as t;
import '../tema/ui.dart' as ui;
import 'copia_seguridad.dart';

/// Versión con la que se compiló, que CI pasa con `--dart-define`.
///
/// En una compilación local no hay ninguna, y decirlo es más honesto que
/// enseñar el `1.0.0+1` de `pubspec.yaml`, que CI siempre pisa.
const versionApp = String.fromEnvironment('VERSION', defaultValue: 'local');

Future<void> abrirAjustes(BuildContext context) => Navigator.of(
  context,
).push(CupertinoPageRoute<void>(builder: (_) => const PantallaAjustes()));

class PantallaAjustes extends ConsumerWidget {
  const PantallaAjustes({super.key});

  Future<void> _fijar(WidgetRef ref, String clave, Object valor) async {
    await ref.read(bdProvider).fijarAjuste(clave, Ajustes.texto(valor));
    invalidarAjustes(ref);
  }

  /// Pide un valor en una hoja y lo guarda si se elige.
  Future<void> _elegir<T extends Object>(
    BuildContext context,
    WidgetRef ref, {
    required String clave,
    required String titulo,
    required List<(T, String)> opciones,
    required T actual,
    String? mensaje,
  }) async {
    final elegido = await ui.elegirEnHoja<T>(
      context,
      titulo: titulo,
      mensaje: mensaje,
      opciones: opciones,
      actual: actual,
      etiquetaCancelar: context.t.comunCancelar,
    );
    if (elegido == null) return;
    await _fijar(ref, clave, elegido.$1);
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
            _unidades(context, ref, ajustes),
            _entrenamiento(context, ref, ajustes),
            _objetivos(context, ref, ajustes),
            _apariencia(context, ref, ajustes),
            const GrupoDatos(),
            _acercaDe(context, ref),
            const SizedBox(height: t.xxl),
          ],
        ),
      ),
    );
  }

  // ── Unidades ───────────────────────────────────────────────────────────────

  Widget _unidades(
    BuildContext context,
    WidgetRef ref,
    Ajustes ajustes,
  ) => ui.Grupo(
    cabecera: 'Unidades',
    pie:
        'El peso se guarda siempre en kilogramos: cambiar a libras solo '
        'cambia cómo se lee, y volver deja los valores originales intactos.',
    filas: [
      _segmentos<Unidad>(
        context,
        etiqueta: 'Unidad de peso',
        valor: ajustes.unidad,
        opciones: const {Unidad.kg: 'kg', Unidad.lb: 'lb'},
        onValor: (valor) => _fijar(ref, Claves.unidad, valor),
      ),
      _fila(
        context,
        titulo: 'Paso del peso',
        valor:
            '${formatoDe(context, ref).numero(ajustes.pasoPeso)} '
            '${ajustes.unidad.sufijo}',
        onTap: () => _elegir<double>(
          context,
          ref,
          clave: Claves.pasoPeso,
          titulo: 'Paso del peso',
          mensaje: 'Cuánto sube o baja cada toque en el registro.',
          actual: ajustes.pasoPeso,
          opciones: [
            for (final paso in pasosPeso)
              (
                paso,
                '${formatoDe(context, ref).numero(paso)} '
                    '${ajustes.unidad.sufijo}',
              ),
          ],
        ),
      ),
    ],
  );

  // ── Entrenamiento ──────────────────────────────────────────────────────────

  Widget _entrenamiento(BuildContext context, WidgetRef ref, Ajustes ajustes) =>
      ui.Grupo(
        cabecera: 'Entrenamiento',
        pie:
            'Las series y repeticiones por defecto solo se usan la primera vez '
            'que entrenas un ejercicio; a partir de ahí se precarga lo que '
            'hiciste la última vez.',
        filas: [
          _fila(
            context,
            titulo: 'Descanso por defecto',
            valor: formatoDe(context, ref).descanso(ajustes.descansoSeg),
            onTap: () => _elegir<int>(
              context,
              ref,
              clave: Claves.descanso,
              titulo: 'Descanso por defecto',
              mensaje:
                  'Cada ejercicio puede llevar el suyo, desde su tarjeta en el '
                  'registro.',
              actual: ajustes.descansoSeg,
              opciones: [
                for (final segundos in descansos)
                  (segundos, formatoDe(context, ref).descanso(segundos)),
              ],
            ),
          ),
          _interruptor(
            context,
            titulo: 'Sonido al terminar',
            valor: ajustes.sonidoDescanso,
            onValor: (valor) => _fijar(ref, Claves.sonidoDescanso, valor),
          ),
          _fila(
            context,
            titulo: 'Series por defecto',
            valor: '${ajustes.seriesPorDefecto}',
            onTap: () => _elegir<int>(
              context,
              ref,
              clave: Claves.series,
              titulo: 'Series por defecto',
              actual: ajustes.seriesPorDefecto,
              opciones: [
                for (var n = 1; n <= 10; n++) (n, context.t.comunSeries(n)),
              ],
            ),
          ),
          _fila(
            context,
            titulo: 'Repeticiones por defecto',
            valor: '${ajustes.repeticionesPorDefecto}',
            onTap: () => _elegir<int>(
              context,
              ref,
              clave: Claves.repeticiones,
              titulo: 'Repeticiones por defecto',
              actual: ajustes.repeticionesPorDefecto,
              opciones: [
                for (var n = 1; n <= 30; n++)
                  (n, context.t.comunRepeticiones(n)),
              ],
            ),
          ),
          _esfuerzo(context, ref, ajustes),
        ],
      );

  /// El esfuerzo percibido en una sola fila de tres opciones.
  ///
  /// Se guarda en dos claves —si está activo y en qué escala— porque apagarlo y
  /// volver a encenderlo debe recordar la escala que usabas.
  Widget _esfuerzo(BuildContext context, WidgetRef ref, Ajustes ajustes) =>
      _segmentos<String>(
        context,
        etiqueta: 'Anotar el esfuerzo',
        valor: switch (ajustes) {
          _ when !ajustes.esfuerzoActivo => 'no',
          _ when ajustes.escala == EscalaEsfuerzo.rir => 'rir',
          _ => 'rpe',
        },
        opciones: const {'no': 'No', 'rpe': 'RPE', 'rir': 'RIR'},
        onValor: (valor) async {
          await ref.read(bdProvider).fijarAjustes({
            Claves.esfuerzoActivo: valor == 'no' ? '0' : '1',
            if (valor != 'no') Claves.esfuerzoEscala: valor,
          });
          invalidarAjustes(ref);
        },
      );

  // ── Objetivos ──────────────────────────────────────────────────────────────

  Widget _objetivos(
    BuildContext context,
    WidgetRef ref,
    Ajustes ajustes,
  ) => ui.Grupo(
    cabecera: 'Objetivos',
    pie:
        'El objetivo semanal es contra lo que se mide la racha en Progreso. '
        'Brzycki estima algo más bajo que Epley en series largas; con pocas '
        'repeticiones apenas se distinguen.',
    filas: [
      _fila(
        context,
        titulo: 'Sesiones por semana',
        valor: '${ajustes.sesionesPorSemana}',
        onTap: () => _elegir<int>(
          context,
          ref,
          clave: Claves.sesionesPorSemana,
          titulo: 'Sesiones por semana',
          actual: ajustes.sesionesPorSemana,
          opciones: [
            for (var n = 1; n <= 7; n++) (n, context.t.comunSesiones(n)),
          ],
        ),
      ),
      _segmentos<Formula>(
        context,
        etiqueta: 'Fórmula de 1RM',
        valor: ajustes.formula,
        opciones: const {Formula.epley: 'Epley', Formula.brzycki: 'Brzycki'},
        onValor: (valor) => _fijar(ref, Claves.formula1RM, valor),
      ),
      _interruptor(
        context,
        titulo: 'Sugerir progresiones',
        valor: ajustes.progresionActiva,
        onValor: (valor) => _fijar(ref, Claves.progresionActiva, valor),
      ),
      // Las dos filas siguientes no se esconden al apagar el interruptor: una
      // lista que cambia de alto bajo el dedo desorienta más de lo que ahorra.
      _fila(
        context,
        titulo: 'Rango de repeticiones',
        valor: '${ajustes.repMinGlobal} – ${ajustes.repMaxGlobal}',
        onTap: () => _elegirRango(context, ref, ajustes),
      ),
      _segmentos<Perfil>(
        context,
        etiqueta: 'Perfil',
        valor: ajustes.perfilProgresion,
        opciones: const {
          Perfil.conservador: 'Conservador',
          Perfil.estandar: 'Estándar',
          Perfil.agresivo: 'Agresivo',
        },
        onValor: (valor) => _fijar(ref, Claves.perfilProgresion, valor),
      ),
    ],
  );

  /// El rango son dos claves, así que no cabe en `_elegir`.
  Future<void> _elegirRango(
    BuildContext context,
    WidgetRef ref,
    Ajustes ajustes,
  ) async {
    final elegido = await ui.elegirEnHoja<(int, int)>(
      context,
      titulo: 'Rango de repeticiones',
      etiquetaCancelar: context.t.comunCancelar,
      mensaje:
          'Dentro de este rango se sube de repeticiones; al completarlo, de '
          'peso. Cada ejercicio puede llevar el suyo.',
      actual: (ajustes.repMinGlobal, ajustes.repMaxGlobal),
      opciones: [
        for (final rango in rangosRepeticiones)
          (rango, '${rango.$1} – ${rango.$2}'),
      ],
    );
    if (elegido == null) return;

    await ref.read(bdProvider).fijarAjustes({
      Claves.repMin: Ajustes.texto(elegido.$1.$1),
      Claves.repMax: Ajustes.texto(elegido.$1.$2),
    });
    invalidarAjustes(ref);
  }

  // ── Apariencia ─────────────────────────────────────────────────────────────

  Widget _apariencia(BuildContext context, WidgetRef ref, Ajustes ajustes) =>
      ui.Grupo(
        cabecera: 'Apariencia',
        pie: 'Con «Sistema», la app sigue el modo claro u oscuro del móvil.',
        filas: [
          _segmentos<Tema>(
            context,
            etiqueta: 'Tema',
            valor: ajustes.tema,
            opciones: const {
              Tema.sistema: 'Sistema',
              Tema.claro: 'Claro',
              Tema.oscuro: 'Oscuro',
            },
            onValor: (valor) => _fijar(ref, Claves.tema, valor),
          ),
        ],
      );

  // ── Acerca de ──────────────────────────────────────────────────────────────

  Widget _acercaDe(BuildContext context, WidgetRef ref) {
    final catalogo = ref.watch(arranqueProvider).value?.length;

    return ui.Grupo(
      cabecera: 'Acerca de',
      pie:
          'Las imágenes y animaciones son ${media.atribucion} y se usan a '
          '180×180 con la atribución visible, según sus condiciones de uso. '
          'Los datos del catálogo vienen de hasaneyldrm/exercises-dataset, con '
          'licencia MIT.',
      filas: [
        _fila(context, titulo: 'Versión', valor: versionApp),
        _fila(
          context,
          titulo: 'Catálogo',
          valor: catalogo == null ? '…' : '$catalogo ejercicios',
        ),
      ],
    );
  }

  // ── Piezas comunes ─────────────────────────────────────────────────────────

  Widget _fila(
    BuildContext context, {
    required String titulo,
    required String valor,
    VoidCallback? onTap,
  }) => CupertinoListTile(
    backgroundColor: context.tarjeta,
    title: Text(titulo, style: ui.estilo(context)),
    additionalInfo: Text(
      valor,
      style: ui.estilo(context, color: context.textoSec),
    ),
    trailing: onTap == null ? null : const CupertinoListTileChevron(),
    onTap: onTap,
  );

  Widget _interruptor(
    BuildContext context, {
    required String titulo,
    required bool valor,
    required ValueChanged<bool> onValor,
  }) => CupertinoListTile(
    backgroundColor: context.tarjeta,
    title: Text(titulo, style: ui.estilo(context)),
    trailing: CupertinoSwitch(value: valor, onChanged: onValor),
  );

  /// Fila con su control segmentado debajo.
  ///
  /// A lo ancho de un móvil, tres segmentos y una etiqueta no caben en la misma
  /// línea sin apretar el texto, así que la etiqueta va encima.
  Widget _segmentos<T extends Object>(
    BuildContext context, {
    required String etiqueta,
    required T valor,
    required Map<T, String> opciones,
    required ValueChanged<T> onValor,
  }) => Container(
    color: context.tarjeta,
    padding: const EdgeInsets.symmetric(horizontal: t.l, vertical: t.m),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiqueta, style: ui.estilo(context)),
        const SizedBox(height: t.s),
        SizedBox(
          width: double.infinity,
          child: CupertinoSlidingSegmentedControl<T>(
            groupValue: valor,
            onValueChanged: (nuevo) {
              if (nuevo != null) onValor(nuevo);
            },
            children: {
              for (final entrada in opciones.entries)
                entrada.key: Padding(
                  padding: const EdgeInsets.symmetric(vertical: t.xs),
                  child: Text(
                    entrada.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            },
          ),
        ),
      ],
    ),
  );
}
