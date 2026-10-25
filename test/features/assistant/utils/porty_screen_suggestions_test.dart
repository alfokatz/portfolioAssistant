// Las preguntas que ofrece la hoja "Preguntale a Porty" según la pantalla:
// ninguna lleva a un paywall y todas tienen su texto en los dos idiomas.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/assistant/models/porty_screen_context.dart';
import 'package:portfolio_assistant/features/assistant/utils/porty_screen_suggestions.dart';

const _screens = [
  PortyScreenContext.position('AAPL'),
  PortyScreenContext(PortyScreen.closedPosition, ticker: 'TSLA'),
  PortyScreenContext(PortyScreen.goalDetail, goalLabel: 'Viaje'),
  PortyScreenContext(PortyScreen.goals),
  PortyScreenContext(PortyScreen.watchlist),
  PortyScreenContext(PortyScreen.watchlist, ticker: 'AMZN'),
  PortyScreenContext(PortyScreen.allocation),
  PortyScreenContext(PortyScreen.weeklyReport),
  // Sin el ticker que necesita: cae en las de la cartera.
  PortyScreenContext(PortyScreen.positionDetail),
];

List<String> _keys(PortyScreenContext screen, SubscriptionTier tier) => [
  for (final s in PortyScreenSuggestions.forScreen(screen, tier)) s.key,
];

void main() {
  group('PortyScreenSuggestions', () {
    test('every screen and plan offers 2 to 3 questions', () {
      for (final screen in _screens) {
        for (final tier in SubscriptionTier.values) {
          final keys = _keys(screen, tier);
          expect(
            keys.length,
            inInclusiveRange(2, PortyScreenSuggestions.max),
            reason: '${screen.screen} / $tier',
          );
          expect(keys.toSet(), hasLength(keys.length));
        }
      }
    });

    test('a position: the "why" and the analysis only where the plan '
        'includes news and the company analysis', () {
      const screen = PortyScreenContext.position('AAPL');
      expect(_keys(screen, SubscriptionTier.gold), [
        'porty_ask_position_why_moved',
        'porty_ask_position_weight',
        'porty_ask_position_analysis',
      ]);
      for (final tier in [SubscriptionTier.free, SubscriptionTier.premium]) {
        expect(_keys(screen, tier), [
          'porty_ask_position_week',
          'porty_ask_position_weight',
          'porty_ask_position_since_buy',
        ]);
      }
    });

    test('a sale: what it did after selling needs market data (Premium)', () {
      const screen = PortyScreenContext(
        PortyScreen.closedPosition,
        ticker: 'TSLA',
      );
      expect(
        _keys(screen, SubscriptionTier.free),
        isNot(contains('porty_ask_closed_since')),
      );
      expect(
        _keys(screen, SubscriptionTier.premium),
        contains('porty_ask_closed_since'),
      );
    });

    test('the ticker and the goal fill the questions, in capitals', () {
      final position = PortyScreenSuggestions.forScreen(
        const PortyScreenContext.position('aapl'),
        SubscriptionTier.free,
      );
      expect(position.first.args, {'ticker': 'AAPL'});
      final goal = PortyScreenSuggestions.forScreen(
        const PortyScreenContext(PortyScreen.goalDetail, goalLabel: 'Viaje'),
        SubscriptionTier.premium,
      );
      expect(goal.first.args, {'goal': 'Viaje'});
    });

    test('every question (and the button tooltip) has its text in Spanish '
        'and English, with the placeholders it fills', () {
      Map<String, Object?> load(String locale) =>
          (jsonDecode(
                    File('assets/translations/$locale.json').readAsStringSync(),
                  )
                  as Map)
              .cast<String, Object?>();
      final es = load('es-ES');
      final en = load('en-US');
      final used = <String, Set<String>>{};
      for (final screen in _screens) {
        for (final tier in SubscriptionTier.values) {
          for (final s in PortyScreenSuggestions.forScreen(screen, tier)) {
            used.putIfAbsent(s.key, () => {}).addAll(s.args.keys);
          }
        }
      }
      used['porty_ask_tooltip'] = {};

      for (final MapEntry(key: key, value: args) in used.entries) {
        for (final (name, file) in [('es', es), ('en', en)]) {
          final text = file[key];
          expect(text, isA<String>(), reason: '$key en $name');
          for (final arg in args) {
            expect(text, contains('{$arg}'), reason: '$key en $name');
          }
        }
      }
    });
  });

  group('PortyScreenContext.toBrief', () {
    test('only what it has, the ticker in capitals and how many turns ago', () {
      expect(const PortyScreenContext.position('nvda').toBrief(turnsAgo: 0), {
        'screen': 'position_detail',
        'ticker': 'NVDA',
        'turns_ago': 0,
      });
      expect(
        const PortyScreenContext(
          PortyScreen.goalDetail,
          goalLabel: 'Casa',
        ).toBrief(turnsAgo: 2),
        {'screen': 'goal_detail', 'goal': 'Casa', 'turns_ago': 2},
      );
    });
  });
}
