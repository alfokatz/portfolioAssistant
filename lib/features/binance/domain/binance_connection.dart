enum BinanceStatus {
  notConnected,
  connected,
  reconnectRequired;

  static BinanceStatus fromWire(String? value) => switch (value) {
    'connected' => BinanceStatus.connected,
    'reconnect_required' => BinanceStatus.reconnectRequired,
    _ => BinanceStatus.notConnected,
  };
}

/// Lo que no se importó y por qué: `cash` (USDT, USDC, monedas), `dust`
/// (menos de USD 1) o `no_price`.
class BinanceSkipped {
  const BinanceSkipped(this.asset, this.reason);

  final String asset;
  final String reason;
}

/// Resumen de la última sincronización (lo arma `binance-sync`).
class BinanceSyncResult {
  const BinanceSyncResult({
    required this.imported,
    this.notImported = const [],
    this.estimatedCost = const [],
  });

  final int imported;
  final List<BinanceSkipped> notImported;

  /// Tickers sin historial suficiente: Porty usó el precio de ese momento
  /// como precio de compra.
  final List<String> estimatedCost;

  static BinanceSyncResult? fromJson(Object? json) {
    if (json is! Map) return null;
    final skipped = json['notImported'];
    final estimated = json['estimatedCost'];
    return BinanceSyncResult(
      imported: (json['imported'] as num?)?.toInt() ?? 0,
      notImported: [
        if (skipped is List)
          for (final s in skipped)
            if (s is Map && s['asset'] is String)
              BinanceSkipped(s['asset'] as String, '${s['reason']}'),
      ],
      estimatedCost: [if (estimated is List) ...estimated.whereType<String>()],
    );
  }
}

class BinanceConnection {
  const BinanceConnection({
    this.status = BinanceStatus.notConnected,
    this.apiKeyHint,
    this.lastSyncAt,
    this.lastResult,
    this.lastErrorType,
  });

  final BinanceStatus status;

  /// Los últimos 4 caracteres de la clave.
  final String? apiKeyHint;
  final DateTime? lastSyncAt;
  final BinanceSyncResult? lastResult;
  final String? lastErrorType;

  bool get isConnected => status != BinanceStatus.notConnected;

  static BinanceConnection fromRow(Map<String, dynamic>? row) {
    if (row == null) return const BinanceConnection();
    final synced = row['last_sync_at'];
    return BinanceConnection(
      status: BinanceStatus.fromWire(row['status'] as String?),
      apiKeyHint: row['api_key_hint'] as String?,
      lastSyncAt: synced is String ? DateTime.parse(synced).toLocal() : null,
      lastResult: BinanceSyncResult.fromJson(row['last_result']),
      lastErrorType: row['last_error_type'] as String?,
    );
  }
}
