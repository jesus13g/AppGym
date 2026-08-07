/// Añadir un ejercicio del catálogo a una rutina, desde donde sea.
///
/// Hasta ahora la única forma de añadir era entrar en la rutina y buscar desde
/// dentro: mirar la ficha de un ejercicio en la pestaña **Ejercicios** y querer
/// añadirlo obligaba a salir, entrar en la rutina y buscarlo otra vez. Con
/// 1.324 fichas, eso dejaba el catálogo infrautilizado.
///
/// Vive en su propio fichero porque lo usan la lista y la ficha, y meterlo en
/// cualquiera de las dos obligaría a la otra a importarla entera.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/bd.dart';
import '../estado/providers.dart';
import '../tema/tokens.dart';
import '../tema/ui.dart' as ui;

/// Pregunta a qué rutina y añade el ejercicio.
///
/// Con una sola rutina no pregunta nada: elegir entre una opción no es elegir.
/// Devuelve `true` si el ejercicio acabó dentro de alguna rutina.
Future<bool> anadirARutina(
  BuildContext context,
  WidgetRef ref,
  FichaCatalogo ficha,
) async {
  final bd = ref.read(bdProvider);
  final rutinas = await bd.todasLasRutinas();
  if (!context.mounted) return false;

  if (rutinas.isEmpty) {
    ui.aviso(context, 'Crea antes una rutina');
    return false;
  }

  final int destino;
  if (rutinas.length == 1) {
    destino = rutinas.single.id;
  } else {
    final elegida = await ui.elegirEnHoja<int>(
      context,
      titulo: 'Añadir «${ficha.nombre}»',
      opciones: [for (final r in rutinas) (r.id, r.nombre)],
    );
    if (elegida == null || !context.mounted) return false;
    destino = elegida.$1;
  }

  final bien = await bd.insertarEjercicio(
    destino,
    ficha.nombre,
    idCatalogo: ficha.id,
  );
  if (!context.mounted) return false;

  final nombre = rutinas.firstWhere((r) => r.id == destino).nombre;
  if (!bien) {
    ui.aviso(context, '«$nombre» ya tiene este ejercicio');
    return false;
  }

  invalidarRutina(ref, destino);
  ref.invalidate(rutinasQueContienenProvider(ficha.id));
  ui.aviso(context, 'Añadido a «$nombre»');
  return true;
}

/// Marca o desmarca un favorito y refresca lo que dependa de ello.
Future<void> alternarFavorito(
  WidgetRef ref,
  String idCatalogo, {
  required bool esFavorito,
}) async {
  await ref.read(bdProvider).marcarFavorito(idCatalogo, !esFavorito);
  invalidarCatalogoDelUsuario(ref);
}

/// Estrella de favorito, con su acción ya montada.
class BotonFavorito extends ConsumerWidget {
  const BotonFavorito({super.key, required this.idCatalogo, this.tamano = 22});

  final String idCatalogo;
  final double tamano;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoritos = ref.watch(idsFavoritosProvider).value ?? const <String>{};
    final marcado = favoritos.contains(idCatalogo);

    return CupertinoButton(
      onPressed: () => alternarFavorito(ref, idCatalogo, esFavorito: marcado),
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      child: Icon(
        marcado ? CupertinoIcons.star_fill : CupertinoIcons.star,
        size: tamano,
        // Amarillo no: la paleta de la app es la semántica de Cupertino y una
        // estrella de acento se lee igual de bien en claro y en oscuro.
        color: marcado ? context.acento : context.textoTer,
      ),
    );
  }
}
