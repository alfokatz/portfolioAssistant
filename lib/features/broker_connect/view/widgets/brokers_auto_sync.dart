import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/binance/domain/binance_connection.dart';
import 'package:portfolio_assistant/features/binance/providers/binance_provider.dart';
import 'package:portfolio_assistant/features/etoro/providers/etoro_connection_provider.dart';
import 'package:portfolio_assistant/features/snaptrade/providers/snaptrade_provider.dart';

/// Sincroniza los brókers conectados (eToro, Binance, SnapTrade) al abrir
/// la app y al volver a ella, cada uno si lo último ya es viejo para él
/// (ver `isSyncDue` y el `staleAfter` de cada notifier). Sin nada conectado
/// solo lee las conexiones (ningún pedido a los brókers). La Home se
/// recarga sola con el `onImported` de cada provider.
///
/// Además, apenas el usuario conecta eToro o Binance directo, sincroniza
/// SnapTrade ya: el servidor saca ese bróker de SnapTrade (no se duplica ni
/// se paga).
class BrokersAutoSync extends ConsumerStatefulWidget {
  const BrokersAutoSync({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<BrokersAutoSync> createState() => _BrokersAutoSyncState();
}

class _BrokersAutoSyncState extends ConsumerState<BrokersAutoSync>
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
    ref.read(binanceProvider.notifier).syncIfStale();
    ref.read(snaptradeProvider.notifier).syncIfStale();
  }

  /// Conectó directo un bróker que también tenía por SnapTrade.
  void _directConnected(String broker) {
    final s = ref.read(snaptradeProvider).connection;
    if (s.imported.any((b) => b.directBroker == broker)) {
      ref.read(snaptradeProvider.notifier).sync(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      etoroConnectionProvider.select((s) => s.connection.isConnected),
      (was, now) {
        if (was == false && now) _directConnected('etoro');
      },
    );
    ref.listen(
      binanceProvider.select(
        (s) => s.connection.status == BinanceStatus.connected,
      ),
      (was, now) {
        if (was == false && now) _directConnected('binance');
      },
    );
    return widget.child;
  }
}
