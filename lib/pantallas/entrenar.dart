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

/// Reabre una sesión ya guardada para corregirla.
Future<void> abrirEditarEntrenamiento(
  BuildContext context,
  int idRutina,
  int idEntrenamiento,
) => Navigator.of(context, rootNavigator: true).push(
  CupertinoPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) =>
        PantallaEntrenar(idRutina: idRutina, idEntrenamiento: idEntrenamiento),
  ),
);

class PantallaEntrenar extends ConsumerStatefulWidget {
  const PantallaEntrenar({
    super.key,
    required this.idRutina,
    this.idEntrenamiento,
  });

  final int idRutina;

  /// Si viene informado se edita esa sesión en vez de crear una nueva.
  final int? idEntrenamiento;

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
  DateTime _fecha = DateTime.now();
  final _nota = TextEditingController();

  bool get _editando => widget.idEntrenamiento != null;

  String get _titulo => _editando ? 'Editar entrenamiento' : 'Entrenamiento';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _nota.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final bd = ref.read(bdProvider);
    final ejercicios = await bd.ejerciciosDeRutina(widget.idRutina);

    // Al editar se parte de lo que se guardó aquel día; los ejercicios de la
    // rutina que no se hicieron aparecen vacíos, por si faltó anotar alguno.
    final sesion = _editando ? await bd.sesion(widget.idEntrenamiento!) : null;
    final guardadas = sesion?.series ?? const {};
    if (sesion != null) {
      _fecha = sesion.fecha;
      _nota.text = sesion.nota ?? '';
    }

    for (final ejercicio in ejercicios) {
      // Se precargan las series de la última sesión —cuántas fueron incluido—,
      // que casi siempre es lo que se repite.
      final ultimas = await bd.ultimasSeriesEjercicio(ejercicio.id);
      _ultimas[ejercicio.id] = ultimas;
      _series[ejercicio.id] = switch (guardadas[ejercicio.id]) {
        final serie? => List.of(serie),
        _ when _editando => const [],
        _ =>
          ultimas.isEmpty
              ? List.filled(_seriesPorDefecto, _serieNueva)
              : List.of(ultimas),
      };
    }

    if (mounted) setState(() => _ejercicios = ejercicios);
  }

  /// Elige el día del entrenamiento, para poder anotar el de ayer.
  ///
  /// Un día pasado se guarda a las 12:00 en vez de a la hora actual: así el
  /// orden dentro del día es estable y no depende de a qué hora uno se acordó
  /// de abrir la app. Hoy conserva la hora, que es la de verdad.
  Future<void> _elegirFecha() async {
    final ahora = DateTime.now();
    final elegida = await ui.selectorFecha(
      context,
      inicial: _fecha,
      maxima: ahora,
    );
    if (elegida == null || !mounted) return;

    bool mismoDia(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;

    setState(() {
      _fecha = switch (elegida) {
        // Elegir el mismo día no debe mover la hora de una sesión ya guardada.
        _ when mismoDia(elegida, _fecha) => _fecha,
        _ when mismoDia(elegida, ahora) => ahora,
        _ => DateTime(elegida.year, elegida.month, elegida.day, 12),
      };
    });
  }

  Future<void> _guardar() async {
    if (_guardando) return;

    setState(() => _guardando = true);
    final bd = ref.read(bdProvider);
    final bien = _editando
        ? await bd.actualizarEntrenamiento(
            widget.idEntrenamiento!,
            _fecha,
            _series,
            nota: _nota.text,
          )
        : await bd.insertarEntrenamiento(
            widget.idRutina,
            _fecha,
            _series,
            nota: _nota.text,
          );
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
    final ajustes = ref.watch(ajustesProvider).value ?? const Ajustes();
    final ejercicios = _ejercicios;

    if (ejercicios != null && ejercicios.isEmpty) {
      return CupertinoPageScaffold(
        backgroundColor: context.fondo,
        navigationBar: ui.barra(
          context,
          titulo: _titulo,
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
        titulo: _titulo,
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
                        CupertinoButton(
                          onPressed: _elegirFecha,
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                formato.fechaLarga(_fecha),
                                style: ui.estilo(
                                  context,
                                  size: t.subhead,
                                  color: context.acento,
                                ),
                              ),
                              const SizedBox(width: t.xs),
                              Icon(
                                CupertinoIcons.calendar,
                                size: 15,
                                color: context.acento,
                              ),
                            ],
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
                        ajustes: ajustes,
                        onSeries: (valor) =>
                            setState(() => _series[ejercicio.id] = valor),
                      ),
                    ),
                  ui.Grupo(
                    cabecera: 'Notas',
                    pie:
                        'Lo que explique este entrenamiento dentro de tres '
                        'semanas: molestias, cinturón, mal día.',
                    filas: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: t.m,
                          vertical: t.s,
                        ),
                        child: CupertinoTextField.borderless(
                          controller: _nota,
                          placeholder: 'Nota de la sesión',
                          maxLines: null,
                          minLines: 2,
                          style: ui.estilo(context),
                        ),
                      ),
                    ],
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
    this.ajustes = const Ajustes(),
  });

  final EjercicioConFicha ejercicio;

  /// Series de la última sesión, solo para la línea de referencia.
  final List<ValoresSerie> ultimas;

  final List<ValoresSerie> series;
  final ValueChanged<List<ValoresSerie>> onSeries;

  /// De aquí sale si se pide el esfuerzo y en qué escala se muestra.
  final Ajustes ajustes;

  void _cambiar(int indice, ValoresSerie valores) {
    final nuevas = List.of(series)..[indice] = valores;
    onSeries(nuevas);
  }

  void _borrar(int indice) => onSeries(List.of(series)..removeAt(indice));

  /// Añadir copia la última serie, que es el gesto más frecuente.
  void _anadir() => onSeries(
    List.of(series)..add(series.isEmpty ? _serieNueva : series.last),
  );

  Future<void> _nota(BuildContext context, int indice) async {
    final serie = series[indice];
    final texto = await ui.dialogoTexto(
      context,
      titulo: 'Nota de la serie ${indice + 1}',
      marcador: 'Fallo en la última, con ayuda…',
      valor: serie.nota ?? '',
      permitirVacio: true,
    );
    if (texto == null) return;

    _cambiar(
      indice,
      texto.trim().isEmpty
          ? serie.copiar(sinNota: true)
          : serie.copiar(nota: texto.trim()),
    );
  }

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
            onPressed: () {
              Navigator.pop(hoja);
              _nota(context, indice);
            },
            child: Text(serie.nota == null ? 'Añadir nota' : 'Editar la nota'),
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
                  ajustes: ajustes,
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
    required this.ajustes,
    required this.onSerie,
    required this.onMenu,
  });

  final int numero;
  final ValoresSerie serie;
  final Ajustes ajustes;
  final ValueChanged<ValoresSerie> onSerie;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: t.m, vertical: t.xs),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _principal(context),
        if (ajustes.esfuerzoActivo)
          _Esfuerzo(
            valor: serie.rpe,
            escala: ajustes.escala,
            onValor: (valor) => onSerie(
              valor == null
                  ? serie.copiar(sinRpe: true)
                  : serie.copiar(rpe: valor),
            ),
          ),
        if (serie.nota case final nota?)
          Padding(
            padding: const EdgeInsets.only(left: 26, bottom: t.xs),
            child: Text(
              nota,
              style: ui.estilo(
                context,
                size: t.caption,
                color: context.textoSec,
              ),
            ),
          ),
      ],
    ),
  );

  Widget _principal(BuildContext context) => Row(
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
        child: Icon(CupertinoIcons.ellipsis, size: 18, color: context.textoSec),
      ),
    ],
  );
}

/// Esfuerzo percibido de una serie, en la escala elegida en Ajustes.
///
/// Son nueve valores (de 6 a 10 en medios puntos) más el «—» de quitarlo: un
/// `CupertinoSlidingSegmentedControl` con diez segmentos no cabe en un móvil,
/// así que van como píldoras en una fila que se desplaza.
class _Esfuerzo extends StatelessWidget {
  const _Esfuerzo({
    required this.valor,
    required this.escala,
    required this.onValor,
  });

  /// Siempre en escala RPE, aunque se muestre como RIR.
  final double? valor;

  final EscalaEsfuerzo escala;
  final ValueChanged<double?> onValor;

  static const _valores = [6.0, 6.5, 7.0, 7.5, 8.0, 8.5, 9.0, 9.5, 10.0];

  String _etiqueta(double rpe) => switch (escala) {
    EscalaEsfuerzo.rpe => formato.numero(rpe),
    EscalaEsfuerzo.rir => formato.numero(10 - rpe),
  };

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 26, bottom: t.xs),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Text(
            escala == EscalaEsfuerzo.rir ? 'RIR' : 'RPE',
            style: ui.estilo(context, size: t.caption, color: context.textoSec),
          ),
          const SizedBox(width: t.s),
          _pildora(context, '—', valor == null, () => onValor(null)),
          for (final v in _valores)
            _pildora(context, _etiqueta(v), valor == v, () => onValor(v)),
        ],
      ),
    ),
  );

  Widget _pildora(
    BuildContext context,
    String etiqueta,
    bool elegida,
    VoidCallback onTap,
  ) => Padding(
    padding: const EdgeInsets.only(right: t.xs),
    child: CupertinoButton(
      onPressed: onTap,
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      child: ui.Pildora(
        etiqueta,
        relleno: elegida ? context.acento : context.relleno,
        color: elegida ? CupertinoColors.white : context.textoSec,
      ),
    ),
  );
}
