/// El mapa muscular: qué se está trabajando y qué se está descuidando.
///
/// No monta scaffold propio porque no es una pantalla suelta: se incrusta en la
/// sección «Cuerpo» de Progreso, encima de las medidas del cuerpo.
///
/// El modelo es **pseudo-3D**: dos siluetas planas con sombreado, no una malla.
/// La sensación de volumen la da la luz, no la geometría, y a cambio el toque
/// lo resuelve `Path.contains` en vez de rayos contra triángulos. La rotación se
/// sustituye por un conmutador Frente / Espalda, que en un móvil se maneja
/// mejor que una rotación libre.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/bd.dart';
import '../datos/formato.dart' as formato;
import '../datos/geometria.dart';
import '../datos/media.dart' as media;
import '../datos/musculos.dart';
import '../datos/reloj.dart' as reloj;
import '../estado/providers.dart';
import '../tema/tokens.dart';
import '../tema/tokens.dart' as t;
import '../tema/ui.dart' as ui;
import 'anadir_a_rutina.dart';
import 'catalogo.dart';
import 'ficha.dart';
import 'sesion.dart';

/// Periodos que se pueden mirar, en días.
const periodos = <int>[7, 30, 90];

/// Clave del lienzo del modelo.
///
/// Existe para que los tests puedan medirlo y tocar un músculo concreto: sin
/// ella, el único camino a la hoja sería la lista de abandonados, que por
/// definición no contiene ningún músculo entrenado.
const claveLienzo = ValueKey<String>('mapaMuscularLienzo');

/// Cuánto se perdona el dedo al tocar, en píxeles de pantalla.
///
/// Las regiones pequeñas (el tibial, los romboides) miden unos pocos píxeles en
/// un móvil, y sin esto solo se acertarían de casualidad.
const toleranciaToque = 12.0;

/// El color de una región según su nivel de trabajo.
///
/// Es público para poder probarlo: montado en los dos brillos tiene que dar
/// colores distintos, que es lo que demuestra que los semánticos de Cupertino
/// se están resolviendo contra el contexto y no usando en crudo.
Color colorNivel(BuildContext context, int nivel) => nivel <= 0
    ? context.relleno
    : context.acento.withValues(alpha: opacidadesNivel[nivel]);

/// El mapa muscular con su leyenda y la lista de músculos abandonados.
class MapaMuscular extends ConsumerStatefulWidget {
  const MapaMuscular({super.key});

  @override
  ConsumerState<MapaMuscular> createState() => _MapaMuscularState();
}

class _MapaMuscularState extends ConsumerState<MapaMuscular> {
  Vista _cara = Vista.frente;
  int _dias = 30;

  /// La región cuya hoja está abierta, que se resalta mientras tanto.
  Region? _resaltada;

  @override
  Widget build(BuildContext context) {
    final modelo = ref.watch(modeloCuerpoProvider).value;
    final trabajos = ref.watch(trabajoMuscularProvider).value ?? const [];
    final hoy = reloj.ahora();
    final desde = hoy.subtract(Duration(days: _dias));

    // Todo lo que sigue son funciones puras sobre la lista ya cargada: cambiar
    // de 7 a 90 días recolorea sin volver a consultar la base.
    final trabajo = trabajoPorRegion(trabajos, desde: desde);
    final niveles = nivelesPorRegion(trabajo);
    final fuera = sinRepresentar(trabajos, desde: desde);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(t.l, t.s, t.l, 0),
          child: CupertinoSlidingSegmentedControl<Vista>(
            groupValue: _cara,
            onValueChanged: (valor) =>
                setState(() => _cara = valor ?? Vista.frente),
            children: const {
              Vista.frente: Padding(
                padding: EdgeInsets.symmetric(vertical: t.xs),
                child: Text('Frente'),
              ),
              Vista.espalda: Padding(
                padding: EdgeInsets.symmetric(vertical: t.xs),
                child: Text('Espalda'),
              ),
            },
          ),
        ),
        // El periodo va en píldoras y no en un segundo segmentado: apilar dos
        // barras iguales debajo de la de Progreso son tres filas de cromo antes
        // de ver el cuerpo.
        Padding(
          padding: const EdgeInsets.fromLTRB(t.l, t.s, t.l, t.s),
          child: Row(
            children: [
              for (final dias in periodos) ...[
                GestureDetector(
                  onTap: () => setState(() => _dias = dias),
                  child: ui.Pildora(
                    '$dias días',
                    color: _dias == dias
                        ? CupertinoColors.white
                        : context.texto,
                    relleno: _dias == dias ? context.acento : context.relleno,
                  ),
                ),
                const SizedBox(width: t.s),
              ],
            ],
          ),
        ),
        // Mientras el dibujo carga se deja el hueco y ya está, sin indicador:
        // son 32 KB que se resuelven en un fotograma, y un indicador de
        // actividad anima para siempre, así que dejaría sin asentar a todo
        // `pumpAndSettle` que pasara por la pestaña de Progreso.
        if (modelo == null)
          const SizedBox(height: 320)
        else
          _Modelo(
            modelo: modelo,
            cara: _cara,
            niveles: niveles,
            resaltada: _resaltada,
            onRegion: _abrir,
          ),
        const _Leyenda(),
        if (fuera.hayAlgo)
          Padding(
            padding: const EdgeInsets.fromLTRB(t.l, t.s, t.l, 0),
            child: Text(
              _avisoDeFuera(fuera),
              style: ui.estilo(
                context,
                size: t.footnote,
                color: context.textoSec,
              ),
            ),
          ),
        if (trabajos.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: t.l),
            child: ui.EstadoVacio(
              icono: CupertinoIcons.person_crop_square,
              titulo: 'Aún no hay nada que colorear',
              subtitulo:
                  'Cuando registres entrenamientos, el modelo se irá tiñendo '
                  'según lo que trabaje cada músculo. Mientras tanto, toca '
                  'cualquier músculo para ver sus ejercicios.',
            ),
          )
        else
          _MenosTrabajados(trabajos: trabajos, hoy: hoy, onRegion: _abrir),
      ],
    );
  }

  String _avisoDeFuera(SinRepresentar fuera) {
    final partes = <String>[
      if (fuera.personalizados > 0)
        '${formato.plural(fuera.personalizados, 'ejercicio personalizado', 'ejercicios personalizados')} sin músculo asignado',
      if (fuera.cardio > 0)
        '${formato.plural(fuera.cardio, 'ejercicio', 'ejercicios')} de cardio',
    ];
    return '${partes.join(' y ')}: no se reparten por el modelo.';
  }

  Future<void> _abrir(Region region) async {
    setState(() => _resaltada = region);
    await abrirHojaRegion(context, region, dias: _dias);
    if (mounted) setState(() => _resaltada = null);
  }
}

// ── El modelo dibujado ───────────────────────────────────────────────────────

class _Modelo extends StatelessWidget {
  const _Modelo({
    required this.modelo,
    required this.cara,
    required this.niveles,
    required this.resaltada,
    required this.onRegion,
  });

  final MapaCuerpo<Region> modelo;
  final Vista cara;
  final Map<Region, int> niveles;
  final Region? resaltada;
  final ValueChanged<Region> onRegion;

  @override
  Widget build(BuildContext context) {
    final datos = modelo.caras[cara.name];
    if (datos == null) return const SizedBox.shrink();

    final colores = (
      silueta: context.tarjeta,
      contorno: context.separador,
      acento: context.acento,
      n0: colorNivel(context, 0),
      n1: colorNivel(context, 1),
      n2: colorNivel(context, 2),
      n3: colorNivel(context, 3),
      n4: colorNivel(context, 4),
    );

    // Se manda con el alto y no con un `AspectRatio`: el lienzo es 1000×2000, y
    // a 375 px de ancho la figura mediría casi 700 px de alto, más de lo que
    // cabe en la pantalla de un móvil.
    final alto = (MediaQuery.sizeOf(context).height * 0.46).clamp(300.0, 520.0);

    return SizedBox(
      height: alto,
      child: LayoutBuilder(
        builder: (context, restricciones) {
          final encaje = Encaje.contener(
            destino: restricciones.biggest,
            lienzo: modelo.lienzo,
          );
          return GestureDetector(
            key: claveLienzo,
            behavior: HitTestBehavior.opaque,
            onTapUp: (detalle) {
              final region = figuraEn(
                datos.regiones,
                encaje.aLienzo(detalle.localPosition),
                // La tolerancia va en unidades del lienzo, no de pantalla: son
                // cinco veces más, y pasarla en píxeles la dejaría en nada.
                tolerancia: encaje.aLienzoDistancia(toleranciaToque),
              );
              // Tocar fuera de toda región no hace nada.
              if (region != null) onRegion(region);
            },
            child: CustomPaint(
              size: Size.infinite,
              painter: _PintorCuerpo(
                cara: datos,
                lienzo: modelo.lienzo,
                niveles: niveles,
                resaltada: resaltada,
                colores: colores,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Los colores del mapa, ya resueltos contra el contexto.
///
/// Es un registro y no una clase ni una lista **a propósito**: trae igualdad
/// estructural gratis, que es lo que hace que `shouldRepaint` distinga de
/// verdad un cambio de tema. Con una lista se compararía por identidad.
typedef _Colores = ({
  Color silueta,
  Color contorno,
  Color acento,
  Color n0,
  Color n1,
  Color n2,
  Color n3,
  Color n4,
});

class _PintorCuerpo extends CustomPainter {
  const _PintorCuerpo({
    required this.cara,
    required this.lienzo,
    required this.niveles,
    required this.resaltada,
    required this.colores,
  });

  final CaraCuerpo<Region> cara;
  final Size lienzo;
  final Map<Region, int> niveles;
  final Region? resaltada;
  final _Colores colores;

  Color _color(int nivel) => switch (nivel) {
    0 => colores.n0,
    1 => colores.n1,
    2 => colores.n2,
    3 => colores.n3,
    _ => colores.n4,
  };

  @override
  void paint(Canvas canvas, Size size) {
    final encaje = Encaje.contener(destino: size, lienzo: lienzo);
    canvas
      ..save()
      ..translate(encaje.desplazamiento.dx, encaje.desplazamiento.dy)
      ..scale(encaje.escala);

    final relleno = Paint()..style = PaintingStyle.fill;
    // El canvas va escalado, así que los grosores se dan en unidades del
    // lienzo: dividir por la escala es lo que deja el trazo igual de fino
    // sea cual sea el tamaño en pantalla.
    final borde = Paint()..style = PaintingStyle.stroke;
    double px(double grosor) => grosor / encaje.escala;

    canvas.drawPath(cara.silueta.completo, relleno..color = colores.silueta);
    canvas.drawPath(
      cara.silueta.completo,
      borde
        ..color = colores.contorno
        ..strokeWidth = px(1.4),
    );

    for (final MapEntry(key: region, value: figura) in cara.regiones.entries) {
      canvas.drawPath(
        figura.completo,
        relleno..color = _color(niveles[region] ?? 0),
      );
    }

    // La luz y la sombra van encima del color base y a baja opacidad: es lo que
    // da el volumen sin geometría de verdad.
    for (final (figuras, color) in [
      (cara.luces, const Color(0x22FFFFFF)),
      (cara.sombras, const Color(0x1A000000)),
    ]) {
      for (final figura in figuras.values) {
        canvas.drawPath(figura.completo, relleno..color = color);
      }
    }

    for (final figura in cara.regiones.values) {
      canvas.drawPath(
        figura.completo,
        borde
          ..color = colores.contorno
          ..strokeWidth = px(0.8),
      );
    }

    if (cara.regiones[resaltada] case final figura?) {
      canvas.drawPath(
        figura.completo,
        borde
          ..color = colores.acento
          ..strokeWidth = px(2.5),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_PintorCuerpo anterior) =>
      anterior.cara != cara ||
      anterior.resaltada != resaltada ||
      anterior.colores != colores ||
      !mapEquals(anterior.niveles, niveles);
}

// ── Leyenda y lista complementaria ───────────────────────────────────────────

class _Leyenda extends StatelessWidget {
  const _Leyenda();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: t.l, vertical: t.s),
    child: Row(
      children: [
        Flexible(
          child: Text(
            'Sin trabajar',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ui.estilo(context, size: t.caption, color: context.textoSec),
          ),
        ),
        const SizedBox(width: t.s),
        for (var nivel = 0; nivel < nivelesColor; nivel++)
          Container(
            width: 22,
            height: 12,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: colorNivel(context, nivel),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: context.separador, width: 0.5),
            ),
          ),
        const SizedBox(width: t.s),
        Flexible(
          child: Text(
            'Muy trabajado',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: ui.estilo(context, size: t.caption, color: context.textoSec),
          ),
        ),
      ],
    ),
  );
}

/// Los músculos más abandonados.
///
/// No es un adorno del mapa: tocar el tibial o los romboides con el dedo es
/// poco fiable, y una lista ordenada por abandono es además la información más
/// accionable de la pantalla. El mapa comunica; la lista permite actuar.
class _MenosTrabajados extends StatelessWidget {
  const _MenosTrabajados({
    required this.trabajos,
    required this.hoy,
    required this.onRegion,
  });

  final List<TrabajoMuscular> trabajos;
  final DateTime hoy;
  final ValueChanged<Region> onRegion;

  @override
  Widget build(BuildContext context) => ui.Grupo(
    cabecera: 'Menos trabajados',
    pie:
        'Cuenta desde la última vez que entrenaste cada músculo, con todo tu '
        'histórico y no solo con el periodo elegido arriba.',
    filas: [
      for (final (region, dias) in menosTrabajados(trabajos, hoy: hoy))
        CupertinoListTile(
          backgroundColor: context.tarjeta,
          title: Text(
            regiones[region]!.nombre,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ui.estilo(context),
          ),
          additionalInfo: Text(
            dias == null
                ? 'nunca'
                : 'hace ${formato.plural(dias, 'día', 'días')}',
            style: ui.estilo(
              context,
              size: t.footnote,
              color: dias == null ? context.textoTer : context.textoSec,
            ),
          ),
          trailing: const CupertinoListTileChevron(),
          onTap: () => onRegion(region),
        ),
    ],
  );
}

// ── La hoja de un músculo ────────────────────────────────────────────────────

/// Abre la hoja de un músculo: qué has hecho con él y qué más puedes hacer.
Future<void> abrirHojaRegion(
  BuildContext context,
  Region region, {
  int dias = 30,
}) => showCupertinoModalPopup<void>(
  context: context,
  builder: (_) => _HojaRegion(region: region, dias: dias),
);

/// La hoja va en un contenedor propio y no en un `CupertinoActionSheet`.
///
/// Lo que lleva dentro —el resumen, cinco sesiones y cinco fichas con
/// miniatura, favorito y botón de añadir— no son «acciones», y una hoja de
/// acciones ni scrollea bien ni admite ese contenido.
class _HojaRegion extends ConsumerWidget {
  const _HojaRegion({required this.region, required this.dias});

  final Region region;
  final int dias;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final datos = regiones[region]!;
    final trabajos = ref.watch(trabajoMuscularProvider).value ?? const [];
    final ajustes = ref.watch(ajustesProvider).value ?? const Ajustes();
    final desde = reloj.ahora().subtract(Duration(days: dias));
    final trabajo = trabajoPorRegion(trabajos, desde: desde)[region];
    final sesiones = sesionesDeRegion(trabajos, region);
    final enRutinas =
        regionesEnRutinas(
          ref.watch(catalogoEnRutinasProvider).value ?? const [],
        )[region] ??
        const <String>[];

    return Container(
      height: MediaQuery.sizeOf(context).height * 0.78,
      decoration: BoxDecoration(
        color: context.fondo,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(t.radioL),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(t.l, t.m, t.l, t.s),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      datos.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ui.estilo(
                        context,
                        size: t.title3,
                        weight: t.semibold,
                      ),
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Listo'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  _resumen(context, trabajo, enRutinas, ajustes),
                  _sesiones(context, sesiones),
                  _Ejercicios(region: region),
                  const SizedBox(height: t.xxl),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resumen(
    BuildContext context,
    TrabajoRegion? trabajo,
    List<String> enRutinas,
    Ajustes ajustes,
  ) => ui.Grupo(
    cabecera: 'Últimos $dias días',
    pie:
        'El músculo objetivo del ejercicio cuenta entero, el grupo muscular a '
        'la mitad y los secundarios a un tercio.',
    filas: [
      _fila(context, 'Series', trabajo == null ? '—' : '${trabajo.nSeries}'),
      _fila(
        context,
        'Volumen',
        trabajo == null ? '—' : formato.peso(trabajo.volumen, ajustes),
      ),
      _fila(
        context,
        'Sesiones',
        trabajo == null ? '—' : '${trabajo.nSesiones}',
      ),
      _fila(
        context,
        'Última vez',
        trabajo?.ultima == null
            ? 'Sin registros'
            : formato.hace(trabajo!.ultima!),
      ),
      if (enRutinas.isNotEmpty)
        _fila(context, 'En tus rutinas', enRutinas.join(', ')),
    ],
  );

  Widget _fila(BuildContext context, String etiqueta, String valor) =>
      CupertinoListTile(
        backgroundColor: context.tarjeta,
        title: Text(etiqueta, style: ui.estilo(context)),
        additionalInfo: Flexible(
          child: Text(
            valor,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: ui.estilo(context, weight: t.semibold),
          ),
        ),
      );

  Widget _sesiones(BuildContext context, List<SesionDeRegion> sesiones) {
    if (sesiones.isEmpty) return const SizedBox.shrink();
    return ui.Grupo(
      cabecera: 'Tus entrenamientos',
      filas: [
        for (final s in sesiones)
          CupertinoListTile(
            backgroundColor: context.tarjeta,
            title: Text(
              s.ejercicio,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ui.estilo(context),
            ),
            subtitle: Text(
              '${formato.fechaCorta(s.fecha)} · ${formato.plural(s.nSeries, 'serie', 'series')}',
              style: ui.estilo(
                context,
                size: t.footnote,
                color: context.textoSec,
              ),
            ),
            trailing: const CupertinoListTileChevron(),
            onTap: () {
              Navigator.of(context).pop();
              abrirSesion(context, s.idEntrenamiento);
            },
          ),
      ],
    );
  }
}

/// Los ejercicios del catálogo de una región, con los que ya usas delante.
class _Ejercicios extends ConsumerWidget {
  const _Ejercicios({required this.region});

  final Region region;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogo = ref.watch(catalogoRegionProvider(region)).value;
    // Igual que en el mapa: hueco en vez de indicador, para no dejar la hoja
    // con una animación perpetua.
    if (catalogo == null) return const SizedBox(height: 120);

    final mios = <String>{
      for (final e in ref.watch(catalogoEnRutinasProvider).value ?? const [])
        if (regionesDeEjercicio(e.ficha).containsKey(region)) e.ficha.id,
    };
    // Delante los que el usuario ya tiene en alguna rutina: son los que va a
    // reconocer, y en una lista de 151 el resto da igual en qué orden vaya.
    final fichas = [...catalogo.fichas]
      ..sort((a, b) {
        final ma = mios.contains(a.id) ? 0 : 1;
        final mb = mios.contains(b.id) ? 0 : 1;
        return ma == mb ? a.nombre.compareTo(b.nombre) : ma.compareTo(mb);
      });

    return ui.Grupo(
      cabecera: 'Ejercicios',
      filas: [
        for (final ficha in fichas.take(8))
          CupertinoListTile(
            backgroundColor: context.tarjeta,
            leading: ui.Miniatura(media.resolver(ficha.image), tamano: 40),
            title: Text(
              ficha.nombre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ui.estilo(context),
            ),
            subtitle: Text(
              mios.contains(ficha.id)
                  ? 'Ya está en tus rutinas'
                  : formato.subtituloCatalogo(ficha),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ui.estilo(
                context,
                size: t.footnote,
                color: context.textoSec,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                BotonFavorito(idCatalogo: ficha.id, tamano: 20),
                CupertinoButton(
                  padding: const EdgeInsets.only(left: t.s),
                  minimumSize: Size.zero,
                  onPressed: () => anadirARutina(context, ref, ficha),
                  child: Icon(
                    CupertinoIcons.add_circled,
                    size: 22,
                    color: context.acento,
                  ),
                ),
              ],
            ),
            onTap: () {
              Navigator.of(context).pop();
              abrirFicha(context, ficha.id);
            },
          ),
        CupertinoListTile(
          backgroundColor: context.tarjeta,
          title: Text(
            'Ver los ${catalogo.total} ejercicios',
            style: ui.estilo(context, color: context.acento),
          ),
          trailing: const CupertinoListTileChevron(),
          onTap: () {
            Navigator.of(context).pop();
            abrirCatalogo(context, region: region);
          },
        ),
      ],
    );
  }
}
