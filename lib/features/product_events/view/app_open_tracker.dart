import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:portfolio_assistant/features/product_events/providers/app_open_source_provider.dart';

/// Registra `app_opened{source}`: al montar el shell y cada vez que la app
/// vuelve a primer plano después de [minBackground] o más. Espera
/// [settleDelay] a que `WidgetLaunchListener` / `PushOpenListener` anoten
/// cómo se abrió (`appOpenSourceProvider`); sin marca, es `icon`.
class AppOpenTracker extends ConsumerStatefulWidget {
  const AppOpenTracker({
    super.key,
    required this.child,
    this.minBackground = const Duration(minutes: 30),
    this.settleDelay = const Duration(milliseconds: 1500),
    this.clock,
    this.onOpen,
  });

  final Widget child;

  /// Cuánto tiene que haber estado en segundo plano para contar otra
  /// apertura (intervalo provisorio, lo ajusta data).
  final Duration minBackground;
  final Duration settleDelay;

  /// Para tests.
  final DateTime Function()? clock;

  /// Se llama una vez por apertura contada (después de anotar el evento).
  final VoidCallback? onOpen;

  @override
  ConsumerState<AppOpenTracker> createState() => _AppOpenTrackerState();
}

class _AppOpenTrackerState extends ConsumerState<AppOpenTracker>
    with WidgetsBindingObserver {
  DateTime? _pausedAt;
  Timer? _timer;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _schedule(log: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _pausedAt ??= _now();
    } else if (state == AppLifecycleState.resumed) {
      final pausedAt = _pausedAt;
      _pausedAt = null;
      if (pausedAt == null) return;
      // Siempre se consume la marca (un toque del widget con la app tibia no
      // cuenta como apertura nueva, pero tampoco puede quedar pendiente).
      _schedule(log: _now().difference(pausedAt) >= widget.minBackground);
    }
  }

  void _schedule({required bool log}) {
    _timer?.cancel();
    _timer = Timer(widget.settleDelay, () {
      if (!mounted) return;
      final marker = ref.read(appOpenSourceProvider);
      ref.read(appOpenSourceProvider.notifier).state = null;
      if (!log) return;
      ref.read(productEventsProvider).log(ProductEvent.appOpened, {
        'source': (marker ?? AppOpenSource.icon).wire,
      });
      widget.onOpen?.call();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
