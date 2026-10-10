import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';

/// Reconstruye cada segundo hasta [until] (bloqueo por intentos, espera para
/// reenviar un email). [builder] recibe lo que falta, o `null` cuando ya
/// venció (y deja de tickear).
class AuthCountdown extends StatefulWidget {
  const AuthCountdown({
    super.key,
    required this.until,
    required this.builder,
    this.now,
  });

  final DateTime? until;
  final Widget Function(BuildContext context, Duration? remaining) builder;

  /// Por defecto, `clock.now()` (en los tests sigue al tiempo simulado).
  final DateTime Function()? now;

  /// `0:42`, `1:05`. Siempre redondea para arriba: nunca muestra `0:00`
  /// mientras sigue bloqueado.
  static String format(Duration remaining) {
    final total = (remaining.inMilliseconds / 1000).ceil();
    final minutes = total ~/ 60;
    final seconds = (total % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  State<AuthCountdown> createState() => _AuthCountdownState();
}

class _AuthCountdownState extends State<AuthCountdown> {
  Timer? _timer;

  Duration? get _remaining {
    final until = widget.until;
    if (until == null) return null;
    final left = until.difference((widget.now ?? clock.now)());
    return left > Duration.zero ? left : null;
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(AuthCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.until != widget.until) _sync();
  }

  void _sync() {
    _timer?.cancel();
    _timer = null;
    if (_remaining == null) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (_remaining == null) {
        _timer?.cancel();
        _timer = null;
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _remaining);
}
