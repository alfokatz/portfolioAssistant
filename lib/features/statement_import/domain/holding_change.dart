import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';
import 'package:portfolio_assistant/features/statement_import/domain/import_row.dart';

/// Lo que el usuario ya tiene de un ticker, para comparar con el archivo.
class HeldHolding {
  const HeldHolding({
    required this.quantity,
    required this.costBasis,
    this.currentPrice,
    this.broker,
  });

  /// Unidades en compras manuales: lo único que la importación puede
  /// tocar (lo de eToro o Binance se actualiza solo).
  final double quantity;

  /// Lo que pagó por esas unidades manuales.
  final double costBasis;

  /// Precio de hoy (el de la cartera). `null` si no hay cotización.
  final double? currentPrice;

  /// Si además le llega de un bróker conectado ([PositionSource.etoro] o
  /// [PositionSource.binance]); `null` si no.
  final PositionSource? broker;

  /// Arma lo que tiene por ticker a partir de las compras de la cartera.
  static Map<String, HeldHolding> fromLots(List<PositionValuation> lots) {
    final out = <String, HeldHolding>{};
    for (final lot in lots) {
      final p = lot.position;
      final ticker = PortfolioCalculator.normalizeTicker(p.ticker);
      final prev = out[ticker];
      final manual = !p.isReadOnly;
      out[ticker] = HeldHolding(
        quantity: (prev?.quantity ?? 0) + (manual ? p.quantity : 0),
        costBasis: (prev?.costBasis ?? 0) + (manual ? p.costBasis : 0),
        currentPrice:
            lot.currentPrice > 0 ? lot.currentPrice : prev?.currentPrice,
        broker: prev?.broker ?? (manual ? null : p.source),
      );
    }
    return out;
  }
}

/// Qué hace la importación con una fila, comparada con la cartera.
enum ImportAction {
  /// No la tiene (en manuales): se agrega como compra nueva.
  add,

  /// El archivo dice más: se compra la diferencia.
  buyMore,

  /// El archivo dice menos: se vende la diferencia (FIFO).
  sell,

  /// Coincide con lo que ya tiene: no se toca.
  unchanged,
}

/// El movimiento que sale de una fila.
class ImportPlan {
  const ImportPlan(this.action, {this.quantity = 0, this.price, this.held = 0});

  final ImportAction action;

  /// Unidades que se compran o venden.
  final double quantity;

  /// Precio por unidad del movimiento. En [ImportAction.buyMore] es el que
  /// se deduce del costo promedio del archivo (o el de hoy); en
  /// [ImportAction.sell], el de hoy. `null` = todavía no se sabe.
  final double? price;

  /// Unidades manuales que tenía antes.
  final double held;
}

abstract final class HoldingDiff {
  /// Diferencia relativa por debajo de la cual es "lo mismo" (redondeos
  /// del bróker).
  static const tolerance = 1e-4;

  /// Con la cantidad calculada desde un monto ("2000 dólares de VOO") el
  /// precio de hoy mueve la cuenta: se tolera más.
  static const amountTolerance = 0.02;

  static ImportPlan plan(
    ImportRow row,
    HeldHolding? held,
    double? currentPrice,
  ) {
    final have = held?.quantity ?? 0;
    if (have <= 1e-9) {
      return ImportPlan(
        ImportAction.add,
        quantity: row.quantity,
        price: row.purchasePrice,
      );
    }
    final diff = row.quantity - have;
    final tol = row.quantityFromAmount ? amountTolerance : tolerance;
    if (diff.abs() <= have * tol || diff.abs() < 1e-8) {
      return ImportPlan(ImportAction.unchanged, held: have);
    }
    if (diff < 0) {
      return ImportPlan(
        ImportAction.sell,
        quantity: _round(-diff),
        price: currentPrice,
        held: have,
      );
    }
    return ImportPlan(
      ImportAction.buyMore,
      quantity: _round(diff),
      price: _impliedPrice(row, held!, diff, currentPrice) ?? currentPrice,
      held: have,
    );
  }

  /// Si el archivo trae el costo promedio, lo que pagó por las unidades de
  /// más es lo que falta para llegar a ese costo total. Solo si da un
  /// precio creíble (el bróker puede calcular el promedio distinto).
  static double? _impliedPrice(
    ImportRow row,
    HeldHolding held,
    double diff,
    double? currentPrice,
  ) {
    final avg = row.purchasePrice;
    if (avg == null || held.costBasis <= 0) return null;
    final implied = (row.quantity * avg - held.costBasis) / diff;
    if (!(implied > 0)) return null;
    final reference = currentPrice ?? avg;
    if (implied < reference / 5 || implied > reference * 5) return null;
    return (implied * 1e6).roundToDouble() / 1e6;
  }

  static double _round(double v) => (v * 1e8).roundToDouble() / 1e8;
}
