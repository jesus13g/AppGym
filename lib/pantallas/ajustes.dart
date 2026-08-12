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
import 'package:url_launcher/url_launcher.dart';

import '../datos/ajustes.dart';
import '../datos/media.dart' as media;
import '../datos/progresion.dart' show rangosRepeticiones;
import '../estado/providers.dart';
import '../l10n/textos.dart';
import '../tema/tokens.dart';
import '../tema/tokens.dart' as t;
import '../tema/ui.dart' as ui;
import 'copia_nube.dart';
import 'copia_seguridad.dart';
import 'cuenta.dart';

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
        titulo: context.t.ajustesTitulo,
        tituloAnterior: context.t.raizRutinas,
      ),
      child: SafeArea(
        child: ListView(
          children: [
            // La cuenta, arriba del todo y antes que cualquier preferencia,
            // como el Apple ID en los ajustes del sistema. Estaba debajo de los
            // cuatro grupos de preferencias y ahí no se encontraba: quien
            // instalaba el APK buscando dónde registrarse se rendía antes de
            // llegar. Es la única fila de esta pantalla que da acceso a algo en
            // vez de cambiar un número.
            const GrupoCuenta(),
            _unidades(context, ref, ajustes),
            _entrenamiento(context, ref, ajustes),
            _objetivos(context, ref, ajustes),
            _apariencia(context, ref, ajustes),
            // Los dos son vecinos temáticos de la cuenta —hablan de sacar los
            // datos del móvil—, pero hacen menos que ella: son copias, y esta
            // trae datos de vuelta. La copia automática va encima de «Datos»,
            // que es la misma copia hecha sola.
            const GrupoCopiaNube(),
            const GrupoDatos(),
            _acercaDe(context, ref),
            const SizedBox(height: t.xxl),
          ],
        ),
      ),
    );
  }

  // ── Unidades ───────────────────────────────────────────────────────────────

  Widget _unidades(BuildContext context, WidgetRef ref, Ajustes ajustes) =>
      ui.Grupo(
        cabecera: context.t.ajustesUnidades,
        pie: context.t.ajustesUnidadesPie,
        filas: [
          _segmentos<Unidad>(
            context,
            etiqueta: context.t.ajustesUnidadPeso,
            valor: ajustes.unidad,
            opciones: const {Unidad.kg: 'kg', Unidad.lb: 'lb'},
            onValor: (valor) => _fijar(ref, Claves.unidad, valor),
          ),
          _fila(
            context,
            titulo: context.t.ajustesPasoPeso,
            valor: context.t.ajustesPasoPesoValor(
              formatoDe(context, ref).numero(ajustes.pasoPeso),
              ajustes.unidad.sufijo,
            ),
            onTap: () => _elegir<double>(
              context,
              ref,
              clave: Claves.pasoPeso,
              titulo: context.t.ajustesPasoPeso,
              mensaje: context.t.ajustesPasoPesoMensaje,
              actual: ajustes.pasoPeso,
              opciones: [
                for (final paso in pasosPeso)
                  (
                    paso,
                    context.t.ajustesPasoPesoValor(
                      formatoDe(context, ref).numero(paso),
                      ajustes.unidad.sufijo,
                    ),
                  ),
              ],
            ),
          ),
        ],
      );

  // ── Entrenamiento ──────────────────────────────────────────────────────────

  Widget _entrenamiento(BuildContext context, WidgetRef ref, Ajustes ajustes) =>
      ui.Grupo(
        cabecera: context.t.ajustesEntrenamiento,
        pie: context.t.ajustesEntrenamientoPie,
        filas: [
          _fila(
            context,
            titulo: context.t.ajustesDescansoDefecto,
            valor: formatoDe(context, ref).descanso(ajustes.descansoSeg),
            onTap: () => _elegir<int>(
              context,
              ref,
              clave: Claves.descanso,
              titulo: context.t.ajustesDescansoDefecto,
              mensaje: context.t.ajustesDescansoMensaje,
              actual: ajustes.descansoSeg,
              opciones: [
                for (final segundos in descansos)
                  (segundos, formatoDe(context, ref).descanso(segundos)),
              ],
            ),
          ),
          _interruptor(
            context,
            titulo: context.t.ajustesSonido,
            valor: ajustes.sonidoDescanso,
            onValor: (valor) => _fijar(ref, Claves.sonidoDescanso, valor),
          ),
          _fila(
            context,
            titulo: context.t.ajustesSeriesDefecto,
            valor: '${ajustes.seriesPorDefecto}',
            onTap: () => _elegir<int>(
              context,
              ref,
              clave: Claves.series,
              titulo: context.t.ajustesSeriesDefecto,
              actual: ajustes.seriesPorDefecto,
              opciones: [
                for (var n = 1; n <= 10; n++) (n, context.t.comunSeries(n)),
              ],
            ),
          ),
          _fila(
            context,
            titulo: context.t.ajustesRepeticionesDefecto,
            valor: '${ajustes.repeticionesPorDefecto}',
            onTap: () => _elegir<int>(
              context,
              ref,
              clave: Claves.repeticiones,
              titulo: context.t.ajustesRepeticionesDefecto,
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
        etiqueta: context.t.ajustesEsfuerzo,
        valor: switch (ajustes) {
          _ when !ajustes.esfuerzoActivo => 'no',
          _ when ajustes.escala == EscalaEsfuerzo.rir => 'rir',
          _ => 'rpe',
        },
        opciones: {
          'no': context.t.ajustesEsfuerzoNo,
          'rpe': 'RPE',
          'rir': 'RIR',
        },
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
    cabecera: context.t.ajustesObjetivos,
    pie: context.t.ajustesObjetivosPie,
    filas: [
      _fila(
        context,
        titulo: context.t.ajustesSesionesSemana,
        valor: '${ajustes.sesionesPorSemana}',
        onTap: () => _elegir<int>(
          context,
          ref,
          clave: Claves.sesionesPorSemana,
          titulo: context.t.ajustesSesionesSemana,
          actual: ajustes.sesionesPorSemana,
          opciones: [
            for (var n = 1; n <= 7; n++) (n, context.t.comunSesiones(n)),
          ],
        ),
      ),
      _segmentos<Formula>(
        context,
        etiqueta: context.t.ajustesFormula,
        valor: ajustes.formula,
        opciones: const {Formula.epley: 'Epley', Formula.brzycki: 'Brzycki'},
        onValor: (valor) => _fijar(ref, Claves.formula1RM, valor),
      ),
      _interruptor(
        context,
        titulo: context.t.ajustesProgresionActiva,
        valor: ajustes.progresionActiva,
        onValor: (valor) => _fijar(ref, Claves.progresionActiva, valor),
      ),
      // Las dos filas siguientes no se esconden al apagar el interruptor: una
      // lista que cambia de alto bajo el dedo desorienta más de lo que ahorra.
      _fila(
        context,
        titulo: context.t.comunRangoRepeticiones,
        valor: context.t.comunRango(ajustes.repMinGlobal, ajustes.repMaxGlobal),
        onTap: () => _elegirRango(context, ref, ajustes),
      ),
      _segmentos<Perfil>(
        context,
        etiqueta: context.t.ajustesPerfil,
        valor: ajustes.perfilProgresion,
        opciones: {
          Perfil.conservador: context.t.ajustesPerfilConservador,
          Perfil.estandar: context.t.ajustesPerfilEstandar,
          Perfil.agresivo: context.t.ajustesPerfilAgresivo,
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
      titulo: context.t.comunRangoRepeticiones,
      etiquetaCancelar: context.t.comunCancelar,
      mensaje: context.t.ajustesRangoMensaje,
      actual: (ajustes.repMinGlobal, ajustes.repMaxGlobal),
      opciones: [
        for (final rango in rangosRepeticiones)
          (rango, context.t.comunRango(rango.$1, rango.$2)),
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
        cabecera: context.t.ajustesApariencia,
        pie: context.t.ajustesAparienciaPie,
        filas: [
          _segmentos<Tema>(
            context,
            etiqueta: context.t.ajustesTema,
            valor: ajustes.tema,
            opciones: {
              Tema.sistema: context.t.ajustesTemaSistema,
              Tema.claro: context.t.ajustesTemaClaro,
              Tema.oscuro: context.t.ajustesTemaOscuro,
            },
            onValor: (valor) => _fijar(ref, Claves.tema, valor),
          ),
          _fila(
            context,
            titulo: context.t.ajustesIdioma,
            valor: _idioma(context, ajustes.idioma),
            onTap: () => _elegir<Idioma>(
              context,
              ref,
              clave: Claves.idioma,
              titulo: context.t.ajustesIdioma,
              mensaje: context.t.ajustesIdiomaMensaje,
              actual: ajustes.idioma,
              opciones: [
                for (final idioma in Idioma.values)
                  (idioma, _idioma(context, idioma)),
              ],
            ),
          ),
        ],
      );

  /// Cada idioma se escribe **en el suyo**, que es la convención universal y
  /// evita el absurdo de buscar «Inglés» estando la app en inglés.
  String _idioma(BuildContext context, Idioma idioma) => switch (idioma) {
    Idioma.auto => context.t.ajustesIdiomaAuto,
    Idioma.es => 'Español',
    Idioma.en => 'English',
  };

  // ── Acerca de ──────────────────────────────────────────────────────────────

  Widget _acercaDe(BuildContext context, WidgetRef ref) {
    final catalogo = ref.watch(arranqueProvider).value?.length;

    return ui.Grupo(
      cabecera: context.t.ajustesAcercaDe,
      pie: context.t.ajustesLicencias(media.atribucion),
      filas: [
        _fila(context, titulo: context.t.ajustesVersion, valor: versionApp),
        _fila(
          context,
          titulo: context.t.ajustesCatalogo,
          valor: catalogo == null
              ? '…'
              : context.t.ajustesCatalogoValor(catalogo),
        ),
        // La política de privacidad se enlaza al repositorio en vez de
        // empaquetarla: hay que poder leerla también desde la pantalla de
        // consentimiento de Google, que solo admite una URL.
        _fila(
          context,
          titulo: context.t.ajustesPrivacidad,
          valor: '',
          onTap: () => launchUrl(
            Uri.parse(
              'https://github.com/jesus13g/AppGym/blob/main/docs/privacidad.md',
            ),
            mode: LaunchMode.externalApplication,
          ),
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
