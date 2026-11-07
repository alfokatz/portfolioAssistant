import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/assistant/providers/assistant_provider.dart';

void main() {
  Map<String, dynamic> load(String locale) =>
      jsonDecode(File('assets/translations/$locale.json').readAsStringSync())
          as Map<String, dynamic>;

  test('cada plan ofrece 4 sugerencias distintas, traducidas', () {
    final es = load('es-ES');
    final en = load('en-US');
    for (final tier in SubscriptionTier.values) {
      final keys = AssistantProvider.starterChipKeysFor(tier);
      expect(keys, hasLength(4), reason: tier.name);
      expect(keys.toSet(), hasLength(4), reason: tier.name);
      for (final key in keys) {
        expect(es, contains(key), reason: '$key (es)');
        expect(en, contains(key), reason: '$key (en)');
      }
    }
  });

  test('Free no sugiere nada que lleve al paywall', () {
    // Datos de mercado de tickers ajenos, simulaciones y metas son Premium;
    // noticias, Gold. Tocar uno gastaría una consulta para ver el paywall.
    const premiumOnly = {
      'assistant_explore_chip_compare',
      'assistant_explore_chip_nvda',
      'assistant_invest_chip_budget',
      'assistant_chip_goal',
      'assistant_chip_why_moved',
    };
    final free = AssistantProvider.starterChipKeysFor(SubscriptionTier.free);
    expect(free.where(premiumOnly.contains), isEmpty);
    final premium = AssistantProvider.starterChipKeysFor(
      SubscriptionTier.premium,
    );
    expect(premium, isNot(contains('assistant_chip_why_moved')));
  });
}
