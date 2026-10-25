import 'package:flutter/widgets.dart';

/// Expone el tipo de componente del catálogo GenUI (`CatalogItemContext.type`,
/// ej. `"QaTickerMove"`) a todo el subárbol que renderiza ese componente.
///
/// Los widgets del catálogo son funciones estáticas, no clases propias, así
/// que no hay un `Type` de Dart que identifique a cada uno — esto permite
/// que piezas genéricas compartidas (`RevealStep`, `QaCardShell`) sepan de
/// qué componente forman parte sin pasarles el nombre a mano. Lo inyecta
/// [guardedCatalogWidget] en cada componente; ante componentes anidados
/// (vía `buildChild`) gana el más cercano.
class CatalogComponentScope extends InheritedWidget {
  const CatalogComponentScope({
    super.key,
    required this.type,
    required super.child,
  });

  final String type;

  /// Lectura sin registrar dependencia — pensado para callbacks (ej. el fin
  /// de una animación), no para `build`.
  static String? maybeTypeOf(BuildContext context) {
    final element =
        context.getElementForInheritedWidgetOfExactType<CatalogComponentScope>();
    return (element?.widget as CatalogComponentScope?)?.type;
  }

  @override
  bool updateShouldNotify(CatalogComponentScope oldWidget) =>
      type != oldWidget.type;
}
