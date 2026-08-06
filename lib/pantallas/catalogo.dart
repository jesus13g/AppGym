/// Catálogo de ejercicios: búsqueda, filtros y alta en una rutina.
///
/// La misma pantalla sirve para dos cosas: la pestaña de exploración del
/// catálogo completo, y el modal que añade ejercicios a una rutina concreta.
library;

import 'dart:async';

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

class PantallaCatalogo extends ConsumerStatefulWidget {
  const PantallaCatalogo({super.key, this.idRutina});

  /// Si es null, la pantalla es la pestaña de exploración: al tocar un
  /// ejercicio se abre su ficha en vez de añadirlo.
  final int? idRutina;

  @override
  ConsumerState<PantallaCatalogo> createState() => _PantallaCatalogoState();
}

class _PantallaCatalogoState extends ConsumerState<PantallaCatalogo> {
  final _scroll = ScrollController();
  final _campo = TextEditingController();

  String _texto = '';
  String? _zona;
  String? _equipo;
  int _desplazamiento = 0;
  bool _hayMas = true;
  bool _cargando = false;
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
    if (_cargando) return;
    _cargando = true;
    if (reiniciar) {
      _desplazamiento = 0;
      _hayMas = true;
      _resultados.clear();
    }

    final fichas = await ref
        .read(bdProvider)
        .buscarCatalogo(
          texto: _texto.isEmpty ? null : i18n.normalizar(_texto),
          bodyPart: _zona,
          equipment: _equipo,
          limite: _pagina,
          desplazamiento: _desplazamiento,
        );
    if (!mounted) return;

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

  @override
  Widget build(BuildContext context) {
    final titulo = _esModal ? 'Añadir ejercicio' : 'Ejercicios';

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
              contador: _contador,
              onZona: (valor) {
                setState(() => _zona = valor);
                _cargar(reiniciar: true);
              },
              onEquipo: _elegirEquipo,
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
    return formato.plural(_resultados.length, 'ejercicio', 'ejercicios');
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

    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.only(bottom: t.xxl),
      itemCount: _resultados.length + extra,
      separatorBuilder: (context, indice) => Padding(
        padding: const EdgeInsets.only(left: 76),
        child: Container(height: 0.5, color: context.separador),
      ),
      itemBuilder: (context, indice) {
        if (indice >= _resultados.length) return _filaPersonalizado();

        final ficha = _resultados[indice];
        final anadido = _yaEnRutina.contains(ficha.id);

        return CupertinoListTile(
          backgroundColor: context.tarjeta,
          leading: ui.Miniatura(media.resolver(ficha.image)),
          leadingSize: 48,
          title: Text(ficha.nombre, style: ui.estilo(context)),
          subtitle: Text(
            formato.subtituloCatalogo(ficha),
            style: ui.estilo(
              context,
              size: t.footnote,
              color: context.textoSec,
            ),
          ),
          trailing: _esModal
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                  ],
                )
              : const CupertinoListTileChevron(),
          onTap: _esModal
              ? () => _anadir(ficha)
              : () => abrirFicha(context, ficha.id),
        );
      },
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

class _Filtros extends StatelessWidget {
  const _Filtros({
    required this.zona,
    required this.equipo,
    required this.contador,
    required this.onZona,
    required this.onEquipo,
  });

  final String? zona;
  final String? equipo;
  final String contador;
  final ValueChanged<String?> onZona;
  final VoidCallback onEquipo;

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
            GestureDetector(
              onTap: onEquipo,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    equipo == null ? 'Equipamiento' : i18n.equipamiento(equipo),
                    style: ui.estilo(
                      context,
                      size: t.footnote,
                      color: context.acento,
                    ),
                  ),
                  const SizedBox(width: t.xs),
                  Icon(
                    CupertinoIcons.chevron_down,
                    size: 12,
                    color: context.acento,
                  ),
                ],
              ),
            ),
            const Spacer(),
            Text(
              contador,
              style: ui.estilo(
                context,
                size: t.footnote,
                color: context.textoSec,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
