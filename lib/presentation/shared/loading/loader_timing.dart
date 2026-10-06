import 'dart:async';

import 'package:flutter/widgets.dart';

/// Tiempos de todos los loaders de la app (skeletons, `PortyLoader`,
/// spinners de botón), en un solo lugar.
abstract final class LoaderTiming {
  /// Una espera más corta que esto no muestra ningún loader: así una carga
  /// rápida no titila.
  static const showDelay = Duration(milliseconds: 300);

  /// Una vez visible, el loader se queda al menos esto: no parpadea.
  static const minVisible = Duration(milliseconds: 400);

  /// Crossfade loader → contenido.
  static const swap = Duration(milliseconds: 200);
  static const swapCurve = Curves.easeOutCubic;

  /// Si la espera de un `PortyLoader` pasa de esto, aparece su línea.
  static const messageDelay = Duration(seconds: 2);
}

/// Decide si un loader tiene que estar en pantalla para [loading]: aparece
/// recién después de [delay] seguidos cargando y, una vez visible, se queda
/// al menos [minVisible] aunque la carga termine antes.
///
/// Solo usa timers (nada de relojes de pared), así que se prueba con el
/// tiempo falso de los widget tests.
class DelayedLoaderVisibility extends StatefulWidget {
  const DelayedLoaderVisibility({
    super.key,
    required this.loading,
    required this.builder,
    this.delay = LoaderTiming.showDelay,
    this.minVisible = LoaderTiming.minVisible,
  });

  final bool loading;

  /// `showLoader`: si el loader va en pantalla en este momento.
  final Widget Function(BuildContext context, bool showLoader) builder;
  final Duration delay;
  final Duration minVisible;

  @override
  State<DelayedLoaderVisibility> createState() =>
      _DelayedLoaderVisibilityState();
}

class _DelayedLoaderVisibilityState extends State<DelayedLoaderVisibility> {
  bool _show = false;
  bool _minElapsed = true;
  Timer? _delayTimer;
  Timer? _minTimer;

  @override
  void initState() {
    super.initState();
    if (widget.loading) _scheduleShow();
  }

  @override
  void didUpdateWidget(DelayedLoaderVisibility oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loading == oldWidget.loading) return;
    if (widget.loading) {
      if (!_show) _scheduleShow();
    } else {
      _delayTimer?.cancel();
      _delayTimer = null;
      if (_show && _minElapsed) _show = false;
    }
  }

  void _scheduleShow() {
    if (widget.delay == Duration.zero) {
      _showNow(rebuild: false);
      return;
    }
    _delayTimer = Timer(widget.delay, () {
      _delayTimer = null;
      if (mounted && widget.loading) _showNow(rebuild: true);
    });
  }

  void _showNow({required bool rebuild}) {
    void apply() {
      _show = true;
      _minElapsed = false;
    }

    rebuild ? setState(apply) : apply();
    _minTimer?.cancel();
    _minTimer = Timer(widget.minVisible, () {
      _minTimer = null;
      _minElapsed = true;
      if (mounted && !widget.loading) setState(() => _show = false);
    });
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _minTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _show);
}

/// Contenido que puede estar cargando: mientras [loading] muestra
/// [placeholder] (un skeleton o un `PortyLoader`) con las reglas de
/// [DelayedLoaderVisibility], y pasa a [child] con un crossfade de
/// [LoaderTiming.swap] (instantáneo con reduce motion).
///
/// En los primeros [LoaderTiming.showDelay] de una carga se ve [pending]:
/// por defecto, nada (el fondo de la pantalla; dura a lo sumo 300 ms).
class LoadingSwitcher extends StatelessWidget {
  const LoadingSwitcher({
    super.key,
    required this.loading,
    required this.placeholder,
    required this.child,
    this.pending,
    this.alignment = Alignment.topCenter,
  });

  final bool loading;
  final WidgetBuilder placeholder;
  final WidgetBuilder child;
  final WidgetBuilder? pending;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return DelayedLoaderVisibility(
      loading: loading,
      builder: (context, showLoader) {
        final (String key, WidgetBuilder build) =
            showLoader
                ? ('loader', placeholder)
                : loading
                ? ('pending', pending ?? (_) => const SizedBox.shrink())
                : ('content', child);
        return AnimatedSwitcher(
          duration: reduceMotion ? Duration.zero : LoaderTiming.swap,
          switchInCurve: LoaderTiming.swapCurve,
          switchOutCurve: LoaderTiming.swapCurve,
          layoutBuilder:
              (current, previous) => Stack(
                alignment: alignment,
                children: [...previous, if (current != null) current],
              ),
          child: KeyedSubtree(key: ValueKey(key), child: build(context)),
        );
      },
    );
  }
}
