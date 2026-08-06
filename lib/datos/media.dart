/// Descarga y resolución de las imágenes y GIFs de los ejercicios.
///
/// La media (miniaturas 180x180 y GIFs animados) es propiedad de **Gym visual**
/// y no se distribuye con este repositorio ni se empaqueta en el APK: se
/// descarga desde el dataset original a un directorio local, que está en el
/// .gitignore.
///
/// Condiciones de uso de la media, según el NOTICE del dataset:
///   - se distribuye únicamente a 180x180
///   - hay que mantener visible la atribución `© Gym visual — https://gymvisual.com/`
///
/// Ver https://gymvisual.com/content/3-terms-and-conditions-of-use
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart' show ImageProvider, FileImage, NetworkImage;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'semilla.dart';

const baseRemota =
    'https://raw.githubusercontent.com/hasaneyldrm/exercises-dataset/main/';

/// Requisito de licencia: se pinta al pie de la ficha de ejercicio.
const atribucion = '© Gym visual — https://gymvisual.com/';

const _descargasSimultaneas = 16;
const _tiempoEspera = Duration(seconds: 30);

Directory? _directorio;

/// Localiza el directorio de media. Hay que llamarlo antes de usar [resolver].
///
/// En Android e iOS el directorio de trabajo no es escribible, así que la ruta
/// la decide path_provider.
Future<void> inicializarMedia() async {
  final soporte = await getApplicationSupportDirectory();
  _directorio = Directory('${soporte.path}/media');
  await _directorio!.create(recursive: true);
}

/// Fija el directorio a mano. Solo lo usan los tests.
void fijarDirectorioMedia(Directory? directorio) => _directorio = directorio;

/// URL en el repositorio original para una ruta como 'images/0001-2gPfomN.jpg'.
String urlRemota(String rutaRelativa) =>
    baseRemota + rutaRelativa.replaceFirst(RegExp('^/'), '');

/// Fichero en disco donde vive (o vivirá) esa media.
File? ficheroLocal(String rutaRelativa) {
  final base = _directorio;
  if (base == null) return null;
  return File('${base.path}/${rutaRelativa.replaceFirst(RegExp('^/'), '')}');
}

bool _estaDescargado(String rutaRelativa) {
  final fichero = ficheroLocal(rutaRelativa);
  if (fichero == null || !fichero.existsSync()) return false;
  return fichero.lengthSync() > 0;
}

/// Devuelve la imagen local si ya está descargada, o la remota si no.
///
/// Es lo que permite que la app funcione igual durante la descarga, si el
/// usuario la omite, o si falló a medias. Flutter anima los GIF en ambos casos.
ImageProvider? resolver(String? rutaRelativa) {
  if (rutaRelativa == null || rutaRelativa.isEmpty) return null;
  if (_estaDescargado(rutaRelativa)) {
    return FileImage(ficheroLocal(rutaRelativa)!);
  }
  return NetworkImage(urlRemota(rutaRelativa));
}

File? get _marcaCompleta {
  final base = _directorio;
  return base == null ? null : File('${base.path}/.complete');
}

/// True si ya se descargó todo el paquete de media.
bool get descargaCompleta => _marcaCompleta?.existsSync() ?? false;

Future<void> _marcarCompleta() async {
  final marca = _marcaCompleta;
  if (marca == null) return;
  await marca.parent.create(recursive: true);
  await marca.writeAsString('');
}

/// Rutas de media que aún no están en disco, dado el catálogo.
List<String> rutasPendientes(List<EjercicioJson> ejercicios) {
  final todas = <String>[];
  for (final ejercicio in ejercicios) {
    for (final ruta in [ejercicio.image, ejercicio.gif]) {
      if (ruta.isNotEmpty) todas.add(ruta);
    }
  }
  return [
    for (final ruta in todas)
      if (!_estaDescargado(ruta)) ruta,
  ];
}

/// Resultado de una tanda de descarga.
class ResultadoDescarga {
  const ResultadoDescarga(this.hechos, this.total, this.fallos);

  final int hechos;
  final int total;
  final int fallos;
}

/// Descarga un fichero si falta. Devuelve true si acabó estando disponible.
Future<bool> _descargarUno(String rutaRelativa, http.Client cliente) async {
  final destino = ficheroLocal(rutaRelativa);
  if (destino == null) return false;
  if (_estaDescargado(rutaRelativa)) return true;

  await destino.parent.create(recursive: true);
  // Se escribe a .part y se renombra al final para que un corte de red no deje
  // ficheros truncados que luego se den por buenos.
  final parcial = File('${destino.path}.part');
  try {
    final respuesta =
        await cliente.get(Uri.parse(urlRemota(rutaRelativa))).timeout(_tiempoEspera);
    if (respuesta.statusCode != 200) throw HttpException('${respuesta.statusCode}');
    await parcial.writeAsBytes(respuesta.bodyBytes);
    await parcial.rename(destino.path);
    return true;
  } on Exception {
    if (parcial.existsSync()) await parcial.delete();
    return false;
  }
}

/// Descarga toda la media que falte, en paralelo y de forma reanudable.
///
/// [alProgresar] se llama periódicamente con (hechos, total, fallos), y
/// [cancelado] permite abortar: los descargas en vuelo terminan y no se lanzan
/// más.
Future<ResultadoDescarga> descargarTodo(
  List<EjercicioJson> ejercicios, {
  void Function(int hechos, int total, int fallos)? alProgresar,
  bool Function()? cancelado,
}) async {
  final pendientes = rutasPendientes(ejercicios);
  final total = pendientes.length;
  if (total == 0) {
    await _marcarCompleta();
    alProgresar?.call(0, 0, 0);
    return const ResultadoDescarga(0, 0, 0);
  }

  var hechos = 0;
  var fallos = 0;
  var siguiente = 0;
  final cliente = http.Client();

  Future<void> trabajador() async {
    while (true) {
      if (cancelado?.call() ?? false) return;
      if (siguiente >= pendientes.length) return;
      final ruta = pendientes[siguiente++];

      final bien = await _descargarUno(ruta, cliente);
      hechos++;
      if (!bien) fallos++;
      if (hechos % 10 == 0 || hechos == total) {
        alProgresar?.call(hechos, total, fallos);
      }
    }
  }

  await Future.wait([
    for (var i = 0; i < _descargasSimultaneas; i++) trabajador(),
  ]);
  cliente.close();

  if (fallos == 0 && hechos == total) await _marcarCompleta();

  return ResultadoDescarga(hechos, total, fallos);
}
