/// Registro de un entrenamiento: series, repeticiones y peso por ejercicio.
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
const _porDefecto = UltimaSerie(series: 4, repeticiones: 10, peso: 20);

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
  /// id de ejercicio -> valores que se van a guardar.
  final _valores = <int, UltimaSerie>{};

  /// id de ejercicio -> si entra en el entrenamiento.
  final _incluidos = <int, bool>{};

  /// id de ejercicio -> lo que se registró la última vez, para la referencia.
  final _ultimas = <int, UltimaSerie?>{};

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
      // Se precarga lo último registrado, que casi siempre es lo que se repite.
      final ultima = await bd.ultimaSerieEjercicio(ejercicio.id);
      _ultimas[ejercicio.id] = ultima;
      _valores[ejercicio.id] = ultima ?? _porDefecto;
      _incluidos[ejercicio.id] = true;
    }

    if (mounted) setState(() => _ejercicios = ejercicios);
  }

  Future<void> _guardar() async {
    if (_guardando) return;

    final aGuardar = {
      for (final entrada in _valores.entries)
        if (_incluidos[entrada.key] ?? false) entrada.key: entrada.value,
    };
    if (aGuardar.isEmpty) {
      ui.aviso(context, 'Marca al menos un ejercicio');
      return;
    }

    setState(() => _guardando = true);
    final bien = await ref
        .read(bdProvider)
        .insertarEntrenamiento(widget.idRutina, DateTime.now(), aGuardar);
    if (!mounted) return;

    if (!bien) {
      setState(() => _guardando = false);
      ui.aviso(context, 'No se pudo guardar el entrenamiento');
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
                      child: _Tarjeta(
                        ejercicio: ejercicio,
                        ultima: _ultimas[ejercicio.id],
                        valores: _valores[ejercicio.id]!,
                        incluido: _incluidos[ejercicio.id] ?? true,
                        onIncluido: (valor) =>
                            setState(() => _incluidos[ejercicio.id] = valor),
                        onValores: (valor) => _valores[ejercicio.id] = valor,
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

/// Tarjeta de un ejercicio con sus tres steppers y el interruptor de incluir.
class _Tarjeta extends StatefulWidget {
  const _Tarjeta({
    required this.ejercicio,
    required this.ultima,
    required this.valores,
    required this.incluido,
    required this.onIncluido,
    required this.onValores,
  });

  final EjercicioConFicha ejercicio;
  final UltimaSerie? ultima;
  final UltimaSerie valores;
  final bool incluido;
  final ValueChanged<bool> onIncluido;
  final ValueChanged<UltimaSerie> onValores;

  @override
  State<_Tarjeta> createState() => _TarjetaState();
}

class _TarjetaState extends State<_Tarjeta> {
  /// Los tres steppers acumulan sus cambios aquí en vez de pisarse entre ellos.
  late UltimaSerie _actual = widget.valores;

  void _emitir(UltimaSerie nuevo) {
    _actual = nuevo;
    widget.onValores(nuevo);
  }

  @override
  Widget build(BuildContext context) {
    final ejercicio = widget.ejercicio;
    final ultima = widget.ultima;
    final incluido = widget.incluido;

    final referencia = ultima == null
        ? 'Primera vez con este ejercicio'
        : 'Último: ${ultima.series}×${ultima.repeticiones} · '
              '${formato.numero(ultima.peso)} kg';

    return Container(
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
                        referencia,
                        style: ui.estilo(
                          context,
                          size: t.caption,
                          color: context.textoSec,
                        ),
                      ),
                    ],
                  ),
                ),
                CupertinoSwitch(
                  value: incluido,
                  activeTrackColor: context.exito,
                  onChanged: widget.onIncluido,
                ),
              ],
            ),
          ),
          Container(height: 0.5, color: context.separador),
          AnimatedOpacity(
            opacity: incluido ? 1 : 0.35,
            duration: const Duration(milliseconds: 150),
            child: IgnorePointer(
              ignoring: !incluido,
              child: Column(
                children: [
                  ui.SelectorNumerico(
                    etiqueta: 'Series',
                    valor: widget.valores.series.toDouble(),
                    minimo: 1,
                    maximo: 20,
                    onChanged: (v) => _emitir(
                      UltimaSerie(
                        series: v.round(),
                        repeticiones: _actual.repeticiones,
                        peso: _actual.peso,
                      ),
                    ),
                  ),
                  Container(height: 0.5, color: context.separador),
                  ui.SelectorNumerico(
                    etiqueta: 'Repeticiones',
                    valor: widget.valores.repeticiones.toDouble(),
                    minimo: 1,
                    maximo: 50,
                    onChanged: (v) => _emitir(
                      UltimaSerie(
                        series: _actual.series,
                        repeticiones: v.round(),
                        peso: _actual.peso,
                      ),
                    ),
                  ),
                  Container(height: 0.5, color: context.separador),
                  ui.SelectorNumerico(
                    etiqueta: 'Peso',
                    valor: widget.valores.peso,
                    minimo: 0,
                    maximo: 400,
                    paso: 2.5,
                    unidad: 'kg',
                    decimales: 1,
                    onChanged: (v) => _emitir(
                      UltimaSerie(
                        series: _actual.series,
                        repeticiones: _actual.repeticiones,
                        peso: v,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
