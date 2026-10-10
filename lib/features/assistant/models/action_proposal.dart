import 'package:portfolio_assistant/domain/entities/closed_position.dart';

/// Qué operación propone Porty (ver `docs/superpowers/plans/
/// 2026-10-08-acciones-de-porty.md`). `alert`: una alerta de precio (plan
/// de notificaciones push, F5); no toca la cartera.
enum ActionKind { buy, sell, delete, alert }

/// En qué unidad dio el usuario la cantidad: acciones o un monto en USD.
enum AmountUnit { shares, usd }

/// De dónde salió el precio con el que se completó la card.
enum PriceSource {
  /// Cierre del día de la operación.
  closeOnDate,

  /// Lo dijo el usuario ("compré a 180").
  user,

  /// No se pudo traer: la card lo pide antes de dejar confirmar.
  missing,
}

/// Un lote que ya tiene el usuario (para vender o borrar).
class ActionLot {
  const ActionLot({
    required this.id,
    required this.quantity,
    required this.purchasePrice,
    required this.purchaseDate,
  });

  final String id;
  final double quantity;
  final double purchasePrice;
  final DateTime purchaseDate;

  Map<String, Object?> toJson() => {
    'id': id,
    'quantity': quantity,
    'purchase_price': purchasePrice,
    'purchase_date': _formatDate(purchaseDate),
  };

  static ActionLot? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final quantity = json['quantity'];
    final price = json['purchase_price'];
    final date = _parseDate(json['purchase_date']);
    if (id is! String || quantity is! num || price is! num || date == null) {
      return null;
    }
    return ActionLot(
      id: id,
      quantity: quantity.toDouble(),
      purchasePrice: price.toDouble(),
      purchaseDate: date,
    );
  }
}

/// Una operación que Porty propone y el usuario todavía no confirmó. La
/// arma una tool `propose_*` (que nunca escribe) y viaja como su resultado:
/// la card `QaActionProposal` la lee desde la evidencia del turno con
/// [fromToolResult], no desde lo que escribió el modelo.
class ActionProposal {
  const ActionProposal({
    required this.id,
    required this.kind,
    required this.ticker,
    this.companyName,
    this.shares,
    this.amountUsd,
    this.unit = AmountUnit.shares,
    this.price,
    this.priceSource = PriceSource.missing,
    this.date,
    this.heldShares,
    this.lots = const [],
    this.alertCondition,
    this.alertTarget,
    this.alertRepeatDaily = false,
  });

  /// `proposal_id`: lo único que el modelo le pasa a la card.
  final String id;
  final ActionKind kind;
  final String ticker;
  final String? companyName;

  /// Acciones de la operación. En una compra o venta por monto, el cálculo
  /// con [price] (la card lo rehace si el usuario edita).
  final double? shares;

  /// El monto en USD que dijo el usuario, si lo dio así.
  final double? amountUsd;
  final AmountUnit unit;
  final double? price;
  final PriceSource priceSource;

  /// Día de la compra o venta (sin hora). En un borrado, `null`.
  final DateTime? date;

  /// Venta y borrado: cuántas acciones de [ticker] tiene hoy.
  final double? heldShares;

  /// Venta y borrado: los lotes de [ticker], del más viejo al más nuevo
  /// (FIFO, el orden en que los vende el repositorio).
  final List<ActionLot> lots;

  /// Alerta: `above`, `below`, `pct_up` o `pct_down` (columna `condition`
  /// de `price_alerts`). [price] es el precio de ahora.
  final String? alertCondition;

  /// Alerta: precio (above/below) o porcentaje (pct_*).
  final double? alertTarget;
  final bool alertRepeatDaily;

  static const toolResultIdKey = 'proposal_id';

  /// Lo que pagó por [shares] acciones vendidas en orden FIFO (como vende el
  /// repositorio). `null` sin lotes o si no alcanzan.
  double? fifoCostBasis(double shares) {
    if (lots.isEmpty) return null;
    var remaining = shares;
    var cost = 0.0;
    for (final lot in lots) {
      if (remaining <= _quantityEpsilon) break;
      final take = remaining < lot.quantity ? remaining : lot.quantity;
      cost += take * lot.purchasePrice;
      remaining -= take;
    }
    return remaining > _quantityEpsilon ? null : cost;
  }

  /// El resultado `ok` de la tool, que también ve el modelo: chico y en
  /// snake_case como el resto de las tools.
  Map<String, Object?> toToolResult() => {
    'status': 'ok',
    toolResultIdKey: id,
    'kind': kind.name,
    'ticker': ticker,
    if (companyName != null) 'company_name': companyName,
    if (shares != null) 'shares': shares,
    if (amountUsd != null) 'amount_usd': amountUsd,
    'unit': unit.name,
    if (price != null) 'price': price,
    'price_source': _priceSourceName(priceSource),
    if (date != null) 'date': _formatDate(date!),
    if (heldShares != null) 'held_shares': heldShares,
    if (lots.isNotEmpty) 'lots': [for (final lot in lots) lot.toJson()],
    if (alertCondition != null) 'condition': alertCondition,
    if (alertTarget != null) 'target': alertTarget,
    if (kind == ActionKind.alert) 'repeat': alertRepeatDaily ? 'daily' : 'once',
  };

  /// `null` si [result] no es una propuesta válida (otro status, o le faltan
  /// campos): la card no se dibuja antes que mostrar datos a medias.
  static ActionProposal? fromToolResult(Map<String, Object?> result) {
    if (result['status'] != 'ok') return null;
    final id = result[toolResultIdKey];
    final kind = _byName(ActionKind.values, result['kind']);
    final ticker = result['ticker'];
    if (id is! String || kind == null || ticker is! String) return null;
    final lots = result['lots'];
    return ActionProposal(
      id: id,
      kind: kind,
      ticker: ticker,
      companyName: result['company_name'] as String?,
      shares: _double(result['shares']),
      amountUsd: _double(result['amount_usd']),
      unit: _byName(AmountUnit.values, result['unit']) ?? AmountUnit.shares,
      price: _double(result['price']),
      priceSource: switch (result['price_source']) {
        'close_on_date' => PriceSource.closeOnDate,
        'user' => PriceSource.user,
        _ => PriceSource.missing,
      },
      date: _parseDate(result['date']),
      heldShares: _double(result['held_shares']),
      lots: [
        if (lots is List)
          for (final lot in lots.map(ActionLot.fromJson))
            if (lot != null) lot,
      ],
      alertCondition: result['condition'] as String?,
      alertTarget: _double(result['target']),
      alertRepeatDaily: result['repeat'] == 'daily',
    );
  }
}

/// Lo que el usuario confirma en la card: la propuesta con sus ediciones.
class ActionDraft {
  const ActionDraft({
    required this.proposalId,
    required this.kind,
    required this.ticker,
    this.shares,
    this.price,
    this.date,
    this.lotIds = const [],
    this.alertCondition,
    this.alertTarget,
    this.alertRepeatDaily = false,
  });

  final String proposalId;
  final ActionKind kind;
  final String ticker;

  /// Compra y venta: acciones (ya convertidas si el usuario dio USD).
  final double? shares;

  /// Compra y venta: precio de la operación. Alerta: el precio de ahora.
  final double? price;
  final DateTime? date;

  /// Borrado: los lotes elegidos.
  final List<String> lotIds;

  /// Alerta: ver [ActionProposal.alertCondition].
  final String? alertCondition;
  final double? alertTarget;
  final bool alertRepeatDaily;
}

/// Lo que el usuario lleva editado en una card todavía sin resolver, tal
/// como está en el formulario (textos incluidos). Lo guarda la pantalla
/// para que una card que se desmonta al scrollear vuelva con las ediciones
/// y no con lo que propuso Porty.
class ActionForm {
  const ActionForm({
    required this.amountText,
    required this.unit,
    required this.priceText,
    required this.priceEdited,
    this.date,
    this.selectedLots = const {},
    this.repeatDaily = false,
  });

  final String amountText;
  final AmountUnit unit;
  final String priceText;

  /// El precio lo escribió el usuario: una fecha nueva no lo reemplaza.
  final bool priceEdited;
  final DateTime? date;

  /// Borrado: los lotes marcados.
  final Set<String> selectedLots;

  /// Alerta: avisar cada vez que cruce ([priceText] es el objetivo).
  final bool repeatDaily;
}

/// En qué quedó una propuesta. Vive en `AssistantState` y no en el `State`
/// de la card, por lo mismo que `PortfolioQaMessage.hasRevealed`: la card se
/// desmonta al scrollear y no puede volver a "pendiente" ni ofrecer
/// Confirmar otra vez después de guardar.
enum ActionProposalStatus { pending, saving, done, failed, cancelled }

class ActionProposalProgress {
  const ActionProposalProgress(
    this.status, {
    this.errorMessage,
    this.draft,
    this.closedPosition,
  });

  static const pending = ActionProposalProgress(ActionProposalStatus.pending);

  final ActionProposalStatus status;

  /// Con [ActionProposalStatus.failed]: el mensaje para el usuario.
  final String? errorMessage;

  /// Lo último que mandó la card: lo que se confirmó (desde `saving`) o lo
  /// que había al cancelar. La card resuelta lo muestra aunque se haya
  /// desmontado y perdido las ediciones del formulario.
  final ActionDraft? draft;

  /// Venta guardada: la posición cerrada que registró, para "Ver posición
  /// cerrada" en la card.
  final ClosedPosition? closedPosition;

  /// Se puede (re)intentar confirmar: nunca mientras guarda ni después.
  bool get canConfirm =>
      status == ActionProposalStatus.pending ||
      status == ActionProposalStatus.failed;

  /// Para `actions_this_conversation` en PORTFOLIO_BRIEF: el modelo sabe qué
  /// confirmó o canceló el usuario sin turnos falsos en la conversación.
  Map<String, Object?> toBrief(String proposalId) {
    final draft = this.draft;
    return {
      ActionProposal.toolResultIdKey: proposalId,
      'status': switch (status) {
        ActionProposalStatus.done => 'confirmed',
        _ => status.name,
      },
      if (draft != null) ...{
        'kind': draft.kind.name,
        'ticker': draft.ticker,
        if (draft.shares != null) 'shares': draft.shares,
        if (draft.price != null) 'price': draft.price,
        if (draft.date != null) 'date': _formatDate(draft.date!),
        if (draft.alertCondition != null) 'condition': draft.alertCondition,
        if (draft.alertTarget != null) 'target': draft.alertTarget,
      },
    };
  }
}

const _quantityEpsilon = 1e-6;

String _priceSourceName(PriceSource source) => switch (source) {
  PriceSource.closeOnDate => 'close_on_date',
  PriceSource.user => 'user',
  PriceSource.missing => 'missing',
};

String _formatDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

DateTime? _parseDate(Object? value) {
  if (value is! String) return null;
  final parsed = DateTime.tryParse(value);
  return parsed == null ? null : DateTime(parsed.year, parsed.month, parsed.day);
}

double? _double(Object? value) => value is num ? value.toDouble() : null;

T? _byName<T extends Enum>(List<T> values, Object? name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}
