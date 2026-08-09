/// Primer arranque: descarga de las imágenes y animaciones de los ejercicios.
///
/// La media no se empaqueta en el APK (es © Gym visual), así que o se descarga
/// aquí o se resuelve contra internet según haga falta. Por eso «Ahora no» es
/// una salida legítima y no un atajo: la app funciona igual sin descargar nada.
library;

import 'package:flutter/cupertino.dart';

import '../datos/media.dart' as media;
import '../datos/semilla.dart';
import '../l10n/textos.dart';
import '../tema/tokens.dart';
import '../tema/tokens.dart' as t;
import '../tema/ui.dart' as ui;

class PantallaSetup extends StatefulWidget {
  const PantallaSetup({
    super.key,
    required this.catalogo,
    required this.onEntrar,
  });

  final List<EjercicioJson> catalogo;
  final VoidCallback onEntrar;

  @override
  State<PantallaSetup> createState() => _PantallaSetupState();
}

class _PantallaSetupState extends State<PantallaSetup> {
  late final int _pendientes = media.rutasPendientes(widget.catalogo).length;

  bool _descargando = false;
  bool _cancelado = false;
  bool _salido = false;
  int _hechos = 0;
  int _fallos = 0;
  String? _detalle;

  /// La descarga corre en paralelo, así que puede intentar entrar a la vez que
  /// el usuario pulsa «Ahora no»: solo vale la primera.
  void _entrar() {
    if (_salido) return;
    _salido = true;
    widget.onEntrar();
  }

  void _omitir() {
    _cancelado = true;
    _entrar();
  }

  Future<void> _descargar() async {
    if (_descargando) return;
    setState(() {
      _descargando = true;
      _detalle = context.t.setupProgreso(0, _pendientes);
    });

    final resultado = await media.descargarTodo(
      widget.catalogo,
      cancelado: () => _cancelado,
      alProgresar: (hechos, total, fallos) {
        if (!mounted) return;
        setState(() {
          _hechos = hechos;
          _fallos = fallos;
          _detalle =
              context.t.setupProgreso(hechos, total) +
              (fallos > 0 ? context.t.setupFallidos(fallos) : '');
        });
      },
    );

    if (!mounted) return;
    if (resultado.fallos > 0) {
      setState(() {
        _detalle = context.t.setupFallosFinal(resultado.fallos);
      });
    }
    _entrar();
  }

  @override
  Widget build(BuildContext context) {
    if (_pendientes == 0) {
      // No hay nada que descargar: la media ya estaba en disco.
      return ui.EstadoVacio(
        icono: CupertinoIcons.check_mark_circled,
        titulo: context.t.setupTodoListo,
        subtitulo: context.t.setupTodoListoDetalle,
        accion: ui.BotonPrincipal(context.t.setupEmpezar, onPressed: _entrar),
      );
    }

    // Media ponderada aproximada entre los JPG (6 KB) y los GIF (93 KB).
    final megas = _pendientes * 50 ~/ 1024;

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(t.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.acento,
                  borderRadius: BorderRadius.circular(t.radioXl),
                ),
                child: const Icon(
                  CupertinoIcons.sparkles,
                  size: 44,
                  color: CupertinoColors.white,
                ),
              ),
              const SizedBox(height: t.l),
              Text(
                context.t.setupCatalogoListo,
                textAlign: TextAlign.center,
                style: ui.estilo(context, size: t.title1, weight: t.bold),
              ),
              const SizedBox(height: t.s),
              SizedBox(
                width: 300,
                child: Text(
                  context.t.setupDetalle,
                  textAlign: TextAlign.center,
                  style: ui.estilo(
                    context,
                    size: t.subhead,
                    color: context.textoSec,
                  ),
                ),
              ),
              const SizedBox(height: t.l),
              SizedBox(
                width: 320,
                child: ui.Grupo(
                  filas: [
                    CupertinoListTile(
                      backgroundColor: context.tarjeta,
                      leading: Icon(
                        CupertinoIcons.photo_on_rectangle,
                        color: context.acento,
                        size: 24,
                      ),
                      title: Text(
                        context.t.setupMedia,
                        style: ui.estilo(context),
                      ),
                      subtitle: Text(
                        context.t.setupTamano(_pendientes, megas),
                        style: ui.estilo(
                          context,
                          size: t.footnote,
                          color: context.textoSec,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: t.l),
              if (_descargando)
                SizedBox(
                  width: 300,
                  child: ui.BarraProgreso(
                    _pendientes == 0 ? 1 : _hechos / _pendientes,
                  ),
                ),
              if (_detalle != null) ...[
                const SizedBox(height: t.s),
                SizedBox(
                  width: 300,
                  child: Text(
                    _detalle!,
                    textAlign: TextAlign.center,
                    style: ui.estilo(
                      context,
                      size: t.footnote,
                      color: _fallos > 0
                          ? context.destructivo
                          : context.textoSec,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: t.l),
              SizedBox(
                width: 300,
                child: ui.BotonPrincipal(
                  _descargando
                      ? context.t.setupDescargando
                      : context.t.setupDescargar,
                  icono: CupertinoIcons.cloud_download,
                  onPressed: _descargando ? null : _descargar,
                ),
              ),
              CupertinoButton(
                onPressed: _omitir,
                child: Text(
                  context.t.setupAhoraNo,
                  style: ui.estilo(context, color: context.textoSec),
                ),
              ),
              SizedBox(
                width: 300,
                child: Text(
                  context.t.setupOmitirDetalle,
                  textAlign: TextAlign.center,
                  style: ui.estilo(
                    context,
                    size: t.caption,
                    color: context.textoTer,
                  ),
                ),
              ),
              const SizedBox(height: t.l),
              Text(
                media.atribucion,
                textAlign: TextAlign.center,
                style: ui.estilo(
                  context,
                  size: t.caption,
                  color: context.textoTer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
