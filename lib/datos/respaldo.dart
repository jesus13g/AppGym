/// Copia de seguridad del fichero de base de datos antes de migrarlo.
///
/// La migración a la v2 del esquema es la única del proyecto que **transforma**
/// datos: expande cada fila agregada de `serie` en una fila por serie. Si algo
/// saliera mal, el histórico del usuario —meses de entrenamientos— no se puede
/// reconstruir, así que antes de tocarlo se guarda una copia intacta al lado.
///
/// La copia se hace con la base **todavía cerrada**: con la conexión abierta,
/// SQLite tiene datos en el WAL que el fichero principal aún no contiene y el
/// duplicado saldría a medias. Por eso esto cuelga de `databasePath`, el
/// callback que `drift_flutter` espera justo antes de abrir, y no de
/// `beforeOpen`, que corre cuando la migración ya ha pasado.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Nombre del fichero que abre `driftDatabase(name: 'appgym')`.
const _fichero = 'appgym.sqlite';

/// Ruta de la base de datos, respaldándola antes si todavía es de la v1.
///
/// Reproduce la ruta por defecto de `drift_flutter` (el directorio de
/// documentos de la aplicación, más `$name.sqlite`): **no la cambia**, o las
/// bases ya instaladas quedarían huérfanas.
Future<String> rutaBaseDeDatos() async {
  final directorio = await getApplicationDocumentsDirectory();
  final base = File('${directorio.path}/$_fichero');
  await respaldarSiHaceFalta(base);
  return base.path;
}

/// Copia `appgym.sqlite` a `appgym.bak-vN.sqlite` si es de una versión anterior
/// a la última que transforma datos.
///
/// Es idempotente: si la copia ya existe no se rehace, de modo que un segundo
/// arranque no pisa el respaldo bueno con uno ya migrado.
Future<void> respaldarSiHaceFalta(File base) async {
  if (!base.existsSync()) return;

  final version = await versionDeEsquema(base);
  if (version == null || version < 1 || version >= 2) return;

  final copia = File('${base.parent.path}/appgym.bak-v$version.sqlite');
  if (copia.existsSync()) return;

  await base.copy(copia.path);
}

/// Lee el `user_version` de un fichero SQLite sin abrirlo.
///
/// Es el número que drift usa como versión de esquema, y vive en la cabecera
/// del fichero: cuatro bytes en big endian a partir del byte 60. Leerlo así
/// evita abrir una segunda conexión —justo lo que se quiere evitar aquí— y
/// ahorra declarar `sqlite3` como dependencia directa.
///
/// Devuelve `null` si el fichero es demasiado corto para ser una base SQLite.
Future<int?> versionDeEsquema(File base) async {
  final manejador = await base.open();
  try {
    await manejador.setPosition(60);
    final bytes = await manejador.read(4);
    if (bytes.length < 4) return null;
    return ByteData.view(Uint8List.fromList(bytes).buffer).getUint32(0);
  } finally {
    await manejador.close();
  }
}
