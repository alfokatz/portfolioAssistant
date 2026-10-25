import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/utils/position_draft_math.dart';

void main() {
  group('positive', () {
    test('a number above zero', () {
      expect(PositionDraftMath.positive('12.5'), 12.5);
    });

    test('zero, negative, empty or text → null', () {
      for (final text in ['0', '-3', '', 'abc']) {
        expect(PositionDraftMath.positive(text), isNull, reason: text);
      }
    });
  });

  group('shares', () {
    test('in shares mode, the amount as is', () {
      expect(
        PositionDraftMath.shares(amountText: '10', isUsd: false, price: 200),
        10,
      );
    });

    test('in USD mode, the amount divided by the price', () {
      expect(
        PositionDraftMath.shares(amountText: '500', isUsd: true, price: 200),
        2.5,
      );
    });

    test('without a valid price → null, even in shares mode', () {
      for (final price in [null, 0.0, -1.0]) {
        expect(
          PositionDraftMath.shares(amountText: '10', isUsd: false, price: price),
          isNull,
          reason: '$price',
        );
      }
    });

    test('without a valid amount → null', () {
      expect(
        PositionDraftMath.shares(amountText: '0', isUsd: true, price: 200),
        isNull,
      );
    });
  });

  group('acceptsFetchedPrice', () {
    test('a fetched price fills the field', () {
      expect(
        PositionDraftMath.acceptsFetchedPrice(
          fetched: 180,
          editedByUser: false,
        ),
        isTrue,
      );
    });

    test('never overwrites what the user typed', () {
      expect(
        PositionDraftMath.acceptsFetchedPrice(fetched: 180, editedByUser: true),
        isFalse,
      );
    });

    test('a price that is not positive is ignored', () {
      expect(
        PositionDraftMath.acceptsFetchedPrice(fetched: 0, editedByUser: false),
        isFalse,
      );
    });
  });
}
