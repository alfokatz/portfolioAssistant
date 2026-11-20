/// Cuentas de una operación a medio cargar (compra o venta) a partir de lo
/// que escribió el usuario. Las usan las pantallas de alta y cierre y la
/// card de confirmación del chat (`QaActionProposal`), así las dos calculan
/// exactamente igual.
abstract final class PositionDraftMath {
  /// El número que escribió el usuario si es mayor a cero; si no, `null`.
  static double? positive(String text) {
    final value = double.tryParse(text);
    return value == null || value <= 0 ? null : value;
  }

  /// Acciones que representa [amountText]: tal cual, o un monto en USD
  /// ([isUsd]) dividido por [price]. `null` si el precio o el monto no son
  /// válidos — también en modo acciones, porque sin precio la operación no
  /// se puede guardar.
  static double? shares({
    required String amountText,
    required bool isUsd,
    required double? price,
  }) {
    if (price == null || price <= 0) return null;
    final amount = positive(amountText);
    if (amount == null) return null;
    return isUsd ? amount / price : amount;
  }

  /// Si un precio traído de la fuente reemplaza al del campo: nunca pisa lo
  /// que escribió el usuario, y un precio que no es positivo no sirve.
  static bool acceptsFetchedPrice({
    required double fetched,
    required bool editedByUser,
  }) => fetched > 0 && !editedByUser;
}
