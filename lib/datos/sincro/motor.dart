/// El motor de reconciliación: bajar, aplicar, subir, confirmar.
///
/// Es el 80 % del bloque K y el 100 % de sus tests. **No importa Flutter ni el
/// SDK de ningún proveedor**: recibe una [AppBD] y un [SincroTransporte], así
/// que se prueba entero contra un mapa en memoria, con dos bases
/// `NativeDatabase.memory()` haciendo de dos móviles.
///
/// ## La regla que lo decide todo
///
/// > **Al bajar, una fila remota se aplica salvo que la local esté pendiente de
/// > subir. El reloj del cliente no decide nada.**
///
/// «Pendiente» es `actualizado > cursorSubida`: esta fila la cambié yo y el
/// servidor todavía no lo sabe. Si lo está, gana la local —y se sube justo
/// después, de modo que el servidor acaba con ella— y si no lo está, la remota
/// es más nueva por construcción, porque lo que hay aquí es exactamente lo que
/// el servidor tenía la última vez que se miró.
///
/// Es una desviación de lo que decía K4 —«gana la fila con el `actualizado` más
/// alto»— y llega al mismo sitio sin tener que fiarse de la hora del móvil. Un
/// usuario con el reloj adelantado dos años no gana todos los conflictos para
/// siempre: lo único que compara sellos es el servidor, que sella con el suyo
/// al aceptar, así que gana quien llega el último. Es lo que hace verificable el
/// octavo escenario de K10 sin inventarse un reloj de confianza.
///
/// ## Lo que nunca hace
///
/// Nada a medias. Todo lo que entra va en una transacción y **el cursor no
/// avanza si la transacción no cierra**; si la subida falla, no se confirma
/// nada y lo pendiente sigue pendiente. Un fallo es un aviso, jamás un error en
/// medio de un entrenamiento.
library;

import 'dart:convert';

import '../ajustes.dart' show Claves;
import '../bd.dart';
import '../identidad.dart';
import '../reloj.dart';
import 'transporte.dart';

/// Lo que no se pudo resolver sin perder algo.
///
/// Es lo único que el usuario llega a ver de un conflicto, y va a una lista con
/// fecha que se puede descartar. **Un diálogo modal de resolución de conflictos
/// es exactamente lo que no hay que construir**: interrumpe, obliga a decidir
/// sobre algo que no se recuerda y se dispara siempre en el peor momento.
///
/// El motivo viaja como enumerado y no como texto, igual que en
/// `progresion.dart`: la frase se compone en la pantalla, que es la que conoce
/// el idioma.
enum MotivoAviso {
  /// Dos rutinas distintas con el mismo nombre. Una se ha renombrado.
  rutinaRenombrada,

  /// Una fila llegó sin su padre y no se pudo colocar.
  sinPadre,

  /// Series de una sesión que apuntaban a un ejercicio que ya no está.
  seriesPerdidas,
}

class AvisoSincro {
  const AvisoSincro(this.motivo, this.detalle, this.cuando);

  final MotivoAviso motivo;

  /// El dato que hace falta para entender el aviso: el nombre nuevo de la
  /// rutina, la fecha de la sesión. **Ya en datos, no en una frase.**
  final String detalle;

  final DateTime cuando;

  Map<String, Object?> aJson() => {
    'motivo': motivo.name,
    'detalle': detalle,
    'cuando': cuando.toIso8601String(),
  };

  static AvisoSincro? deJson(Map<String, Object?> json) {
    final motivo = MotivoAviso.values
        .where((m) => m.name == json['motivo'])
        .firstOrNull;
    if (motivo == null) return null;
    return AvisoSincro(
      motivo,
      json['detalle'] as String? ?? '',
      DateTime.tryParse(json['cuando'] as String? ?? '') ?? DateTime(2000),
    );
  }

  @override
  String toString() => '${motivo.name}($detalle)';
}

/// Qué dio de sí una pasada.
class ResultadoSincro {
  const ResultadoSincro({
    this.subidas = 0,
    this.bajadas = 0,
    this.avisos = const [],
  });

  final int subidas;
  final int bajadas;
  final List<AvisoSincro> avisos;

  bool get algoCambio => subidas > 0 || bajadas > 0;
}

/// Reconcilia la base local con la copia remota.
class MotorSincro {
  MotorSincro(this.bd, this.transporte);

  final AppBD bd;
  final SincroTransporte transporte;

  /// Cuántas lápidas se conservan antes de podarlas.
  ///
  /// Una lápida sigue haciendo falta mientras quede un dispositivo que no la
  /// haya bajado, y eso desde aquí no se sabe; lo que sí se puede es no
  /// guardarlas para siempre.
  static const diasDeLapidas = 90;

  /// Una pasada completa: bajar, aplicar, subir, confirmar.
  ///
  /// Lanza [ErrorSincro] si el transporte falla, dejando anotado el error y sin
  /// haber avanzado el cursor de lo que no llegó a hacerse.
  Future<ResultadoSincro> sincronizar() async {
    try {
      final bajada = await _bajar();
      final subidas = await _subir();
      final resultado = ResultadoSincro(
        subidas: subidas,
        bajadas: bajada.$1,
        avisos: bajada.$2,
      );
      await bd.fijarEstadoSincro(
        ultimaSincro: Value(ahora()),
        subidas: Value(resultado.subidas),
        bajadas: Value(resultado.bajadas),
        avisos: Value(
          jsonEncode([for (final a in resultado.avisos) a.aJson()]),
        ),
        ultimoError: const Value(null),
      );
      await _podar();
      return resultado;
    } on ErrorSincro catch (e) {
      await bd.fijarEstadoSincro(ultimoError: Value(e.mensaje));
      rethrow;
    }
  }

  // ── Bajar ──────────────────────────────────────────────────────────────────

  Future<(int, List<AvisoSincro>)> _bajar() async {
    final estado = await bd.estadoSincro();
    final paquete = await transporte.bajar(estado.cursorBajada);

    // Antes de escribir nada: los sellos del servidor pueden ir por delante de
    // la hora de este móvil, y un sello local que quedara por debajo del cursor
    // haría pasar por subido un cambio que no lo está.
    sembrarSello(paquete.cursor);

    return bd.transaction(() async {
      // Se apunta lo pendiente **antes** de aplicar nada: después, las filas
      // recién bajadas llevan sellos del servidor por encima del cursor viejo y
      // no habría forma de distinguirlas de un cambio de aquí.
      final antes = await pendientes(estado.cursorSubida);
      final aplicadas = await _aplicar(paquete, estado.cursorSubida);
      await _reafirmarPendientes(antes, paquete.cursor);
      await bd.fijarEstadoSincro(
        cursorBajada: Value(paquete.cursor),
        // Lo que se acaba de bajar **no está pendiente de subir**: viene del
        // servidor, y lleva su sello. Subir el cursor hasta donde llega el
        // paquete es lo que impide que los dos móviles se devuelvan las mismas
        // filas una y otra vez, cada uno creyendo que las suyas son nuevas.
        cursorSubida: Value(
          paquete.cursor > estado.cursorSubida
              ? paquete.cursor
              : estado.cursorSubida,
        ),
      );
      return aplicadas;
    });
  }

  /// Vuelve a sellar lo que sigue pendiente, por encima del cursor nuevo.
  ///
  /// Subir el cursor de subida hasta donde llega el paquete daría por subido
  /// todo lo que tuviera un sello menor, incluido lo que este móvil cambió
  /// mientras el otro escribía. Esto es lo que lo salva: a [antes] —lo que
  /// estaba pendiente al empezar— se le pone un sello nuevo, que [sembrarSello]
  /// garantiza por encima del cursor, antes de moverlo.
  ///
  /// El `esperado` no sobra: si la fila cambió al aplicar el paquete, la que
  /// vale es la de ahora y no hay que tocarla.
  Future<void> _reafirmarPendientes(
    List<FilaRemota> antes,
    int cursorNuevo,
  ) async {
    for (final fila in antes) {
      if (fila.actualizado > cursorNuevo) continue;
      final tabla = TablaSincro.values.byName(fila.tabla);
      final sello = selloLocal();
      if (fila.borrada) {
        await bd.resellarLapida(
          tabla,
          fila.clave,
          sello,
          esperado: fila.actualizado,
        );
      } else {
        await bd.resellar(tabla, fila.clave, sello, esperado: fila.actualizado);
      }
    }
  }

  /// Aplica un paquete entero, en el orden en que se puede aplicar.
  ///
  /// El paquete puede venir en cualquier orden, así que primero se ordena por
  /// dependencias —rutinas, ejercicios, entrenamientos, y después lo que no
  /// depende de nada— y lo que aun así no se pueda colocar queda **en
  /// cuarentena** y se reintenta mientras la pasada anterior haya colocado algo.
  /// Cuando una pasada no avanza, lo que queda ya no puede resolverse dentro de
  /// este paquete —es una fila huérfana de verdad, cuyo padre se borró— y se
  /// aplica en modo laxo o se descarta con un aviso.
  ///
  /// En la práctica la cuarentena no se usa nunca: el servidor devuelve el
  /// delta entero y las series viajan dentro de su sesión. Está porque un
  /// paquete parcial rompería las claves foráneas, que aquí están activas.
  Future<(int, List<AvisoSincro>)> _aplicar(
    Paquete paquete,
    int cursorSubida,
  ) async {
    final avisos = <AvisoSincro>[];
    final orden = {for (final (i, t) in TablaSincro.values.indexed) t.name: i};

    // Las lápidas al final de su tabla: si en el mismo paquete llega una fila y
    // el borrado de su padre, el borrado es lo último que pasó.
    final pendientes = [...paquete.filas]
      ..sort((a, b) {
        final porTabla = (orden[a.tabla] ?? 99).compareTo(orden[b.tabla] ?? 99);
        if (porTabla != 0) return porTabla;
        if (a.borrada != b.borrada) return a.borrada ? 1 : -1;
        return a.actualizado.compareTo(b.actualizado);
      });

    var aplicadas = 0;
    var estricto = true;
    while (pendientes.isNotEmpty) {
      final cuarentena = <FilaRemota>[];
      var progreso = false;
      for (final fila in pendientes) {
        final resultado = await _aplicarFila(
          fila,
          cursorSubida,
          avisos,
          estricto: estricto,
        );
        switch (resultado) {
          case _Aplicada.si:
            aplicadas++;
            progreso = true;
          case _Aplicada.no:
            progreso = true;
          case _Aplicada.cuarentena:
            cuarentena.add(fila);
        }
      }
      if (cuarentena.isEmpty) break;
      if (!progreso) {
        // Nadie avanza: lo que queda es huérfano. Una vuelta más en modo laxo
        // y, lo que siga sin poder colocarse, se descarta con su aviso.
        if (!estricto) {
          for (final fila in cuarentena) {
            avisos.add(AvisoSincro(MotivoAviso.sinPadre, fila.id, ahora()));
          }
          break;
        }
        estricto = false;
      }
      pendientes
        ..clear()
        ..addAll(cuarentena);
    }
    return (aplicadas, avisos);
  }

  Future<_Aplicada> _aplicarFila(
    FilaRemota fila,
    int cursorSubida,
    List<AvisoSincro> avisos, {
    required bool estricto,
  }) async {
    final tabla = TablaSincro.values
        .where((t) => t.name == fila.tabla)
        .firstOrNull;
    // Una tabla que este cliente no conoce: la escribió una versión más nueva
    // de la app. Se ignora en vez de romper; el cursor avanza igual.
    if (tabla == null) return _Aplicada.no;

    // Lo pendiente local gana, sea una edición o un borrado.
    if (await _pendiente(tabla, fila.clave, cursorSubida)) return _Aplicada.no;

    // El borrado se aplica sin comparar sellos, y no es un descuido: si la fila
    // de aquí no está pendiente, es exactamente la que el servidor tenía, así
    // que la lápida es posterior por construcción. Comparar un sello local con
    // uno del servidor sería comparar dos relojes distintos, que es justo lo
    // que este diseño evita. El caso de «la rutina revive» es el otro lado de
    // la misma regla: si aquí se editó y no se ha subido, ya se ha salido
    // arriba y el borrado no llega a aplicarse.
    if (fila.borrada) {
      final borro = await bd.aplicarBorrado(tabla, fila.clave);
      return borro ? _Aplicada.si : _Aplicada.no;
    }

    final datos = fila.datos!;
    switch (tabla) {
      case TablaSincro.rutinas:
        await _aplicarRutina(fila, datos, avisos);
      case TablaSincro.ejercicios:
        final idRutina = (await bd.rutinaPorUuid(
          datos['rutina'] as String? ?? '',
        ))?.id;
        if (idRutina == null) return _Aplicada.cuarentena;
        await bd.aplicarEjercicio(
          uuid: fila.clave,
          idRutina: idRutina,
          nombre: datos['nombre'] as String? ?? '',
          actualizado: fila.actualizado,
          idCatalogo: datos['idCatalogo'] as String?,
          descripcion: datos['descripcion'] as String?,
          orden: (datos['orden'] as num?)?.toInt() ?? 0,
          descansoSeg: (datos['descansoSeg'] as num?)?.toInt(),
          repMin: (datos['repMin'] as num?)?.toInt(),
          repMax: (datos['repMax'] as num?)?.toInt(),
          incrementoKg: (datos['incrementoKg'] as num?)?.toDouble(),
          estrategia: (datos['estrategia'] as num?)?.toInt(),
        );
      case TablaSincro.entrenamientos:
        return _aplicarEntrenamiento(fila, datos, avisos, estricto: estricto);
      case TablaSincro.medidas:
        final [tipo, dia] = fila.clave.split('|');
        await bd.aplicarMedida(
          fecha: DateTime.parse(dia),
          tipo: tipo,
          valor: (datos['valor'] as num?)?.toDouble() ?? 0,
          actualizado: fila.actualizado,
        );
      case TablaSincro.favoritos:
        await bd.aplicarFavorito(
          idCatalogo: fila.clave,
          creado:
              DateTime.tryParse(datos['creado'] as String? ?? '') ?? ahora(),
          actualizado: fila.actualizado,
        );
      case TablaSincro.ajustes:
        // Una clave de dispositivo no entra ni aunque el servidor la mande: la
        // cuenta conectada o el cursor de otro móvil no son preferencias.
        if (Claves.locales.contains(fila.clave)) return _Aplicada.no;
        await bd.aplicarAjuste(
          clave: fila.clave,
          valor: datos['valor'] as String? ?? '',
          actualizado: fila.actualizado,
        );
    }
    return _Aplicada.si;
  }

  /// Una rutina, deshaciendo antes el choque de nombres si lo hay.
  ///
  /// `rutinas.nombre` es único, así que dos móviles que creen «Empuje» a la vez
  /// no pueden convivir tal cual. **Se renombra la de `uuid` mayor**, que es una
  /// regla que los dos dispositivos aplican igual sin hablar entre ellos, y el
  /// renombrado se sella como cambio local para que el nombre nuevo suba: así el
  /// choque se resuelve una vez y no se recalcula en cada bajada.
  Future<void> _aplicarRutina(
    FilaRemota fila,
    Map<String, Object?> datos,
    List<AvisoSincro> avisos,
  ) async {
    var nombre = datos['nombre'] as String? ?? '';
    var sello = fila.actualizado;

    final choca = await bd.rutinaPorNombre(nombre);
    if (choca != null && choca.uuid != fila.clave) {
      if (fila.clave.compareTo(choca.uuid) > 0) {
        nombre = await _nombreLibre(nombre);
        sello = selloLocal();
      } else {
        await bd.renombrarRutinaSincro(
          choca.id,
          await _nombreLibre(nombre),
          selloLocal(),
        );
      }
      avisos.add(AvisoSincro(MotivoAviso.rutinaRenombrada, nombre, ahora()));
    }

    await bd.aplicarRutina(
      uuid: fila.clave,
      nombre: nombre,
      color: datos['color'] as String?,
      actualizado: sello,
    );
  }

  /// Una sesión con sus series, **en bloque**.
  ///
  /// Las series no se fusionan nunca: llegan las de la versión que gana y
  /// sustituyen a las de aquí enteras. Mezclarlas daría una sesión con series de
  /// dos versiones, que es «una fila que nunca existió» en su peor forma.
  Future<_Aplicada> _aplicarEntrenamiento(
    FilaRemota fila,
    Map<String, Object?> datos,
    List<AvisoSincro> avisos, {
    required bool estricto,
  }) async {
    final idRutina = (await bd.rutinaPorUuid(
      datos['rutina'] as String? ?? '',
    ))?.id;
    if (idRutina == null) return _Aplicada.cuarentena;

    final series = <int, List<ValoresSerie>>{};
    var perdidas = 0;
    for (final cruda in (datos['series'] as List? ?? const [])) {
      final s = (cruda as Map).cast<String, Object?>();
      final idEjercicio = (await bd.ejercicioPorUuid(
        s['ejercicio'] as String? ?? '',
      ))?.id;
      if (idEjercicio == null) {
        // Todavía puede llegar en este mismo paquete.
        if (estricto) return _Aplicada.cuarentena;
        perdidas++;
        continue;
      }
      (series[idEjercicio] ??= []).add(
        ValoresSerie(
          repeticiones: (s['repeticiones'] as num?)?.toInt() ?? 0,
          peso: (s['peso'] as num?)?.toDouble() ?? 0,
          calentamiento: s['calentamiento'] == true,
          rpe: (s['rpe'] as num?)?.toDouble(),
          nota: s['nota'] as String?,
        ),
      );
    }

    final fecha = DateTime.tryParse(datos['fecha'] as String? ?? '');
    if (fecha == null) return _Aplicada.no;

    if (perdidas > 0) {
      avisos.add(
        AvisoSincro(
          MotivoAviso.seriesPerdidas,
          fecha.toIso8601String(),
          ahora(),
        ),
      );
    }

    // Una sesión sin ninguna serie no existe en este modelo de datos: si todas
    // sus series se quedaron por el camino, se descarta entera.
    if (series.isEmpty) return _Aplicada.no;

    await bd.aplicarEntrenamiento(
      uuid: fila.clave,
      idRutina: idRutina,
      fecha: fecha,
      actualizado: fila.actualizado,
      series: series,
      nota: datos['nota'] as String?,
      duracionSeg: (datos['duracionSeg'] as num?)?.toInt(),
    );
    return _Aplicada.si;
  }

  Future<String> _nombreLibre(String nombre) async {
    for (var n = 2; ; n++) {
      final candidato = '$nombre ($n)';
      if (await bd.rutinaPorNombre(candidato) == null) return candidato;
    }
  }

  /// Si la fila de aquí la cambió este móvil y el servidor todavía no lo sabe.
  ///
  /// Cuenta también la lápida: haber borrado algo es un cambio pendiente, y es
  /// lo que hace que una fila que este móvil borró no reviva al bajarla.
  Future<bool> _pendiente(
    TablaSincro tabla,
    String clave,
    int cursorSubida,
  ) async {
    final sello = await _selloLocalDe(tabla, clave);
    if (sello != null && sello > cursorSubida) return true;
    final lapida = await _selloLapida(tabla, clave);
    return lapida != null && lapida > cursorSubida;
  }

  Future<int?> _selloLocalDe(TablaSincro tabla, String clave) async {
    switch (tabla) {
      case TablaSincro.rutinas:
        return (await bd.rutinaPorUuid(clave))?.actualizado;
      case TablaSincro.ejercicios:
        return (await bd.ejercicioPorUuid(clave))?.actualizado;
      case TablaSincro.entrenamientos:
        return (await bd.entrenamientoPorUuid(clave))?.actualizado;
      case TablaSincro.medidas:
        final [tipo, dia] = clave.split('|');
        return (await bd.medidaPorClave(
          DateTime.parse(dia),
          tipo,
        ))?.actualizado;
      case TablaSincro.favoritos:
        return (await bd.favoritoPorId(clave))?.actualizado;
      case TablaSincro.ajustes:
        return (await bd.ajustePorClave(clave))?.actualizado;
    }
  }

  Future<int?> _selloLapida(TablaSincro tabla, String clave) async =>
      (await bd.lapidaDe(tabla, clave))?.actualizado;

  // ── Subir ──────────────────────────────────────────────────────────────────

  Future<int> _subir() async {
    final estado = await bd.estadoSincro();
    final filas = await pendientes(estado.cursorSubida);
    if (filas.isEmpty) return 0;

    final respuesta = await transporte.subir(Paquete(filas));

    // Igual que al bajar: el sello del servidor puede ir por delante de la hora
    // de este móvil, y lo que se vuelva a marcar como pendiente tiene que
    // quedar por encima del cursor nuevo.
    sembrarSello(respuesta.cursor);

    return bd.transaction(() async {
      var subidas = 0;
      for (final fila in filas) {
        final sello = respuesta.sellos[fila.id];
        // Lo que el servidor no confirmó se queda pendiente y vuelve a subir en
        // la siguiente pasada.
        if (sello == null) continue;
        final tabla = TablaSincro.values.byName(fila.tabla);
        final escrito = fila.borrada
            ? await bd.resellarLapida(
                tabla,
                fila.clave,
                sello,
                esperado: fila.actualizado,
              )
            : await bd.resellar(
                tabla,
                fila.clave,
                sello,
                esperado: fila.actualizado,
              );
        if (escrito) {
          subidas++;
        } else {
          // Cambió mientras se subía: se le pone un sello nuevo, por encima del
          // cursor, para que la próxima pasada la vuelva a coger.
          final nuevo = selloLocal();
          if (fila.borrada) {
            await bd.resellarLapida(tabla, fila.clave, nuevo);
          } else {
            await bd.resellar(tabla, fila.clave, nuevo);
          }
        }
      }
      // Si el servidor estaba donde lo dejó la bajada de hace un momento, todo
      // lo que hay hasta el cursor nuevo lo acaba de escribir este móvil y ya
      // lo tiene. Adelantar también el cursor de bajada evita que la siguiente
      // pasada se descargue su propio eco.
      final estado = await bd.estadoSincro();
      await bd.fijarEstadoSincro(
        cursorSubida: Value(respuesta.cursor),
        cursorBajada: respuesta.cursorPrevio == estado.cursorBajada
            ? Value(respuesta.cursor)
            : const Value.absent(),
      );
      return subidas;
    });
  }

  /// Todo lo que este móvil ha cambiado por encima de [cursor], como paquete.
  ///
  /// **No hay tabla de cola de salida**: como la unidad de reconciliación es la
  /// fila entera, «lo pendiente» se deduce de su sello. Una tabla menos y un
  /// modo de fallo menos —una cola que se desincroniza de los datos que
  /// describe—, por el mismo razonamiento que hace que los récords se calculen
  /// en vez de guardarse.
  ///
  /// Sale en orden de dependencia, para que quien lo reciba pueda aplicarlo
  /// leyéndolo de arriba abajo.
  Future<List<FilaRemota>> pendientes(int cursor) async {
    final filas = <FilaRemota>[];

    for (final r in await bd.rutinasDesde(cursor)) {
      filas.add(
        FilaRemota(
          tabla: TablaSincro.rutinas.name,
          clave: r.uuid,
          actualizado: r.actualizado,
          datos: {'nombre': r.nombre, 'color': r.color},
        ),
      );
    }

    final rutinaDe = <int, String>{};
    for (final e in await bd.ejerciciosDesde(cursor)) {
      final uuidRutina = rutinaDe[e.idRutina] ??=
          (await bd.rutina(e.idRutina))?.uuid ?? '';
      filas.add(
        FilaRemota(
          tabla: TablaSincro.ejercicios.name,
          clave: e.uuid,
          actualizado: e.actualizado,
          datos: {
            'rutina': uuidRutina,
            'idCatalogo': e.idCatalogo,
            'nombre': e.nombre,
            'descripcion': e.descripcion,
            'orden': e.orden,
            'descansoSeg': e.descansoSeg,
            'repMin': e.repMin,
            'repMax': e.repMax,
            'incrementoKg': e.incrementoKg,
            'estrategia': e.estrategia,
          },
        ),
      );
    }

    final uuidEjercicio = <int, String>{};
    for (final t in await bd.entrenamientosDesde(cursor)) {
      final series = <Map<String, Object?>>[];
      for (final s in await bd.seriesDeEntrenamiento(t.id)) {
        final uuid = uuidEjercicio[s.idEjercicio] ??=
            (await bd.ejercicioPorId(s.idEjercicio))?.uuid ?? '';
        series.add({
          'ejercicio': uuid,
          'nSerie': s.nSerie,
          'repeticiones': s.repeticiones,
          'peso': s.peso,
          'calentamiento': s.calentamiento,
          'rpe': s.rpe,
          'nota': s.nota,
        });
      }
      filas.add(
        FilaRemota(
          tabla: TablaSincro.entrenamientos.name,
          clave: t.uuid,
          actualizado: t.actualizado,
          datos: {
            'rutina': rutinaDe[t.idRutina] ??=
                (await bd.rutina(t.idRutina))?.uuid ?? '',
            'fecha': t.fecha.toIso8601String(),
            'nota': t.nota,
            'duracionSeg': t.duracionSeg,
            'series': series,
          },
        ),
      );
    }

    for (final m in await bd.medidasDesde(cursor)) {
      filas.add(
        FilaRemota(
          tabla: TablaSincro.medidas.name,
          clave: AppBD.claveMedida(m.fecha, m.tipo),
          actualizado: m.actualizado,
          datos: {'valor': m.valor},
        ),
      );
    }

    for (final f in await bd.favoritosDesde(cursor)) {
      filas.add(
        FilaRemota(
          tabla: TablaSincro.favoritos.name,
          clave: f.idCatalogo,
          actualizado: f.actualizado,
          datos: {'creado': f.creado.toIso8601String()},
        ),
      );
    }

    for (final a in await bd.ajustesDesde(cursor)) {
      // Las claves de dispositivo no viajan, por lo mismo que no se exportan en
      // la copia de seguridad: son de este móvil, no del usuario.
      if (Claves.locales.contains(a.clave)) continue;
      filas.add(
        FilaRemota(
          tabla: TablaSincro.ajustes.name,
          clave: a.clave,
          actualizado: a.actualizado,
          datos: {'valor': a.valor},
        ),
      );
    }

    for (final l in await bd.lapidasDesde(cursor)) {
      filas.add(
        FilaRemota.borrada(
          tabla: l.tabla,
          clave: l.clave,
          actualizado: l.actualizado,
        ),
      );
    }

    return filas;
  }

  Future<void> _podar() async {
    final estado = await bd.estadoSincro();
    final limite = ahora().subtract(const Duration(days: diasDeLapidas));
    await bd.podarLapidas(
      // Nunca por encima de lo ya subido: una lápida que el servidor no tenga
      // todavía no se puede tirar.
      limite.millisecondsSinceEpoch < estado.cursorSubida
          ? limite.millisecondsSinceEpoch
          : estado.cursorSubida,
    );
  }
}

/// Qué pasó con una fila del paquete.
enum _Aplicada {
  /// Se escribió.
  si,

  /// Se decidió no escribirla: gana la local, o no interesa.
  no,

  /// Le falta el padre. Se reintenta cuando el resto del paquete esté puesto.
  cuarentena,
}
