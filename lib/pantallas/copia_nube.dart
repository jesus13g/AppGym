/// Grupo «Copia automática» de Ajustes, y su aviso en la cabecera de Rutinas.
///
/// Vive aparte de `ajustes.dart` por el mismo motivo que `copia_seguridad.dart`:
/// es de lo poco de esa pantalla que hace trabajo de verdad —abre el navegador,
/// habla con la red, sube el histórico entero— y mezclarlo con las filas de
/// preferencias dejaría un fichero que no se puede leer de un tirón.
///
/// **Se llama «Copia automática» y en ningún sitio «sincronizar».** No lo es:
/// es una copia con fecha que se sube sola. Dos móviles que copien el mismo día
/// se pisan, y llamarlo sincronización prometería algo que no hace.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/copia_automatica.dart';
import '../datos/nube/drive.dart' show carpetaCopias;
import '../estado/copia_automatica.dart';
import '../estado/providers.dart';
import '../l10n/textos.dart';
import '../tema/tokens.dart';
import '../tema/tokens.dart' as t;
import '../tema/ui.dart' as ui;
import 'ajustes.dart' show abrirAjustes;

/// El nombre de cada frecuencia.
///
/// Un `switch` exhaustivo y no un mapa: añadir un valor al enumerado rompe la
/// compilación justo aquí, que es donde falta la traducción.
String nombreFrecuencia(BuildContext context, Frecuencia frecuencia) =>
    switch (frecuencia) {
      Frecuencia.no => context.t.nubeFrecuenciaNo,
      Frecuencia.diaria => context.t.nubeFrecuenciaDiaria,
      Frecuencia.semanal => context.t.nubeFrecuenciaSemanal,
      Frecuencia.mensual => context.t.nubeFrecuenciaMensual,
    };

class GrupoCopiaNube extends ConsumerWidget {
  const GrupoCopiaNube({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vista = ref.watch(motorCopiaProvider);
    // Sin destino configurado en la compilación, la funcionalidad no existe:
    // ni se pinta el grupo ni hay nada que explicar. Es lo mismo que hace la
    // versión, que en una compilación local pone «local».
    if (!vista.disponible) return const SizedBox.shrink();

    return vista.conectado
        ? _conectado(context, ref, vista)
        : _sinConectar(context, ref, vista);
  }

  // ── Sin cuenta ─────────────────────────────────────────────────────────────

  Widget _sinConectar(
    BuildContext context,
    WidgetRef ref,
    VistaCopiaAutomatica vista,
  ) => ui.Grupo(
    cabecera: context.t.nubeCabecera,
    pie: vista.estado.error ?? context.t.nubeSinConectarPie,
    filas: [
      _accion(
        context,
        icono: CupertinoIcons.cloud_upload,
        titulo: context.t.nubeConectar(ref.read(nubeProvider)!.nombre),
        cargando: vista.enMarcha,
        onTap: () => ref
            .read(motorCopiaProvider.notifier)
            .conectar(context.t.nubeVuelta),
      ),
    ],
  );

  // ── Con cuenta ─────────────────────────────────────────────────────────────

  Widget _conectado(
    BuildContext context,
    WidgetRef ref,
    VistaCopiaAutomatica vista,
  ) {
    final estado = vista.estado;
    final formato = formatoDe(context, ref);

    return ui.Grupo(
      cabecera: context.t.nubeCabecera,
      pie: estado.error != null
          ? context.t.nubeErrorPie(estado.error!)
          : context.t.nubePie(
              copiasQueSeConservan,
              carpetaCopias,
              ref.read(nubeProvider)!.nombre,
            ),
      filas: [
        _valor(context, titulo: context.t.nubeCuenta, valor: estado.cuenta!),
        _valor(
          context,
          titulo: context.t.nubeFrecuencia,
          valor: nombreFrecuencia(context, estado.frecuencia),
          onTap: () => _elegirFrecuencia(context, ref, estado.frecuencia),
        ),
        _valor(
          context,
          titulo: context.t.nubeUltima,
          valor: estado.ultima == null
              ? context.t.nubeNunca
              : formato.desde(estado.ultima!),
        ),
        _accion(
          context,
          icono: CupertinoIcons.cloud_upload,
          titulo: context.t.nubeAhora,
          cargando: vista.enMarcha,
          onTap: () =>
              ref.read(motorCopiaProvider.notifier).intentar(Disparador.manual),
        ),
        _accion(
          context,
          icono: CupertinoIcons.xmark_circle,
          titulo: context.t.nubeDesconectar,
          destructivo: true,
          cargando: false,
          onTap: () => _desconectar(context, ref),
        ),
      ],
    );
  }

  Future<void> _elegirFrecuencia(
    BuildContext context,
    WidgetRef ref,
    Frecuencia actual,
  ) async {
    final elegida = await ui.elegirEnHoja<Frecuencia>(
      context,
      titulo: context.t.nubeFrecuencia,
      mensaje: context.t.nubeFrecuenciaMensaje,
      actual: actual,
      opciones: [
        for (final frecuencia in Frecuencia.values)
          (frecuencia, nombreFrecuencia(context, frecuencia)),
      ],
      etiquetaCancelar: context.t.comunCancelar,
    );
    if (elegida == null) return;
    await ref.read(motorCopiaProvider.notifier).fijarFrecuencia(elegida.$1);
  }

  Future<void> _desconectar(BuildContext context, WidgetRef ref) async {
    final confirmado = await ui.dialogoConfirmar(
      context,
      titulo: context.t.nubeDesconectarTitulo,
      mensaje: context.t.nubeDesconectarMensaje,
      etiquetaAceptar: context.t.nubeDesconectar,
      etiquetaCancelar: context.t.comunCancelar,
    );
    if (!confirmado) return;
    await ref.read(motorCopiaProvider.notifier).desconectar();
  }

  // ── Piezas ─────────────────────────────────────────────────────────────────

  Widget _valor(
    BuildContext context, {
    required String titulo,
    required String valor,
    VoidCallback? onTap,
  }) => CupertinoListTile(
    backgroundColor: context.tarjeta,
    title: Text(titulo, style: ui.estilo(context)),
    additionalInfo: Flexible(
      child: Text(
        valor,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: ui.estilo(context, color: context.textoSec),
      ),
    ),
    trailing: onTap == null ? null : const CupertinoListTileChevron(),
    onTap: onTap,
  );

  Widget _accion(
    BuildContext context, {
    required IconData icono,
    required String titulo,
    required bool cargando,
    required VoidCallback onTap,
    bool destructivo = false,
  }) {
    final color = destructivo ? context.destructivo : context.acento;
    return CupertinoListTile(
      backgroundColor: context.tarjeta,
      leading: Icon(icono, color: color, size: 24),
      title: Text(titulo, style: ui.estilo(context, color: color)),
      trailing: cargando
          ? const CupertinoActivityIndicator()
          : const CupertinoListTileChevron(),
      onTap: cargando ? null : onTap,
    );
  }
}

/// El aviso discreto de la cabecera de Rutinas.
///
/// Aparece **solo** cuando la copia automática está encendida y falló o lleva
/// más de dos periodos sin conseguirse; el resto del tiempo no ocupa nada. El
/// modo de fallo real de esta funcionalidad no es fallar una vez: es dejar de
/// funcionar sin que nadie se entere hasta el día en que hace falta la copia.
///
/// Nada de un icono girando permanente: copiar bien es lo normal y lo normal no
/// se anuncia.
class AvisoCopia extends ConsumerWidget {
  const AvisoCopia({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vista = ref.watch(motorCopiaProvider);
    if (!vista.disponible) return const SizedBox.shrink();
    if (!avisar(vista.estado, ahora: DateTime.now())) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(t.l, t.s, t.l, 0),
      child: GestureDetector(
        onTap: () => abrirAjustes(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: t.m, vertical: t.s),
          decoration: BoxDecoration(
            color: context.tarjeta,
            borderRadius: BorderRadius.circular(t.radioM),
          ),
          child: Row(
            children: [
              Icon(
                CupertinoIcons.exclamationmark_triangle,
                size: 18,
                color: context.destructivo,
              ),
              const SizedBox(width: t.s),
              // Flexible: a 375 px la frase no cabe en una línea junto al icono
              // y el chevron, y sin esto desborda.
              Flexible(
                child: Text(
                  context.t.nubeAviso,
                  style: ui.estilo(context, size: t.footnote),
                ),
              ),
              const SizedBox(width: t.xs),
              Icon(
                CupertinoIcons.chevron_right,
                size: 14,
                color: context.textoSec,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
