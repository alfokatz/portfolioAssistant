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

/// Resumen de la última importación (lo arma el servidor en cada sync).
class EtoroImportResult {
  const EtoroImportResult({
    required this.imported,
    required this.closedImported,
    required this.notImported,
    required this.closedNotImported,
    required this.possibleDuplicates,
    required this.syncedAt,
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

  int get notImportedCount =>
      notImported.fold(0, (sum, item) => sum + item.count);

  static List<EtoroNotImportedItem> _items(Object? raw) => [
    if (raw is List)
      for (final e in raw)
        if (e is Map) EtoroNotImportedItem.fromJson(Map<String, dynamic>.from(e)),
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
