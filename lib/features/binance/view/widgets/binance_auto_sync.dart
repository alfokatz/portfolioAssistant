import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/binance/providers/binance_provider.dart';

/// Sincroniza Binance al abrir la app y al volver a ella, si lo último
/// tiene más de [BinanceNotifier.staleAfter]. Sin cuenta conectada solo lee
/// la conexión (ningún pedido a Binance).
class BinanceAutoSync extends ConsumerStatefulWidget {
  const BinanceAutoSync({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<BinanceAutoSync> createState() => _BinanceAutoSyncState();
}

class _BinanceAutoSyncState extends ConsumerState<BinanceAutoSync>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncIfStale());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _syncIfStale();
  }

  void _syncIfStale() {
    if (!mounted) return;
    ref.read(binanceProvider.notifier).syncIfStale();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
