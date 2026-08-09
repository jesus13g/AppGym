/// Preferencias de la app: claves, valores por defecto y tipado.
///
/// Viven en la tabla `ajustes` de la propia base de datos (clave/texto) y no en
/// un fichero aparte: así no hace falta otra dependencia y entran gratis en la
/// copia de seguridad junto al resto de los datos.
///
/// Todo se guarda como texto y se castea al leer. Esto es lo único que sabe
/// interpretar esos textos; `AppBD.ajustes()` se limita a traer las filas.
///
/// **El peso se guarda siempre en kilogramos.** Las libras son solo
/// presentación: convertir al mostrar y al introducir deja el histórico intacto
/// si el usuario cambia de unidad a mitad de camino, que es justo lo que
/// guardar en la unidad activa no permitiría.
library;

/// Unidad en la que se muestran los pesos. En la base siempre hay kilos.
enum Unidad {
  kg('kg'),
  lb('lb');

  const Unidad(this.sufijo);

  /// Lo que se escribe detrás del número.
  final String sufijo;
}

/// Un kilogramo en libras.
const factorLibras = 2.20462;

/// Escala con la que se pide el esfuerzo al registrar.
///
/// Solo cambia cómo se muestra: en la base siempre se guarda RPE.
enum EscalaEsfuerzo {
  /// 6–10, donde 10 es el fallo.
  rpe,

  /// Repeticiones en recámara: `RIR = 10 − RPE`, así que 0 es el fallo.
  rir,
}

/// Fórmula con la que se estima el máximo de una repetición.
///
/// Vive aquí, con el resto de los tipos de las preferencias, y no en
/// `metricas.dart`, que es quien la aplica: si estuviera allí, `ajustes.dart`
/// tendría que importar un módulo que a su vez importa `bd.dart`, que importa
/// este. Es el mismo sitio en el que están [EscalaEsfuerzo] y [Unidad], que
/// también las usa otro.
enum Formula {
  /// `peso × (1 + repeticiones / 30)`.
  epley,

  /// `peso × 36 / (37 − repeticiones)`, algo más conservadora en repeticiones
  /// altas.
  brzycki,
}

/// Cuánto se arriesga al proponer una progresión.
///
/// Vive aquí por el mismo motivo que [Formula]: es el tipo de una preferencia, y
/// si estuviera en `progresion.dart` este fichero tendría que importar un módulo
/// que a su vez importa `bd.dart`, que importa este.
enum Perfil {
  /// No sube de peso hasta ver el rango completo dos sesiones seguidas.
  conservador,

  /// Sube un escalón en cuanto el rango se completa.
  estandar,

  /// Con el rango completo y el esfuerzo bajo, sube dos escalones.
  agresivo,
}

/// Brillo de la interfaz.
enum Tema { sistema, claro, oscuro }

/// Claves de la tabla `ajustes`.
///
/// Son texto porque acaban en una columna de texto; cambiarlas equivale a
/// perder el valor guardado, así que no se tocan.
abstract final class Claves {
  static const unidad = 'unidad';
  static const pasoPeso = 'paso_peso';
  static const descanso = 'descanso_seg';
  static const sonidoDescanso = 'sonido_descanso';
  static const series = 'series_por_defecto';
  static const repeticiones = 'repeticiones_por_defecto';
  static const esfuerzoActivo = 'esfuerzo_activo';
  static const esfuerzoEscala = 'esfuerzo_escala';
  static const sesionesPorSemana = 'sesiones_por_semana';
  static const formula1RM = 'formula_1rm';
  static const tema = 'tema';
  static const progresionActiva = 'progresion_activa';
  static const repMin = 'rep_min';
  static const repMax = 'rep_max';
  static const perfilProgresion = 'perfil_progresion';

  /// Versión del índice de búsqueda del catálogo. No es una preferencia del
  /// usuario: vive aquí porque es el sitio donde ya hay una tabla clave/valor.
  static const versionIndice = 'version_indice';
}

/// Pasos de peso que se ofrecen, en la unidad activa.
const pasosPeso = <double>[0.5, 1, 1.25, 2.5, 5];

/// Descansos que se ofrecen, en segundos.
const descansos = <int>[30, 45, 60, 90, 120, 150, 180, 240, 300];

/// Las preferencias, ya interpretadas.
class Ajustes {
  const Ajustes({
    this.unidad = Unidad.kg,
    this.pasoPeso = 2.5,
    this.descansoSeg = 90,
    this.sonidoDescanso = true,
    this.seriesPorDefecto = 4,
    this.repeticionesPorDefecto = 10,
    this.esfuerzoActivo = false,
    this.escala = EscalaEsfuerzo.rpe,
    this.sesionesPorSemana = 3,
    this.formula = Formula.epley,
    this.tema = Tema.sistema,
    this.progresionActiva = true,
    this.repMinGlobal = 8,
    this.repMaxGlobal = 12,
    this.perfilProgresion = Perfil.estandar,
  });

  /// Interpreta las filas de la tabla. Lo que falte o no se entienda se queda
  /// con su valor por defecto, de modo que una clave con basura no rompe nada.
  factory Ajustes.desdeMapa(Map<String, String> valores) {
    const porDefecto = Ajustes();

    int entero(
      String clave,
      int siNo, {
      required int minimo,
      required int maximo,
    }) {
      final valor = int.tryParse(valores[clave] ?? '');
      if (valor == null || valor < minimo || valor > maximo) return siNo;
      return valor;
    }

    return Ajustes(
      unidad: valores[Claves.unidad] == 'lb' ? Unidad.lb : Unidad.kg,
      pasoPeso: switch (double.tryParse(valores[Claves.pasoPeso] ?? '')) {
        final paso? when pasosPeso.contains(paso) => paso,
        _ => porDefecto.pasoPeso,
      },
      descansoSeg: entero(
        Claves.descanso,
        porDefecto.descansoSeg,
        minimo: 15,
        maximo: 600,
      ),
      // Un ajuste booleano sin fila guardada vale su valor por defecto, que
      // aquí es «sí»: solo el '0' explícito lo apaga.
      sonidoDescanso: (valores[Claves.sonidoDescanso] ?? '1') == '1',
      seriesPorDefecto: entero(
        Claves.series,
        porDefecto.seriesPorDefecto,
        minimo: 1,
        maximo: 10,
      ),
      repeticionesPorDefecto: entero(
        Claves.repeticiones,
        porDefecto.repeticionesPorDefecto,
        minimo: 1,
        maximo: 30,
      ),
      esfuerzoActivo: valores[Claves.esfuerzoActivo] == '1',
      escala: valores[Claves.esfuerzoEscala] == 'rir'
          ? EscalaEsfuerzo.rir
          : EscalaEsfuerzo.rpe,
      sesionesPorSemana: entero(
        Claves.sesionesPorSemana,
        porDefecto.sesionesPorSemana,
        minimo: 1,
        maximo: 7,
      ),
      formula: valores[Claves.formula1RM] == 'brzycki'
          ? Formula.brzycki
          : Formula.epley,
      tema: switch (valores[Claves.tema]) {
        'claro' => Tema.claro,
        'oscuro' => Tema.oscuro,
        _ => Tema.sistema,
      },
      progresionActiva: (valores[Claves.progresionActiva] ?? '1') == '1',
      repMinGlobal: entero(
        Claves.repMin,
        porDefecto.repMinGlobal,
        minimo: 1,
        maximo: 30,
      ),
      repMaxGlobal: entero(
        Claves.repMax,
        porDefecto.repMaxGlobal,
        minimo: 1,
        maximo: 30,
      ),
      perfilProgresion: switch (valores[Claves.perfilProgresion]) {
        'conservador' => Perfil.conservador,
        'agresivo' => Perfil.agresivo,
        _ => Perfil.estandar,
      },
    );
  }

  final Unidad unidad;

  /// Cuánto sube o baja el selector de peso, **en la unidad activa**.
  final double pasoPeso;

  final int descansoSeg;
  final bool sonidoDescanso;
  final int seriesPorDefecto;
  final int repeticionesPorDefecto;

  /// Por defecto desactivado: quien no use el RPE no debe verlo estorbando en
  /// el registro.
  final bool esfuerzoActivo;

  final EscalaEsfuerzo escala;

  /// Objetivo de sesiones semanales; es contra esto que se mide la racha.
  final int sesionesPorSemana;

  /// Con la que se estiman el 1RM y sus récords.
  final Formula formula;

  final Tema tema;

  /// Interruptor general de las sugerencias de progresión.
  ///
  /// Con esto apagado la app se comporta exactamente como antes del bloque J: ni
  /// la tarjeta de entrenar ni la de resultados enseñan nada, y la sugerencia no
  /// llega a calcularse.
  final bool progresionActiva;

  /// Suelo del rango de repeticiones por defecto.
  ///
  /// Se llama así, y no `repMin` a secas, porque cada ejercicio puede tener el
  /// suyo en la columna homónima: esto es el que se usa cuando no lo tiene.
  final int repMinGlobal;

  /// Tope del rango de repeticiones por defecto.
  final int repMaxGlobal;

  final Perfil perfilProgresion;

  /// Cómo se escribe cada ajuste en la tabla. Es la vuelta de [desdeMapa].
  static String texto(Object valor) => switch (valor) {
    final bool v => v ? '1' : '0',
    Unidad.lb => 'lb',
    Unidad.kg => 'kg',
    EscalaEsfuerzo.rir => 'rir',
    EscalaEsfuerzo.rpe => 'rpe',
    Formula.epley => 'epley',
    Formula.brzycki => 'brzycki',
    Tema.claro => 'claro',
    Tema.oscuro => 'oscuro',
    Tema.sistema => 'sistema',
    Perfil.conservador => 'conservador',
    Perfil.estandar => 'estandar',
    Perfil.agresivo => 'agresivo',
    _ => '$valor',
  };

  // ── Conversión de unidades ─────────────────────────────────────────────────

  /// Un peso guardado (kilos) en la unidad activa.
  double desdeKilos(double kilos) =>
      unidad == Unidad.kg ? kilos : kilos * factorLibras;

  /// Un valor introducido en la unidad activa, de vuelta a kilos.
  double aKilos(double valor) =>
      unidad == Unidad.kg ? valor : valor / factorLibras;

  /// El valor para el selector: convertido y cuadrado al paso.
  ///
  /// Sin cuadrarlo, 60 kg en libras arrancaría en 132,2772 y cada toque
  /// arrastraría ese resto por toda la columna.
  double paraSelector(double kilos) =>
      (desdeKilos(kilos) / pasoPeso).round() * pasoPeso;

  /// Decimales con los que se escribe un peso en el selector.
  ///
  /// El paso de 1,25 es el único que necesita dos.
  int get decimalesPaso => pasoPeso == 1.25 ? 2 : 1;

  /// Tope del selector de peso en la unidad activa (400 kg).
  double get pesoMaximo => desdeKilos(400).ceilToDouble();
}
