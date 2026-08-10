/// El motor de la sincronización en la app: cuándo se dispara y qué hace al
/// fallar.
///
/// Es el gemelo de `copia_automatica.dart` y tiene su misma forma, incluidas las
/// dos reglas heredadas de `descanso.dart` que allí costaron un fallo cada una:
/// el `Timer` se cancela en el acto al desmontar, y no se escribe el estado del
/// provider cuando el `ProviderScope` puede haberse ido (`ref.mounted`).
///
/// **No sabe qué proveedor hay detrás.** Habla con [SincroTransporte], con
/// `MotorSincro` —que es quien reconcilia— y con `AppBD`. Eso es lo que permite
/// probar los disparadores, la espera creciente y el primer enlace contra el
/// transporte falso, sin red y sin cuenta.
///
/// **Nada de esto se ve en la ruta de entrenar.** El disparador de guardar salta
/// después de cerrar la sesión, va sin esperar y corta solo si hay un borrador
/// vivo; un fallo se anota y se enseña más tarde, en la cabecera de Rutinas.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/ajustes.dart';
import '../datos/bd.dart';
import '../datos/reloj.dart' as reloj;
import '../datos/sincro/enlace.dart';
import '../datos/sincro/motor.dart';
import '../datos/sincro/transporte.dart';
import 'providers.dart';

/// Qué ha provocado el intento.
///
/// Va con nombre propio y no reutiliza el `Disparador` de la copia automática a
/// propósito: son **dos costuras independientes** y ninguna debe depender de la
/// otra, igual que `MotivoSincro` va repetido frente a `MotivoFallo`. Además,
/// `raiz.dart` importa los dos motores y con el mismo nombre el import sería
/// ambiguo.
enum DisparadorSincro {
  /// Al arrancar la app, después del catálogo y sin bloquear el primer frame.
  arranque,

  /// Al volver del segundo plano.
  vuelta,

  /// Al guardar un entrenamiento: el cambio que de verdad importa, y el momento
  /// en que el usuario acaba de salir del gimnasio.
  guardado,

  /// El botón «Sincronizar ahora» de Ajustes.
  manual,
}

/// Lo mínimo entre dos pasadas por volver del segundo plano.
///
/// Sin esto, alternar entre la app y WhatsApp diez veces seguidas dispararía
/// diez pasadas.
const minimoEntreVueltasSincro = Duration(minutes: 5);

/// La espera creciente ante un fallo temporal.
///
/// Cuatro intentos y para hasta el siguiente disparador. Sin tope sería el modo
/// de agotar una batería y una cuota gratuita el mismo día.
const esperasReintentoSincro = <Duration>[
  Duration(seconds: 5),
  Duration(seconds: 30),
  Duration(minutes: 2),
  Duration(minutes: 10),
];

/// Cuánto puede pasar sin una pasada buena antes de avisar en la cabecera.
const margenDeAviso = Duration(days: 1);

/// El estado de la sincronización tal y como lo pinta la interfaz.
class VistaSincro {
  const VistaSincro({
    this.estado = AppBD.sinSincronizar,
    this.sesion,
    this.activa = false,
    this.enMarcha = false,
    this.disponible = false,
    this.enlacePendiente = false,
    this.avisos = const [],
    this.cambios = 0,
  });

  /// La contabilidad de la última pasada, de la tabla `sincro_estado`.
  final EstadoSincro estado;

  /// La cuenta, o `null` si no hay ninguna.
  final SesionRemota? sesion;

  /// El interruptor «Sincronizar» de este dispositivo.
  final bool activa;

  /// Hay una pasada en curso ahora mismo.
  final bool enMarcha;

  /// Si la app se compiló con servicio configurado. Cuando es `false` el grupo
  /// de Ajustes **no aparece**: un fork o una compilación local funcionan sin
  /// tocar nada, igual que hoy ponen `local` en la versión.
  final bool disponible;

  /// Hay datos a los dos lados y el usuario todavía no ha dicho cuál manda.
  ///
  /// Mientras esté puesto **no se sincroniza**: una pasada normal aplicaría la
  /// salida «fusionar» sin haberla preguntado, y aunque fusionar es la
  /// recomendada y no pierde nada, elegir por el usuario en el único punto del
  /// bloque donde K7 exige preguntar sería justo lo que no hay que hacer.
  ///
  /// Es transitorio y no se persiste: si la app se cierra con la pregunta a
  /// medias, la pasada siguiente fusiona, que es la salida recomendada y la
  /// única de las tres que no destruye nada.
  final bool enlacePendiente;

  /// Los avisos de la última pasada, ya decodificados.
  ///
  /// Se parsean aquí y no en el `build` de la pantalla: el JSON es el mismo
  /// hasta la pasada siguiente y no hay motivo para releerlo en cada repintado.
  final List<AvisoSincro> avisos;

  /// Cuántas veces ha cambiado la base por debajo de la interfaz.
  ///
  /// Solo sube. `raiz.dart` lo escucha y llama a `invalidarTodo` cuando crece,
  /// que es cómo se repinta la app tras una pasada de fondo sin que este motor
  /// —que tiene un `Ref`, no un `WidgetRef`— tenga que invalidar nada.
  final int cambios;

  bool get conectado => sesion != null;

  /// Si hay que enseñar la línea de aviso en la cabecera de Rutinas.
  ///
  /// K8 decía «falló o hay cambios pendientes desde hace más de un día». Lo
  /// segundo se aproxima con «no ha habido una pasada buena en más de un día»:
  /// contar lo pendiente son siete consultas en cada repintado de la pestaña por
  /// la que se entra a la app, y lo que el usuario acaba viendo es lo mismo.
  bool avisar({required DateTime ahora}) {
    if (!disponible || !conectado || !activa) return false;
    if (estado.ultimoError != null) return true;
    final ultima = estado.ultimaSincro;
    return ultima == null || ahora.difference(ultima) > margenDeAviso;
  }

  /// Lo único que cambia fuera de [Sincronizador.refrescar], que reconstruye la
  /// vista entera leyendo de la base.
  VistaSincro copiar({
    bool? enMarcha,
    bool? enlacePendiente,
    bool masCambios = false,
  }) => VistaSincro(
    estado: estado,
    sesion: sesion,
    activa: activa,
    enMarcha: enMarcha ?? this.enMarcha,
    disponible: disponible,
    enlacePendiente: enlacePendiente ?? this.enlacePendiente,
    avisos: avisos,
    cambios: masCambios ? cambios + 1 : cambios,
  );
}

class Sincronizador extends Notifier<VistaSincro> {
  Timer? _reintento;

  /// Cuántos fallos temporales seguidos lleva, para elegir la espera.
  int _fallos = 0;

  /// Cuándo fue la última pasada, para el mínimo de [minimoEntreVueltasSincro].
  DateTime? _ultimoIntento;

  SincroTransporte? get _transporte => ref.read(sincroProvider);

  AppBD get _bd => ref.read(bdProvider);

  @override
  VistaSincro build() {
    ref.onDispose(_pararReintento);
    final disponible = ref.read(sincroProvider) != null;

    // El estado se carga aparte y **no con `ref.watch` de un provider async**,
    // por lo mismo que en la copia automática: si `build` dependiera de una
    // consulta, cada resolución reconstruiría el estado y podría pisar lo que
    // una pasada en curso acabara de escribir.
    if (disponible) unawaited(refrescar());

    return VistaSincro(disponible: disponible);
  }

  /// Vuelve a leer la cuenta, el interruptor y la contabilidad.
  Future<void> refrescar() async {
    final transporte = _transporte;
    if (transporte == null) return;

    // `sesionActual` no toca la red: sale del almacén seguro.
    final sesion = await transporte.sesionActual();
    final estado = await _bd.estadoSincro();
    final activa = (await _bd.ajustesCrudos())[Claves.sincroActiva] == '1';
    if (!ref.mounted) return;

    state = VistaSincro(
      estado: estado,
      sesion: sesion,
      activa: activa,
      enMarcha: state.enMarcha,
      disponible: true,
      enlacePendiente: state.enlacePendiente,
      avisos: _avisosDe(estado.avisos),
      cambios: state.cambios,
    );
  }

  /// Los avisos que dejó la última pasada, tolerando un JSON que no valga: es
  /// contabilidad, y no puede impedir que la pantalla se pinte.
  List<AvisoSincro> _avisosDe(String json) {
    try {
      final lista = jsonDecode(json);
      if (lista is! List) return const [];
      return [
        for (final entrada in lista)
          if (entrada is Map<String, Object?>) ?AvisoSincro.deJson(entrada),
      ];
    } on Object {
      return const [];
    }
  }

  // ── La cuenta ──────────────────────────────────────────────────────────────

  /// Crea la cuenta y entra en ella. Como [entrar] en todo lo demás.
  ///
  /// Lanza [ErrorSincro] si el correo ya tiene cuenta o si el servidor no admite
  /// cuentas nuevas: eso lo enseña la pantalla.
  Future<ResumenLados?> registrar(String correo, String contrasena) =>
      _entrar((t) => t.registrar(correo, contrasena));

  /// Entra y enlaza. Devuelve las cifras de los dos lados **si hay que
  /// preguntar**, y `null` si el enlace ya está hecho.
  ///
  /// Lanza [ErrorSincro] si las credenciales no valen: eso lo enseña la pantalla.
  Future<ResumenLados?> entrar(String correo, String contrasena) =>
      _entrar((t) => t.entrar(correo, contrasena));

  Future<ResumenLados?> _entrar(
    Future<SesionRemota> Function(SincroTransporte) abrir,
  ) async {
    final transporte = _transporte;
    if (transporte == null) return null;

    await abrir(transporte);
    // El interruptor se enciende al entrar: quien acaba de crear una cuenta
    // quiere sincronizar, y pedírselo dos veces sería preguntar por preguntar.
    await _bd.fijarAjustes({Claves.sincroActiva: '1'});
    await refrescar();
    return enlazar();
  }

  /// El primer enlace ([K7]). Sin [estrategia], solo actúa si no hay nada que
  /// decidir; si lo hay, devuelve las cifras para que la pantalla pregunte.
  ///
  /// La decisión llega como **valor de retorno y no como excepción**:
  /// `DecisionPendiente` existe para que olvidarse salte en un test, y este es
  /// justamente el sitio que no puede olvidarse.
  Future<ResumenLados?> enlazar({
    EstrategiaEnlace? estrategia,
    Future<void> Function()? respaldoPrevio,
  }) async {
    final transporte = _transporte;
    if (transporte == null) return null;

    _marcar(enMarcha: true);
    try {
      await Enlace(
        _bd,
        transporte,
      ).enlazar(estrategia: estrategia, respaldoPrevio: respaldoPrevio);
      _fallos = 0;
      await refrescar();
      _marcar(enMarcha: false, enlacePendiente: false, masCambios: true);
      return null;
    } on DecisionPendiente catch (e) {
      _marcar(enMarcha: false, enlacePendiente: true);
      return e.lados;
    } on Object {
      _marcar(enMarcha: false);
      await refrescar();
      rethrow;
    }
  }

  /// Cierra la sesión. Con [borrandoDatos] se lleva también lo de este móvil,
  /// que es lo que hace falta en un teléfono que se vende o se presta.
  ///
  /// Sin él, **la base local queda intacta y utilizable**: la nube es una copia,
  /// no el original.
  Future<void> salir({bool borrandoDatos = false}) async {
    _pararReintento();
    _fallos = 0;
    try {
      await _transporte?.salir();
    } on ErrorSincro {
      // Salir es lo que el usuario pidió. Que el servidor no se entere hoy no
      // puede dejarle la cuenta abierta aquí.
    }

    if (borrandoDatos) await _bd.borrarTodosLosDatos();

    // Los cursores a cero: si mañana se entra con otra cuenta, un cursor viejo
    // haría que la primera pasada se saltara el delta entero y el móvil se
    // quedaría con la mitad de los datos sin que nada avisara.
    await _bd.fijarEstadoSincro(
      cursorSubida: const Value(0),
      cursorBajada: const Value(0),
      ultimaSincro: const Value(null),
      subidas: const Value(0),
      bajadas: const Value(0),
      avisos: const Value('[]'),
      ultimoError: const Value(null),
    );
    await _bd.fijarAjustes({Claves.sincroActiva: ''});
    await refrescar();
    _marcar(enlacePendiente: false, masCambios: true);
  }

  /// Borra la cuenta del servidor. **Los datos locales no se tocan.**
  Future<void> borrarCuenta() async {
    final transporte = _transporte;
    if (transporte == null) return;
    await transporte.borrarCuenta();
    await salir();
  }

  /// Enciende o apaga la sincronización en este dispositivo.
  Future<void> activar(bool valor) async {
    await _bd.fijarAjustes({Claves.sincroActiva: valor ? '1' : ''});
    await refrescar();
    if (valor) await intentar(DisparadorSincro.manual);
  }

  // ── Las pasadas ────────────────────────────────────────────────────────────

  Future<void> intentar(DisparadorSincro disparador) async {
    final transporte = _transporte;
    if (transporte == null || state.enMarcha) return;
    if (!state.activa || !state.conectado) return;
    // Con la pregunta del primer enlace sin contestar no se toca nada: ver la
    // nota de `VistaSincro.enlacePendiente`.
    if (state.enlacePendiente) return;

    final ahora = reloj.ahora();

    if (disparador != DisparadorSincro.manual) {
      // Nunca durante una sesión viva: el borrador se reescribe cada dos
      // segundos y pelearse con el disco ahí no aporta nada. Al guardar el
      // entrenamiento el borrador ya no está, así que el disparador que importa
      // no se pierde por esto.
      if (await _bd.sesionActiva() != null) return;

      final ultimo = _ultimoIntento;
      if (disparador == DisparadorSincro.vuelta &&
          ultimo != null &&
          ahora.difference(ultimo) < minimoEntreVueltasSincro) {
        return;
      }
    }

    // Un disparo nuevo manda sobre la espera creciente en curso.
    _pararReintento();
    _ultimoIntento = ahora;
    await _pasada(transporte);
  }

  /// Una pasada completa. **Nunca lanza**: un fallo de sincronización es un
  /// aviso, no un error, y menos todavía en la ruta de entrenar.
  Future<void> _pasada(SincroTransporte transporte) async {
    _marcar(enMarcha: true);
    try {
      final resultado = await MotorSincro(_bd, transporte).sincronizar();
      _fallos = 0;
      await refrescar();
      _marcar(enMarcha: false, masCambios: resultado.algoCambio);
    } on ErrorSincro catch (e) {
      // `MotorSincro` ya dejó anotado el error en la tabla; aquí solo se decide
      // si vuelve a intentarse. Reintentar un permiso revocado no lo arregla
      // nunca y gasta batería y cuota.
      await refrescar();
      _marcar(enMarcha: false);
      if (e.seReintenta) _programarReintento();
    } on Object catch (e) {
      // Cualquier otra cosa —un fallo de la base, por ejemplo— se trata como
      // permanente: reintentarla no la arregla y el usuario tiene que verla
      // escrita en algún sitio.
      await _bd.fijarEstadoSincro(ultimoError: Value('$e'));
      await refrescar();
      _marcar(enMarcha: false);
    }
  }

  void _programarReintento() {
    if (_fallos >= esperasReintentoSincro.length) return;
    final espera = esperasReintentoSincro[_fallos];
    _fallos++;

    _pararReintento();
    _reintento = Timer(espera, () {
      if (!ref.mounted) return;
      // Se reintenta como «manual» a propósito: el mínimo entre vueltas ya se
      // comprobó en el intento que falló, y volver a exigirlo dejaría el
      // reintento sin efecto justo cuando hace falta.
      intentar(DisparadorSincro.manual);
    });
  }

  /// Para la espera creciente sin tocar el estado. Es lo que necesita
  /// `ref.onDispose`: el `Timer` tiene que morir en ese instante.
  void _pararReintento() {
    _reintento?.cancel();
    _reintento = null;
  }

  void _marcar({
    bool? enMarcha,
    bool? enlacePendiente,
    bool masCambios = false,
  }) {
    if (!ref.mounted) return;
    state = state.copiar(
      enMarcha: enMarcha,
      enlacePendiente: enlacePendiente,
      masCambios: masCambios,
    );
  }
}
