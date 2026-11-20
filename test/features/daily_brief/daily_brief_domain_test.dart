// Dominio del brief: números iguales a los de la Home, claim, payload y
// armado por plan. Correr: flutter test test/features/daily_brief/daily_brief_domain_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_day_move.dart';
import 'package:portfolio_assistant/features/daily_brief/data/daily_brief_numbers_loader.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_bundle.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_claim.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_numbers.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_writer.dart';

import 'fakes/daily_brief_fakes.dart';

void main() {
  group('DailyBriefNumbers', () {
    test('abs, pct, period and asOfDay equal the Home 1D line', () async {
      final numbers = await DailyBriefNumbersLoader(quotes: FakeQuotes()).load(
        history: history(),
        lots: lots,
        now: briefNow(),
      );
      final move = PortfolioDayMove.compute(
        history: history(),
        positions: lots,
        candlesByTicker: candles,
        now: briefNow(),
      );
      expect(numbers.abs, move.absolute);
      expect(numbers.pct, move.percent);
      expect(numbers.period, move.period);
      expect(numbers.asOfDay, move.asOfDay);
      expect(numbers.period, DayMovePeriod.lastClose);
    });

    test('the top mover is the Home top contributor', () {
      final numbers = DailyBriefNumbers.compute(
        history: history(),
        lots: lots,
        candlesByTicker: candles,
        now: briefNow(),
      );
      final move = PortfolioDayMove.compute(
        history: history(),
        positions: lots,
        candlesByTicker: candles,
        now: briefNow(),
      );
      expect(numbers.movers.first.ticker, move.topContributor!.ticker);
      expect(
        numbers.movers.first.contributionAbs,
        closeTo(move.topContributor!.amount, 1e-9),
      );
    });

    test('movers: contribution, pct and weight from the closes', () {
      final numbers = DailyBriefNumbers.compute(
        history: history(),
        lots: lots,
        candlesByTicker: candles,
        now: briefNow(),
      );
      expect(numbers.movers.map((m) => m.ticker), ['NVDA', 'AAPL']);
      final nvda = numbers.movers.first;
      expect(nvda.contributionAbs, closeTo(41, 1e-9));
      expect(nvda.pct, closeTo(4.1, 1e-9));
      // 1041 de 5021.
      expect(nvda.weightPct, closeTo(1041 / 5021 * 100, 1e-9));
      expect(
        numbers.movers.fold<double>(0, (a, m) => a + m.weightPct),
        closeTo(100, 1e-9),
      );
    });

    test('a ticker without candles is left out, never invented', () {
      final numbers = DailyBriefNumbers.compute(
        history: history(),
        lots: lots,
        candlesByTicker: {'AAPL': candles['AAPL']!},
        now: briefNow(),
      );
      expect(numbers.movers.map((m) => m.ticker), ['AAPL']);
    });

    test('no history: empty, no brief', () {
      final numbers = DailyBriefNumbers.compute(
        history: const [],
        lots: lots,
        candlesByTicker: candles,
      );
      expect(numbers.isEmpty, isTrue);
    });

    test('toJson / tryParse round trip', () {
      final numbers = DailyBriefNumbers.compute(
        history: history(),
        lots: lots,
        candlesByTicker: candles,
        now: briefNow(),
      );
      final back = DailyBriefNumbers.tryParse(numbers.toJson())!;
      expect(back.abs, numbers.abs);
      expect(back.pct, numbers.pct);
      expect(back.asOfDay, numbers.asOfDay);
      expect(back.movers.length, numbers.movers.length);
      expect(back.movers.first.ticker, 'NVDA');
    });
  });

  group('DailyBriefClaim.parse', () {
    test('every server state maps to its type', () {
      DailyBriefClaim p(Map<String, Object?> m) => DailyBriefClaim.parse(m);
      expect(
        p({'state': 'ready', 'payload': <String, Object?>{}, 'courtesy': true}),
        isA<BriefClaimReady>().having((c) => c.courtesy, 'courtesy', isTrue),
      );
      expect(
        p({
          'state': 'claimed',
          'courtesy': true,
          'courtesy_number': 2,
          'courtesy_total': 7,
          'attempt': 1,
        }),
        isA<BriefClaimGranted>()
            .having((c) => c.courtesyNumber, 'n', 2)
            .having((c) => c.courtesyTotal, 'total', 7),
      );
      expect(p({'state': 'numbers_only'}), isA<BriefClaimNumbersOnly>());
      expect(p({'state': 'in_progress'}), isA<BriefClaimInProgress>());
      expect(p({'state': 'failed'}), isA<BriefClaimFailed>());
      expect(p({'state': 'disabled'}), isA<BriefClaimDisabled>());
      expect(p({'state': 'no_portfolio'}), isA<BriefClaimNoPortfolio>());
      expect(p({'state': 'not_business_day'}), isA<BriefClaimNotBusinessDay>());
      expect(p({'state': 'rareza'}), isA<BriefClaimUnavailable>());
      expect(DailyBriefClaim.parse(null), isA<BriefClaimUnavailable>());
      // ready sin payload no es usable.
      expect(p({'state': 'ready'}), isA<BriefClaimUnavailable>());
    });

    test('courtesy numbers are ignored when it is not a courtesy brief', () {
      final c =
          DailyBriefClaim.parse({
                'state': 'claimed',
                'courtesy_number': 2,
                'courtesy_total': 7,
              })
              as BriefClaimGranted;
      expect(c.courtesyNumber, isNull);
    });
  });

  group('DailyBriefStatus.parse', () {
    test('off unless enabled is exactly true', () {
      expect(DailyBriefStatus.parse(null).enabled, isFalse);
      expect(DailyBriefStatus.parse({'enabled': false}).enabled, isFalse);
      expect(DailyBriefStatus.parse({'enabled': 'yes'}).enabled, isFalse);
    });

    test('a missing piece counts as on, an explicit false as off', () {
      final s = DailyBriefStatus.parse({
        'enabled': true,
        'pieces': {'feed': false},
      });
      expect(s.piece('feed'), isFalse);
      expect(s.piece('market'), isTrue);
      expect(DailyBriefStatus.off.piece('market'), isFalse);
    });
  });

  group('DailyBriefBundle.parse (contract fixtures)', () {
    test('full: held headlines, pulse facts, sources and asset classes', () {
      final b = DailyBriefBundle.parse(bundleFixture('bundle_brief_full'));
      expect(b.variant, 'full');
      expect(b.held.map((h) => h.id), ['h1', 'h2', 'h3']);
      expect(b.watch, isEmpty);
      expect(b.market, hasLength(3));
      expect(b.market.last.assetClass, 'bond');
      expect(b.sources.keys, containsAll(['p1', 'p2', 'p3']));
      expect(b.assetClasses, {'equity', 'bond'});
    });

    test('numbers: one market fact and no headlines', () {
      final b = DailyBriefBundle.parse(bundleFixture('bundle_brief_numbers'));
      expect(b.variant, 'numbers');
      expect(b.mine, isEmpty);
      expect(b.market, hasLength(1));
    });

    test('garbage blocks come out empty, never throw', () {
      final b = DailyBriefBundle.parse({
        'mine': 'x',
        'market': 3,
        'sources': [],
        'earnings': {'a': 1},
      });
      expect(b.mine, isEmpty);
      expect(b.market, isEmpty);
      expect(b.sources, isEmpty);
    });
  });

  group('DailyBrief.compose', () {
    final numbers = DailyBriefNumbers.compute(
      history: history(),
      lots: lots,
      candlesByTicker: candles,
      now: briefNow(),
    );
    final full = DailyBriefBundle.parse(bundleFixture('bundle_brief_full'));
    final free = DailyBriefBundle.parse(bundleFixture('bundle_brief_numbers'));
    const prose = DailyBriefProse(
      why: [BriefLine(ticker: 'NVDA', text: 'Subió 4,1 %.', newsId: 'h1')],
      held: [BriefLine(ticker: 'AAPL', text: 'Productos nuevos.', newsId: 'h3')],
      connections: {'bonds_rates': 'Tenés renta fija.', 'fed_rates': '  '},
    );

    DailyBrief compose(
      DailyBriefBundle bundle,
      DailyBriefVariant variant, [
      DailyBriefProse p = DailyBriefProse.empty,
    ]) => DailyBrief.compose(
      day: briefDay,
      lang: 'es',
      now: briefNow(),
      numbers: numbers,
      bundle: bundle,
      variant: variant,
      prose: p,
    );

    test('free: no prose, 1 market fact without connection and a teaser', () {
      final b = compose(free, DailyBriefVariant.numbers, prose);
      expect(b.why, isEmpty);
      expect(b.heldNews, isEmpty);
      expect(b.market, hasLength(1));
      expect(b.market.single.connection, isNull);
      expect(b.teaser?.requiredPlan, 'premium');
      expect(b.toJson()['teaser'], {'kind': 'held_news', 'required_plan': 'premium'});
    });

    test('free: the payload carries no ticker of a headline', () {
      final json = compose(free, DailyBriefVariant.numbers).toJson();
      expect(json['why'], isEmpty);
      expect(json['held_news'], isEmpty);
      expect(json['watch_news'], isEmpty);
    });

    test('full: every line and fact has outlet and link', () {
      final b = compose(full, DailyBriefVariant.full, prose);
      expect(b.why.single.newsId, 'h1');
      for (final line in [...b.why, ...b.heldNews]) {
        final s = b.sourceOf(line.newsId)!;
        expect(s.source, isNotEmpty);
        expect(Uri.parse(s.url).scheme, 'https');
      }
      for (final m in b.market) {
        expect(b.sourceOf(m.sourceIds.first)!.url, startsWith('https://'));
      }
      expect(b.teaser, isNull);
    });

    test('full: connection only from the model, blank ones are null', () {
      final b = compose(full, DailyBriefVariant.full, prose);
      final byTopic = {for (final m in b.market) m.topicId: m.connection};
      expect(byTopic['bonds_rates'], 'Tenés renta fija.');
      expect(byTopic['fed_rates'], isNull);
      expect(byTopic['oil_energy'], isNull);
    });

    test('lines that cite an unknown headline are dropped', () {
      final b = compose(
        full,
        DailyBriefVariant.full,
        const DailyBriefProse(
          why: [BriefLine(ticker: 'X', text: 'inventado', newsId: 'h99')],
          held: [BriefLine(ticker: 'X', text: 'sin id')],
        ),
      );
      expect(b.why, isEmpty);
      expect(b.heldNews, isEmpty);
      expect(b.sources.keys, everyElement(startsWith('p')));
    });

    test('a watchlist headline never becomes a "why"', () {
      final withWatch = DailyBriefBundle(
        mine: [
          BriefHeadline(
            id: 'w1',
            ticker: 'MELI',
            watch: true,
            title: 't',
            source: 'Reuters',
            domain: 'reuters.com',
            url: 'https://www.reuters.com/x',
          ),
        ],
      );
      final b = compose(
        withWatch,
        DailyBriefVariant.full,
        const DailyBriefProse(
          why: [BriefLine(ticker: 'MELI', text: 'x', newsId: 'w1')],
          watch: [BriefLine(ticker: 'MELI', text: 'y', newsId: 'w1')],
        ),
      );
      expect(b.why, isEmpty);
      expect(b.watchNews, hasLength(1));
    });

    test('numbers fallback for a paying user carries no teaser', () {
      final b = DailyBrief.compose(
        day: briefDay,
        lang: 'es',
        now: briefNow(),
        numbers: numbers,
        bundle: DailyBriefBundle.empty,
        variant: DailyBriefVariant.numbers,
        withTeaser: false,
      );
      expect(b.teaser, isNull);
    });

    test('toJson → tryParse keeps everything and audio stays null', () {
      final b = compose(full, DailyBriefVariant.full, prose);
      final json = b.toJson();
      expect(json['v'], 1);
      expect(json['audio'], isNull);
      final back = DailyBrief.tryParse(json, courtesy: true)!;
      expect(back.day, briefDay);
      expect(back.variant, DailyBriefVariant.full);
      expect(back.why.single.text, 'Subió 4,1 %.');
      expect(back.market, hasLength(3));
      expect(back.sources.keys, b.sources.keys);
      expect(back.courtesy, isTrue);
      expect(back.numbers.pct, numbers.pct);
    });

    test('a payload of another version is not parsed', () {
      final json = compose(full, DailyBriefVariant.full).toJson()..['v'] = 2;
      expect(DailyBrief.tryParse(json), isNull);
    });
  });
}
