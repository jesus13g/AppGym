/// Registro de un entrenamiento, en dos modos.
///
/// **Sesión viva** (`Modo.vivo`) es la de entrenar: arranca un cronómetro, cada
/// serie se marca conforme se completa, al marcarla salta el descanso y el
/// borrador se guarda solo, de forma que cerrar la app a mitad no se lleva la
/// hora que llevabas anotando. Al terminar se enseña el resumen de cierre.
///
/// **Formulario** (`Modo.formulario`) es la de siempre: se rellena entero y se
/// guarda al final. Sigue existiendo porque anotar el entrenamiento de ayer no
/// puede exigir un cronómetro, y porque editar una sesión guardada es eso
/// mismo. La diferencia está en el punto de entrada, no en un ajuste.
///
/// En ambos, cada serie es una fila con sus repeticiones y su peso: una
/// pirámide o un drop set se anotan tal y como se hicieron. Un ejercicio sin
/// series no se guarda.
library;

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/bd.dart';
import '../datos/borrador.dart';
import '../datos/formato.dart';
import '../datos/progresion.dart' as progresion;
import '../datos/reloj.dart' as reloj;
import '../estado/descanso.dart';
import '../estado/providers.dart';
import '../tema/tokens.dart';
import '../tema/tokens.dart' as t;
import '../tema/ui.dart' as ui;
import 'opciones_ejercicio.dart';
import 'resumen_sesion.dart';
import 'sugerencia.dart';

/// Cada cuánto se escribe el borrador en disco.
///
/// Sin esperar, cada toque de un selector sería una escritura: se anota una
/// serie de diez repeticiones a golpe de botón.
const _esperaBorrador = Duration(seconds: 2);

bool _mismoDia(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool _esHoy(DateTime fecha) => _mismoDia(fecha, DateTime.now());

/// Cómo se registra.
enum Modo {
  /// Entrenando ahora: cronómetro, series que se marcan y descanso.
  vivo,

  /// Anotando: se rellena y se guarda, sin reloj.
  formulario,
}

/// Empieza un entrenamiento en curso.
///
/// Con [borrador] se retoma una sesión que quedó a medias en vez de empezar de
/// cero.
Future<void> abrirEntrenar(
  BuildContext context,
  int idRutina, {
  Modo modo = Modo.vivo,
  SesionActiva? borrador,
  DateTime? fecha,
}) => Navigator.of(context, rootNavigator: true).push(
  CupertinoPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => PantallaEntrenar(
      idRutina: idRutina,
      modo: modo,
      borrador: borrador,
      fecha: fecha,
    ),
  ),
);

/// Anota una sesión pasada con el formulario de siempre.
///
/// Con [fecha] arranca en ese día en vez de en hoy, que es como se llega desde
/// una celda del calendario (C19).
Future<void> abrirRegistrarAnterior(
  BuildContext context,
  int idRutina, {
  DateTime? fecha,
}) => abrirEntrenar(context, idRutina, modo: Modo.formulario, fecha: fecha);

/// Reabre una sesión ya guardada para corregirla.
Future<void> abrirEditarEntrenamiento(
  BuildContext context,
  int idRutina,
  int idEntrenamiento,
) => Navigator.of(context, rootNavigator: true).push(
  CupertinoPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => PantallaEntrenar(
      idRutina: idRutina,
      idEntrenamiento: idEntrenamiento,
      modo: Modo.formulario,
    ),
  ),
);

class PantallaEntrenar extends ConsumerStatefulWidget {
  const PantallaEntrenar({
    super.key,
    required this.idRutina,
    this.idEntrenamiento,
    this.modo = Modo.formulario,
    this.borrador,
    this.fecha,
  });

  final int idRutina;

  /// Si viene informado se edita esa sesión en vez de crear una nueva.
  final int? idEntrenamiento;

  final Modo modo;

  /// Sesión a medias que se retoma. Solo tiene sentido en [Modo.vivo].
  final SesionActiva? borrador;

  /// Día en el que se registra. Sin él es hoy; al editar manda el guardado.
  final DateTime? fecha;

  @override
  ConsumerState<PantallaEntrenar> createState() => _PantallaEntrenarState();
}

class _PantallaEntrenarState extends ConsumerState<PantallaEntrenar> {
  /// id de ejercicio -> series que se van a guardar, en orden.
  final _series = <int, List<SerieEnCurso>>{};

  /// id de ejercicio -> lo que se registró la última vez, para la referencia.
  final _ultimas = <int, List<ValoresSerie>>{};

  /// Ejercicios cuya sugerencia se ha descartado. Viaja en el borrador.
  final _descartadas = <int>{};

  List<EjercicioConFicha>? _ejercicios;
  bool _guardando = false;

  /// Un día pasado se registra a las 12:00, igual que al elegirlo a mano en
  /// [_elegirFecha]: así el orden dentro del día no depende de a qué hora uno
  /// se acordó de anotarlo.
  late DateTime _fecha = switch (widget.fecha) {
    null => DateTime.now(),
    final elegida when _esHoy(elegida) => DateTime.now(),
    final elegida => DateTime(elegida.year, elegida.month, elegida.day, 12),
  };
  final _nota = TextEditingController();

  /// Cuándo empezó la sesión viva. En formulario no se usa.
  late DateTime _inicio = reloj.ahora();

  /// Repinta la cabecera del cronómetro una vez por segundo.
  Timer? _cronometro;

  /// Aplaza la escritura del borrador mientras se está tocando la pantalla.
  Timer? _guardadoBorrador;

  /// Guardado en un campo porque `dispose` lo necesita, y ahí `ref` ya no se
  /// puede tocar: cuelga del `BuildContext`, que para entonces está desactivado.
  DescansoNotifier? _descanso;

  bool get _editando => widget.idEntrenamiento != null;
  bool get _vivo => widget.modo == Modo.vivo;

  String get _titulo => switch (widget.modo) {
    _ when _editando => 'Editar entrenamiento',
    Modo.vivo => 'Entrenando',
    Modo.formulario => 'Registrar sesión',
  };

  @override
  void initState() {
    super.initState();
    _descanso = ref.read(descansoProvider.notifier);
    _cargar();
    if (_vivo) {
      _cronometro = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _cronometro?.cancel();
    _guardadoBorrador?.cancel();
    // Cerrar la pantalla cancela el descanso: dejar el `Timer` vivo es la fuga
    // clásica de esta funcionalidad, y aquí ya no hay nada que descansar.
    //
    // Al frame siguiente, no ahora: `saltar` escribe el estado del provider, y
    // hacerlo mientras se desmonta el árbol es justo lo que Riverpod prohíbe.
    // El `Timer` sí se para en el acto; lo que se aplaza es el repintado.
    if (_descanso case final descanso?) {
      descanso.pararReloj();
      WidgetsBinding.instance.addPostFrameCallback((_) => descanso.saltar());
    }
    _nota.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final bd = ref.read(bdProvider);
    final ajustes = await ref.read(ajustesProvider.future);
    final ejercicios = await bd.ejerciciosDeRutina(widget.idRutina);

    // Al editar se parte de lo que se guardó aquel día; los ejercicios de la
    // rutina que no se hicieron aparecen vacíos, por si faltó anotar alguno.
    final sesion = _editando ? await bd.sesion(widget.idEntrenamiento!) : null;
    final guardadas = sesion?.series ?? const <int, List<ValoresSerie>>{};
    if (sesion != null) {
      _fecha = sesion.fecha;
      _nota.text = sesion.nota ?? '';
    }

    // Una sesión recuperada manda sobre cualquier precarga: son las series que
    // el usuario ya tenía delante cuando se cerró la app.
    final recuperado = switch (widget.borrador) {
      final b? => Borrador.desdeJson(b.estado),
      _ => null,
    };
    if (widget.borrador case final b?) _inicio = b.inicio;
    if (recuperado != null) {
      _nota.text = recuperado.nota;
      _descartadas.addAll(recuperado.descartadas);
    }

    final serieNueva = ValoresSerie(
      repeticiones: ajustes.repeticionesPorDefecto,
      peso: 20,
    );

    for (final ejercicio in ejercicios) {
      final ultimas = await bd.ultimasSeriesEjercicio(ejercicio.id);
      _ultimas[ejercicio.id] = ultimas;

      if (recuperado?.series[ejercicio.id] case final enCurso?) {
        _series[ejercicio.id] = List.of(enCurso);
        continue;
      }

      // Se precargan las series de la última sesión —cuántas fueron incluido—,
      // que casi siempre es lo que se repite.
      final valores = switch (guardadas[ejercicio.id]) {
        final serie? => List.of(serie),
        _ when _editando => const <ValoresSerie>[],
        _ =>
          ultimas.isEmpty
              ? List.filled(ajustes.seriesPorDefecto, serieNueva)
              : List.of(ultimas),
      };
      _series[ejercicio.id] = [
        for (final v in valores) (valores: v, hecha: false),
      ];
    }

    if (mounted) setState(() => _ejercicios = ejercicios);
  }

  // ── Borrador ───────────────────────────────────────────────────────────────

  Borrador get _borrador =>
      Borrador(series: _series, nota: _nota.text, descartadas: _descartadas);

  /// Programa la escritura del borrador. Solo en sesión viva.
  void _apuntarBorrador() {
    if (!_vivo || _guardando) return;
    _guardadoBorrador?.cancel();
    _guardadoBorrador = Timer(_esperaBorrador, _escribirBorrador);
  }

  Future<void> _escribirBorrador() async {
    if (!mounted || _guardando) return;
    await ref
        .read(bdProvider)
        .guardarSesionActiva(widget.idRutina, _inicio, _borrador.aJson());
  }

  void _cambiarSeries(int idEjercicio, List<SerieEnCurso> series) {
    setState(() => _series[idEjercicio] = series);
    _apuntarBorrador();
  }

  /// Marca o desmarca una serie. Marcarla dispara el descanso.
  void _marcar(EjercicioConFicha ejercicio, int indice, bool hecha) {
    final series = List.of(_series[ejercicio.id] ?? const <SerieEnCurso>[]);
    if (indice >= series.length) return;

    series[indice] = (valores: series[indice].valores, hecha: hecha);
    _cambiarSeries(ejercicio.id, series);
    if (hecha) _empezarDescanso(ejercicio);
  }

  // ── Descanso ───────────────────────────────────────────────────────────────

  int _descansoDe(EjercicioConFicha ejercicio, Ajustes ajustes) =>
      ejercicio.ejercicio.descansoSeg ?? ajustes.descansoSeg;

  void _empezarDescanso(EjercicioConFicha ejercicio) {
    final ajustes = ref.read(ajustesProvider).value ?? const Ajustes();
    _descanso?.arrancar(_descansoDe(ejercicio, ajustes));
  }

  /// Abre las opciones propias del ejercicio: descanso y progresión.
  Future<void> _opciones(EjercicioConFicha ejercicio) async {
    final cambiado = await abrirOpcionesEjercicio(
      context,
      widget.idRutina,
      ejercicio.id,
    );
    if (!cambiado || !mounted) return;

    // La lista local se relee, o la tarjeta seguiría enseñando el valor viejo
    // hasta salir y volver a entrar. Es una consulta de una rutina; no compensa
    // reconstruir la fila a mano solo para ahorrársela.
    final refrescados = await ref
        .read(bdProvider)
        .ejerciciosDeRutina(widget.idRutina);
    if (!mounted) return;
    setState(() => _ejercicios = refrescados);
  }

  // ── Sugerencia de progresión ───────────────────────────────────────────────

  /// Reescribe las series precargadas con las que propone la sugerencia.
  ///
  /// **No guarda nada**: solo cambia los valores del formulario, que el usuario
  /// sigue pudiendo tocar uno a uno. Las series ya marcadas no se tocan; en
  /// sesión viva la línea desaparece en cuanto se marca la primera, así que en
  /// la práctica no hay ninguna.
  void _aplicarSugerencia(int idEjercicio, progresion.Sugerencia sugerencia) {
    setState(() {
      _series[idEjercicio] = [
        for (final v in sugerencia.series) (valores: v, hecha: false),
      ];
      _descartadas.add(idEjercicio);
    });
    _apuntarBorrador();
  }

  void _descartarSugerencia(int idEjercicio) {
    setState(() => _descartadas.add(idEjercicio));
    _apuntarBorrador();
  }

  // ── Fecha ──────────────────────────────────────────────────────────────────

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

    setState(() {
      _fecha = switch (elegida) {
        // Elegir el mismo día no debe mover la hora de una sesión ya guardada.
        _ when _mismoDia(elegida, _fecha) => _fecha,
        _ when _esHoy(elegida) => ahora,
        _ => DateTime(elegida.year, elegida.month, elegida.day, 12),
      };
    });
  }

  // ── Guardar y salir ────────────────────────────────────────────────────────

  Future<void> _guardar() async {
    if (_guardando) return;

    setState(() => _guardando = true);
    _guardadoBorrador?.cancel();

    final bd = ref.read(bdProvider);
    // En sesión viva solo cuentan las series marcadas: las que quedaron sin
    // hacer eran el plan, no el entrenamiento.
    final series = _borrador.paraGuardar(soloHechas: _vivo);

    final int? idGuardado;
    if (_editando) {
      final bien = await bd.actualizarEntrenamiento(
        widget.idEntrenamiento!,
        _fecha,
        series,
        nota: _nota.text,
      );
      idGuardado = bien ? widget.idEntrenamiento : null;
    } else {
      idGuardado = await bd.insertarEntrenamiento(
        widget.idRutina,
        _vivo ? reloj.ahora() : _fecha,
        series,
        nota: _nota.text,
        duracionSeg: _vivo ? _transcurrido.inSeconds : null,
        descartarBorrador: _vivo,
      );
    }
    if (!mounted) return;

    if (idGuardado == null) {
      setState(() => _guardando = false);
      ui.aviso(
        context,
        _vivo ? 'Marca al menos una serie' : 'Añade al menos una serie',
      );
      return;
    }

    invalidarEntrenamientos(ref, widget.idRutina);
    ref.invalidate(sesionActivaProvider);
    _descanso?.saltar();

    final navegador = Navigator.of(context);
    navegador.pop();
    // El resumen de cierre sustituye a la pantalla que se acaba de cerrar, no
    // se apila encima: al cerrarlo se vuelve a la rutina, no al registro.
    if (_vivo) await abrirResumenSesion(context, idGuardado);
  }

  Duration get _transcurrido => reloj.ahora().difference(_inicio);

  /// Cierra la sesión viva ofreciendo conservarla o tirarla.
  Future<void> _salirDeVivo() async {
    final elegido = await ui.elegirEnHoja<bool>(
      context,
      titulo: 'Dejar el entrenamiento',
      mensaje:
          'Si lo dejas para luego, al abrir la app te ofrecerá continuarlo '
          'donde lo dejaste.',
      opciones: const [
        (true, 'Seguir luego'),
        (false, 'Descartar el entrenamiento'),
      ],
    );
    if (elegido == null || !mounted) return;

    if (elegido.$1) {
      await _escribirBorrador();
    } else {
      await ref.read(bdProvider).descartarSesionActiva();
    }
    if (!mounted) return;

    ref.invalidate(sesionActivaProvider);
    Navigator.of(context).pop();
  }

  // ── Interfaz ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final rutina = ref.watch(rutinaProvider(widget.idRutina)).value;
    final f = formatoDe(context, ref);
    final descanso = ref.watch(descansoProvider);
    final ejercicios = _ejercicios;

    if (ejercicios != null && ejercicios.isEmpty) {
      return CupertinoPageScaffold(
        backgroundColor: context.fondo,
        navigationBar: ui.barra(
          context,
          titulo: _titulo,
          izquierda: _botonSalir(context),
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
        izquierda: _botonSalir(context),
        derecha: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          onPressed: _guardando ? null : _guardar,
          child: Text(
            _vivo ? 'Terminar' : 'Guardar',
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
          : Column(
              children: [
                Expanded(
                  child: SafeArea(
                    bottom: false,
                    child: _lista(context, ejercicios, rutina, f),
                  ),
                ),
                if (descanso != null)
                  ui.BarraDescanso(
                    reloj: descanso.reloj,
                    progreso: descanso.progreso,
                    excedido: descanso.excedido,
                    onMas: () => _descanso?.ajustar(ajusteDescanso),
                    onMenos: () => _descanso?.ajustar(-ajusteDescanso),
                    onSaltar: () => _descanso?.saltar(),
                  ),
              ],
            ),
    );
  }

  /// La sugerencia de un ejercicio, o `null` si aquí no toca enseñarla.
  ///
  /// Cuatro motivos para no pedirla, y el orden importa: **con la progresión
  /// apagada el provider ni se toca**, que es lo que garantiza que no se calcula
  /// nada. Editar una sesión guardada tampoco es sitio: lo que se está anotando
  /// ya pasó. Descartada no vuelve. Y en sesión viva desaparece al marcar la
  /// primera serie, que es la pantalla más densa de la app y la que menos admite
  /// un elemento de más.
  progresion.Sugerencia? _sugerenciaDe(
    EjercicioConFicha ejercicio,
    Ajustes ajustes,
  ) {
    if (!ajustes.progresionActiva) return null;
    if (_editando) return null;
    if (_descartadas.contains(ejercicio.id)) return null;
    if (_vivo && (_series[ejercicio.id] ?? const []).any((s) => s.hecha)) {
      return null;
    }

    return ref
        .watch(
          sugerenciaProvider((
            idRutina: widget.idRutina,
            idEjercicio: ejercicio.id,
          )),
        )
        .value;
  }

  Widget _lista(
    BuildContext context,
    List<EjercicioConFicha> ejercicios,
    Rutina? rutina,
    Formato f,
  ) => ListView(
    children: [
      _cabecera(context, rutina),
      for (final ejercicio in ejercicios)
        Padding(
          padding: const EdgeInsets.only(bottom: t.l),
          child: TarjetaEjercicio(
            ejercicio: ejercicio,
            ultimas: _ultimas[ejercicio.id] ?? const [],
            series: _series[ejercicio.id] ?? const [],
            formato: f,
            vivo: _vivo,
            descansoSeg: _descansoDe(ejercicio, f.ajustes),
            descansoPropio: ejercicio.ejercicio.descansoSeg != null,
            sugerencia: _sugerenciaDe(ejercicio, f.ajustes),
            onAplicarSugerencia: (s) => _aplicarSugerencia(ejercicio.id, s),
            onDescartarSugerencia: () => _descartarSugerencia(ejercicio.id),
            onSeries: (valor) => _cambiarSeries(ejercicio.id, valor),
            onMarcar: (indice, hecha) => _marcar(ejercicio, indice, hecha),
            onDescanso: () => _empezarDescanso(ejercicio),
            onCambiarDescanso: () => _opciones(ejercicio),
          ),
        ),
      ui.Grupo(
        cabecera: 'Notas',
        pie:
            'Lo que explique este entrenamiento dentro de tres semanas: '
            'molestias, cinturón, mal día.',
        filas: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: t.m, vertical: t.s),
            child: CupertinoTextField.borderless(
              controller: _nota,
              placeholder: 'Nota de la sesión',
              maxLines: null,
              minLines: 2,
              style: ui.estilo(context),
              onChanged: (_) => _apuntarBorrador(),
            ),
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.all(t.l),
        child: ui.BotonPrincipal(
          _vivo ? 'Terminar entrenamiento' : 'Guardar entrenamiento',
          icono: CupertinoIcons.check_mark,
          onPressed: _guardando ? null : _guardar,
        ),
      ),
      const SizedBox(height: t.xl),
    ],
  );

  /// Nombre de la rutina y, debajo, la fecha o el progreso de la sesión.
  Widget _cabecera(BuildContext context, Rutina? rutina) {
    final (hechas, total) = _borrador.progreso;

    return Padding(
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
            style: ui.estilo(context, size: t.title2, weight: t.bold),
          ),
          const SizedBox(height: 2),
          if (_vivo)
            Text(
              '$hechas / $total series · '
              '${formatoDe(context, ref).duracion(_transcurrido.inSeconds)}',
              style: ui.estilo(
                context,
                size: t.subhead,
                color: context.textoSec,
              ),
            )
          else
            CupertinoButton(
              onPressed: _elegirFecha,
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatoDe(context, ref).fechaLarga(_fecha),
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
    );
  }

  Widget _botonSalir(BuildContext context) => CupertinoButton(
    padding: EdgeInsets.zero,
    minimumSize: Size.zero,
    onPressed: _vivo ? _salirDeVivo : () => Navigator.of(context).pop(),
    child: Text(_vivo ? 'Dejarlo' : 'Cancelar'),
  );
}

/// Tarjeta de un ejercicio con la lista de sus series.
///
/// Es pública para poder montarla suelta en los tests de widget, que es donde
/// se vigila que la fila de controles no desborde en un móvil estrecho.
class TarjetaEjercicio extends StatelessWidget {
  const TarjetaEjercicio({
    super.key,
    required this.ejercicio,
    required this.ultimas,
    required this.series,
    required this.onSeries,
    required this.formato,
    this.vivo = false,
    this.descansoSeg = 90,
    this.descansoPropio = false,
    this.sugerencia,
    this.onAplicarSugerencia,
    this.onDescartarSugerencia,
    this.onMarcar,
    this.onDescanso,
    this.onCambiarDescanso,
  });

  final EjercicioConFicha ejercicio;

  /// Series de la última sesión, solo para la línea de referencia.
  final List<ValoresSerie> ultimas;

  final List<SerieEnCurso> series;
  final ValueChanged<List<SerieEnCurso>> onSeries;

  /// De aquí salen el idioma, la unidad, el paso del peso y si se pide el
  /// esfuerzo.
  final Formato formato;

  /// En sesión viva cada fila lleva su check y la tarjeta, su descanso.
  final bool vivo;

  final int descansoSeg;

  /// True si el valor de arriba es propio del ejercicio y no el global.
  final bool descansoPropio;

  /// Qué propone la app para hoy. `null` es lo normal las dos primeras veces
  /// que se hace un ejercicio, y entonces no se pinta nada.
  final progresion.Sugerencia? sugerencia;

  final void Function(progresion.Sugerencia sugerencia)? onAplicarSugerencia;
  final VoidCallback? onDescartarSugerencia;

  final void Function(int indice, bool hecha)? onMarcar;
  final VoidCallback? onDescanso;
  final VoidCallback? onCambiarDescanso;

  void _cambiar(int indice, ValoresSerie valores) => onSeries(
    List.of(series)..[indice] = (valores: valores, hecha: series[indice].hecha),
  );

  void _borrar(int indice) => onSeries(List.of(series)..removeAt(indice));

  /// Añadir copia la última serie, que es el gesto más frecuente.
  void _anadir() {
    final ultima = series.isEmpty
        ? ValoresSerie(
            repeticiones: formato.ajustes.repeticionesPorDefecto,
            peso: 20,
          )
        : series.last.valores;
    onSeries(List.of(series)..add((valores: ultima, hecha: false)));
  }

  Future<void> _nota(BuildContext context, int indice) async {
    final serie = series[indice].valores;
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
    final serie = series[indice].valores;
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
    return 'Último: ${formato.textos.comunSeries(ultimas.length)} · '
        '${formato.peso(volumen)}';
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
              ui.Miniatura(imagenEjercicio(ejercicio), tamano: 40),
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
              if (onCambiarDescanso != null) _botonDescanso(context),
            ],
          ),
        ),
        Container(height: 0.5, color: context.separador),
        if (sugerencia case final propuesta?) ...[
          LineaSugerencia(
            sugerencia: propuesta,
            formato: formato,
            onAplicar: onAplicarSugerencia == null
                ? null
                : () => onAplicarSugerencia!(propuesta),
            onDescartar: onDescartarSugerencia,
          ),
          Container(height: 0.5, color: context.separador),
        ],
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
                  serie: serie.valores,
                  hecha: serie.hecha,
                  formato: formato,
                  vivo: vivo,
                  onSerie: (valores) => _cambiar(indice, valores),
                  onMenu: () => _menu(context, indice),
                  onMarcar: () => onMarcar?.call(indice, !serie.hecha),
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

  /// Descanso del ejercicio: se toca para arrancarlo, se mantiene para
  /// cambiarlo.
  ///
  /// Es también el «botón de descanso» suelto de la especificación: en el
  /// formulario, donde no hay checks que lo disparen, es la única forma de
  /// echar a andar la cuenta atrás.
  Widget _botonDescanso(BuildContext context) => CupertinoButton(
    onPressed: onDescanso,
    onLongPress: onCambiarDescanso,
    padding: const EdgeInsets.symmetric(horizontal: t.s, vertical: t.xs),
    minimumSize: Size.zero,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          CupertinoIcons.timer,
          size: 18,
          color: descansoPropio ? context.acento : context.textoSec,
        ),
        Text(
          formato.descanso(descansoSeg),
          style: ui.estilo(
            context,
            size: t.caption,
            color: descansoPropio ? context.acento : context.textoSec,
          ),
        ),
      ],
    ),
  );
}

/// Una serie: número (o check), repeticiones, peso y su menú.
class _FilaSerie extends StatelessWidget {
  const _FilaSerie({
    required this.numero,
    required this.serie,
    required this.hecha,
    required this.formato,
    required this.vivo,
    required this.onSerie,
    required this.onMenu,
    required this.onMarcar,
  });

  final int numero;
  final ValoresSerie serie;
  final bool hecha;
  final Formato formato;
  final bool vivo;
  final ValueChanged<ValoresSerie> onSerie;
  final VoidCallback onMenu;
  final VoidCallback onMarcar;

  @override
  Widget build(BuildContext context) => Opacity(
    // Una serie hecha se atenúa: lo que queda por delante es lo que importa.
    opacity: hecha ? 0.55 : 1,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: t.m, vertical: t.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _principal(context),
          if (formato.ajustes.esfuerzoActivo)
            _Esfuerzo(
              valor: serie.rpe,
              formato: formato,
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
    ),
  );

  Widget _principal(BuildContext context) => Row(
    children: [
      if (vivo) ui.CheckSerie(hecha: hecha, onCambiar: onMarcar),
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
          // El selector trabaja en la unidad activa y devuelve kilos: es lo
          // único que sabe de libras en toda la pantalla.
          valor: formato.ajustes.paraSelector(serie.peso),
          minimo: 0,
          maximo: formato.ajustes.pesoMaximo,
          paso: formato.ajustes.pasoPeso,
          unidad: formato.ajustes.unidad.sufijo,
          decimales: formato.ajustes.decimalesPaso,
          onChanged: (v) =>
              onSerie(serie.copiar(peso: formato.ajustes.aKilos(v))),
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
    required this.formato,
    required this.onValor,
  });

  /// Siempre en escala RPE, aunque se muestre como RIR.
  final double? valor;

  final Formato formato;
  final ValueChanged<double?> onValor;

  EscalaEsfuerzo get escala => formato.ajustes.escala;

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
