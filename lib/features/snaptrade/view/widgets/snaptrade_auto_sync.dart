import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/snaptrade/providers/snaptrade_provider.dart';

/// Sincroniza los brókers conectados por SnapTrade al abrir la app y al
/// volver a ella, si lo último tiene más de [SnaptradeNotifier.staleAfter].
/// Sin nada conectado solo lee la conexión (ningún pedido a SnapTrade).
class SnaptradeAutoSync extends ConsumerStatefulWidget {
  const SnaptradeAutoSync({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SnaptradeAutoSync> createState() => _SnaptradeAutoSyncState();
}

class _SnaptradeAutoSyncState extends ConsumerState<SnaptradeAutoSync>
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
    ref.read(snaptradeProvider.notifier).syncIfStale();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
