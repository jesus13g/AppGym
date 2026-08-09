/// El motor de la copia automática: cuándo se dispara y qué hace al fallar.
///
/// Es el único sitio con estado mutable de esta funcionalidad, igual que
/// `descanso.dart` lo es del temporizador, y por el mismo motivo: la copia tiene
/// que sobrevivir a navegar entre pantallas y no puede vivir en el estado de un
/// widget.
///
/// **No sabe que Google existe.** Habla con [DestinoNube] y con `AppBD`, y la
/// decisión de si toca copiar la toma `datos/copia_automatica.dart`, que es puro.
/// Eso es lo que permite probar los ocho casos que importan contra un destino
/// falso, sin red y sin cuenta.
///
/// Dos reglas heredadas de `descanso.dart`, que allí costaron un fallo cada una:
/// el `Timer` se cancela en el acto al desmontar, y no se escribe el estado del
/// provider cuando el `ProviderScope` puede haberse ido (`ref.mounted`).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/ajustes.dart';
import '../datos/bd.dart';
import '../datos/copia.dart' as copia;
import '../datos/copia_automatica.dart';
import '../datos/nube/nube.dart';
import '../datos/reloj.dart' as reloj;
import 'providers.dart';

/// Qué ha provocado el intento.
///
/// Viaja como enumerado y no como bandera suelta porque cada uno tiene reglas
/// distintas: solo [manual] se salta el «le toca», y solo [vuelta] tiene el
/// mínimo de cinco minutos.
enum Disparador {
  /// Al arrancar la app, después del catálogo y sin bloquear el primer frame.
  arranque,

  /// Al volver del segundo plano.
  vuelta,

  /// Al guardar un entrenamiento: el cambio que de verdad importa, y el momento
  /// en que el usuario acaba de salir del gimnasio.
  guardado,

  /// El botón «Copiar ahora» de Ajustes.
  manual,
}

/// Lo mínimo entre dos intentos por volver del segundo plano.
///
/// Sin esto, alternar entre la app y WhatsApp diez veces seguidas dispararía
/// diez exportaciones del histórico entero.
const minimoEntreVueltas = Duration(minutes: 5);

/// La espera creciente ante un fallo temporal.
///
/// Cuatro intentos y para hasta el siguiente disparador. Sin tope sería el modo
/// de agotar una batería y una cuota el mismo día, y con los disparadores que
/// hay —arranque, vuelta y guardar— nunca pasa mucho hasta el siguiente.
const esperasReintento = <Duration>[
  Duration(seconds: 5),
  Duration(seconds: 30),
  Duration(minutes: 2),
  Duration(minutes: 10),
];

/// El estado de la copia automática tal y como lo pinta la interfaz.
class VistaCopiaAutomatica {
  const VistaCopiaAutomatica({
    required this.estado,
    this.enMarcha = false,
    this.disponible = false,
  });

  final EstadoCopiaAutomatica estado;

  /// Hay una copia subiéndose ahora mismo.
  final bool enMarcha;

  /// Si la app se compiló con destino configurado. Cuando es `false` el grupo
  /// de Ajustes **no aparece**: un fork o una compilación local funcionan sin
  /// tocar nada, igual que hoy ponen `local` en la versión.
  final bool disponible;

  bool get conectado => estado.conectado;
}

class MotorCopiaAutomatica extends Notifier<VistaCopiaAutomatica> {
  Timer? _reintento;

  /// Cuántos fallos temporales seguidos lleva, para elegir la espera.
  int _fallos = 0;

  /// Cuándo fue el último intento, para el mínimo de [minimoEntreVueltas].
  DateTime? _ultimoIntento;

  DestinoNube? get _nube => ref.read(nubeProvider);

  AppBD get _bd => ref.read(bdProvider);

  @override
  VistaCopiaAutomatica build() {
    ref.onDispose(_pararReintento);
    final disponible = ref.read(nubeProvider) != null;

    // El estado se carga aparte y **no con `ref.watch` de un provider async**:
    // si `build` dependiera de una consulta, cada resolución volvería a
    // construir el estado y podría pisar lo que una copia en curso acabara de
    // escribir. Mientras la carga llega se enseña «sin conectar», que es lo
    // correcto cuando todavía no se sabe.
    if (disponible) unawaited(refrescar());

    return VistaCopiaAutomatica(
      estado: const EstadoCopiaAutomatica(),
      disponible: disponible,
    );
  }

  /// Vuelve a leer el estado de la tabla.
  Future<void> refrescar() async {
    final estado = EstadoCopiaAutomatica.desdeMapa(await _bd.ajustesCrudos());
    if (!ref.mounted) return;
    state = VistaCopiaAutomatica(
      estado: estado,
      enMarcha: state.enMarcha,
      disponible: true,
    );
  }

  // ── Configuración ──────────────────────────────────────────────────────────

  /// Conecta una cuenta. Abre el navegador y espera a que el usuario vuelva.
  ///
  /// Al conectar se copia enseguida: quien acaba de encenderlo quiere ver que
  /// funciona, no esperar a mañana.
  Future<void> conectar(String mensajeVuelta) async {
    final nube = _nube;
    if (nube == null) return;

    try {
      final correo = await nube.conectar(mensajeVuelta);
      await _guardar({
        Claves.copiaNubeCuenta: correo,
        // Conectar sin elegir frecuencia dejaría una cuenta enlazada que no
        // copia nada, que es lo peor de los dos mundos: se enciende semanal,
        // que es la que sirve para casi todo el mundo.
        if (!state.estado.frecuencia.activa)
          Claves.copiaNubeFrecuencia: Frecuencia.semanal.name,
        Claves.copiaNubeError: '',
      });
      await intentar(Disparador.manual);
    } on ErrorNube catch (e) {
      await _guardar({Claves.copiaNubeError: e.mensaje});
    }
  }

  /// Revoca el permiso y olvida la cuenta. **Los datos locales no se tocan**, y
  /// lo que ya está en la nube tampoco: es del usuario.
  Future<void> desconectar() async {
    _pararReintento();
    await _nube?.desconectar();
    await _guardar({
      Claves.copiaNubeCuenta: '',
      Claves.copiaNubeUltima: '',
      Claves.copiaNubeError: '',
      Claves.copiaNubeFrecuencia: Frecuencia.no.name,
    });
  }

  Future<void> fijarFrecuencia(Frecuencia frecuencia) async {
    await _guardar({Claves.copiaNubeFrecuencia: frecuencia.name});
    if (frecuencia.activa) await intentar(Disparador.arranque);
  }

  // ── El intento ─────────────────────────────────────────────────────────────

  /// Sube una copia si toca. Nunca lanza: un fallo aquí es un aviso, no un
  /// error, y desde luego no puede romper la pantalla que lo disparó.
  Future<void> intentar(Disparador disparador) async {
    final nube = _nube;
    if (nube == null || state.enMarcha) return;

    final ahora = reloj.ahora();
    final estado = state.estado;
    if (!estado.conectado) return;

    if (disparador != Disparador.manual) {
      if (!toca(estado, ahora: ahora)) return;

      // Nunca durante una sesión viva: el borrador se reescribe cada dos
      // segundos y exportar el histórico entero ahí es pelearse con el disco
      // por nada. Al guardar el entrenamiento el borrador ya no está, así que
      // el disparador que importa no se pierde por esto.
      if (await _bd.sesionActiva() != null) return;

      final ultimo = _ultimoIntento;
      if (disparador == Disparador.vuelta &&
          ultimo != null &&
          ahora.difference(ultimo) < minimoEntreVueltas) {
        return;
      }
    }

    // Un disparo nuevo manda sobre la espera creciente en curso.
    _pararReintento();
    _ultimoIntento = ahora;
    await _copiar(nube, ahora);
  }

  Future<void> _copiar(DestinoNube nube, DateTime ahora) async {
    if (!ref.mounted) return;
    state = VistaCopiaAutomatica(
      estado: state.estado,
      enMarcha: true,
      disponible: true,
    );

    try {
      final datos = await copia.exportar(_bd);
      // Se serializa aquí y no en un isolate con `compute`, al revés que el
      // megabyte del catálogo en `semilla.dart`: una copia de años de
      // entrenamiento ronda el megabyte y `jsonEncode` la resuelve en unos
      // milisegundos, mientras que arrancar el isolate cuesta más que eso.
      // Sin indentar, que es la mitad de bytes que sube.
      final texto = jsonEncode(datos);

      await nube.subir(copia.nombreFichero(ahora), texto);
      await _rotar(nube);

      _fallos = 0;
      await _guardar({
        Claves.copiaNubeUltima: ahora.toIso8601String(),
        Claves.copiaNubeError: '',
      });
    } on ErrorNube catch (e) {
      await _guardar({Claves.copiaNubeError: e.mensaje});
      if (e.seReintenta) _programarReintento();
    } on Object catch (e) {
      // Cualquier otra cosa —un fallo de la base, por ejemplo— se trata como
      // permanente: reintentarla no la arregla y el usuario tiene que verla
      // escrita en algún sitio.
      await _guardar({Claves.copiaNubeError: '$e'});
    } finally {
      if (ref.mounted) {
        state = VistaCopiaAutomatica(estado: state.estado, disponible: true);
      }
    }
  }

  /// Borra las copias que sobran, sin dejar que un fallo al rotar cuente como
  /// fallo de la copia: la copia ya está subida, que es lo que importaba.
  Future<void> _rotar(DestinoNube nube) async {
    try {
      for (final sobra in sobrantes(await nube.listar())) {
        await nube.borrar(sobra.id);
      }
    } on ErrorNube {
      // Nada. La próxima vez se vuelve a intentar y mientras tanto hay copias
      // de más, que es el lado bueno en el que equivocarse.
    }
  }

  void _programarReintento() {
    if (_fallos >= esperasReintento.length) return;
    final espera = esperasReintento[_fallos];
    _fallos++;

    _pararReintento();
    _reintento = Timer(espera, () {
      if (!ref.mounted) return;
      // Se reintenta como «manual» a propósito: «le toca» ya se comprobó en el
      // intento que falló, y volver a exigirlo dejaría el reintento sin efecto
      // cuando la copia de hoy ya se dio por pendiente.
      intentar(Disparador.manual);
    });
  }

  /// Para la espera creciente sin tocar el estado. Es lo que necesita
  /// `ref.onDispose`: el `Timer` tiene que morir en ese instante.
  void _pararReintento() {
    _reintento?.cancel();
    _reintento = null;
  }

  /// Escribe en la tabla y refresca el estado. Un valor vacío borra la clave
  /// del punto de vista de `EstadoCopiaAutomatica`, que trata `''` como `null`.
  Future<void> _guardar(Map<String, String> valores) async {
    await _bd.fijarAjustes(valores);
    await refrescar();
  }
}

final motorCopiaProvider =
    NotifierProvider<MotorCopiaAutomatica, VistaCopiaAutomatica>(
      MotorCopiaAutomatica.new,
    );
