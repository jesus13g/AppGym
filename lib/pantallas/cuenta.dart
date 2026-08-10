/// Grupo «Cuenta» de Ajustes, el flujo de entrada y su aviso en la cabecera de
/// Rutinas.
///
/// Vive aparte de `ajustes.dart` por el mismo motivo que `copia_nube.dart` y
/// `copia_seguridad.dart`: es de lo poco de esa pantalla que hace trabajo de
/// verdad —habla con la red, sustituye el histórico entero, borra una cuenta— y
/// mezclarlo con las filas de preferencias dejaría un fichero ilegible de un
/// tirón.
///
/// **La sincronización se ve lo menos posible** (K8): no hay pestaña nueva —la
/// decisión H1 sigue cerrada en tres—, no hay pantalla de bienvenida obligatoria
/// y no hay indicador permanente. Sin cuenta, la app es exactamente la de antes
/// de esta fase.
///
/// **No hay fila «Dispositivos».** K8 la pedía y se deja fuera a propósito:
/// exigiría una tabla más en el servidor, registrarse en cada pasada y un
/// «revocar» que, sin introspección de tokens, no echa de verdad al otro móvil.
/// Prometería algo que no cumple. Cerrar sesión en el móvil que se tiene delante
/// —que es lo que se hace cuando se vende o se presta— sí está.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/sincro/enlace.dart';
import '../datos/sincro/transporte.dart';
import '../estado/providers.dart';
import '../estado/sincro.dart';
import '../l10n/textos.dart';
import '../tema/tokens.dart';
import '../tema/tokens.dart' as t;
import '../tema/ui.dart' as ui;
import 'ajustes.dart' show abrirAjustes;
import 'copia_seguridad.dart' show escribirCopiaLocal;
import 'sincro_detalle.dart';

class GrupoCuenta extends ConsumerWidget {
  const GrupoCuenta({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vista = ref.watch(sincronizacionProvider);
    // Sin servicio configurado en la compilación, la funcionalidad no existe:
    // ni se pinta el grupo ni hay nada que explicar. Es lo mismo que hace la
    // versión, que en una compilación local pone «local».
    if (!vista.disponible) return const SizedBox.shrink();

    return vista.conectado
        ? _conCuenta(context, ref, vista)
        : _sinCuenta(context, ref, vista);
  }

  // ── Sin cuenta ─────────────────────────────────────────────────────────────

  Widget _sinCuenta(BuildContext context, WidgetRef ref, VistaSincro vista) =>
      ui.Grupo(
        cabecera: context.t.cuentaCabecera,
        pie: context.t.cuentaSinCuentaPie,
        filas: [
          _accion(
            context,
            icono: CupertinoIcons.person_crop_circle,
            titulo: context.t.cuentaEntrar,
            cargando: vista.enMarcha,
            onTap: () => _entrar(context, ref, creando: false),
          ),
          // Dos filas y no una: con contraseña, «entrar» y «crear cuenta» dejan
          // de poder ser el mismo botón. Quien se equivoca al teclear su correo
          // tiene que leer «contraseña incorrecta», no acabar con una cuenta
          // nueva y vacía sin enterarse.
          _accion(
            context,
            icono: CupertinoIcons.person_crop_circle_badge_plus,
            titulo: context.t.cuentaCrear,
            cargando: vista.enMarcha,
            onTap: () => _entrar(context, ref, creando: true),
          ),
        ],
      );

  // ── Con cuenta ─────────────────────────────────────────────────────────────

  Widget _conCuenta(BuildContext context, WidgetRef ref, VistaSincro vista) {
    final formato = formatoDe(context, ref);
    final error = vista.estado.ultimoError;

    return ui.Grupo(
      cabecera: context.t.cuentaCabecera,
      pie: error != null
          ? context.t.cuentaErrorPie(error)
          : context.t.cuentaPie,
      filas: [
        _valor(
          context,
          titulo: context.t.cuentaCorreo,
          valor: vista.sesion!.correo,
        ),
        _interruptor(
          context,
          titulo: context.t.cuentaSincronizar,
          valor: vista.activa,
          onChanged: (valor) =>
              ref.read(sincronizacionProvider.notifier).activar(valor),
        ),
        _valor(
          context,
          titulo: context.t.cuentaUltimaVez,
          valor: vista.estado.ultimaSincro == null
              ? context.t.cuentaNunca
              : formato.desde(vista.estado.ultimaSincro!),
          onTap: () => abrirSincroDetalle(context),
        ),
        // Mientras la pregunta del primer enlace siga sin contestar, no se
        // ofrece sincronizar: hacerlo aplicaría «fusionar» sin haberlo
        // preguntado, que es justo lo que K7 no permite.
        if (vista.enlacePendiente)
          _accion(
            context,
            icono: CupertinoIcons.exclamationmark_circle,
            titulo: context.t.cuentaEnlaceElegir,
            cargando: vista.enMarcha,
            onTap: () => decidirEnlace(context, ref),
          )
        else
          _accion(
            context,
            icono: CupertinoIcons.arrow_2_circlepath,
            titulo: context.t.cuentaAhora,
            cargando: vista.enMarcha,
            onTap: () => ref
                .read(sincronizacionProvider.notifier)
                .intentar(DisparadorSincro.manual),
          ),
        _accion(
          context,
          icono: CupertinoIcons.square_arrow_left,
          titulo: context.t.cuentaSalir,
          cargando: false,
          onTap: () => _salir(context, ref),
        ),
        _accion(
          context,
          icono: CupertinoIcons.trash,
          titulo: context.t.cuentaBorrar,
          destructivo: true,
          cargando: false,
          onTap: () => _borrarCuenta(context, ref, vista.sesion!),
        ),
      ],
    );
  }

  // ── Entrar: correo y contraseña ────────────────────────────────────────────

  Future<void> _entrar(
    BuildContext context,
    WidgetRef ref, {
    required bool creando,
  }) async {
    final motor = ref.read(sincronizacionProvider.notifier);

    final credenciales = await _pedirCredenciales(context, creando: creando);
    if (credenciales == null || !context.mounted) return;

    try {
      final (correo, contrasena) = credenciales;
      final lados = creando
          ? await motor.registrar(correo, contrasena)
          : await motor.entrar(correo, contrasena);
      // Solo hay que preguntar si hay datos a los dos lados. Los otros tres
      // casos de K7 se resuelven solos y no interrumpen a nadie.
      if (lados != null && context.mounted) await decidirEnlace(context, ref);
    } on ErrorSincro catch (e) {
      // «Correo o contraseña incorrectos», tal cual lo dice el servidor.
      if (context.mounted) ui.aviso(context, e.mensaje);
    }
  }

  /// El diálogo de credenciales. Devuelve `null` si se cancela.
  ///
  /// No sale de `ui.dart` —donde está `dialogoTexto`, que es de un campo— porque
  /// es el único sitio de la app que pide dos o tres a la vez, y uno de ellos
  /// oculto. El día que haga falta en otro sitio, sube; hoy sería un componente
  /// compartido con un solo cliente.
  ///
  /// Al **crear** la cuenta pide la contraseña dos veces. En un servidor sin
  /// correo saliente no hay «he olvidado mi contraseña», así que un dedazo al
  /// teclearla no se puede arreglar: la cuenta queda inaccesible y hay que crear
  /// otra. Un campo más es barato comparado con eso.
  Future<(String, String)?> _pedirCredenciales(
    BuildContext context, {
    required bool creando,
  }) {
    final textos = context.t;
    final correo = TextEditingController();
    final contrasena = TextEditingController();
    final repetida = TextEditingController();

    // Fuera del `builder`: dentro se reiniciaría en cada repintado y el aviso no
    // llegaría a verse nunca.
    String? error;

    return showCupertinoDialog<(String, String)>(
      context: context,
      builder: (dialogo) => StatefulBuilder(
        builder: (dialogo, repintar) {
          void aceptar() {
            final unCorreo = correo.text.trim();
            final unaClave = contrasena.text;
            if (!unCorreo.contains('@') || unCorreo.length < 3) {
              repintar(() => error = textos.cuentaCorreoNoVale);
              return;
            }
            if (creando && unaClave.length < largoMinimoContrasena) {
              repintar(
                () =>
                    error = textos.cuentaContrasenaCorta(largoMinimoContrasena),
              );
              return;
            }
            if (creando && unaClave != repetida.text) {
              repintar(() => error = textos.cuentaContrasenaNoCoincide);
              return;
            }
            if (unaClave.isEmpty) return;
            Navigator.pop(dialogo, (unCorreo, unaClave));
          }

          return CupertinoAlertDialog(
            title: Text(creando ? textos.cuentaCrear : textos.cuentaEntrar),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: t.s),
                Text(
                  creando
                      ? textos.cuentaCrearMensaje
                      : textos.cuentaEntrarMensaje,
                  textAlign: TextAlign.center,
                  style: ui.estilo(dialogo, size: t.footnote),
                ),
                const SizedBox(height: t.s),
                CupertinoTextField(
                  controller: correo,
                  placeholder: textos.cuentaCorreoMarcador,
                  autofocus: true,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.none,
                ),
                const SizedBox(height: t.s),
                CupertinoTextField(
                  controller: contrasena,
                  placeholder: textos.cuentaContrasenaMarcador,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.none,
                  onSubmitted: creando ? null : (_) => aceptar(),
                ),
                if (creando) ...[
                  const SizedBox(height: t.s),
                  CupertinoTextField(
                    controller: repetida,
                    placeholder: textos.cuentaContrasenaRepetir,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.none,
                    onSubmitted: (_) => aceptar(),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: t.s),
                  Text(
                    error!,
                    textAlign: TextAlign.center,
                    style: ui.estilo(
                      dialogo,
                      size: t.footnote,
                      color: dialogo.destructivo,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(dialogo),
                child: Text(textos.comunCancelar),
              ),
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: aceptar,
                child: Text(textos.cuentaContinuar),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Cerrar sesión, con sus dos salidas ─────────────────────────────────────

  Future<void> _salir(BuildContext context, WidgetRef ref) async {
    final textos = context.t;
    final elegida = await ui.elegirEnHoja<bool>(
      context,
      titulo: textos.cuentaSalirTitulo,
      mensaje: textos.cuentaSalirMensaje,
      opciones: [
        (false, textos.cuentaSalirConservar),
        (true, textos.cuentaSalirBorrar),
      ],
      etiquetaCancelar: textos.comunCancelar,
    );
    if (elegida == null || !context.mounted) return;

    final borrando = elegida.$1;
    if (borrando) {
      // Borrar el histórico de este móvil es destructivo y no se hace desde una
      // hoja de opciones sin más, igual que no se hace el «borrar todos los
      // datos» del grupo Datos.
      final confirmado = await ui.dialogoConfirmar(
        context,
        titulo: textos.cuentaSalirBorrarTitulo,
        mensaje: textos.cuentaSalirBorrarMensaje,
        etiquetaAceptar: textos.cuentaSalirBorrar,
        etiquetaCancelar: textos.comunCancelar,
      );
      if (!confirmado || !context.mounted) return;
    }

    await ref
        .read(sincronizacionProvider.notifier)
        .salir(borrandoDatos: borrando);
    if (context.mounted) invalidarTodo(ref);
  }

  // ── Borrar la cuenta ───────────────────────────────────────────────────────

  Future<void> _borrarCuenta(
    BuildContext context,
    WidgetRef ref,
    SesionRemota sesion,
  ) async {
    final textos = context.t;

    // Se confirma escribiendo el correo, como el «borrar todos los datos» que
    // ya existe: es irreversible y en el servidor no queda copia.
    final escrito = await ui.dialogoTexto(
      context,
      titulo: textos.cuentaBorrarTitulo,
      mensaje: textos.cuentaBorrarMensaje(sesion.correo),
      marcador: textos.cuentaCorreoMarcador,
      teclado: TextInputType.emailAddress,
      etiquetaAceptar: textos.cuentaBorrarConfirmar,
      etiquetaCancelar: textos.comunCancelar,
    );
    if (escrito == null || !context.mounted) return;

    if (escrito.trim().toLowerCase() != sesion.correo.toLowerCase()) {
      ui.aviso(context, textos.cuentaBorrarNoCoincide);
      return;
    }

    try {
      await ref.read(sincronizacionProvider.notifier).borrarCuenta();
      if (!context.mounted) return;
      invalidarTodo(ref);
      // Los datos locales no se tocan: la nube era una copia, no el original.
      ui.aviso(context, textos.cuentaBorrada);
    } on ErrorSincro catch (e) {
      if (context.mounted) ui.aviso(context, e.mensaje);
    }
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

  Widget _interruptor(
    BuildContext context, {
    required String titulo,
    required bool valor,
    required ValueChanged<bool> onChanged,
  }) => CupertinoListTile(
    backgroundColor: context.tarjeta,
    title: Text(titulo, style: ui.estilo(context)),
    trailing: CupertinoSwitch(value: valor, onChanged: onChanged),
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

// ── El primer enlace ─────────────────────────────────────────────────────────

/// La hoja del primer enlace: qué lado manda, **con las cifras de los dos**.
///
/// Es el momento más peligroso de todo el bloque: un usuario con dos años de
/// histórico local entra por primera vez en una cuenta que ya tiene datos. Sin
/// los números delante, la pregunta no se puede responder.
///
/// Va suelta y no dentro de [GrupoCuenta] porque la llaman dos sitios: el flujo
/// de entrada y la fila que queda si se cancela.
Future<void> decidirEnlace(BuildContext context, WidgetRef ref) async {
  final textos = context.t;
  final motor = ref.read(sincronizacionProvider.notifier);

  final lados = await motor.enlazar();
  if (lados == null || !context.mounted) return;

  final elegida = await ui.elegirEnHoja<EstrategiaEnlace>(
    context,
    titulo: textos.cuentaEnlaceTitulo,
    // Las cuatro cifras se componen con los plurales que ya existen: «1
    // rutinas» en la pantalla que decide si se borra un histórico es
    // exactamente donde no conviene.
    mensaje: textos.cuentaEnlaceMensaje(
      textos.comunRutinas(lados.local.rutinas),
      textos.comunSesiones(lados.local.sesiones),
      textos.comunRutinas(lados.remoto.rutinas),
      textos.comunSesiones(lados.remoto.sesiones),
    ),
    opciones: [
      (EstrategiaEnlace.fusionar, textos.cuentaEnlaceFusionar),
      (
        EstrategiaEnlace.esteDispositivo,
        textos.cuentaEnlaceEsteDispositivo(lados.remoto.sesiones),
      ),
      (
        EstrategiaEnlace.laCuenta,
        textos.cuentaEnlaceLaCuenta(lados.local.sesiones),
      ),
    ],
    etiquetaCancelar: textos.comunCancelar,
  );
  // Cancelar deja la sesión abierta y sin enlazar: la fila «Elegir qué manda»
  // del grupo vuelve a traer aquí. Cerrar la sesión al cancelar obligaría a
  // pedir otro código para algo que el usuario solo quería posponer.
  if (elegida == null || !context.mounted) return;

  final estrategia = elegida.$1;
  if (estrategia == EstrategiaEnlace.laCuenta) {
    final confirmado = await ui.dialogoConfirmar(
      context,
      titulo: textos.cuentaEnlaceLaCuentaTitulo,
      mensaje: textos.cuentaEnlaceLaCuentaMensaje(lados.local.sesiones),
      etiquetaAceptar: textos.cuentaContinuar,
      etiquetaCancelar: textos.comunCancelar,
    );
    if (!confirmado || !context.mounted) return;
  }

  final bd = ref.read(bdProvider);
  try {
    await motor.enlazar(
      estrategia: estrategia,
      // La salida que puede destruir dos años de datos no se ofrece sin red de
      // seguridad: se exporta una copia antes, sin preguntar.
      respaldoPrevio: estrategia == EstrategiaEnlace.laCuenta
          ? () => escribirCopiaLocal(bd)
          : null,
    );
    if (!context.mounted) return;
    invalidarTodo(ref);
  } on ErrorSincro catch (e) {
    if (context.mounted) ui.aviso(context, e.mensaje);
  }
}

// ── El aviso de la cabecera ──────────────────────────────────────────────────

/// El aviso discreto de la cabecera de Rutinas.
///
/// Aparece **solo** si la última pasada falló o lleva más de un día sin
/// conseguirse; el resto del tiempo no ocupa nada. Nada de un icono girando
/// permanente: sincronizar bien es lo normal y lo normal no se anuncia.
class AvisoSincronizacion extends ConsumerWidget {
  const AvisoSincronizacion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vista = ref.watch(sincronizacionProvider);
    if (!vista.avisar(ahora: DateTime.now())) return const SizedBox.shrink();

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
                CupertinoIcons.arrow_2_circlepath,
                size: 18,
                color: context.destructivo,
              ),
              const SizedBox(width: t.s),
              // Flexible: a 375 px la frase no cabe en una línea junto al icono
              // y el chevron, y sin esto desborda.
              Flexible(
                child: Text(
                  context.t.sincroAviso,
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
