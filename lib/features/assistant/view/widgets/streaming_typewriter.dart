import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// El typewriter de Porty sobre un texto que todavía está llegando (la
/// vista previa del streaming): revela palabra por palabra al mismo ritmo
/// que [TypewriterText] y, cuando llega más texto, sigue desde donde iba
/// en vez de empezar de nuevo. Si alcanza al texto que llegó, espera.
///
/// [onRevealed] avisa lo que ya se ve, para que la respuesta final siga
/// tipeando desde ahí (ver `QaStreamedTextScope`).
///
/// Accesibilidad y reduced motion: igual que [TypewriterText] (el texto
/// recibido entero va en semantics; sin animaciones se muestra de una).
class StreamingTypewriter extends StatefulWidget {
  const StreamingTypewriter({
    super.key,
    required this.text,
    required this.builder,
    this.charsPerSecond = 40,
    this.onWordRevealed,
    this.onRevealed,
  });

  /// Lo recibido hasta ahora; solo crece (si cambia el principio, sigue
  /// desde lo que coincide).
  final String text;
  final Widget Function(BuildContext context, String visible) builder;
  final double charsPerSecond;

  /// Ver [TypewriterText.onWordRevealed].
  final VoidCallback? onWordRevealed;
  final ValueChanged<String>? onRevealed;

  @override
  State<StreamingTypewriter> createState() => _StreamingTypewriterState();
}

class _StreamingTypewriterState extends State<StreamingTypewriter>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  Duration _lastTick = Duration.zero;

  /// Caracteres visibles, con la fracción acumulada entre frames.
  double _visible = 0;
  int _shown = 0;

  bool get _reducedMotion => MediaQuery.disableAnimationsOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant StreamingTypewriter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.text.startsWith(oldWidget.text.substring(0, _shown))) {
      // Cambió lo que ya se veía: sigue desde lo que todavía coincide.
      var same = 0;
      final limit = _shown < widget.text.length ? _shown : widget.text.length;
      while (same < limit &&
          widget.text.codeUnitAt(same) == oldWidget.text.codeUnitAt(same)) {
        same++;
      }
      _shown = same;
      _visible = same.toDouble();
    }
    _sync();
  }

  void _sync() {
    if (_reducedMotion) {
      if (_shown != widget.text.length) {
        _shown = widget.text.length;
        _visible = _shown.toDouble();
        _report();
      }
      return;
    }
    if (_shown < widget.text.length && !_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final dt = elapsed - _lastTick;
    _lastTick = elapsed;
    final target = widget.text.length;
    if (_shown >= target) {
      _ticker.stop();
      return;
    }
    _visible = (_visible + dt.inMicroseconds / 1e6 * widget.charsPerSecond)
        .clamp(0, target.toDouble());
    final next = _visible.floor();
    if (next == _shown) return;
    final from = _shown;
    setState(() => _shown = next);
    _wordTick(from, next);
    _report();
  }

  void _wordTick(int from, int to) {
    final onWord = widget.onWordRevealed;
    if (onWord == null) return;
    final text = widget.text;
    for (var i = from < 1 ? 1 : from; i < to; i++) {
      if (_isWhitespace(text.codeUnitAt(i)) &&
          !_isWhitespace(text.codeUnitAt(i - 1))) {
        onWord();
        return;
      }
    }
  }

  void _report() => widget.onRevealed?.call(widget.text.substring(0, _shown));

  static bool _isWhitespace(int c) => c == 0x20 || c == 0x0A || c == 0x09;

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown.clamp(0, widget.text.length);
    return Semantics(
      label: widget.text,
      child: ExcludeSemantics(
        child: widget.builder(context, widget.text.substring(0, shown)),
      ),
    );
  }
}
