/// Estado de la conexión con eToro tal como lo guarda el servidor
/// (`etoro_connections`, ver supabase/migrations/20261009000000_etoro_sync.sql).
enum EtoroConnectionStatus {
  notConnected,
  connected,

  /// eToro invalidó la sesión (venció o el usuario la revocó desde eToro):
  /// las posiciones importadas siguen, pero no se actualizan hasta
  /// reconectar.
  reconnectRequired;

  static EtoroConnectionStatus fromWire(String? value) => switch (value) {
    'connected' => EtoroConnectionStatus.connected,
    'reconnect_required' => EtoroConnectionStatus.reconnectRequired,
    _ => EtoroConnectionStatus.notConnected,
  };
}

/// Por qué una posición de eToro no se importó. Los nombres de la base son
/// los de `NotImportedReason` en supabase/functions/etoro-sync/mapping.ts.
enum EtoroSkipReason {
  cfd,
  leveraged,
  short,
  copyTrading,
  crypto,
  nonUs,
  unsupportedType,
  unknownInstrument;

  static EtoroSkipReason fromWire(String? value) => switch (value) {
    'cfd' => EtoroSkipReason.cfd,
    'leveraged' => EtoroSkipReason.leveraged,
    'short' => EtoroSkipReason.short,
    'copy_trading' => EtoroSkipReason.copyTrading,
    'crypto' => EtoroSkipReason.crypto,
    'non_us' => EtoroSkipReason.nonUs,
    'unsupported_type' => EtoroSkipReason.unsupportedType,
    _ => EtoroSkipReason.unknownInstrument,
  };

  /// Clave de traducción con la explicación en lenguaje simple.
  String get explanationKey => switch (this) {
    EtoroSkipReason.cfd => 'etoro_skip_cfd',
    EtoroSkipReason.leveraged => 'etoro_skip_leveraged',
    EtoroSkipReason.short => 'etoro_skip_short',
    EtoroSkipReason.copyTrading => 'etoro_skip_copy_trading',
    EtoroSkipReason.crypto => 'etoro_skip_crypto',
    EtoroSkipReason.nonUs => 'etoro_skip_non_us',
    EtoroSkipReason.unsupportedType => 'etoro_skip_unsupported_type',
    EtoroSkipReason.unknownInstrument => 'etoro_skip_unknown_instrument',
  };
}

class EtoroNotImportedItem {
  const EtoroNotImportedItem({
    required this.ticker,
    required this.reason,
    required this.count,
    this.name,
  });

  final String ticker;
  final String? name;
  final EtoroSkipReason reason;

  /// Cuántas posiciones de ese ticker por ese motivo.
  final int count;

  factory EtoroNotImportedItem.fromJson(Map<String, dynamic> json) =>
      EtoroNotImportedItem(
        ticker: (json['ticker'] as String?) ?? '?',
        name: json['name'] as String?,
        reason: EtoroSkipReason.fromWire(json['reason'] as String?),
        count: (json['count'] as num?)?.toInt() ?? 1,
      );
}

/// Algo que el usuario tiene en eToro y Porty no importa como posición
/// (cripto, CFD, fuera de EE.UU., apalancado, en corto), con el valor y el
/// P&L que calcula eToro. Se muestra aparte, sin sumarlo al total de Porty.
class EtoroOtherHolding {
  const EtoroOtherHolding({
    required this.ticker,
    required this.reason,
    required this.count,
    required this.units,
    required this.investedUsd,
    required this.valueUsd,
    required this.pnlUsd,
    this.name,
  });

  final String ticker;
  final String? name;
  final EtoroSkipReason reason;

  /// Cuántas posiciones de eToro se agruparon.
  final int count;
  final double units;
  final double investedUsd;
  final double valueUsd;
  final double pnlUsd;

  /// P&L sobre lo invertido, en porcentaje. `null` si no hay inversión.
  double? get pnlPercent => investedUsd > 0 ? pnlUsd / investedUsd * 100 : null;

  static double _n(Object? v) => v is num ? v.toDouble() : 0;

  factory EtoroOtherHolding.fromJson(Map<String, dynamic> json) =>
      EtoroOtherHolding(
        ticker: (json['ticker'] as String?) ?? '?',
        name: json['name'] as String?,
        reason: EtoroSkipReason.fromWire(json['reason'] as String?),
        count: (json['count'] as num?)?.toInt() ?? 1,
        units: _n(json['units']),
        investedUsd: _n(json['investedUsd']),
        valueUsd: _n(json['valueUsd']),
        pnlUsd: _n(json['pnlUsd']),
      );
}

/// Resumen de la última importación (lo arma el servidor en cada sync).
class EtoroImportResult {
  const EtoroImportResult({
    required this.imported,
    required this.closedImported,
    required this.notImported,
    required this.closedNotImported,
    required this.possibleDuplicates,
    required this.syncedAt,
    this.cashUsd,
    this.otherHoldings = const [],
    this.logos = const {},
  });

  /// Posiciones abiertas importadas (cada compra cuenta por separado).
  final int imported;
  final int closedImported;
  final List<EtoroNotImportedItem> notImported;
  final List<EtoroNotImportedItem> closedNotImported;

  /// Tickers que el usuario ya tenía cargados a mano y también llegaron de
  /// eToro.
  final List<String> possibleDuplicates;
  final DateTime? syncedAt;

  /// Efectivo disponible en eToro, en USD. `null` si eToro no lo informó
  /// (o el resultado es de antes de que el servidor lo guardara).
  final double? cashUsd;

  /// Lo que no se importa como posición, ordenado por valor.
  final List<EtoroOtherHolding> otherHoldings;

  /// Logo de eToro por ticker (en mayúsculas). Respaldo de Finnhub.
  final Map<String, String> logos;

  double get otherHoldingsValueUsd =>
      otherHoldings.fold(0, (sum, h) => sum + h.valueUsd);
  double get otherHoldingsPnlUsd =>
      otherHoldings.fold(0, (sum, h) => sum + h.pnlUsd);

  /// Hay algo para la card "Además en eToro".
  bool get hasExtras =>
      otherHoldings.isNotEmpty || (cashUsd != null && cashUsd! > 0);

  int get notImportedCount =>
      notImported.fold(0, (sum, item) => sum + item.count);

  static List<EtoroNotImportedItem> _items(Object? raw) => [
    if (raw is List)
      for (final e in raw)
        if (e is Map)
          EtoroNotImportedItem.fromJson(Map<String, dynamic>.from(e)),
  ];

  factory EtoroImportResult.fromJson(Map<String, dynamic> json) =>
      EtoroImportResult(
        imported: (json['imported'] as num?)?.toInt() ?? 0,
        closedImported: (json['closedImported'] as num?)?.toInt() ?? 0,
        notImported: _items(json['notImported']),
        closedNotImported: _items(json['closedNotImported']),
        possibleDuplicates: [
          for (final t in (json['possibleDuplicates'] as List?) ?? const [])
            if (t is String) t,
        ],
        syncedAt:
            json['syncedAt'] is String
                ? DateTime.tryParse(json['syncedAt'] as String)?.toLocal()
                : null,
        cashUsd: (json['cashUsd'] as num?)?.toDouble(),
        otherHoldings: [
          if (json['otherHoldings'] is List)
            for (final e in json['otherHoldings'] as List)
              if (e is Map)
                EtoroOtherHolding.fromJson(Map<String, dynamic>.from(e)),
        ],
        logos: {
          if (json['logos'] is Map)
            for (final e in (json['logos'] as Map).entries)
              if (e.key is String &&
                  e.value is String &&
                  (e.value as String).startsWith('https://'))
                (e.key as String).toUpperCase(): e.value as String,
        },
      );
}

class EtoroConnection {
  const EtoroConnection({
    required this.status,
    this.lastSyncAt,
    this.lastSyncFailed = false,
    this.lastErrorType,
    this.lastResult,
  });

  static const notConnected = EtoroConnection(
    status: EtoroConnectionStatus.notConnected,
  );

  final EtoroConnectionStatus status;
  final DateTime? lastSyncAt;

  /// La última sincronización falló (eToro caído, límite de pedidos…). Lo
  /// importado sigue con los datos de [lastSyncAt].
  final bool lastSyncFailed;
  final String? lastErrorType;
  final EtoroImportResult? lastResult;

  bool get isConnected => status == EtoroConnectionStatus.connected;
  bool get needsReconnect => status == EtoroConnectionStatus.reconnectRequired;

  /// Hay algo importado que mostrar (conectada o esperando reconexión).
  bool get hasImportedData => status != EtoroConnectionStatus.notConnected;

  factory EtoroConnection.fromRow(Map<String, dynamic> row) {
    final result = row['last_result'];
    return EtoroConnection(
      status: EtoroConnectionStatus.fromWire(row['status'] as String?),
      lastSyncAt:
          row['last_sync_at'] is String
              ? DateTime.tryParse(row['last_sync_at'] as String)?.toLocal()
              : null,
      lastSyncFailed: row['last_sync_status'] == 'error',
      lastErrorType: row['last_error_type'] as String?,
      lastResult:
          result is Map
              ? EtoroImportResult.fromJson(Map<String, dynamic>.from(result))
              : null,
    );
  }
}
