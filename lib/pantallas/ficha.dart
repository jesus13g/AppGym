/// Ficha de un ejercicio del catálogo: animación, músculos e instrucciones.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/bd.dart';
import '../datos/formato.dart' as formato;
import '../datos/i18n.dart' as i18n;
import '../datos/media.dart' as media;
import '../estado/providers.dart';
import '../tema/tokens.dart';
import '../tema/tokens.dart' as t;
import '../tema/ui.dart' as ui;
import 'anadir_a_rutina.dart';

Future<void> abrirFicha(BuildContext context, String idCatalogo) =>
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => PantallaFicha(idCatalogo: idCatalogo),
      ),
    );

class PantallaFicha extends ConsumerStatefulWidget {
  const PantallaFicha({super.key, required this.idCatalogo});

  final String idCatalogo;

  @override
  ConsumerState<PantallaFicha> createState() => _PantallaFichaState();
}

class _PantallaFichaState extends ConsumerState<PantallaFicha> {
  @override
  void initState() {
    super.initState();
    // Abrir la ficha es lo que cuenta como «visto»: es el gesto de interesarse
    // por un ejercicio, y lo que alimenta la lista del estado inicial.
    _anotarVisto();
  }

  Future<void> _anotarVisto() async {
    await ref.read(bdProvider).registrarVisto(widget.idCatalogo);
    if (mounted) ref.invalidate(vistosProvider);
  }

  @override
  Widget build(BuildContext context) {
    final ficha = ref.watch(fichaProvider(widget.idCatalogo));

    return CupertinoPageScaffold(
      backgroundColor: context.fondo,
      navigationBar: ui.barra(
        context,
        titulo: ficha.value?.nombre ?? 'Ejercicio',
        derecha: BotonFavorito(idCatalogo: widget.idCatalogo),
      ),
      child: ficha.when(
        loading: () => const ui.Cargando(),
        error: (e, _) => ui.EstadoVacio(
          icono: CupertinoIcons.exclamationmark_triangle,
          titulo: 'No se pudo cargar el ejercicio',
          subtitulo: '$e',
        ),
        data: (datos) => datos == null
            ? const ui.EstadoVacio(
                icono: CupertinoIcons.exclamationmark_triangle,
                titulo: 'Ejercicio no encontrado',
              )
            : _Contenido(ficha: datos),
      ),
    );
  }
}

class _Contenido extends ConsumerWidget {
  const _Contenido({required this.ficha});

  final FichaCatalogo ficha;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final secundarios = i18n.musculos(
      formato.listaJson(ficha.secondaryMuscles),
    );
    final pasos = formato.listaJson(ficha.instrucciones);
    final animacion = media.resolver(ficha.gif);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.only(top: t.m),
        children: [
          // El GIF se pinta sobre blanco porque el original tiene fondo blanco:
          // en tema oscuro, sin esto, queda un recuadro sucio.
          Container(
            height: 240,
            margin: const EdgeInsets.symmetric(horizontal: t.l),
            decoration: BoxDecoration(
              color: CupertinoColors.white,
              borderRadius: BorderRadius.circular(t.radioL),
            ),
            clipBehavior: Clip.antiAlias,
            child: animacion == null
                ? Icon(CupertinoIcons.photo, size: 44, color: context.textoTer)
                : Image(
                    image: animacion,
                    fit: BoxFit.contain,
                    errorBuilder: (context, _, _) => Icon(
                      CupertinoIcons.photo,
                      size: 44,
                      color: context.textoTer,
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: t.l, right: t.l, top: t.l),
            child: Text(
              ficha.nombre,
              style: ui.estilo(context, size: t.title2, weight: t.bold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: t.l, vertical: t.m),
            child: Wrap(
              spacing: t.s,
              runSpacing: t.s,
              children: [
                ui.Pildora(
                  i18n.musculo(ficha.target),
                  color: CupertinoColors.white,
                  relleno: context.acento,
                ),
                ui.Pildora(i18n.equipamiento(ficha.equipment)),
                ui.Pildora(i18n.zonaCuerpo(ficha.bodyPart)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: t.l),
            child: ui.BotonPrincipal(
              'Añadir a una rutina',
              icono: CupertinoIcons.add,
              onPressed: () => anadirARutina(context, ref, ficha),
            ),
          ),
          _EnRutinas(idCatalogo: ficha.id),
          const SizedBox(height: t.s),
          ui.Grupo(
            cabecera: 'Detalles',
            filas: [
              _detalle(
                context,
                'Músculo principal',
                i18n.musculo(ficha.target),
              ),
              _detalle(
                context,
                'Grupo muscular',
                i18n.musculo(ficha.muscleGroup),
              ),
              _detalle(
                context,
                'Equipamiento',
                i18n.equipamiento(ficha.equipment),
              ),
              if (secundarios.isNotEmpty)
                CupertinoListTile(
                  backgroundColor: context.tarjeta,
                  title: Text(
                    'Músculos secundarios',
                    style: ui.estilo(context),
                  ),
                  subtitle: Text(
                    secundarios.join(', '),
                    style: ui.estilo(
                      context,
                      size: t.footnote,
                      color: context.textoSec,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: t.l),
          ui.Grupo(
            cabecera: 'Cómo se hace',
            filas: pasos.isEmpty
                ? [
                    CupertinoListTile(
                      backgroundColor: context.tarjeta,
                      title: Text(
                        'Sin instrucciones disponibles',
                        style: ui.estilo(context),
                      ),
                    ),
                  ]
                : [
                    for (final (indice, paso) in pasos.indexed)
                      _Paso(numero: indice + 1, texto: paso),
                  ],
          ),
          // Requisito de licencia de Gym visual, no decoración.
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: t.xl,
              vertical: t.xl,
            ),
            child: Text(
              'Animación e imagen: ${media.atribucion}',
              textAlign: TextAlign.center,
              style: ui.estilo(
                context,
                size: t.caption,
                color: context.textoTer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detalle(BuildContext context, String etiqueta, String valor) =>
      CupertinoListTile(
        backgroundColor: context.tarjeta,
        title: Text(etiqueta, style: ui.estilo(context)),
        additionalInfo: Text(
          valor,
          style: ui.estilo(context, color: context.textoSec),
        ),
      );
}

/// «Ya está en: Empuje · Tirón», debajo del botón de añadir.
///
/// Responde antes de pulsar la pregunta que llevaba a pulsar: si ya lo tienes
/// puesto en algún sitio y dónde.
class _EnRutinas extends ConsumerWidget {
  const _EnRutinas({required this.idCatalogo});

  final String idCatalogo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rutinas =
        ref.watch(rutinasQueContienenProvider(idCatalogo)).value ?? const [];
    if (rutinas.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(left: t.l, right: t.l, top: t.s),
      child: Text(
        'Ya está en: ${rutinas.map((r) => r.nombre).join(' · ')}',
        textAlign: TextAlign.center,
        style: ui.estilo(context, size: t.footnote, color: context.textoSec),
      ),
    );
  }
}

class _Paso extends StatelessWidget {
  const _Paso({required this.numero, required this.texto});

  final int numero;
  final String texto;

  @override
  Widget build(BuildContext context) => Container(
    color: context.tarjeta,
    padding: const EdgeInsets.symmetric(horizontal: t.l, vertical: t.m),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.acento,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$numero',
            style: ui.estilo(
              context,
              size: t.caption,
              weight: t.semibold,
              color: CupertinoColors.white,
            ),
          ),
        ),
        const SizedBox(width: t.m),
        Expanded(
          child: Text(texto, style: ui.estilo(context, size: t.subhead)),
        ),
      ],
    ),
  );
}
