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
import '../datos/reloj.dart' as reloj;
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

/// Músculos objetivo con su número de ejercicios, para el filtro del catálogo.
final objetivosProvider = FutureProvider<List<(String, int)>>(
  (ref) => ref.watch(bdProvider).objetivosDisponibles(),
);

final favoritosProvider = FutureProvider<List<FichaCatalogo>>(
  (ref) => ref.watch(bdProvider).fichasFavoritas(),
);

final idsFavoritosProvider = FutureProvider<Set<String>>(
  (ref) => ref.watch(bdProvider).idsFavoritos(),
);

final vistosProvider = FutureProvider<List<FichaCatalogo>>(
  (ref) => ref.watch(bdProvider).vistosRecientes(),
);

/// En qué rutinas está ya un ejercicio del catálogo.
final rutinasQueContienenProvider = FutureProvider.family<List<Rutina>, String>(
  (ref, idCatalogo) => ref.watch(bdProvider).rutinasQueContienen(idCatalogo),
);

// ── Medidas del cuerpo ───────────────────────────────────────────────────────

final serieMedidaProvider = FutureProvider.family<List<Medida>, String>(
  (ref, tipo) => ref.watch(bdProvider).serieMedida(tipo),
);

final ultimaMedidaProvider = FutureProvider.family<Medida?, String>(
  (ref, tipo) => ref.watch(bdProvider).ultimaMedida(tipo),
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
///
/// Depende de los ajustes por la fórmula de 1RM: cambiarla en Ajustes invalida
/// `ajustesProvider` y esto se recalcula solo.
final resumenSesionesEjercicioProvider =
    FutureProvider.family<List<ResumenSesionEjercicio>, ClaveSeries>((
      ref,
      clave,
    ) async {
      final ajustes = await ref.watch(ajustesProvider.future);
      return ref
          .watch(bdProvider)
          .resumenSesionesEjercicio(
            clave.idRutina,
            clave.idEjercicio,
            formula: ajustes.formula,
          );
    });

/// Las sesiones de los últimos dos años con su volumen, para el resumen
/// semanal.
///
/// Dos años son de sobra para la racha más larga que nadie va a encomendarse, y
/// ponen techo a lo que se carga en memoria en una pantalla que se abre
/// constantemente.
final sesionesRecientesProvider = FutureProvider<List<SesionConVolumen>>((ref) {
  final desde = reloj.ahora().subtract(const Duration(days: 730));
  return ref.watch(bdProvider).sesionesConVolumen(desde: desde);
});

/// Sesiones del mes visible del calendario, día a día.
///
/// Recibe el mes como parámetro —igual que `seriesConFechaProvider` recibe su
/// [ClaveSeries]— para que pintar un mes no consulte los demás.
final entrenamientosPorDiaProvider =
    FutureProvider.family<Map<DateTime, List<SesionDelDia>>, DateTime>((
      ref,
      mes,
    ) {
      final desde = DateTime(mes.year, mes.month);
      return ref
          .watch(bdProvider)
          .entrenamientosPorDia(
            desde: desde,
            hasta: DateTime(mes.year, mes.month + 1),
          );
    });

// ── Sesiones ─────────────────────────────────────────────────────────────────

final historialRutinaProvider = FutureProvider.family<List<ResumenSesion>, int>(
  (ref, idRutina) => ref.watch(bdProvider).historialRutina(idRutina),
);

final sesionProvider = FutureProvider.family<SesionCompleta?, int>(
  (ref, idEntrenamiento) => ref.watch(bdProvider).sesion(idEntrenamiento),
);

/// Récords batidos en una sesión, para el resumen de cierre.
final recordsSesionProvider = FutureProvider.family<List<RecordSesion>, int>((
  ref,
  idEntrenamiento,
) async {
  final ajustes = await ref.watch(ajustesProvider.future);
  return ref
      .watch(bdProvider)
      .recordsDeSesion(idEntrenamiento, formula: ajustes.formula);
});

/// El borrador de la sesión en curso, si lo hay.
///
/// Se consulta una vez al arrancar para ofrecer recuperarla; el resto del
/// tiempo la sesión viva lleva su estado en la pantalla.
final sesionActivaProvider = FutureProvider<SesionActiva?>(
  (ref) => ref.watch(bdProvider).sesionActiva(),
);

// ── Ajustes ──────────────────────────────────────────────────────────────────

final ajustesProvider = FutureProvider<Ajustes>(
  (ref) => ref.watch(bdProvider).ajustes(),
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
  ref.invalidate(sesionesRecientesProvider);
  ref.invalidate(ultimasSeriesProvider);
  // El historial y el detalle de sesión son fáciles de olvidar aquí, y dejarlos
  // fuera se nota enseguida: una pantalla mostrando lo que ya no está.
  ref.invalidate(historialRutinaProvider(idRutina));
  ref.invalidate(sesionProvider);
  ref.invalidate(recordsSesionProvider);
  ref.invalidate(estadisticasRutinaProvider(idRutina));
  invalidarRutinas(ref);
}

/// Refresca lo que depende de las preferencias.
void invalidarAjustes(WidgetRef ref) => ref.invalidate(ajustesProvider);

/// Refresca los favoritos y los vistos recientemente.
void invalidarCatalogoDelUsuario(WidgetRef ref) {
  ref.invalidate(favoritosProvider);
  ref.invalidate(idsFavoritosProvider);
  ref.invalidate(vistosProvider);
}

/// Refresca las medidas del cuerpo.
void invalidarMedidas(WidgetRef ref) {
  ref.invalidate(serieMedidaProvider);
  ref.invalidate(ultimaMedidaProvider);
}

/// Refresca **todo**, sin saber qué ha cambiado.
///
/// Es lo que hace falta tras importar una copia de seguridad o borrar los
/// datos: ahí no cambia una rutina, cambia la base entera, y enumerar provider
/// a provider sería justo el sitio donde olvidarse de uno.
void invalidarTodo(WidgetRef ref) {
  invalidarRutinas(ref);
  invalidarCatalogoDelUsuario(ref);
  invalidarMedidas(ref);
  invalidarAjustes(ref);
  ref.invalidate(ejerciciosRutinaProvider);
  ref.invalidate(ejercicioProvider);
  ref.invalidate(estadisticasRutinaProvider);
  ref.invalidate(idsCatalogoEnRutinaProvider);
  ref.invalidate(rutinaProvider);
  ref.invalidate(rutinasQueContienenProvider);
  ref.invalidate(ultimasSeriesProvider);
  ref.invalidate(seriesConFechaProvider);
  ref.invalidate(resumenSesionesEjercicioProvider);
  ref.invalidate(sesionesRecientesProvider);
  ref.invalidate(entrenamientosPorDiaProvider);
  ref.invalidate(historialRutinaProvider);
  ref.invalidate(sesionProvider);
  ref.invalidate(recordsSesionProvider);
  ref.invalidate(sesionActivaProvider);
}
