import 'package:easy_localization/easy_localization.dart';
import 'package:portfolio_assistant/features/binance/domain/binance_connection.dart';
import 'package:portfolio_assistant/features/binance/providers/binance_provider.dart';
import 'package:portfolio_assistant/features/etoro/domain/etoro_connection.dart';
import 'package:portfolio_assistant/features/etoro/providers/etoro_connection_provider.dart';
import 'package:portfolio_assistant/features/etoro/view/widgets/etoro_sync_note.dart';
import 'package:portfolio_assistant/features/snaptrade/domain/snaptrade_connection.dart';
import 'package:portfolio_assistant/features/snaptrade/providers/snaptrade_provider.dart';

/// El estado de cada conexión en una línea, para Ajustes y para "Conectá tu
/// bróker". `null` mientras no se sabe (sin saltos de texto).
abstract final class BrokerStatusLabels {
  static String? etoro(EtoroState state) {
    if (!state.loaded) return null;
    final connection = state.connection;
    return switch (connection.status) {
      EtoroConnectionStatus.notConnected => null,
      EtoroConnectionStatus.reconnectRequired =>
        'etoro_settings_reconnect'.tr(),
      EtoroConnectionStatus.connected =>
        connection.lastSyncAt == null
            ? 'etoro_settings_connected'.tr()
            : 'etoro_settings_connected_synced'.tr(
              namedArgs: {
                'when': EtoroSyncTime.relative(connection.lastSyncAt!),
              },
            ),
    };
  }

  static String? binance(BinanceState state) {
    if (!state.loaded) return null;
    return switch (state.connection.status) {
      BinanceStatus.notConnected => null,
      BinanceStatus.reconnectRequired => 'binance_settings_reconnect'.tr(),
      BinanceStatus.connected =>
        state.connection.lastSyncAt == null
            ? 'binance_settings_connected'.tr()
            : 'etoro_settings_connected_synced'.tr(
              namedArgs: {
                'when': EtoroSyncTime.relative(state.connection.lastSyncAt!),
              },
            ),
    };
  }

  /// Los otros brókers: sus nombres si hay alguno conectado.
  static String? snaptrade(SnaptradeState state) {
    if (!state.loaded) return null;
    final c = state.connection;
    final names = [for (final b in c.imported) b.name].join(', ');
    return switch (c.status) {
      SnaptradeStatus.notConnected || SnaptradeStatus.pending => null,
      SnaptradeStatus.reconnectRequired => 'snaptrade_settings_reconnect'.tr(),
      SnaptradeStatus.connected when c.imported.any((b) => b.disabled) =>
        'snaptrade_settings_reconnect'.tr(),
      SnaptradeStatus.connected =>
        names.isEmpty ? 'snaptrade_settings_connected'.tr() : names,
    };
  }

  /// Los brókers conectados, por nombre ("eToro, Binance, IBKR"), o vacío.
  static List<String> connectedNames({
    required EtoroState etoro,
    required BinanceState binance,
    required SnaptradeState snaptrade,
  }) => [
    if (etoro.connection.status != EtoroConnectionStatus.notConnected) 'eToro',
    if (binance.connection.isConnected) 'Binance',
    if (snaptrade.connection.isConnected)
      for (final b in snaptrade.connection.imported) b.name,
  ];
}
