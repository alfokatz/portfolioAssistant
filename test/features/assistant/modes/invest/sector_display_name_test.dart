import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/modes/invest/sector_display_name.dart';

void main() {
  group('SectorDisplayName', () {
    test('translates known English sectors to Spanish', () {
      expect(SectorDisplayName.fromRaw('Technology'), 'Tecnología');
      expect(SectorDisplayName.fromRaw('Financial Services'), 'Finanzas');
      expect(SectorDisplayName.fromRaw('Healthcare'), 'Salud');
    });

    test('maps Other to Sin clasificar', () {
      expect(SectorDisplayName.fromRaw('Other'), 'Sin clasificar');
    });

    test('returns Sin clasificar for null or empty', () {
      expect(SectorDisplayName.fromRaw(null), 'Sin clasificar');
      expect(SectorDisplayName.fromRaw(''), 'Sin clasificar');
    });

    test('passes through unknown Yahoo sectors as-is', () {
      expect(SectorDisplayName.fromRaw('Communication Services'), 'Comunicaciones');
    });
  });
}
