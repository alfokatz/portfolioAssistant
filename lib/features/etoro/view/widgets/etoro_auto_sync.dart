import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/etoro/providers/etoro_connection_provider.dart';

/// Sincroniza eToro al abrir la app y al volver a ella, si lo último tiene
/// más de [EtoroConnectionNotifier.staleAfter]. Sin UI: la Home recarga sola
/// cuando llegan datos nuevos (ver `importRevision`). Sin cuenta conectada
/// no hace ningún pedido a eToro (solo lee la conexión).
class EtoroAutoSync extends ConsumerStatefulWidget {
  const EtoroAutoSync({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<EtoroAutoSync> createState() => _EtoroAutoSyncState();
}

class _EtoroAutoSyncState extends ConsumerState<EtoroAutoSync>
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
    ref.read(etoroConnectionProvider.notifier).syncIfStale();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
