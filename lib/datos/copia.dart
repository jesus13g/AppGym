/// Copia de seguridad de los datos del usuario: exportar e importar.
///
/// Todo el histórico vive hoy en un único fichero SQLite del directorio de la
/// aplicación, sin copia. En Android, además, desinstalar la app se lo lleva.
/// Es el riesgo más serio del proyecto y crece con cada mes de uso.
///
/// **No se llama `respaldo.dart`** —el nombre que proponía la especificación—
/// porque ese fichero ya existe y hace otra cosa: duplicar el fichero de base
/// de datos antes de una migración destructiva. Aquello protege de una
/// migración; esto, de perder el móvil.
///
/// Decisiones del formato, todas en la misma dirección (que una copia sea
/// reimportable en cualquier instalación):
///
///   - **No se exportan los ids internos.** Las series apuntan a su ejercicio
///     por **nombre** dentro de la rutina, que es único por la regla de
///     `insertarEjercicio`.
///   - **No se exporta el catálogo.** Son 1.324 filas regenerables desde
///     `assets/ejercicios.es.json`, que sí se versiona. Los ejercicios se
///     referencian por `idCatalogo`; si al importar ese id no existe, el
///     ejercicio entra como personalizado conservando el nombre y se avisa.
///   - **`version`** permite migrar copias antiguas el día que el formato
///     cambie.
library;

import 'dart:convert';

import 'bd.dart';

/// Marca del formato, para no tragarse el JSON de otra aplicación.
const formatoCopia = 'appgym-backup';

/// Versión del formato. Sube cuando cambie de forma incompatible.
const versionCopia = 2;

/// Qué hacer con lo que ya hay al importar.
enum ModoImportacion {
  /// Borra los datos actuales y restaura la copia entera.
  reemplazar,

  /// Añade las rutinas que no existan; una repetida entra como «(importada)».
  ///
  /// No intenta fusionar sesiones dentro de una misma rutina: no hay forma
  /// fiable de reconocer un duplicado y el resultado sería peor que el
  /// problema que viene a resolver.
  fusionar,
}

/// Lo que ha entrado, para poder contárselo al usuario.
class InformeImportacion {
  const InformeImportacion({
    required this.rutinas,
    required this.ejercicios,
    required this.entrenamientos,
    required this.series,
    required this.medidas,
    this.avisos = const [],
  });

  final int rutinas;
  final int ejercicios;
  final int entrenamientos;
  final int series;
  final int medidas;

  /// Lo que no ha entrado tal cual: rutinas renombradas, ejercicios que ya no
  /// están en el catálogo.
  final List<String> avisos;

  String get resumen =>
      '$rutinas ${rutinas == 1 ? 'rutina' : 'rutinas'}, '
      '$entrenamientos ${entrenamientos == 1 ? 'sesión' : 'sesiones'} '
      'y $series ${series == 1 ? 'serie' : 'series'}.';
}

// ── Exportar ─────────────────────────────────────────────────────────────────

/// Vuelca todos los datos del usuario al mapa que se serializa a JSON.
Future<Map<String, dynamic>> exportar(AppBD bd) async {
  final rutinas = await bd.todasLasRutinas();
  final salida = <Map<String, dynamic>>[];

  for (final rutina in rutinas) {
    final ejercicios = await bd.ejerciciosDeRutina(rutina.id);
    // Las series apuntan a su ejercicio por nombre, así que hace falta el
    // camino de vuelta desde el id interno.
    final nombrePorId = {for (final e in ejercicios) e.id: e.nombre};

    final entrenamientos = await bd.entrenamientosDeRutina(rutina.id);
    final seriesPorSesion = await bd.seriesPorEntrenamiento(rutina.id);

    salida.add({
      'nombre': rutina.nombre,
      'color': rutina.color,
      'ejercicios': [
        for (final e in ejercicios)
          {
            'nombre': e.nombre,
            'idCatalogo': e.ejercicio.idCatalogo,
            'descripcion': e.ejercicio.descripcion,
            'orden': e.ejercicio.orden,
            'descansoSeg': e.ejercicio.descansoSeg,
          },
      ],
      'entrenamientos': [
        for (final entrenamiento in entrenamientos)
          {
            'fecha': entrenamiento.fecha.toIso8601String(),
            'duracionSeg': entrenamiento.duracionSeg,
            'nota': entrenamiento.nota,
            'series': [
              for (final s in seriesPorSesion[entrenamiento.id] ?? const [])
                if (nombrePorId[s.idEjercicio] case final nombre?)
                  {
                    'ejercicio': nombre,
                    'nSerie': s.nSerie,
                    'repeticiones': s.repeticiones,
                    'peso': s.peso,
                    'rpe': s.rpe,
                    'calentamiento': s.calentamiento,
                    'nota': s.nota,
                  },
            ],
          },
      ],
    });
  }

  return {
    'formato': formatoCopia,
    'version': versionCopia,
    'exportado': DateTime.now().toIso8601String(),
    'ajustes': await bd.ajustesCrudos(),
    'rutinas': salida,
    'medidas': [
      for (final m in await bd.todasLasMedidas())
        {'fecha': m.fecha.toIso8601String(), 'tipo': m.tipo, 'valor': m.valor},
    ],
  };
}

/// Una fila por serie, para abrir en una hoja de cálculo.
///
/// Separador de coma y comillas dobles a la manera de RFC 4180. El BOM lo pone
/// quien escribe el fichero: es cosa de la codificación, no del contenido.
Future<String> exportarCsv(AppBD bd) async {
  final lineas = <String>[
    'fecha,rutina,ejercicio,serie,repeticiones,peso_kg,rpe,calentamiento',
  ];

  for (final rutina in await bd.todasLasRutinas()) {
    final ejercicios = await bd.ejerciciosDeRutina(rutina.id);
    final nombrePorId = {for (final e in ejercicios) e.id: e.nombre};
    final seriesPorSesion = await bd.seriesPorEntrenamiento(rutina.id);

    for (final entrenamiento in await bd.entrenamientosDeRutina(rutina.id)) {
      for (final s in seriesPorSesion[entrenamiento.id] ?? const []) {
        lineas.add(
          [
            entrenamiento.fecha.toIso8601String(),
            _csv(rutina.nombre),
            _csv(nombrePorId[s.idEjercicio] ?? ''),
            '${s.nSerie}',
            '${s.repeticiones}',
            '${s.peso}',
            s.rpe?.toString() ?? '',
            s.calentamiento ? '1' : '0',
          ].join(','),
        );
      }
    }
  }

  return lineas.join('\n');
}

/// Escapa un campo con coma, comillas o salto de línea.
String _csv(String valor) {
  if (!valor.contains(RegExp('[",\n]'))) return valor;
  return '"${valor.replaceAll('"', '""')}"';
}

/// El nombre sugerido para el fichero de una copia hecha hoy.
String nombreFichero(DateTime fecha, {String extension = 'json'}) {
  String dos(int n) => n.toString().padLeft(2, '0');
  return 'appgym-copia-${fecha.year}-${dos(fecha.month)}-${dos(fecha.day)}'
      '.$extension';
}

// ── Validar ──────────────────────────────────────────────────────────────────

/// Errores legibles de un fichero de copia. Vacío significa que se puede
/// importar.
///
/// Se comprueba **antes** de tocar nada: un fichero corrupto o de otra
/// aplicación no debe dejar la base a medio restaurar.
List<String> validar(Map<String, dynamic> datos) {
  final errores = <String>[];

  if (datos['formato'] != formatoCopia) {
    errores.add('El archivo no es una copia de seguridad de AppGym.');
    // Sin la marca, lo demás no significa nada: no tiene sentido seguir
    // enumerando problemas de un fichero que no es este formato.
    return errores;
  }

  final version = datos['version'];
  if (version is! int || version < 1) {
    errores.add('El archivo no dice de qué versión es.');
  } else if (version > versionCopia) {
    errores.add(
      'La copia es de una versión más nueva de AppGym (v$version). '
      'Actualiza la app para poder importarla.',
    );
  }

  if (datos['rutinas'] is! List) {
    errores.add('El archivo no contiene ninguna rutina.');
    return errores;
  }

  for (final (indice, cruda) in (datos['rutinas'] as List).indexed) {
    final donde = 'La rutina ${indice + 1}';
    if (cruda is! Map) {
      errores.add('$donde está mal formada.');
      continue;
    }
    if (cruda['nombre'] is! String || (cruda['nombre'] as String).isEmpty) {
      errores.add('$donde no tiene nombre.');
    }
    for (final clave in ['ejercicios', 'entrenamientos']) {
      if (cruda[clave] != null && cruda[clave] is! List) {
        errores.add('$donde tiene un campo «$clave» que no es una lista.');
      }
    }
  }

  if (datos['medidas'] != null && datos['medidas'] is! List) {
    errores.add('Las medidas no son una lista.');
  }
  return errores;
}

/// Lee un JSON de copia. Devuelve `null` si ni siquiera es un objeto JSON.
Map<String, dynamic>? leer(String contenido) {
  try {
    final cargado = jsonDecode(contenido);
    return cargado is Map<String, dynamic> ? cargado : null;
  } on FormatException {
    return null;
  }
}

// ── Importar ─────────────────────────────────────────────────────────────────

/// Restaura una copia ya validada, en una sola transacción.
///
/// Si algo falla a mitad, la transacción se deshace y la base queda como
/// estaba: no hay estado intermedio en el que el usuario se quede sin lo que
/// tenía y sin lo que importaba.
Future<InformeImportacion> importar(
  AppBD bd,
  Map<String, dynamic> datos, {
  required ModoImportacion modo,
}) async {
  final errores = validar(datos);
  if (errores.isNotEmpty) throw FormatException(errores.first);

  final crudas = (datos['rutinas'] as List).cast<Map<String, dynamic>>();

  // Qué ids del catálogo de la copia existen de verdad aquí. Se resuelve de una
  // vez, antes de la transacción, para no consultar por cada ejercicio.
  final idsPropuestos = <String>{
    for (final rutina in crudas)
      for (final e in _lista(rutina['ejercicios']))
        if (e['idCatalogo'] case final String id) id,
  };
  final idsValidos = await bd.idsDeCatalogoExistentes(idsPropuestos);

  final avisos = <String>[];
  var nRutinas = 0;
  var nEjercicios = 0;
  var nEntrenamientos = 0;
  var nSeries = 0;
  var nMedidas = 0;
  var perdidosDelCatalogo = 0;

  await bd.transaction(() async {
    if (modo == ModoImportacion.reemplazar) await bd.borrarTodosLosDatos();

    final ocupados = await bd.nombresDeRutinas();

    for (final cruda in crudas) {
      final propuesto = cruda['nombre'] as String;
      final nombre = _nombreLibre(propuesto, ocupados);
      if (nombre != propuesto) {
        avisos.add('«$propuesto» ya existía: se importó como «$nombre».');
      }
      ocupados.add(nombre);

      final idRutina = await bd.restaurarRutina(
        nombre,
        cruda['color'] as String?,
      );
      nRutinas++;

      // id interno por nombre de ejercicio: es la referencia que usan las
      // series de la copia.
      final idPorNombre = <String, int>{};
      for (final (indice, e) in _lista(cruda['ejercicios']).indexed) {
        final nombreEjercicio = e['nombre'] as String?;
        if (nombreEjercicio == null || nombreEjercicio.isEmpty) continue;
        if (idPorNombre.containsKey(nombreEjercicio)) continue;

        final idCatalogo = e['idCatalogo'] as String?;
        if (idCatalogo != null && !idsValidos.contains(idCatalogo)) {
          perdidosDelCatalogo++;
        }

        idPorNombre[nombreEjercicio] = await bd.restaurarEjercicio(
          idRutina,
          nombre: nombreEjercicio,
          orden: _entero(e['orden']) ?? indice,
          idCatalogo: idsValidos.contains(idCatalogo) ? idCatalogo : null,
          descripcion: e['descripcion'] as String?,
          descansoSeg: _entero(e['descansoSeg']),
        );
        nEjercicios++;
      }

      for (final s in _lista(cruda['entrenamientos'])) {
        final fecha = DateTime.tryParse('${s['fecha']}');
        if (fecha == null) {
          avisos.add('Una sesión de «$nombre» tenía una fecha ilegible.');
          continue;
        }

        // Se agrupan por ejercicio conservando el orden del fichero: `nSerie`
        // se reasigna al insertar, así que un hueco en la numeración de la
        // copia no deja huecos aquí.
        final porEjercicio = <int, List<ValoresSerie>>{};
        for (final serie in _lista(s['series'])) {
          final idEjercicio = idPorNombre[serie['ejercicio']];
          if (idEjercicio == null) continue;
          (porEjercicio[idEjercicio] ??= []).add(
            ValoresSerie(
              repeticiones: _entero(serie['repeticiones']) ?? 0,
              peso: _real(serie['peso']) ?? 0,
              calentamiento: serie['calentamiento'] == true,
              rpe: _real(serie['rpe']),
              nota: serie['nota'] as String?,
            ),
          );
        }
        if (porEjercicio.isEmpty) continue;

        final idEntrenamiento = await bd.restaurarEntrenamiento(
          idRutina,
          fecha,
          nota: s['nota'] as String?,
          duracionSeg: _entero(s['duracionSeg']),
        );
        await bd.restaurarSeries(idEntrenamiento, porEjercicio);
        nEntrenamientos++;
        nSeries += porEjercicio.values.fold(0, (suma, l) => suma + l.length);
      }
    }

    for (final m in _lista(datos['medidas'])) {
      final fecha = DateTime.tryParse('${m['fecha']}');
      final valor = _real(m['valor']);
      final tipo = m['tipo'] as String?;
      if (fecha == null || valor == null || tipo == null) continue;
      await bd.registrarMedida(fecha, tipo, valor);
      nMedidas++;
    }

    // Las preferencias solo se pisan al reemplazar: fusionar añade rutinas, no
    // debería cambiarle a nadie la unidad de peso por sorpresa.
    if (modo == ModoImportacion.reemplazar && datos['ajustes'] is Map) {
      await bd.fijarAjustes({
        for (final entrada in (datos['ajustes'] as Map).entries)
          '${entrada.key}': '${entrada.value}',
      });
    }
  });

  if (perdidosDelCatalogo > 0) {
    avisos.add(
      '$perdidosDelCatalogo ${perdidosDelCatalogo == 1 ? 'ejercicio' : 'ejercicios'} '
      'ya no está en el catálogo y se importó como personalizado.',
    );
  }

  return InformeImportacion(
    rutinas: nRutinas,
    ejercicios: nEjercicios,
    entrenamientos: nEntrenamientos,
    series: nSeries,
    medidas: nMedidas,
    avisos: avisos,
  );
}

/// Un nombre que no choque con los ya usados.
///
/// «Empuje» → «Empuje (importada)» → «Empuje (importada 2)». Fusionar dos veces
/// la misma copia no duplica en silencio: se ve en el nombre.
String _nombreLibre(String propuesto, Set<String> ocupados) {
  if (!ocupados.contains(propuesto)) return propuesto;

  final conMarca = '$propuesto (importada)';
  if (!ocupados.contains(conMarca)) return conMarca;

  for (var i = 2; i < 1000; i++) {
    final candidato = '$propuesto (importada $i)';
    if (!ocupados.contains(candidato)) return candidato;
  }
  return '$propuesto (${DateTime.now().millisecondsSinceEpoch})';
}

List<Map<String, dynamic>> _lista(Object? valor) => switch (valor) {
  final List<dynamic> l => [
    for (final e in l)
      if (e is Map<String, dynamic>) e,
  ],
  _ => const [],
};

int? _entero(Object? valor) => switch (valor) {
  final int v => v,
  final double v => v.round(),
  final String v => int.tryParse(v),
  _ => null,
};

double? _real(Object? valor) => switch (valor) {
  final num v => v.toDouble(),
  final String v => double.tryParse(v),
  _ => null,
};
