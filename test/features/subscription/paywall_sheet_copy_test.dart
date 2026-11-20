// Paywall con los textos reales en español: títulos por motivo, línea de
// renovación con precio y período, ahorro del anual y el bloque de
// términos. Además, un guardián sobre los dos JSON: ningún título ni
// subtítulo del paywall habla de "modos" ni de "Pro".
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/subscription/subscription_policy.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_paywall_sheet.dart';

import 'paywall_test_harness.dart';

Map<String, dynamic> _json(String locale) =>
    jsonDecode(File('assets/translations/$locale.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  setUpAll(() {
    PortyAvatar.ambientMotion = false;
    Localization.load(
      const Locale('es', 'ES'),
      translations: Translations(_json('es-ES')),
      ignorePluralRules: false,
    );
  });

  group('SubscriptionPaywallSheet copy (es-ES)', () {
    testWidgets('plans: "Elegí tu plan", monthly renewal lines and the '
        'Google Play terms', (tester) async {
      final h = PaywallHarness(offer: monthlyOffer);
      await h.pump(tester, reason: PaywallReason.plans, source: 'settings');
      await h.open(tester);

      expect(find.text('Elegí tu plan'), findsOneWidget);
      expect(find.text('US\$4.99/mes'), findsOneWidget);
      expect(
        find.text('Se renueva cada mes a US\$9.99. Cancelás cuando quieras.'),
        findsOneWidget,
      );
      expect(
        find.text('Se renueva cada mes a US\$4.99. Cancelás cuando quieras.'),
        findsOneWidget,
      );
      expect(find.text('Uso justo: 500 consultas por mes'), findsOneWidget);
      expect(
        find.textContaining('El cobro se hace en tu cuenta de Google Play'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Borrar la app o tu cuenta de Porty no cancela'),
        findsOneWidget,
      );
      expect(find.text('Términos'), findsOneWidget);
      expect(find.text('Privacidad'), findsOneWidget);
    });

    testWidgets('annual: price per year, savings vs monthly and yearly '
        'renewal', (tester) async {
      final h = PaywallHarness(offer: fullOffer, annualEnabled: true);
      await h.pump(tester, reason: PaywallReason.positionLimit);
      await h.open(tester);

      await tester.tap(find.text('Anual'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('US\$49.99/año'), findsOneWidget);
      // floor((1 - 49,99 / 59,88) × 100) = 16
      expect(find.text('Ahorrás 16 % frente al mensual'), findsNWidgets(2));
      expect(
        find.text('Se renueva cada año a US\$99.99. Cancelás cuando quieras.'),
        findsOneWidget,
      );
    });

    testWidgets('position limit says the Free limit', (tester) async {
      final h = PaywallHarness();
      await h.pump(tester, reason: PaywallReason.positionLimit);
      await h.open(tester);
      final limit = SubscriptionPolicy.positionLimit(SubscriptionTier.free);
      expect(find.text('Traé toda tu cartera'), findsOneWidget);
      expect(
        find.textContaining('Free llega a $limit posiciones'),
        findsOneWidget,
      );
    });

    testWidgets('watchlist limit fills {limit} and {premium} from the matrix', (
      tester,
    ) async {
      final h = PaywallHarness();
      await h.pump(tester, reason: PaywallReason.watchlistLimit);
      await h.open(tester);
      expect(find.text('Seguí todas las que te interesan'), findsOneWidget);
      expect(
        find.textContaining('Free sigue hasta 3. Con Premium seguís hasta 30'),
        findsOneWidget,
      );
    });

    testWidgets('benchmark and held news titles, and both plan promises', (
      tester,
    ) async {
      final h = PaywallHarness();
      await h.pump(tester, reason: PaywallReason.benchmark);
      await h.open(tester);
      expect(find.text('¿Le ganás al mercado?'), findsOneWidget);
      expect(
        find.text('Tu plata ordenada y al día, y por qué se movió lo tuyo.'),
        findsOneWidget,
      );
      expect(
        find.text('Porty te explica cualquier empresa y qué está pasando.'),
        findsOneWidget,
      );
    });

    test('2026-11-05 plan copy: es and en have the same keys, none of the '
        'removed ones', () {
      final es = _json('es-ES');
      final en = _json('en-US');
      expect(es.keys.toSet(), en.keys.toSet());
      for (final key in [
        'settings_plan_free_desc',
        'settings_plan_premium_desc',
        'settings_plan_gold_desc',
        'settings_upgrade_pro',
        'paywall_premium_desc',
        'paywall_premium_feature_explore',
        'paywall_premium_feature_benchmark',
        'paywall_premium_feature_alerts',
        'paywall_gold_desc',
        'paywall_gold_feature_invest',
        'paywall_gold_feature_plan',
        'paywall_gold_feature_news',
        'paywall_title_news',
        'paywall_subtitle_news',
      ]) {
        expect(es.containsKey(key), isFalse, reason: key);
      }
      for (final key in [
        'paywall_premium_promise',
        'paywall_gold_promise',
        'plan_feature_held_news',
        'import_first_full_note',
        'watchlist_locked_body',
      ]) {
        expect(es[key], isA<String>(), reason: key);
        expect(en[key], isA<String>(), reason: key);
      }
      // Los placeholders de los avisos con números.
      for (final json in [es, en]) {
        expect(json['import_first_full_note'], contains('{limit}'));
        expect(json['paywall_subtitle_watchlist_limit'], contains('{limit}'));
        expect(json['paywall_subtitle_watchlist_limit'], contains('{premium}'));
      }
    });

    testWidgets(
      'iOS terms name the App Store',
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
      (tester) async {
        final h = PaywallHarness();
        await h.pump(
          tester,
          reason: PaywallReason.goals,
          source: 'test_source',
        );
        await h.open(tester);
        expect(
          find.textContaining('El cobro se hace en tu cuenta de App Store'),
          findsOneWidget,
        );
      },
    );

    test('every reason has a title and subtitle in both languages', () {
      for (final locale in ['es-ES', 'en-US']) {
        final json = _json(locale);
        for (final reason in PaywallReason.values) {
          for (final key in [
            SubscriptionPaywallSheet.titleKeyFor(reason),
            SubscriptionPaywallSheet.subtitleKeyFor(reason),
          ]) {
            expect(json[key], isA<String>(), reason: '$locale $key');
          }
        }
      }
    });

    test('no paywall title or subtitle talks about "modes" or "Pro"', () {
      final modes = RegExp(r'\b(modos?|modes?)\b', caseSensitive: false);
      final pro = RegExp(r'\bPro\b');
      for (final locale in ['es-ES', 'en-US']) {
        final json = _json(locale);
        final keys = json.keys.where(
          (k) =>
              k.startsWith('paywall_title_') ||
              k.startsWith('paywall_subtitle_') ||
              k == 'settings_upgrade_coming_soon',
        );
        expect(keys, isNotEmpty);
        for (final key in keys) {
          final text = json[key] as String;
          expect(modes.hasMatch(text), isFalse, reason: '$locale $key: $text');
          expect(pro.hasMatch(text), isFalse, reason: '$locale $key: $text');
        }
      }
    });
  });

  test('tr() is wired to the loaded Spanish file', () {
    expect('paywall_title_plans'.tr(), 'Elegí tu plan');
  });
}
