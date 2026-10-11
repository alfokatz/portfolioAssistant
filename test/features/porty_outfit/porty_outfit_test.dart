import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/porty_outfit/domain/porty_outfit.dart';

void main() {
  test('one accessory per slot; toggling the same one takes it off', () {
    var outfit = PortyOutfit.none
        .toggle(PortyAccessory.beanie)
        .toggle(PortyAccessory.glasses);
    expect(outfit.wears(PortyAccessory.beanie), isTrue);

    outfit = outfit.toggle(PortyAccessory.crown);
    expect(outfit[PortyOutfitSlot.head], PortyAccessory.crown);
    expect(outfit.wears(PortyAccessory.glasses), isTrue);

    outfit = outfit.toggle(PortyAccessory.crown);
    expect(outfit[PortyOutfitSlot.head], isNull);
  });

  test('round-trips through storage and ignores unknown values', () {
    final outfit = PortyOutfit.none
        .toggle(PortyAccessory.partyHat)
        .toggle(PortyAccessory.bowTie);
    expect(PortyOutfit.fromStorage(outfit.toStorage()), outfit);
    expect(
      PortyOutfit.fromStorage(['cape', 'sunglasses']),
      PortyOutfit.none.toggle(PortyAccessory.sunglasses),
    );
  });

  testWidgets('every accessory paints, from the scope or explicit', (
    tester,
  ) async {
    for (final accessory in PortyAccessory.values) {
      await tester.pumpWidget(
        PortyOutfitScope(
          outfit: PortyOutfit({accessory.slot: accessory}),
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: PortyAvatar(size: 80, state: PortyAvatarState.thinking),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull, reason: accessory.name);
    }
  });
}
