/// Copia automática: cuándo toca, qué se rota y cuándo hay que avisar.
///
/// Es el cuarto módulo puro del proyecto, con la misma forma que
/// `metricas.dart`, `musculos.dart` y `progresion.dart`: **no importa Flutter,
/// no escribe en la base y no toca la red**. Recibe el estado guardado y una
/// fecha, y devuelve decisiones. Así todo lo que de verdad decide algo se
/// prueba con fechas escritas a mano, sin cuenta y sin conexión.
///
/// Lo que hay aquí es la mitad barata de la Fase 8a. La otra —el destino— vive
/// detrás de `nube/nube.dart`.
///
/// **Esto no es sincronización y la interfaz no debe llamarlo así.** Es una
/// copia de seguridad con fecha, subida sola. Dos dispositivos que escriban el
/// mismo día se pisan, y eso es aceptable porque el caso de uso es restaurar en
/// un móvil nuevo, no entrenar en dos a la vez.
library;

import 'ajustes.dart';
import 'metricas.dart' show lunesDe;
import 'nube/nube.dart';

/// Cada cuánto se sube una copia.
///
/// El valor de fábrica es [no]: la copia automática se enciende a mano, como
/// todo lo que saca datos del dispositivo.
enum Frecuencia {
  no,
  diaria,
  semanal,
  mensual;

  bool get activa => this != Frecuencia.no;
}

/// Cuántas copias se conservan en la nube.
///
/// No es configurable a propósito: es el número por debajo del cual la rotación
/// deja de proteger de nada y por encima del cual nadie mira. Con la frecuencia
/// semanal son dos meses y medio de histórico recuperable.
const copiasQueSeConservan = 10;

/// El estado de la copia automática en **este** dispositivo.
///
/// Vive en la tabla `ajustes` porque ahí ya hay una tabla clave/valor, pero
/// **no son preferencias del usuario** y por eso no las interpreta
/// `Ajustes.desdeMapa`: son estado de este móvil. De ahí que estén en
/// `Claves.locales` y que `copia.exportar` las deje fuera — restaurar una copia
/// en un móvil nuevo no debe traerse la cuenta ni la carpeta del viejo.
///
/// El *refresh token* **no está aquí**: va al almacén seguro de la plataforma
/// (`nube/token.dart`). La tabla `ajustes` se exporta entera en la copia de
/// seguridad, y un token dentro de un JSON que el usuario comparte por correo
/// es una fuga.
class EstadoCopiaAutomatica {
  const EstadoCopiaAutomatica({
    this.frecuencia = Frecuencia.no,
    this.cuenta,
    this.ultima,
    this.error,
  });

  /// Interpreta las filas de la tabla. Lo que falte o no se entienda se queda
  /// con su valor de fábrica, igual que en [Ajustes.desdeMapa]: una clave con
  /// basura no puede impedir que la app arranque.
  factory EstadoCopiaAutomatica.desdeMapa(Map<String, String> valores) {
    String? texto(String clave) {
      final valor = valores[clave];
      return valor == null || valor.isEmpty ? null : valor;
    }

    return EstadoCopiaAutomatica(
      frecuencia: switch (valores[Claves.copiaNubeFrecuencia]) {
        'diaria' => Frecuencia.diaria,
        'semanal' => Frecuencia.semanal,
        'mensual' => Frecuencia.mensual,
        _ => Frecuencia.no,
      },
      cuenta: texto(Claves.copiaNubeCuenta),
      ultima: DateTime.tryParse(valores[Claves.copiaNubeUltima] ?? ''),
      error: texto(Claves.copiaNubeError),
    );
  }

  final Frecuencia frecuencia;

  /// El correo conectado, solo para enseñarlo. `null` es «sin conectar».
  final String? cuenta;

  /// Cuándo se consiguió la última copia.
  final DateTime? ultima;

  /// El último fallo, o `null` si la última vez fue bien.
  final String? error;

  bool get conectado => cuenta != null;

  /// Cómo se escribe cada valor en la tabla. Es la vuelta de [desdeMapa].
  static String textoFrecuencia(Frecuencia frecuencia) => frecuencia.name;

  EstadoCopiaAutomatica copiaCon({
    Frecuencia? frecuencia,
    String? cuenta,
    DateTime? ultima,
    String? error,
  }) => EstadoCopiaAutomatica(
    frecuencia: frecuencia ?? this.frecuencia,
    cuenta: cuenta ?? this.cuenta,
    ultima: ultima ?? this.ultima,
    error: error ?? this.error,
  );
}

// ── Cuándo toca ──────────────────────────────────────────────────────────────

/// Si le toca subir una copia.
///
/// **Se decide por frontera natural, no por horas transcurridas.** Una copia a
/// las 23:50 no puede bloquear la del día siguiente, que es lo que pasaría con
/// un «hace menos de 24 h»: bastaría entrenar por la noche dos días seguidos
/// para saltarse una. Así que se compara el día, el lunes o el mes, que además
/// es lo que el usuario entiende por «diaria».
///
/// La semana empieza en lunes, con el [lunesDe] de `metricas.dart` y por su
/// mismo motivo: dos móviles del mismo usuario no pueden discrepar.
bool toca(EstadoCopiaAutomatica estado, {required DateTime ahora}) {
  if (!estado.frecuencia.activa || !estado.conectado) return false;

  final ultima = estado.ultima;
  // Conectado y sin ninguna copia todavía: la primera va en cuanto se pueda.
  if (ultima == null) return true;

  return switch (estado.frecuencia) {
    Frecuencia.no => false,
    Frecuencia.diaria => !_mismoDia(ultima, ahora),
    Frecuencia.semanal => lunesDe(ultima) != lunesDe(ahora),
    Frecuencia.mensual =>
      ultima.year != ahora.year || ultima.month != ahora.month,
  };
}

bool _mismoDia(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Cuánto dura un periodo de la frecuencia, para medir un retraso.
Duration periodoDe(Frecuencia frecuencia) => switch (frecuencia) {
  Frecuencia.no => Duration.zero,
  Frecuencia.diaria => const Duration(days: 1),
  Frecuencia.semanal => const Duration(days: 7),
  // Un mes no dura lo mismo siempre; 31 días es el techo, y aquí solo se usa
  // para decidir si hay que avisar de un retraso, no para calcular una fecha.
  Frecuencia.mensual => const Duration(days: 31),
};

// ── Qué se rota ──────────────────────────────────────────────────────────────

/// Las copias que sobran, de la más antigua en adelante.
///
/// Se conservan las [copiasQueSeConservan] más recientes. El orden se impone
/// aquí y no se confía en el que devuelva el proveedor.
///
/// **No puede borrar un fichero del usuario**, y eso no es una comprobación
/// sino una propiedad del permiso que se pide: con el ámbito `drive.file` la
/// app solo ve lo que ella misma creó, así que esta lista nunca contiene otra
/// cosa.
List<CopiaRemota> sobrantes(
  List<CopiaRemota> copias, {
  int conservar = copiasQueSeConservan,
}) {
  if (copias.length <= conservar) return const [];
  final ordenadas = [...copias]..sort((a, b) => b.creada.compareTo(a.creada));
  return ordenadas.sublist(conservar);
}

// ── Cuándo se avisa ──────────────────────────────────────────────────────────

/// Si hay que enseñar el aviso de la cabecera de Rutinas.
///
/// El modo de fallo real de esto no es que falle una vez: es que deje de
/// funcionar —permiso revocado, cuenta cerrada, la carpeta borrada— y nadie se
/// entere durante meses, hasta el día en que hace falta la copia. Por eso hay
/// un aviso, y por eso es lo único que se enseña fuera de Ajustes.
///
/// Se avisa cuando la copia está encendida y además:
///
///   - la última vez falló, o
///   - lleva **más de dos periodos** sin conseguirse ninguna.
///
/// Dos periodos y no uno para que un retraso normal —el móvil apagado el fin de
/// semana con la copia semanal— no encienda nada. Nada de un icono girando
/// permanente: copiar bien es lo normal y lo normal no se anuncia.
bool avisar(EstadoCopiaAutomatica estado, {required DateTime ahora}) {
  if (!estado.frecuencia.activa || !estado.conectado) return false;
  if (estado.error != null) return true;

  final ultima = estado.ultima;
  // Conectado, encendido y sin ninguna copia todavía no es motivo de aviso: el
  // primer disparador está a punto de hacerla.
  if (ultima == null) return false;

  return ahora.difference(ultima) > periodoDe(estado.frecuencia) * 2;
}
