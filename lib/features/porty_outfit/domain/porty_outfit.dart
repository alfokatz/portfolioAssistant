import 'package:flutter/widgets.dart';

/// Dónde se pone un accesorio: uno por lugar.
enum PortyOutfitSlot { head, face, neck }

/// Los accesorios de Porty. Los dibuja `PortyAvatarPainter` con la misma
/// geometría del cuerpo (ver `PortyAccessoryPainter`), así se mueven con
/// él y se ven nítidos a cualquier tamaño.
enum PortyAccessory {
  beanie('beanie', PortyOutfitSlot.head),
  partyHat('party_hat', PortyOutfitSlot.head),
  topHat('top_hat', PortyOutfitSlot.head),
  cap('cap', PortyOutfitSlot.head),
  crown('crown', PortyOutfitSlot.head),
  bow('bow', PortyOutfitSlot.head),
  flower('flower', PortyOutfitSlot.head),
  glasses('glasses', PortyOutfitSlot.face),
  sunglasses('sunglasses', PortyOutfitSlot.face),
  bowTie('bow_tie', PortyOutfitSlot.neck);

  const PortyAccessory(this.storageValue, this.slot);
  final String storageValue;
  final PortyOutfitSlot slot;

  static PortyAccessory? fromStorage(String? value) =>
      values.where((v) => v.storageValue == value).firstOrNull;
}

/// Lo que tiene puesto Porty: a lo sumo un accesorio por [PortyOutfitSlot].
@immutable
class PortyOutfit {
  const PortyOutfit([this._items = const {}]);

  static const none = PortyOutfit();

  final Map<PortyOutfitSlot, PortyAccessory> _items;

  PortyAccessory? operator [](PortyOutfitSlot slot) => _items[slot];

  bool get isEmpty => _items.isEmpty;

  Iterable<PortyAccessory> get items => _items.values;

  bool wears(PortyAccessory accessory) => _items[accessory.slot] == accessory;

  /// Se lo pone (reemplaza lo que hubiera en su lugar) o, si ya lo tenía,
  /// se lo saca.
  PortyOutfit toggle(PortyAccessory accessory) {
    final next = {..._items};
    if (wears(accessory)) {
      next.remove(accessory.slot);
    } else {
      next[accessory.slot] = accessory;
    }
    return PortyOutfit(next);
  }

  List<String> toStorage() => [for (final a in items) a.storageValue];

  static PortyOutfit fromStorage(List<String>? values) {
    final items = <PortyOutfitSlot, PortyAccessory>{};
    for (final value in values ?? const <String>[]) {
      final accessory = PortyAccessory.fromStorage(value);
      if (accessory != null) items[accessory.slot] = accessory;
    }
    return PortyOutfit(items);
  }

  @override
  bool operator ==(Object other) =>
      other is PortyOutfit &&
      other._items.length == _items.length &&
      _items.entries.every((e) => other._items[e.key] == e.value);

  @override
  int get hashCode => Object.hashAllUnordered(
    _items.entries.map((e) => Object.hash(e.key, e.value)),
  );
}

/// El outfit del usuario para todos los [PortyAvatar] de la app, sin tocar
/// cada call site. Sin scope (login, tests), Porty va sin accesorios.
class PortyOutfitScope extends InheritedWidget {
  const PortyOutfitScope({
    super.key,
    required this.outfit,
    required super.child,
  });

  final PortyOutfit outfit;

  static PortyOutfit of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PortyOutfitScope>()?.outfit ??
      PortyOutfit.none;

  @override
  bool updateShouldNotify(PortyOutfitScope oldWidget) =>
      oldWidget.outfit != outfit;
}
