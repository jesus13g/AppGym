/// Catálogo de ejercicios: búsqueda, filtros y alta en una rutina.
///
/// La misma pantalla sirve para dos cosas: la pestaña de exploración del
/// catálogo completo, y el modal que añade ejercicios a una rutina concreta.
library;

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/bd.dart';
import '../datos/i18n.dart' as i18n;
import '../datos/musculos.dart';
import '../datos/media.dart' as media;
import '../estado/providers.dart';
import '../l10n/textos.dart';
import '../tema/tokens.dart';
import '../tema/tokens.dart' as t;
import '../tema/ui.dart' as ui;
import 'anadir_a_rutina.dart';
import 'ficha.dart';

/// Resultados por tanda. Nunca se pintan los 1.324 de golpe.
const _pagina = 40;

/// Reposo antes de lanzar la consulta, para no buscar en cada tecla.
const _esperaBusqueda = Duration(milliseconds: 250);

const _zonas = <(String?, String)>[
  (null, 'Todas'),
  ('chest', 'Pecho'),
  ('back', 'Espalda'),
  ('upper legs', 'Piernas'),
  ('lower legs', 'Gemelos'),
  ('shoulders', 'Hombros'),
  ('upper arms', 'Brazos'),
  ('lower arms', 'Antebrazos'),
  ('waist', 'Core'),
  ('cardio', 'Cardio'),
  ('neck', 'Cuello'),
];

/// Abre el modal de alta de ejercicios sobre una rutina.
Future<void> abrirAnadirEjercicio(BuildContext context, int idRutina) =>
    Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => PantallaCatalogo(idRutina: idRutina),
      ),
    );

/// Abre el catálogo como pantalla, opcionalmente filtrado por una región.
///
/// Se empuja en el navegador de la pestaña de quien llama —no en el raíz—, para
/// que desde el mapa muscular se pueda volver deslizando sin salir de Progreso.
Future<void> abrirCatalogo(BuildContext context, {Region? region}) =>
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => PantallaCatalogo(region: region),
      ),
    );

class PantallaCatalogo extends ConsumerStatefulWidget {
  const PantallaCatalogo({super.key, this.idRutina, this.region});

  /// Si es null, la pantalla es la pestaña de exploración: al tocar un
  /// ejercicio se abre su ficha en vez de añadirlo.
  final int? idRutina;

  /// Región muscular con la que llega ya filtrada, desde el mapa.
  ///
  /// Filtra por los mismos términos que usa la atribución del mapa, y no solo
  /// por `target`: cuatro regiones —deltoides posterior, oblicuos, flexores de
  /// cadera y tibial— no tienen ningún `target` propio y saldrían vacías.
  final Region? region;

  @override
  ConsumerState<PantallaCatalogo> createState() => _PantallaCatalogoState();
}

class _PantallaCatalogoState extends ConsumerState<PantallaCatalogo> {
  final _scroll = ScrollController();
  final _campo = TextEditingController();

  String _texto = '';
  late Region? _region = widget.region;
  String? _zona;
  String? _equipo;
  String? _objetivo;
  int _desplazamiento = 0;
  bool _hayMas = true;
  bool _cargando = false;
  int _generacion = 0;
  Timer? _temporizador;

  final _resultados = <FichaCatalogo>[];
  Set<String> _yaEnRutina = {};

  bool get _esModal => widget.idRutina != null;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_alHacerScroll);
    _cargar(reiniciar: true);
    if (_esModal) {
      ref.read(bdProvider).idsCatalogoEnRutina(widget.idRutina!).then((ids) {
        if (mounted) setState(() => _yaEnRutina = ids);
      });
    }
  }

  @override
  void dispose() {
    _temporizador?.cancel();
    _scroll.dispose();
    _campo.dispose();
    super.dispose();
  }

  void _alHacerScroll() {
    if (!_hayMas || _cargando) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      _cargar();
    }
  }

  Future<void> _cargar({bool reiniciar = false}) async {
    // Una búsqueda o un cambio de filtro siempre mandan. Si se descartaran por
    // haber una página en vuelo, escribir rápido perdería la última consulta y
    // la lista se quedaría con los resultados del texto anterior.
    if (_cargando && !reiniciar) return;

    if (reiniciar) {
      _desplazamiento = 0;
      _hayMas = true;
      _resultados.clear();
    }
    // Cada tanda lleva su número: si vuelve una consulta que ya ha quedado
    // obsoleta, se tira en vez de mezclarla con los resultados buenos.
    final generacion = ++_generacion;
    _cargando = true;

    final fichas = await ref
        .read(bdProvider)
        .buscarCatalogo(
          texto: _texto.isEmpty ? null : i18n.normalizar(_texto),
          bodyPart: _zona,
          equipment: _equipo,
          target: _objetivo,
          musculos: _region == null ? null : terminosDe(_region!),
          limite: _pagina,
          desplazamiento: _desplazamiento,
        );
    if (!mounted || generacion != _generacion) return;

    setState(() {
      _resultados.addAll(fichas);
      _desplazamiento += fichas.length;
      _hayMas = fichas.length == _pagina;
    });
    _cargando = false;
  }

  void _buscar(String valor) {
    _texto = valor.trim();
    _temporizador?.cancel();
    _temporizador = Timer(_esperaBusqueda, () => _cargar(reiniciar: true));
  }

  Future<void> _anadir(FichaCatalogo ficha) async {
    if (_yaEnRutina.contains(ficha.id)) {
      ui.aviso(context, 'Ya está en la rutina');
      return;
    }
    final bien = await ref
        .read(bdProvider)
        .insertarEjercicio(
          widget.idRutina!,
          ficha.nombre,
          idCatalogo: ficha.id,
        );
    if (!mounted) return;

    if (!bien) {
      ui.aviso(context, 'No se pudo añadir el ejercicio');
      return;
    }
    setState(() => _yaEnRutina = {..._yaEnRutina, ficha.id});
    invalidarRutina(ref, widget.idRutina!);
    ui.aviso(context, '«${ficha.nombre}» añadido');
  }

  Future<void> _crearPersonalizado() async {
    final nombre = await ui.dialogoTexto(
      context,
      titulo: 'Ejercicio personalizado',
      marcador: 'Nombre del ejercicio',
      mensaje: 'Para lo que no esté en el catálogo.',
      etiquetaAceptar: 'Añadir',
      etiquetaCancelar: context.t.comunCancelar,
    );
    if (nombre == null || !mounted) return;

    final bien = await ref
        .read(bdProvider)
        .insertarEjercicio(widget.idRutina!, nombre);
    if (!mounted) return;

    if (!bien) {
      ui.aviso(context, 'Ya tienes un ejercicio con ese nombre');
      return;
    }
    invalidarRutina(ref, widget.idRutina!);
    Navigator.of(context).pop();
  }

  Future<void> _elegirEquipo() async {
    final disponibles = await ref.read(equipamientosProvider.future);
    if (!mounted) return;

    final elegido = await showCupertinoModalPopup<(String?,)>(
      context: context,
      builder: (hoja) => CupertinoActionSheet(
        title: const Text('Equipamiento'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(hoja, (null,)),
            child: const Text('Todos'),
          ),
          for (final valor in disponibles)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(hoja, (valor,)),
              child: Text(i18n.equipamiento(valor)),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(hoja),
          child: const Text('Cancelar'),
        ),
      ),
    );
    if (elegido == null || !mounted) return;

    setState(() => _equipo = elegido.$1);
    await _cargar(reiniciar: true);
  }

  /// Filtro por músculo objetivo: la clasificación más fina del catálogo.
  ///
  /// Va con su recuento («Bíceps · 151») porque es lo que dice de antemano si
  /// merece la pena entrar en el filtro.
  Future<void> _elegirObjetivo() async {
    final disponibles = await ref.read(objetivosProvider.future);
    if (!mounted) return;

    final elegido = await ui.elegirEnHoja<String?>(
      context,
      titulo: 'Músculo objetivo',
      actual: _objetivo,
      opciones: [
        (null, 'Todos'),
        for (final (valor, cuantos) in disponibles)
          (valor, '${i18n.musculo(valor)} · $cuantos'),
      ],
      etiquetaCancelar: context.t.comunCancelar,
    );
    if (elegido == null || !mounted) return;

    setState(() => _objetivo = elegido.$1);
    await _cargar(reiniciar: true);
  }

  /// True cuando no hay ni búsqueda ni filtros: es el estado inicial, donde en
  /// vez de los 1.324 de golpe se enseñan los favoritos y lo visto hace poco.
  bool get _sinFiltros =>
      _texto.isEmpty &&
      _zona == null &&
      _equipo == null &&
      _objetivo == null &&
      _region == null;

  @override
  Widget build(BuildContext context) {
    final titulo = switch ((_esModal, widget.region)) {
      (true, _) => 'Añadir ejercicio',
      (false, final region?) => regiones[region]!.nombre,
      _ => 'Ejercicios',
    };

    return CupertinoPageScaffold(
      backgroundColor: context.fondo,
      navigationBar: ui.barra(
        context,
        titulo: titulo,
        izquierda: _esModal
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              )
            : null,
        derecha: _esModal
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: _crearPersonalizado,
                child: Text(
                  'Personalizado',
                  style: ui.estilo(
                    context,
                    size: t.subhead,
                    color: context.acento,
                  ),
                ),
              )
            : null,
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: t.l,
                vertical: t.s,
              ),
              child: CupertinoSearchTextField(
                controller: _campo,
                placeholder: 'Buscar ejercicio, músculo o material',
                onChanged: _buscar,
              ),
            ),
            _Filtros(
              zona: _zona,
              equipo: _equipo,
              objetivo: _objetivo,
              region: _region,
              contador: _contador,
              onQuitarRegion: () {
                setState(() => _region = null);
                _cargar(reiniciar: true);
              },
              onZona: (valor) {
                setState(() => _zona = valor);
                _cargar(reiniciar: true);
              },
              onEquipo: _elegirEquipo,
              onObjetivo: _elegirObjetivo,
            ),
            Expanded(child: _lista()),
          ],
        ),
      ),
    );
  }

  String get _contador {
    if (_resultados.isEmpty) return '';
    if (_hayMas) return '${_resultados.length}+ ejercicios';
    return context.t.comunEjercicios(_resultados.length);
  }

  Widget _lista() {
    if (_resultados.isEmpty) {
      return _cargando
          ? const ui.Cargando()
          : const ui.EstadoVacio(
              icono: CupertinoIcons.search,
              titulo: 'Sin resultados',
              subtitulo:
                  'Prueba con otro término o quita alguno de los filtros.',
            );
    }

    // Una fila extra al final para ofrecer el ejercicio personalizado.
    final extra = _esModal && !_hayMas ? 1 : 0;
    // En el estado inicial de la pestaña, encima de todo van los favoritos y lo
    // visto hace poco. Antes esta pantalla arrancaba con el buscador y nada más.
    final cabecera = !_esModal && _sinFiltros ? 1 : 0;

    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.only(bottom: t.xxl),
      itemCount: cabecera + _resultados.length + extra,
      separatorBuilder: (context, indice) => indice < cabecera
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(left: 76),
              child: Container(height: 0.5, color: context.separador),
            ),
      itemBuilder: (context, posicion) {
        if (posicion < cabecera) return const _Destacados();

        final indice = posicion - cabecera;
        if (indice >= _resultados.length) return _filaPersonalizado();
        return _fila(_resultados[indice]);
      },
    );
  }

  Widget _fila(FichaCatalogo ficha) {
    final anadido = _yaEnRutina.contains(ficha.id);

    return CupertinoListTile(
      backgroundColor: context.tarjeta,
      leading: ui.Miniatura(media.resolver(ficha.image)),
      leadingSize: 48,
      title: Text(ficha.nombre, style: ui.estilo(context)),
      subtitle: Text(
        formatoDe(context, ref).subtituloCatalogo(ficha),
        style: ui.estilo(context, size: t.footnote, color: context.textoSec),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: _esModal
            ? [
                // El icono ⓘ abre la ficha sin añadir nada.
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  onPressed: () => abrirFicha(context, ficha.id),
                  child: Icon(
                    CupertinoIcons.info_circle,
                    size: 20,
                    color: context.textoTer,
                  ),
                ),
                const SizedBox(width: t.s),
                Icon(
                  anadido
                      ? CupertinoIcons.check_mark_circled_solid
                      : CupertinoIcons.plus_circle,
                  color: anadido ? context.exito : context.acento,
                  size: 24,
                ),
              ]
            : [
                // Fuera del modal, la fila lleva su estrella y su «+»: añadir a
                // una rutina sin salir de la pestaña Ejercicios es justo lo que
                // faltaba. El chevron sobra, la fila entera sigue abriendo la
                // ficha.
                BotonFavorito(idCatalogo: ficha.id, tamano: 20),
                const SizedBox(width: t.s),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  onPressed: () => anadirARutina(context, ref, ficha),
                  child: Icon(
                    CupertinoIcons.plus_circle,
                    size: 22,
                    color: context.acento,
                  ),
                ),
              ],
      ),
      onTap: _esModal
          ? () => _anadir(ficha)
          : () => abrirFicha(context, ficha.id),
    );
  }

  Widget _filaPersonalizado() => Padding(
    padding: const EdgeInsets.only(top: t.s),
    child: CupertinoListTile(
      backgroundColor: context.tarjeta,
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: context.relleno,
          borderRadius: BorderRadius.circular(t.radioM),
        ),
        child: Icon(
          CupertinoIcons.pencil_outline,
          color: context.acento,
          size: 22,
        ),
      ),
      leadingSize: 48,
      title: Text('Crear ejercicio personalizado', style: ui.estilo(context)),
      subtitle: Text(
        'Si no encuentras lo que buscas',
        style: ui.estilo(context, size: t.footnote, color: context.textoSec),
      ),
      trailing: const CupertinoListTileChevron(),
      onTap: _crearPersonalizado,
    ),
  );
}

/// Favoritos y vistos recientemente, encima del catálogo.
///
/// Solo aparece sin búsqueda ni filtros: en cuanto se escribe algo, lo que
/// interesa son los resultados. Cada sección se calla si está vacía, de modo
/// que una instalación recién estrenada ve exactamente lo de antes.
class _Destacados extends ConsumerWidget {
  const _Destacados();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoritos = ref.watch(favoritosProvider).value ?? const [];
    final vistos = ref.watch(vistosProvider).value ?? const [];
    if (favoritos.isEmpty && vistos.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        if (favoritos.isNotEmpty)
          _seccion(context, ref, 'Favoritos', favoritos),
        if (vistos.isNotEmpty)
          _seccion(context, ref, 'Vistos recientemente', vistos),
        Padding(
          padding: const EdgeInsets.only(
            left: t.l,
            right: t.l,
            top: t.m,
            bottom: t.xs,
          ),
          child: Text(
            'TODOS LOS EJERCICIOS',
            style: ui.estilo(
              context,
              size: t.footnote,
              color: context.textoSec,
            ),
          ),
        ),
      ],
    );
  }

  Widget _seccion(
    BuildContext context,
    WidgetRef ref,
    String cabecera,
    List<FichaCatalogo> fichas,
  ) => ui.Grupo(
    cabecera: cabecera,
    filas: [
      for (final ficha in fichas)
        CupertinoListTile(
          backgroundColor: context.tarjeta,
          leading: ui.Miniatura(media.resolver(ficha.image), tamano: 40),
          leadingSize: 40,
          title: Text(ficha.nombre, style: ui.estilo(context)),
          subtitle: Text(
            formatoDe(context, ref).subtituloCatalogo(ficha),
            style: ui.estilo(
              context,
              size: t.footnote,
              color: context.textoSec,
            ),
          ),
          trailing: CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            onPressed: () => anadirARutina(context, ref, ficha),
            child: Icon(
              CupertinoIcons.plus_circle,
              size: 22,
              color: context.acento,
            ),
          ),
          onTap: () => abrirFicha(context, ficha.id),
        ),
    ],
  );
}

class _Filtros extends StatelessWidget {
  const _Filtros({
    required this.zona,
    required this.equipo,
    required this.objetivo,
    required this.region,
    required this.contador,
    required this.onZona,
    required this.onEquipo,
    required this.onObjetivo,
    required this.onQuitarRegion,
  });

  final String? zona;
  final String? equipo;
  final String? objetivo;
  final Region? region;
  final VoidCallback onObjetivo;
  final String contador;
  final ValueChanged<String?> onZona;
  final VoidCallback onEquipo;
  final VoidCallback onQuitarRegion;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: t.l, right: t.l, bottom: t.s),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 32,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _zonas.length,
            separatorBuilder: (_, _) => const SizedBox(width: t.s),
            itemBuilder: (context, indice) {
              final (valor, etiqueta) = _zonas[indice];
              final activo = zona == valor;
              return GestureDetector(
                onTap: () => onZona(valor),
                child: ui.Pildora(
                  etiqueta,
                  color: activo ? CupertinoColors.white : context.texto,
                  relleno: activo ? context.acento : context.relleno,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: t.s),
        Row(
          children: [
            _desplegable(
              context,
              equipo == null ? 'Equipamiento' : i18n.equipamiento(equipo),
              onEquipo,
            ),
            const SizedBox(width: t.l),
            // Con una región puesta manda ella: dos filtros musculares a la
            // vez confunden, y quitarla devuelve el desplegable de siempre.
            if (region case final region?)
              GestureDetector(
                onTap: onQuitarRegion,
                child: ui.Pildora(
                  '${regiones[region]!.nombre}  ✕',
                  color: CupertinoColors.white,
                  relleno: context.acento,
                ),
              )
            else
              _desplegable(
                context,
                objetivo == null ? 'Músculo' : i18n.musculo(objetivo),
                onObjetivo,
              ),
            const Spacer(),
            // El contador se encoge antes que los filtros: es informativo y
            // «1.324+ ejercicios» junto a dos desplegables no cabe en un móvil.
            Flexible(
              child: Text(
                contador,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: ui.estilo(
                  context,
                  size: t.footnote,
                  color: context.textoSec,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  /// Etiqueta con chevron que abre una hoja de opciones.
  Widget _desplegable(
    BuildContext context,
    String etiqueta,
    VoidCallback onTap,
  ) => GestureDetector(
    onTap: onTap,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          etiqueta,
          style: ui.estilo(context, size: t.footnote, color: context.acento),
        ),
        const SizedBox(width: t.xs),
        Icon(CupertinoIcons.chevron_down, size: 12, color: context.acento),
      ],
    ),
  );
}
