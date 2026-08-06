/// Providers de Riverpod: la fuente de datos de todas las pantallas.
///
/// Sustituyen al `_render()` del router de Flet, que reconstruía la pila entera
/// en cada navegación para que al volver atrás se vieran datos frescos. Aquí
/// cada pantalla declara de qué depende y, tras una escritura, basta con
/// invalidar el provider afectado: se repinta solo lo que cambió y sin perder el
/// estado local de la pantalla (texto de búsqueda, filtros, scroll).
///
/// Se declaran a mano en vez de con riverpod_generator porque su generador y el
/// de drift no coinciden en la versión de analyzer que admite este SDK.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/bd.dart';
import '../datos/media.dart';
import '../datos/semilla.dart';

/// La base de datos, viva mientras viva la app.
final bdProvider = Provider<AppBD>((ref) {
  final bd = AppBD();
  ref.onDispose(bd.close);
  return bd;
});

/// Trabajo de arranque: localizar el directorio de media y sembrar el catálogo.
///
/// El parseo del megabyte de JSON ocurre en un isolate (ver `semilla.dart`), así
/// que esto no bloquea el primer frame.
final arranqueProvider = FutureProvider<List<EjercicioJson>>((ref) async {
  await inicializarMedia();
  final catalogo = await cargarCatalogo();
  await sembrarCatalogo(ref.watch(bdProvider), datos: catalogo);
  return catalogo;
});

// ── Rutinas ──────────────────────────────────────────────────────────────────

final resumenRutinasProvider = FutureProvider<List<ResumenRutina>>(
  (ref) => ref.watch(bdProvider).resumenRutinas(),
);

final rutinaProvider = FutureProvider.family<Rutina?, int>(
  (ref, idRutina) => ref.watch(bdProvider).rutina(idRutina),
);

final coloresRutinasProvider = FutureProvider<Map<int, (String, String)>>(
  (ref) => ref.watch(bdProvider).coloresRutinas(),
);

/// Las tres cifras de la cabecera del detalle de rutina.
typedef EstadisticasRutina = ({
  int nEjercicios,
  int nEntrenamientos,
  DateTime? ultima,
});

final estadisticasRutinaProvider =
    FutureProvider.family<EstadisticasRutina, int>((ref, idRutina) async {
      final bd = ref.watch(bdProvider);
      return (
        nEjercicios: await bd.contarEjerciciosDeRutina(idRutina),
        nEntrenamientos: await bd.contarEntrenamientosRutina(idRutina),
        ultima: await bd.ultimoEntrenamientoRutina(idRutina),
      );
    });

// ── Ejercicios ───────────────────────────────────────────────────────────────

final ejerciciosRutinaProvider =
    FutureProvider.family<List<EjercicioConFicha>, int>(
      (ref, idRutina) => ref.watch(bdProvider).ejerciciosDeRutina(idRutina),
    );

final ejercicioProvider = FutureProvider.family<EjercicioConFicha?, int>(
  (ref, idEjercicio) => ref.watch(bdProvider).ejercicio(idEjercicio),
);

final idsCatalogoEnRutinaProvider = FutureProvider.family<Set<String>, int>(
  (ref, idRutina) => ref.watch(bdProvider).idsCatalogoEnRutina(idRutina),
);

/// Series de la última sesión de un ejercicio, para precargar el registro.
final ultimasSeriesProvider = FutureProvider.family<List<ValoresSerie>, int>(
  (ref, idEjercicio) =>
      ref.watch(bdProvider).ultimasSeriesEjercicio(idEjercicio),
);

// ── Catálogo ─────────────────────────────────────────────────────────────────

final fichaProvider = FutureProvider.family<FichaCatalogo?, String>(
  (ref, idCatalogo) => ref.watch(bdProvider).ficha(idCatalogo),
);

final equipamientosProvider = FutureProvider<List<String>>(
  (ref) => ref.watch(bdProvider).equipamientosDisponibles(),
);

// ── Progreso ─────────────────────────────────────────────────────────────────

/// Clave de las series de un ejercicio dentro de una rutina.
typedef ClaveSeries = ({int idRutina, int idEjercicio});

final seriesConFechaProvider =
    FutureProvider.family<List<RegistroSerie>, ClaveSeries>(
      (ref, clave) => ref
          .watch(bdProvider)
          .seriesConFecha(clave.idRutina, clave.idEjercicio),
    );

/// Una entrada por sesión, que es lo que pintan el gráfico y las listas.
final resumenSesionesEjercicioProvider =
    FutureProvider.family<List<ResumenSesionEjercicio>, ClaveSeries>(
      (ref, clave) => ref
          .watch(bdProvider)
          .resumenSesionesEjercicio(clave.idRutina, clave.idEjercicio),
    );

final entrenamientosPorDiaProvider = FutureProvider<Map<DateTime, int>>(
  (ref) => ref.watch(bdProvider).entrenamientosPorDia(),
);

// ── Sesiones ─────────────────────────────────────────────────────────────────

final historialRutinaProvider = FutureProvider.family<List<ResumenSesion>, int>(
  (ref, idRutina) => ref.watch(bdProvider).historialRutina(idRutina),
);

final sesionProvider = FutureProvider.family<SesionCompleta?, int>(
  (ref, idEntrenamiento) => ref.watch(bdProvider).sesion(idEntrenamiento),
);

// ── Invalidación ─────────────────────────────────────────────────────────────

/// Refresca todo lo que depende de la lista de rutinas.
void invalidarRutinas(WidgetRef ref) {
  ref.invalidate(resumenRutinasProvider);
  ref.invalidate(coloresRutinasProvider);
}

/// Refresca todo lo que cuelga de una rutina concreta.
void invalidarRutina(WidgetRef ref, int idRutina) {
  ref.invalidate(ejerciciosRutinaProvider(idRutina));
  ref.invalidate(estadisticasRutinaProvider(idRutina));
  ref.invalidate(idsCatalogoEnRutinaProvider(idRutina));
  ref.invalidate(rutinaProvider(idRutina));
  invalidarRutinas(ref);
}

/// Refresca lo que cambia tras guardar un entrenamiento.
void invalidarEntrenamientos(WidgetRef ref, int idRutina) {
  ref.invalidate(entrenamientosPorDiaProvider);
  ref.invalidate(seriesConFechaProvider);
  ref.invalidate(resumenSesionesEjercicioProvider);
  ref.invalidate(ultimasSeriesProvider);
  // El historial y el detalle de sesión son fáciles de olvidar aquí, y dejarlos
  // fuera se nota enseguida: una pantalla mostrando lo que ya no está.
  ref.invalidate(historialRutinaProvider(idRutina));
  ref.invalidate(sesionProvider);
  ref.invalidate(estadisticasRutinaProvider(idRutina));
  invalidarRutinas(ref);
}
