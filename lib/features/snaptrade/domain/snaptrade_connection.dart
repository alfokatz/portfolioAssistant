enum SnaptradeStatus {
  notConnected,

  /// Tiene usuario en SnapTrade pero todavía no conectó un bróker (abrió el
  /// portal y lo cerró, por ejemplo).
  pending,
  connected,
  reconnectRequired;

  static SnaptradeStatus fromWire(String? value) => switch (value) {
    'pending' => SnaptradeStatus.pending,
    'connected' => SnaptradeStatus.connected,
    'reconnect_required' => SnaptradeStatus.reconnectRequired,
    _ => SnaptradeStatus.notConnected,
  };
}

/// Un bróker conectado en SnapTrade.
class SnaptradeBrokerage {
  const SnaptradeBrokerage({
    required this.id,
    required this.name,
    this.disabled = false,
    this.imported = true,
    this.reason,
    this.url,
  });

  final String id;
  final String name;

  /// La web del bróker (solo https), para "Abrir en tu bróker".
  final Uri? url;

  /// La conexión se cayó en el bróker: hay que reconectarla.
  final bool disabled;

  /// false: está conectado pero Porty no lo importa.
  final bool imported;

  /// Por qué no se importa: `plan_limit` (Premium importa uno),
  /// `direct_connection` (eToro y Binance se conectan directo) o
  /// `trade_permissions`.
  final String? reason;

  static SnaptradeBrokerage? fromJson(Object? json) {
    if (json is! Map || json['id'] is! String) return null;
    return SnaptradeBrokerage(
      id: json['id'] as String,
      name:
          (json['name'] as String?)?.trim().isNotEmpty == true
              ? json['name'] as String
              : '—',
      disabled: json['disabled'] == true,
      imported: json['imported'] != false,
      reason: json['reason'] as String?,
      url: switch (Uri.tryParse('${json['url'] ?? ''}')) {
        final u? when u.scheme == 'https' && u.host.isNotEmpty => u,
        _ => null,
      },
    );
  }
}

/// Lo que no se importó y por qué: `cash`, `unsupported` (opciones,
/// futuros, bonos…), `short` o `no_price`.
class SnaptradeSkipped {
  const SnaptradeSkipped(this.ticker, this.broker, this.reason);

  final String ticker;
  final String broker;
  final String reason;
}

/// Resumen de la última sincronización (lo arma `snaptrade-sync`).
class SnaptradeSyncResult {
  const SnaptradeSyncResult({
    required this.imported,
    this.notImported = const [],
    this.estimatedCost = const [],
  });

  final int imported;
  final List<SnaptradeSkipped> notImported;

  /// Tickers sin precio de compra del bróker: Porty usó el precio de ese
  /// momento.
  final List<String> estimatedCost;

  static SnaptradeSyncResult? fromJson(Object? json) {
    if (json is! Map) return null;
    final skipped = json['notImported'];
    final estimated = json['estimatedCost'];
    return SnaptradeSyncResult(
      imported: (json['imported'] as num?)?.toInt() ?? 0,
      notImported: [
        if (skipped is List)
          for (final s in skipped)
            if (s is Map && s['ticker'] is String)
              SnaptradeSkipped(
                s['ticker'] as String,
                '${s['broker'] ?? ''}',
                '${s['reason']}',
              ),
      ],
      estimatedCost: [if (estimated is List) ...estimated.whereType<String>()],
    );
  }
}

class SnaptradeConnection {
  const SnaptradeConnection({
    this.status = SnaptradeStatus.notConnected,
    this.brokerages = const [],
    this.lastSyncAt,
    this.lastResult,
    this.lastErrorType,
  });

  final SnaptradeStatus status;
  final List<SnaptradeBrokerage> brokerages;
  final DateTime? lastSyncAt;
  final SnaptradeSyncResult? lastResult;
  final String? lastErrorType;

  /// Tiene al menos un bróker conectado (o lo tuvo y hay que reconectar).
  bool get isConnected =>
      status == SnaptradeStatus.connected ||
      status == SnaptradeStatus.reconnectRequired;

  /// Los que Porty importa.
  List<SnaptradeBrokerage> get imported => [
    for (final b in brokerages)
      if (b.imported) b,
  ];

  /// Conectados pero no importados porque el plan no alcanza.
  List<SnaptradeBrokerage> get overPlanLimit => [
    for (final b in brokerages)
      if (b.reason == 'plan_limit') b,
  ];

  static SnaptradeConnection fromRow(Map<String, dynamic>? row) {
    if (row == null) return const SnaptradeConnection();
    final synced = row['last_sync_at'];
    final brokerages = row['brokerages'];
    return SnaptradeConnection(
      status: SnaptradeStatus.fromWire(row['status'] as String?),
      brokerages: [
        if (brokerages is List)
          for (final b in brokerages)
            if (SnaptradeBrokerage.fromJson(b) case final brokerage?) brokerage,
      ],
      lastSyncAt: synced is String ? DateTime.parse(synced).toLocal() : null,
      lastResult: SnaptradeSyncResult.fromJson(row['last_result']),
      lastErrorType: row['last_error_type'] as String?,
    );
  }
}
