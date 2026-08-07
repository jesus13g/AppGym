/// Componentes de interfaz con estética iOS.
///
/// Aquí solo vive lo que Flutter **no** trae ya resuelto. Antes de añadir nada,
/// comprueba que el framework no lo tenga: una lista agrupada es
/// `CupertinoListSection.insetGrouped` (envuelta en [Grupo]), una fila es
/// `CupertinoListTile`, un buscador es `CupertinoSearchTextField` y deslizar
/// para borrar es `Dismissible`.
library;

import 'package:flutter/cupertino.dart';

import 'tokens.dart' as t;
import 'tokens.dart' show Paleta;

/// Estilo de texto del tema. Evita repetir `TextStyle` en cada pantalla.
TextStyle estilo(
  BuildContext context, {
  double size = t.body,
  Color? color,
  FontWeight? weight,
}) => TextStyle(
  fontSize: size,
  color: color ?? context.texto,
  fontWeight: weight,
);

/// Título de pantalla, al estilo de los large titles de iOS.
class TituloGrande extends StatelessWidget {
  const TituloGrande(this.valor, {super.key});

  final String valor;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(
      left: t.l,
      right: t.l,
      top: t.s,
      bottom: t.m,
    ),
    child: Text(
      valor,
      style: estilo(context, size: t.largeTitle, weight: t.bold),
    ),
  );
}

/// Grupo de lista con esquinas redondeadas, cabecera y pie opcionales.
class Grupo extends StatelessWidget {
  const Grupo({super.key, required this.filas, this.cabecera, this.pie});

  final List<Widget> filas;
  final String? cabecera;
  final String? pie;

  @override
  Widget build(BuildContext context) {
    if (filas.isEmpty) return const SizedBox.shrink();
    return CupertinoListSection.insetGrouped(
      backgroundColor: const Color(0x00000000),
      decoration: BoxDecoration(
        color: context.tarjeta,
        borderRadius: BorderRadius.circular(t.radioL),
      ),
      margin: const EdgeInsets.symmetric(horizontal: t.l, vertical: t.s),
      header: cabecera == null
          ? null
          : Text(
              cabecera!.toUpperCase(),
              style: estilo(context, size: t.footnote, color: context.textoSec),
            ),
      footer: pie == null
          ? null
          : Text(
              pie!,
              style: estilo(context, size: t.footnote, color: context.textoSec),
            ),
      children: filas,
    );
  }
}

/// Etiqueta redondeada para categorías (equipamiento, músculo…).
class Pildora extends StatelessWidget {
  const Pildora(this.valor, {super.key, this.color, this.relleno});

  final String valor;
  final Color? color;
  final Color? relleno;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: t.s + 2, vertical: t.xs),
    decoration: BoxDecoration(
      color: relleno ?? context.relleno,
      borderRadius: BorderRadius.circular(t.radioXl),
    ),
    child: Text(
      valor,
      style: estilo(context, size: t.caption, color: color ?? context.textoSec),
    ),
  );
}

/// Círculo de color, para identificar rutinas.
class PuntoColor extends StatelessWidget {
  const PuntoColor(this.color, {super.key, this.tamano = 10});

  final Color color;
  final double tamano;

  @override
  Widget build(BuildContext context) => Container(
    width: tamano,
    height: tamano,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// Miniatura del ejercicio, con hueco gris si no hay imagen disponible.
class Miniatura extends StatelessWidget {
  const Miniatura(this.imagen, {super.key, this.tamano = 48});

  final ImageProvider? imagen;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    final hueco = Container(
      width: tamano,
      height: tamano,
      decoration: BoxDecoration(
        color: context.relleno,
        borderRadius: BorderRadius.circular(t.radioM),
      ),
      child: Icon(
        CupertinoIcons.photo,
        size: tamano / 2.5,
        color: context.textoTer,
      ),
    );
    if (imagen == null) return hueco;

    return ClipRRect(
      borderRadius: BorderRadius.circular(t.radioM),
      child: Container(
        width: tamano,
        height: tamano,
        color: CupertinoColors.white,
        child: Image(
          image: imagen!,
          width: tamano,
          height: tamano,
          fit: BoxFit.cover,
          errorBuilder: (context, _, _) => hueco,
        ),
      ),
    );
  }
}

/// Botón relleno de ancho completo.
class BotonPrincipal extends StatelessWidget {
  const BotonPrincipal(
    this.etiqueta, {
    super.key,
    required this.onPressed,
    this.icono,
    this.color,
  });

  final String etiqueta;
  final VoidCallback? onPressed;
  final IconData? icono;

  /// Se usa para pintar en rojo las acciones destructivas.
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: CupertinoButton(
      onPressed: onPressed,
      color: color ?? context.acento,
      disabledColor: context.relleno,
      borderRadius: BorderRadius.circular(t.radioL),
      padding: const EdgeInsets.symmetric(vertical: t.m + 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null) ...[
            Icon(icono, size: 18, color: CupertinoColors.white),
            const SizedBox(width: t.s),
          ],
          // Flexible para que una etiqueta larga —o un tamaño de texto grande
          // por accesibilidad— no desborde el ancho disponible.
          Flexible(
            child: Text(
              etiqueta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: estilo(
                context,
                size: t.headline,
                weight: t.semibold,
                color: CupertinoColors.white,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Control `−  valor  +` para ajustar repeticiones o peso.
///
/// Más preciso a dedo que un slider, y no obliga a abrir el teclado. No hay
/// equivalente Cupertino en Flutter, así que se compone a mano.
///
/// Va en horizontal y sin etiqueta para que repeticiones y peso quepan en la
/// misma fila de una serie. El valor lo manda quien lo monta: la lista de
/// series vive en la pantalla, no aquí.
class SelectorEnLinea extends StatelessWidget {
  const SelectorEnLinea({
    super.key,
    required this.valor,
    required this.onChanged,
    this.minimo = 0,
    this.maximo = 999,
    this.paso = 1,
    this.unidad = '',
    this.decimales = 0,
    this.semantica,
  });

  final double valor;
  final ValueChanged<double> onChanged;
  final double minimo;
  final double maximo;
  final double paso;
  final String unidad;
  final int decimales;

  /// Nombre del campo para lectores de pantalla («Repeticiones», «Peso»).
  final String? semantica;

  String get _formateado {
    // Coma decimal: la interfaz está en español y `toStringAsFixed` siempre
    // escribe el punto, sea cual sea la localización.
    final cuerpo = decimales > 0
        ? valor.toStringAsFixed(decimales).replaceAll('.', ',')
        : valor.round().toString();
    return unidad.isEmpty ? cuerpo : '$cuerpo $unidad';
  }

  void _ajustar(double delta) {
    final nuevo = (valor + delta).clamp(minimo, maximo);
    if (nuevo == valor) return;
    onChanged(nuevo);
  }

  Widget _signo(BuildContext context, IconData icono, double delta) =>
      CupertinoButton(
        onPressed: () => _ajustar(delta),
        padding: const EdgeInsets.symmetric(horizontal: t.xs, vertical: t.s),
        minimumSize: Size.zero,
        child: Icon(icono, size: 16, color: context.acento),
      );

  @override
  Widget build(BuildContext context) => Semantics(
    label: semantica,
    value: _formateado,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: context.relleno,
        borderRadius: BorderRadius.circular(t.radioS),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _signo(context, CupertinoIcons.minus, -paso),
          // Flexible y con ellipsis: cuatro controles en una fila es justo el
          // caso en el que un tamaño de texto grande desbordaría el ancho.
          Flexible(
            child: Text(
              _formateado,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: estilo(context, size: t.subhead, weight: t.semibold),
            ),
          ),
          _signo(context, CupertinoIcons.plus, paso),
        ],
      ),
    ),
  );
}

/// Pantalla vacía con icono, mensaje y acción opcional.
class EstadoVacio extends StatelessWidget {
  const EstadoVacio({
    super.key,
    required this.icono,
    required this.titulo,
    this.subtitulo,
    this.accion,
  });

  final IconData icono;
  final String titulo;
  final String? subtitulo;
  final Widget? accion;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(t.xxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icono, size: 52, color: context.textoTer),
          const SizedBox(height: t.m),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: estilo(context, size: t.title3, weight: t.semibold),
          ),
          if (subtitulo != null) ...[
            const SizedBox(height: t.m),
            SizedBox(
              width: 280,
              child: Text(
                subtitulo!,
                textAlign: TextAlign.center,
                style: estilo(
                  context,
                  size: t.subhead,
                  color: context.textoSec,
                ),
              ),
            ),
          ],
          if (accion != null) ...[
            const SizedBox(height: t.xl),
            SizedBox(width: 220, child: accion),
          ],
        ],
      ),
    ),
  );
}

/// Indicador de carga centrado.
class Cargando extends StatelessWidget {
  const Cargando({super.key, this.mensaje});

  final String? mensaje;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CupertinoActivityIndicator(radius: 14),
        if (mensaje != null) ...[
          const SizedBox(height: t.m),
          Text(
            mensaje!,
            style: estilo(context, size: t.subhead, color: context.textoSec),
          ),
        ],
      ],
    ),
  );
}

/// Barra de progreso.
///
/// Se compone a mano porque `LinearProgressIndicator` es de Material y esta app
/// no lo importa: traería consigo todo el tema de Material.
class BarraProgreso extends StatelessWidget {
  const BarraProgreso(this.valor, {super.key});

  /// Entre 0 y 1.
  final double valor;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(t.radioS),
    child: Container(
      height: 6,
      color: context.relleno,
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: valor.clamp(0.0, 1.0),
        child: ColoredBox(color: context.acento),
      ),
    ),
  );
}

/// Envuelve una fila para poder borrarla deslizando hacia la izquierda.
///
/// A diferencia de Flet, `confirmDismiss` de Flutter **sí** respeta el valor
/// devuelto, así que basta con devolver el resultado del diálogo.
class DeslizarParaBorrar extends StatelessWidget {
  const DeslizarParaBorrar({
    super.key,
    required this.llave,
    required this.child,
    required this.onBorrar,
    this.titulo,
    this.mensaje,
  });

  final Key llave;
  final Widget child;
  final VoidCallback onBorrar;

  /// Si se indica, se pide confirmación antes de borrar.
  final String? titulo;
  final String? mensaje;

  @override
  Widget build(BuildContext context) => Dismissible(
    key: llave,
    direction: DismissDirection.endToStart,
    dismissThresholds: const {DismissDirection.endToStart: 0.4},
    background: Container(
      color: context.destructivo,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: t.xl),
      child: const Icon(
        CupertinoIcons.delete,
        color: CupertinoColors.white,
        size: 22,
      ),
    ),
    confirmDismiss: (_) async {
      if (titulo == null) return true;
      return dialogoConfirmar(context, titulo: titulo!, mensaje: mensaje ?? '');
    },
    onDismissed: (_) => onBorrar(),
    child: child,
  );
}

// ── Barras y diálogos ────────────────────────────────────────────────────────

/// Barra de navegación Cupertino, con el botón atrás automático.
CupertinoNavigationBar barra(
  BuildContext context, {
  String? titulo,
  Widget? izquierda,
  Widget? derecha,
  String? tituloAnterior,
}) => CupertinoNavigationBar(
  leading: izquierda,
  middle: titulo == null
      ? null
      : Text(
          titulo,
          style: estilo(context, size: t.headline, weight: t.semibold),
        ),
  trailing: derecha,
  previousPageTitle: tituloAnterior,
  backgroundColor: context.barra,
  border: Border(bottom: BorderSide(color: context.separador, width: 0.5)),
);

/// Selector de fecha en una hoja inferior. Devuelve null si se cancela.
///
/// Es `CupertinoDatePicker` tal cual: la localización en español ya la resuelve
/// `flutter_localizations` desde `main.dart`, así que no hace falta ni
/// dependencia ni componente propio.
Future<DateTime?> selectorFecha(
  BuildContext context, {
  required DateTime inicial,
  DateTime? maxima,
  DateTime? minima,
}) {
  var elegida = inicial;

  return showCupertinoModalPopup<DateTime>(
    context: context,
    builder: (hoja) => Container(
      height: 300,
      padding: const EdgeInsets.only(top: t.s),
      color: hoja.tarjeta,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(
                  onPressed: () => Navigator.pop(hoja),
                  child: const Text('Cancelar'),
                ),
                CupertinoButton(
                  onPressed: () => Navigator.pop(hoja, elegida),
                  child: Text(
                    'Listo',
                    style: estilo(hoja, weight: t.semibold, color: hoja.acento),
                  ),
                ),
              ],
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: inicial,
                minimumDate: minima,
                maximumDate: maxima,
                onDateTimeChanged: (valor) => elegida = valor,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Diálogo con un campo de texto. Devuelve el texto, o null si se cancela.
Future<String?> dialogoTexto(
  BuildContext context, {
  required String titulo,
  required String marcador,
  String valor = '',
  String? mensaje,
  String etiquetaAceptar = 'Guardar',
  bool permitirVacio = false,
}) {
  final controlador = TextEditingController(text: valor);

  return showCupertinoDialog<String>(
    context: context,
    builder: (dialogo) {
      void aceptar() {
        final actual = controlador.text.trim();
        // Un nombre de rutina en blanco no vale; una nota vaciada sí, que es
        // como se borra.
        if (actual.isEmpty && !permitirVacio) return;
        Navigator.pop(dialogo, actual);
      }

      return CupertinoAlertDialog(
        title: Text(titulo),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: t.s),
            if (mensaje != null) ...[
              Text(
                mensaje,
                textAlign: TextAlign.center,
                style: estilo(dialogo, size: t.footnote),
              ),
              const SizedBox(height: t.s),
            ],
            CupertinoTextField(
              controller: controlador,
              placeholder: marcador,
              autofocus: true,
              onSubmitted: (_) => aceptar(),
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialogo),
            child: const Text('Cancelar'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: aceptar,
            child: Text(etiquetaAceptar),
          ),
        ],
      );
    },
  ).whenComplete(controlador.dispose);
}

/// Diálogo de confirmación destructiva. Devuelve true si se acepta.
Future<bool> dialogoConfirmar(
  BuildContext context, {
  required String titulo,
  required String mensaje,
  String etiquetaAceptar = 'Eliminar',
}) async {
  final confirmado = await showCupertinoDialog<bool>(
    context: context,
    builder: (dialogo) => CupertinoAlertDialog(
      title: Text(titulo),
      content: Padding(
        padding: const EdgeInsets.only(top: t.s),
        child: Text(mensaje, textAlign: TextAlign.center),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(dialogo, false),
          child: const Text('Cancelar'),
        ),
        CupertinoDialogAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(dialogo, true),
          child: Text(etiquetaAceptar),
        ),
      ],
    ),
  );
  return confirmado ?? false;
}

/// Mensaje breve al pie de la pantalla.
///
/// iOS no tiene snackbars, así que se pinta como un aviso flotante que se retira
/// solo. Se apoya en el Overlay para no depender de la pantalla que lo lanza.
void aviso(BuildContext context, String mensaje) {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;

  late final OverlayEntry entrada;
  entrada = OverlayEntry(
    builder: (contexto) => Positioned(
      left: t.l,
      right: t.l,
      bottom: MediaQuery.of(contexto).padding.bottom + 72,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xE6000000),
            borderRadius: BorderRadius.circular(t.radioM),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: t.l, vertical: t.m),
            child: Text(
              mensaje,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: t.subhead,
                color: CupertinoColors.white,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  overlay.insert(entrada);
  Future.delayed(const Duration(milliseconds: 1800), entrada.remove);
}
