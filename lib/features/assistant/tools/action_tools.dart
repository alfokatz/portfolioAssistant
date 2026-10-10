import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/features/assistant/models/action_proposal.dart';
import 'package:portfolio_assistant/features/assistant/tools/alert_tools.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/assistant/tools/tool_args.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';
import 'package:uuid/uuid.dart';

/// Tools que proponen una operación sobre la cartera. NINGUNA escribe: una
/// alucinación o un reintento del modelo nunca toca la cartera. Validan,
/// completan el precio y devuelven un [ActionProposal]; la card
/// `QaActionProposal` lo muestra y la app recién guarda cuando el usuario
/// confirma (ver docs/superpowers/plans/2026-10-08-acciones-de-porty.md).
///
/// Resultados además de `ok` y `locked`:
/// - `needs_input` + `missing`: faltan datos; el modelo los pide todos en
///   una sola pregunta.
/// - `invalid` + `reason`: el pedido no tiene sentido (fecha futura, vender
///   lo que no tiene…); el modelo lo explica.
/// - `failed` + `reason: price_unavailable`: no se pudo verificar el ticker
///   ni traer su precio, y el usuario no lo dijo.
abstract final class ActionTools {
  static const proposeBuy = 'propose_buy';
  static const proposeSell = 'propose_sell';
  static const proposeDelete = 'propose_delete_position';

  static const names = {proposeBuy, proposeSell, proposeDelete};

  /// Todas las tools cuyo resultado `ok` es una card `QaActionProposal`
  /// (las de la cartera y la de alertas de precio).
  static const proposalTools = {...names, AlertTools.proposePriceAlert};

  static List<DataTool> build(AssistantToolContext ctx) => [
    ProposeBuyTool(ctx),
    ProposeSellTool(ctx),
    ProposeDeletePositionTool(ctx),
  ];
}

/// Cierre de un día para una operación. La comparten las tools y la card
/// (al cambiar la fecha), así las dos completan el precio igual.
abstract final class ActionPrices {
  /// Cierre de [date] (o el último hábil anterior). `fetched` en `false` si
  /// no hubo histórico; `close` en `null` también si la fecha es anterior a
  /// todo el histórico — no se completa con otro día (a diferencia de
  /// `GetPriceOnDateUseCase`): mejor pedir el precio que poner uno falso.
  static Future<({bool fetched, double? close})> closeOn(
    QuoteRepository quotes,
    String ticker,
    DateTime date,
  ) async {
    final day = DateTime(date.year, date.month, date.day);
    final result = await quotes.getHistoricalDaily(ticker);
    return result.fold((_) => (fetched: false, close: null), (candles) {
      if (candles.isEmpty) return (fetched: false, close: null);
      PriceCandle? best;
      for (final c in candles) {
        final candleDay = DateTime(c.date.year, c.date.month, c.date.day);
        if (candleDay.isAfter(day)) continue;
        if (best == null || c.date.isAfter(best.date)) best = c;
      }
      final close = best?.close;
      return (fetched: true, close: close != null && close > 0 ? close : null);
    });
  }
}

const _uuid = Uuid();

/// Margen para comparar cantidades fraccionarias (mismo criterio que el
/// repositorio de cierres).
const _quantityEpsilon = 1e-6;

const _tickerProperty = {
  'type': 'string',
  'description':
      'US ticker. If the user named a company and the ticker is not known '
      'yet, call search_symbol first.',
};

const _dateProperty = {
  'type': 'string',
  'description':
      'YYYY-MM-DD, resolved from what the user said ("ayer", "el lunes") '
      'using as_of. Omit it if the user did not say when.',
};

const _priceProperty = {
  'type': 'number',
  'description':
      'Price per share in USD, ONLY if the user said it. Otherwise omit it: '
      'the app uses that day\'s close.',
};

/// Base común: gating, faltantes, fecha y precio.
abstract class _ProposeTool implements DataTool {
  _ProposeTool(this.ctx);

  final AssistantToolContext ctx;

  DateTime get _today => DateTime(ctx.now.year, ctx.now.month, ctx.now.day);

  Map<String, Object?>? _gate() => ctx.gate(PlanFeature.portfolioActions, []);

  /// Solo `YYYY-MM-DD`: "compré en marzo" no alcanza para el precio del día,
  /// así que un mes suelto cuenta como fecha faltante.
  DateTime? _date(Map<String, Object?> args) {
    final value = ToolArgs.string(args, 'date');
    if (value == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return null;
    }
    final parsed = ToolArgs.date(args, 'date');
    return parsed == null
        ? null
        : DateTime(parsed.year, parsed.month, parsed.day);
  }

  Map<String, Object?> _needsInput(List<String> missing) => {
    'status': 'needs_input',
    'missing': missing,
  };

  Map<String, Object?> _invalid(
    String reason, [
    Map<String, Object?> extra = const {},
  ]) => {'status': 'invalid', 'reason': reason, ...extra};

  /// Fecha futura o anterior a cualquier dato de mercado razonable.
  Map<String, Object?>? _checkDate(DateTime date) {
    if (date.isAfter(_today)) return _invalid('future_date');
    if (date.year < 1970) return _invalid('date_too_old');
    return null;
  }

  /// Un número que vino del modelo: `null` si no lo mandó, y un valor que
  /// no es positivo cuenta como cantidad inválida.
  double? _positive(Map<String, Object?> args, String key) {
    final value = ToolArgs.number(args, key);
    return value == null || value <= 0 ? null : value;
  }

  bool _sentNonPositive(Map<String, Object?> args, String key) {
    final value = ToolArgs.number(args, key);
    return value != null && value <= 0;
  }

  Future<({bool fetched, double? close})> _closeOn(
    String ticker,
    DateTime date,
  ) => ActionPrices.closeOn(ctx.data.quoteRepository, ticker, date);

  /// Los lotes MANUALES del usuario en [ticker], del más viejo al más nuevo
  /// (FIFO). Los importados de eToro no se venden ni se borran desde Porty.
  List<ActionLot> _lotsOf(String ticker) {
    final lots = [
      for (final v in ctx.summary?.lots ?? const [])
        if (v.position.ticker.toUpperCase() == ticker &&
            !v.position.isReadOnly)
          ActionLot(
            id: v.position.id,
            quantity: v.position.quantity,
            purchasePrice: v.position.purchasePrice,
            purchaseDate: v.position.purchaseDate,
          ),
    ]..sort((a, b) => a.purchaseDate.compareTo(b.purchaseDate));
    return lots;
  }

  /// Acciones cargadas a mano que tiene hoy de [ticker], o `null` si no
  /// tiene ninguna (las importadas de eToro no cuentan: no se tocan desde
  /// Porty).
  double? _heldShares(String ticker) {
    final summary = ctx.summary;
    // Un resumen sin lotes (armado a mano) trae solo las valuaciones.
    final rows =
        (summary?.lots.isNotEmpty ?? false)
            ? summary!.lots
            : summary?.valuations ?? const [];
    double? held;
    for (final v in rows) {
      if (v.position.ticker.toUpperCase() != ticker || v.position.isReadOnly) {
        continue;
      }
      held = (held ?? 0) + v.position.quantity;
    }
    return held;
  }

  /// `not_held`, o `managed_by_broker` si [ticker] está en la cartera pero
  /// solo importado de eToro (se vende en eToro y llega solo).
  Map<String, Object?> _notHeld(String ticker) {
    final imported = (ctx.summary?.lots ?? const []).any(
      (v) => v.position.ticker.toUpperCase() == ticker && v.position.isReadOnly,
    );
    return _invalid(imported ? 'managed_by_broker' : 'not_held');
  }

  String? _ticker(Map<String, Object?> args) {
    final value = ToolArgs.string(args, 'ticker');
    if (value == null) return null;
    final tickers = ToolArgs.tickers({
      'tickers': [value],
    }, max: 1);
    return tickers.isEmpty ? null : tickers.first;
  }
}

/// Compra que el usuario ya hizo y quiere registrar.
class ProposeBuyTool extends _ProposeTool {
  ProposeBuyTool(super.ctx);

  @override
  String get name => ActionTools.proposeBuy;

  @override
  String get description =>
      'Prepares a BUY the user says they ALREADY made ("compré 10 de Apple el '
      'lunes") or asks to register, for them to review and confirm in a card. '
      'Nothing is saved until the user confirms. NOT for advice ("¿compro?") '
      'or hypotheticals ("si comprara…"). One call per purchase. Pass shares '
      'OR amount_usd, as the user said it. status: ok (show '
      'QaActionProposal with proposal_id) | needs_input (ask for everything '
      'in missing, in ONE question) | invalid (explain reason) | failed '
      '(price_unavailable: could not verify the ticker; ask the user to '
      'check it or give the price) | locked.';

  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': {
      'ticker': _tickerProperty,
      'shares': {'type': 'number', 'description': 'Number of shares.'},
      'amount_usd': {
        'type': 'number',
        'description': 'Amount invested in USD, if given instead of shares.',
      },
      'date': _dateProperty,
      'price_usd': _priceProperty,
    },
    'required': ['ticker'],
    'additionalProperties': false,
  };

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async {
    final locked = _gate();
    if (locked != null) return locked;

    final ticker = _ticker(args);
    final shares = _positive(args, 'shares');
    final amountUsd = _positive(args, 'amount_usd');
    final date = _date(args);
    if (_sentNonPositive(args, 'shares') ||
        _sentNonPositive(args, 'amount_usd')) {
      return _invalid('invalid_quantity');
    }
    final missing = [
      if (ticker == null) 'ticker',
      if (shares == null && amountUsd == null) 'quantity',
      if (date == null) 'date',
    ];
    if (missing.isNotEmpty) return _needsInput(missing);

    final dateError = _checkDate(date!);
    if (dateError != null) return dateError;

    final userPrice = _positive(args, 'price_usd');
    final market = await _closeOn(ticker!, date);
    // Sin histórico no se puede verificar que el ticker exista: sin un
    // precio del usuario, no se propone algo que puede ser inventado.
    if (!market.fetched && userPrice == null) {
      return {'status': 'failed', 'reason': 'price_unavailable'};
    }
    final price = userPrice ?? market.close;
    final unit = shares != null ? AmountUnit.shares : AmountUnit.usd;

    return ActionProposal(
      id: _uuid.v4(),
      kind: ActionKind.buy,
      ticker: ticker,
      shares: shares ?? (price == null ? null : amountUsd! / price),
      amountUsd: shares == null ? amountUsd : null,
      unit: unit,
      price: price,
      priceSource:
          userPrice != null
              ? PriceSource.user
              : price != null
              ? PriceSource.closeOnDate
              : PriceSource.missing,
      date: date,
    ).toToolResult();
  }
}

/// Venta (cierre total o parcial) que el usuario ya hizo.
class ProposeSellTool extends _ProposeTool {
  ProposeSellTool(super.ctx);

  @override
  String get name => ActionTools.proposeSell;

  @override
  String get description =>
      'Prepares a SELL (full or partial close) of a position the user HOLDS '
      'and says they ALREADY sold ("vendí todas mis TSLA hoy"), for them to '
      'review and confirm in a card. Nothing is saved until the user '
      'confirms. NOT for advice or hypotheticals. One call per sale. Pass '
      'shares, amount_usd or all=true. Shares are sold oldest purchase '
      'first. status: ok (show QaActionProposal with proposal_id) | '
      'needs_input (ask for everything in missing, in ONE question) | '
      'invalid (not_held, exceeds_holdings with held_shares, '
      'sale_before_purchase, future_date…: explain it; managed_by_broker = '
      'the position is imported from eToro, read-only in Porty: it is sold '
      'in eToro and updates by itself) | locked.';

  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': {
      'ticker': _tickerProperty,
      'shares': {'type': 'number', 'description': 'Number of shares sold.'},
      'amount_usd': {
        'type': 'number',
        'description': 'Amount sold in USD, if given instead of shares.',
      },
      'all': {
        'type': 'boolean',
        'description': 'true if they sold the whole position.',
      },
      'date': _dateProperty,
      'price_usd': _priceProperty,
    },
    'required': ['ticker'],
    'additionalProperties': false,
  };

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async {
    final locked = _gate();
    if (locked != null) return locked;

    final ticker = _ticker(args);
    final all = args['all'] == true;
    final shares = _positive(args, 'shares');
    final amountUsd = _positive(args, 'amount_usd');
    final date = _date(args);
    if (!all &&
        (_sentNonPositive(args, 'shares') ||
            _sentNonPositive(args, 'amount_usd'))) {
      return _invalid('invalid_quantity');
    }
    final missing = [
      if (ticker == null) 'ticker',
      if (!all && shares == null && amountUsd == null) 'quantity',
      if (date == null) 'date',
    ];
    if (missing.isNotEmpty) return _needsInput(missing);

    final held = _heldShares(ticker!);
    if (held == null) return _notHeld(ticker);

    final dateError = _checkDate(date!);
    if (dateError != null) return dateError;
    final lots = _lotsOf(ticker);
    if (lots.isNotEmpty && date.isBefore(_dayOf(lots.first.purchaseDate))) {
      return _invalid('sale_before_purchase', {
        'first_purchase_date': _format(lots.first.purchaseDate),
      });
    }

    final userPrice = _positive(args, 'price_usd');
    final price = userPrice ?? (await _closeOn(ticker, date)).close;
    final double? sold =
        all ? held : shares ?? (price == null ? null : amountUsd! / price);
    if (sold != null && sold > held + _quantityEpsilon) {
      return _invalid('exceeds_holdings', {'held_shares': held});
    }

    return ActionProposal(
      id: _uuid.v4(),
      kind: ActionKind.sell,
      ticker: ticker,
      shares: sold,
      amountUsd: !all && shares == null ? amountUsd : null,
      unit: !all && shares == null ? AmountUnit.usd : AmountUnit.shares,
      price: price,
      priceSource:
          userPrice != null
              ? PriceSource.user
              : price != null
              ? PriceSource.closeOnDate
              : PriceSource.missing,
      date: date,
      heldShares: held,
      lots: lots,
    ).toToolResult();
  }
}

/// Borrar una posición cargada por error (no es una venta).
class ProposeDeletePositionTool extends _ProposeTool {
  ProposeDeletePositionTool(super.ctx);

  @override
  String get name => ActionTools.proposeDelete;

  @override
  String get description =>
      'Prepares DELETING a position the user HOLDS because it was loaded by '
      'mistake ("la cargué mal", "borrá AAPL"). It is NOT a sale: no P&L is '
      'recorded — if they sold it, use propose_sell. The card lists the '
      'purchases so the user picks which to delete, and nothing is deleted '
      'until they confirm. status: ok (show QaActionProposal with '
      'proposal_id) | needs_input | invalid (not_held; managed_by_broker = '
      'imported from eToro, read-only in Porty) | locked.';

  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': {'ticker': _tickerProperty},
    'required': ['ticker'],
    'additionalProperties': false,
  };

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async {
    final locked = _gate();
    if (locked != null) return locked;

    final ticker = _ticker(args);
    if (ticker == null) return _needsInput(['ticker']);
    final held = _heldShares(ticker);
    if (held == null) return _notHeld(ticker);

    return ActionProposal(
      id: _uuid.v4(),
      kind: ActionKind.delete,
      ticker: ticker,
      shares: held,
      heldShares: held,
      lots: _lotsOf(ticker),
    ).toToolResult();
  }
}

DateTime _dayOf(DateTime date) => DateTime(date.year, date.month, date.day);

String _format(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
