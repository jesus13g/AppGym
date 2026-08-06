/// Registro de un entrenamiento: las series de cada ejercicio, una a una.
///
/// Cada serie es una fila con sus repeticiones y su peso, de modo que una
/// pirámide o un drop set se anotan tal y como se hicieron. Un ejercicio sin
/// series no se guarda, que es lo que sustituye al antiguo interruptor de
/// «incluir ejercicio».
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/bd.dart';
import '../datos/formato.dart' as formato;
import '../estado/providers.dart';
import '../tema/tokens.dart';
import '../tema/tokens.dart' as t;
import '../tema/ui.dart' as ui;

/// Lo que se propone cuando el ejercicio nunca se ha entrenado.
const _serieNueva = ValoresSerie(repeticiones: 10, peso: 20);
const _seriesPorDefecto = 4;

Future<void> abrirEntrenar(BuildContext context, int idRutina) =>
    Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => PantallaEntrenar(idRutina: idRutina),
      ),
    );

class PantallaEntrenar extends ConsumerStatefulWidget {
  const PantallaEntrenar({super.key, required this.idRutina});

  final int idRutina;

  @override
  ConsumerState<PantallaEntrenar> createState() => _PantallaEntrenarState();
}

class _PantallaEntrenarState extends ConsumerState<PantallaEntrenar> {
  /// id de ejercicio -> series que se van a guardar, en orden.
  final _series = <int, List<ValoresSerie>>{};

  /// id de ejercicio -> lo que se registró la última vez, para la referencia.
  final _ultimas = <int, List<ValoresSerie>>{};

  List<EjercicioConFicha>? _ejercicios;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final bd = ref.read(bdProvider);
    final ejercicios = await bd.ejerciciosDeRutina(widget.idRutina);

    for (final ejercicio in ejercicios) {
      // Se precargan las series de la última sesión —cuántas fueron incluido—,
      // que casi siempre es lo que se repite.
      final ultimas = await bd.ultimasSeriesEjercicio(ejercicio.id);
      _ultimas[ejercicio.id] = ultimas;
      _series[ejercicio.id] = ultimas.isEmpty
          ? List.filled(_seriesPorDefecto, _serieNueva)
          : List.of(ultimas);
    }

    if (mounted) setState(() => _ejercicios = ejercicios);
  }

  Future<void> _guardar() async {
    if (_guardando) return;

    setState(() => _guardando = true);
    final bien = await ref
        .read(bdProvider)
        .insertarEntrenamiento(widget.idRutina, DateTime.now(), _series);
    if (!mounted) return;

    if (!bien) {
      setState(() => _guardando = false);
      ui.aviso(context, 'Añade al menos una serie');
      return;
    }
    invalidarEntrenamientos(ref, widget.idRutina);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final rutina = ref.watch(rutinaProvider(widget.idRutina)).value;
    final ejercicios = _ejercicios;

    if (ejercicios != null && ejercicios.isEmpty) {
      return CupertinoPageScaffold(
        backgroundColor: context.fondo,
        navigationBar: ui.barra(
          context,
          titulo: 'Entrenamiento',
          izquierda: _botonCancelar(context),
        ),
        child: const ui.EstadoVacio(
          icono: CupertinoIcons.exclamationmark_triangle,
          titulo: 'Esta rutina no tiene ejercicios',
        ),
      );
    }

    return CupertinoPageScaffold(
      backgroundColor: context.fondo,
      navigationBar: ui.barra(
        context,
        titulo: 'Entrenamiento',
        izquierda: _botonCancelar(context),
        derecha: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          onPressed: _guardando ? null : _guardar,
          child: Text(
            'Guardar',
            style: ui.estilo(
              context,
              weight: t.semibold,
              color: context.acento,
            ),
          ),
        ),
      ),
      child: ejercicios == null
          ? const ui.Cargando()
          : SafeArea(
              child: ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                      left: t.l,
                      right: t.l,
                      top: t.m,
                      bottom: t.l,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rutina?.nombre ?? '',
                          style: ui.estilo(
                            context,
                            size: t.title2,
                            weight: t.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formato.fechaLarga(DateTime.now()),
                          style: ui.estilo(
                            context,
                            size: t.subhead,
                            color: context.textoSec,
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (final ejercicio in ejercicios)
                    Padding(
                      padding: const EdgeInsets.only(bottom: t.l),
                      child: TarjetaEjercicio(
                        ejercicio: ejercicio,
                        ultimas: _ultimas[ejercicio.id] ?? const [],
                        series: _series[ejercicio.id] ?? const [],
                        onSeries: (valor) =>
                            setState(() => _series[ejercicio.id] = valor),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(t.l),
                    child: ui.BotonPrincipal(
                      'Guardar entrenamiento',
                      icono: CupertinoIcons.check_mark,
                      onPressed: _guardando ? null : _guardar,
                    ),
                  ),
                  const SizedBox(height: t.xl),
                ],
              ),
            ),
    );
  }

  Widget _botonCancelar(BuildContext context) => CupertinoButton(
    padding: EdgeInsets.zero,
    minimumSize: Size.zero,
    onPressed: () => Navigator.of(context).pop(),
    child: const Text('Cancelar'),
  );
}

/// Tarjeta de un ejercicio con la lista de sus series.
///
/// Es pública para poder montarla suelta en los tests de widget, que es donde
/// se vigila que la fila de cuatro controles no desborde.
class TarjetaEjercicio extends StatelessWidget {
  const TarjetaEjercicio({
    super.key,
    required this.ejercicio,
    required this.ultimas,
    required this.series,
    required this.onSeries,
  });

  final EjercicioConFicha ejercicio;

  /// Series de la última sesión, solo para la línea de referencia.
  final List<ValoresSerie> ultimas;

  final List<ValoresSerie> series;
  final ValueChanged<List<ValoresSerie>> onSeries;

  void _cambiar(int indice, ValoresSerie valores) {
    final nuevas = List.of(series)..[indice] = valores;
    onSeries(nuevas);
  }

  void _borrar(int indice) => onSeries(List.of(series)..removeAt(indice));

  /// Añadir copia la última serie, que es el gesto más frecuente.
  void _anadir() => onSeries(
    List.of(series)..add(series.isEmpty ? _serieNueva : series.last),
  );

  Future<void> _menu(BuildContext context, int indice) async {
    final serie = series[indice];
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (hoja) => CupertinoActionSheet(
        title: Text('Serie ${indice + 1}'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(hoja);
              _cambiar(
                indice,
                serie.copiar(calentamiento: !serie.calentamiento),
              );
            },
            child: Text(
              serie.calentamiento
                  ? 'Quitar el calentamiento'
                  : 'Marcar como calentamiento',
            ),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(hoja);
              _borrar(indice);
            },
            child: const Text('Eliminar serie'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(hoja),
          child: const Text('Cancelar'),
        ),
      ),
    );
  }

  String get _referencia {
    if (ultimas.isEmpty) return 'Primera vez con este ejercicio';
    final volumen = ultimas
        .where((s) => !s.calentamiento)
        .fold<double>(0, (suma, s) => suma + s.peso * s.repeticiones);
    return 'Último: ${formato.plural(ultimas.length, 'serie', 'series')} · '
        '${formato.numero(volumen)} kg';
  }

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: t.l),
    decoration: BoxDecoration(
      color: context.tarjeta,
      borderRadius: BorderRadius.circular(t.radioL),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: t.l, vertical: t.m),
          child: Row(
            children: [
              ui.Miniatura(formato.imagenEjercicio(ejercicio), tamano: 40),
              const SizedBox(width: t.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ejercicio.nombre,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: ui.estilo(
                        context,
                        size: t.callout,
                        weight: t.semibold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _referencia,
                      style: ui.estilo(
                        context,
                        size: t.caption,
                        color: context.textoSec,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Container(height: 0.5, color: context.separador),
        if (series.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: t.m),
            child: Text(
              'Sin series: este ejercicio no se guardará',
              style: ui.estilo(
                context,
                size: t.footnote,
                color: context.textoTer,
              ),
            ),
          )
        else
          for (final (indice, serie) in series.indexed)
            ui.DeslizarParaBorrar(
              // El índice no vale como llave: al borrar una serie, las de abajo
              // cambian de índice y Flutter reutilizaría el estado equivocado.
              llave: ValueKey('${ejercicio.id}-$indice-${series.length}'),
              onBorrar: () => _borrar(indice),
              child: ColoredBox(
                color: context.tarjeta,
                child: _FilaSerie(
                  numero: indice + 1,
                  serie: serie,
                  onSerie: (valores) => _cambiar(indice, valores),
                  onMenu: () => _menu(context, indice),
                ),
              ),
            ),
        Container(height: 0.5, color: context.separador),
        CupertinoButton(
          onPressed: _anadir,
          padding: const EdgeInsets.symmetric(vertical: t.m),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(CupertinoIcons.add, size: 16, color: context.acento),
              const SizedBox(width: t.xs),
              Text(
                'Añadir serie',
                style: ui.estilo(
                  context,
                  size: t.subhead,
                  color: context.acento,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Una serie: número, repeticiones, peso y su menú.
class _FilaSerie extends StatelessWidget {
  const _FilaSerie({
    required this.numero,
    required this.serie,
    required this.onSerie,
    required this.onMenu,
  });

  final int numero;
  final ValoresSerie serie;
  final ValueChanged<ValoresSerie> onSerie;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: t.m, vertical: t.xs),
    child: Row(
      children: [
        SizedBox(
          width: 26,
          child: serie.calentamiento
              ? Icon(CupertinoIcons.flame, size: 16, color: context.textoTer)
              : Text(
                  '$numero',
                  textAlign: TextAlign.center,
                  style: ui.estilo(
                    context,
                    size: t.subhead,
                    color: context.textoSec,
                  ),
                ),
        ),
        // El reparto 2:3 no es decorativo: el peso lleva decimales y unidad, y
        // con las repeticiones a la mitad de ancho la fila desbordaba en un
        // móvil estrecho. Hay un test que lo fija.
        Expanded(
          flex: 2,
          child: ui.SelectorEnLinea(
            semantica: 'Repeticiones',
            valor: serie.repeticiones.toDouble(),
            minimo: 1,
            maximo: 50,
            onChanged: (v) => onSerie(serie.copiar(repeticiones: v.round())),
          ),
        ),
        const SizedBox(width: t.s),
        Expanded(
          flex: 3,
          child: ui.SelectorEnLinea(
            semantica: 'Peso',
            valor: serie.peso,
            minimo: 0,
            maximo: 400,
            paso: 2.5,
            unidad: 'kg',
            decimales: 1,
            onChanged: (v) => onSerie(serie.copiar(peso: v)),
          ),
        ),
        CupertinoButton(
          onPressed: onMenu,
          padding: const EdgeInsets.symmetric(horizontal: t.s, vertical: t.s),
          minimumSize: Size.zero,
          child: Icon(
            CupertinoIcons.ellipsis,
            size: 18,
            color: context.textoSec,
          ),
        ),
      ],
    ),
  );
}
