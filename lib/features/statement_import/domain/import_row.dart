import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';

/// De dónde salieron las filas (lo devuelve `statement-import`).
enum ImportSource {
  /// CSV con columnas reconocibles: sin IA y sin consumir consultas.
  csv,

  /// La IA leyó el archivo (consumió una consulta del plan).
  ai;

  static ImportSource fromWire(Object? value) =>
      value == 'ai' ? ImportSource.ai : ImportSource.csv;
}

/// Aviso del servidor para la vista previa. [type] es estable:
/// `skipped_rows`, `cash_skipped`, `ambiguous_dates`, `truncated`,
/// `non_usd_currency`.
class ImportWarning {
  const ImportWarning({
    required this.type,
    this.count,
    this.currencies = const [],
  });

  final String type;
  final int? count;
  final List<String> currencies;

  static ImportWarning? fromJson(Object? json) {
    if (json is! Map) return null;
    final type = json['type'];
    if (type is! String) return null;
    final count = json['count'] ?? json['limit'];
    final currencies = json['currencies'];
    return ImportWarning(
      type: type,
      count: count is num ? count.toInt() : null,
      currencies:
          currencies is List
              ? currencies.whereType<String>().toList()
              : const [],
    );
  }
}

/// Lo que encontró el servidor en el archivo.
class StatementReadResult {
  const StatementReadResult({
    required this.source,
    required this.rows,
    this.warnings = const [],
  });

  final ImportSource source;
  final List<ImportRow> rows;
  final List<ImportWarning> warnings;

  static StatementReadResult fromJson(Map<String, Object?> json) {
    final rows = json['rows'];
    final warnings = json['warnings'];
    return StatementReadResult(
      source: ImportSource.fromWire(json['source']),
      rows: [
        if (rows is List)
          for (final (i, r) in rows.indexed)
            if (ImportRow.fromJson(r, id: i) case final row?) row,
      ],
      warnings: [
        if (warnings is List)
          for (final w in warnings)
            if (ImportWarning.fromJson(w) case final warning?) warning,
      ],
    );
  }
}

/// Una posición de la vista previa. El usuario la puede corregir o
/// descartar antes de importar.
class ImportRow {
  const ImportRow({
    required this.id,
    required this.ticker,
    required this.quantity,
    this.name,
    this.purchasePrice,
    this.purchaseDate,
    this.currency,
    this.included = true,
    this.quote = QuoteCheck.pending,
    this.amount,
    this.quantityFromAmount = false,
  });

  /// Identificador local (posición en el archivo), para editar la fila.
  final int id;
  final String ticker;
  final String? name;
  final double quantity;
  final double? purchasePrice;
  final DateTime? purchaseDate;
  final String? currency;

  /// El usuario la deja en la importación.
  final bool included;

  /// Si Porty encontró cotización para el ticker.
  final QuoteCheck quote;

  /// Lo que dijo que tiene en dinero ("2000 dólares en QQQ") cuando no dijo
  /// unidades (lo que escribe o una captura): con la cotización de hoy se
  /// calcula la cantidad.
  final double? amount;

  /// La cantidad salió de [amount] y el precio de hoy (la vista previa lo
  /// aclara).
  final bool quantityFromAmount;

  static ImportRow? fromJson(Object? json, {required int id}) {
    if (json is! Map) return null;
    final ticker = json['ticker'];
    final quantity = json['quantity'];
    if (ticker is! String || ticker.trim().isEmpty || quantity is! num) {
      return null;
    }
    final price = json['purchase_price'];
    final date = json['purchase_date'];
    final name = json['name'];
    final currency = json['currency'];
    final amount = json['amount'];
    return ImportRow(
      id: id,
      ticker: PortfolioCalculator.normalizeTicker(ticker),
      name: name is String && name.trim().isNotEmpty ? name.trim() : null,
      quantity: quantity.toDouble(),
      purchasePrice: price is num && price > 0 ? price.toDouble() : null,
      purchaseDate: date is String ? DateTime.tryParse(date) : null,
      currency: currency is String ? currency : null,
      amount: amount is num && amount > 0 ? amount.toDouble() : null,
    );
  }

  /// Lo que falta para poder importarla.
  Set<ImportIssue> get issues => {
    if (!(quantity > 0)) ImportIssue.quantity,
    if (purchasePrice == null || !(purchasePrice! > 0)) ImportIssue.price,
    if (purchaseDate == null) ImportIssue.date,
    if (quote == QuoteCheck.notFound) ImportIssue.unknownTicker,
  };

  bool get isReady => issues.isEmpty;

  /// La moneda del archivo no es dólar: Porty valúa en dólares, así que el
  /// precio de compra puede no corresponder.
  bool get hasForeignCurrency =>
      currency != null && currency!.toUpperCase() != 'USD';

  ImportRow copyWith({
    String? ticker,
    double? quantity,
    double? purchasePrice,
    DateTime? purchaseDate,
    bool? included,
    QuoteCheck? quote,
    bool? quantityFromAmount,
  }) {
    return ImportRow(
      id: id,
      ticker: ticker ?? this.ticker,
      name: name,
      quantity: quantity ?? this.quantity,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      currency: currency,
      included: included ?? this.included,
      amount: amount,
      // Si la corrige a mano, ya no es "calculada".
      quantityFromAmount:
          quantityFromAmount ??
          (quantity != null ? false : this.quantityFromAmount),
      // Cambiar el ticker obliga a volver a buscar su cotización.
      quote:
          quote ??
          (ticker != null && ticker != this.ticker
              ? QuoteCheck.pending
              : this.quote),
    );
  }
}

enum QuoteCheck { pending, found, notFound }

enum ImportIssue { quantity, price, date, unknownTicker }
