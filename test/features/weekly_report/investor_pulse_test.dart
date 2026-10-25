import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/weekly_report/data/investor_pulse_client.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/investor_pulse_item.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/investor_pulse_relevance.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/report_week.dart';

InvestorPulseItem _news(String id, String investor, String headline) =>
    InvestorPulseItem.tryParse({
      'id': id,
      'investor_id': investor,
      'investor_name': investor,
      'voice': 'investor',
      'type': 'news',
      'date': '2026-09-24',
      'url': 'https://news.google.com/$id',
      'headline': headline,
      'source': 'Reuters',
    })!;

InvestorPulseItem _filing(String id, {String? ticker, String? issuer}) =>
    InvestorPulseItem.tryParse({
      'id': id,
      'investor_id': 'warren-buffett',
      'investor_name': 'Warren Buffett',
      'voice': 'investor',
      'type': 'filing',
      'form': '4',
      'action': 'buy',
      'issuer_ticker': ticker,
      'issuer_name': issuer,
      'shares': 638813,
      'date': '2026-09-25',
      'url': 'https://www.sec.gov/Archives/edgar/data/1067983/x-index.htm',
    })!;

/// Respuesta fija para el cliente HTTP, sin red.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.status, this.body);
  final int status;
  final Object body;
  RequestOptions? last;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    last = options;
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('InvestorPulseItem.tryParse', () {
    test('reads news and filings', () {
      final n = _news('i2', 'bill-ackman', 'Ackman warns about the Fed');
      expect(n.isFiling, isFalse);
      expect(n.date, DateTime(2026, 9, 24));
      final f = _filing('i1', ticker: 'len', issuer: 'LENNAR CORP /NEW/');
      expect(f.isFiling, isTrue);
      expect(f.issuerTicker, 'LEN');
      expect(f.shares, 638813);
    });

    test('drops items without an https url or without a headline', () {
      final base = {
        'id': 'i1',
        'investor_id': 'x',
        'investor_name': 'X',
        'type': 'news',
        'date': '2026-09-24',
        'headline': 'h',
      };
      expect(
        InvestorPulseItem.tryParse({...base, 'url': 'javascript:alert(1)'}),
        isNull,
      );
      expect(
        InvestorPulseItem.tryParse({
          ...base,
          'url': 'https://a.com',
          'headline': '',
        }),
        isNull,
      );
      expect(
        InvestorPulseItem.tryParse({...base, 'url': 'https://a.com'}),
        isNotNull,
      );
    });
  });

  group('InvestorPulseRelevance', () {
    final holdings = {
      'AAPL': 'Apple Inc',
      'LEN': 'Lennar Corp',
      'NVDA': 'NVIDIA Corp',
      'F': 'Ford Motor Co',
    };

    List<String> related(InvestorPulseItem item) =>
        InvestorPulseRelevance.rank(
          [item],
          holdings: holdings,
          limit: 5,
        ).single.relatedTickers;

    test('a filing matches by ticker or by company name', () {
      expect(related(_filing('i1', ticker: 'LEN')), ['LEN']);
      expect(related(_filing('i1', issuer: 'Apple Inc.')), ['AAPL']);
      // "LEN" dentro de "LENNAR" no cuenta como ticker suelto.
      expect(related(_filing('i1', issuer: 'LENNARX HOLDINGS')), isEmpty);
    });

    test('a headline matches the ticker as a word or the company name', () {
      expect(related(_news('i1', 'a', 'Burry bets against NVDA again')), [
        'NVDA',
      ]);
      expect(related(_news('i1', 'a', r'Ackman likes $AAPL')), ['AAPL']);
      expect(related(_news('i1', 'a', 'Buffett trims apple stake')), ['AAPL']);
      expect(related(_news('i1', 'a', 'NVDAX fund launches')), isEmpty);
      // Un ticker de una letra solo con `$`.
      expect(related(_news('i1', 'a', 'Plan F for the Fed')), isEmpty);
      expect(related(_news('i1', 'a', r'Wood buys $F shares')), ['F']);
    });

    test('relevant items go first, max 2 per investor, up to the limit', () {
      final ranked = InvestorPulseRelevance.rank(
        [
          _news('i1', 'dalio', 'Dalio warns on bonds'),
          _news('i2', 'dalio', 'Dalio on the dollar'),
          _news('i3', 'dalio', 'Dalio on gold'),
          _news('i4', 'wood', 'Cathie Wood buys more NVDA'),
          _news('i5', 'marks', 'Howard Marks memo on markets'),
        ],
        holdings: holdings,
        limit: 4,
      );
      expect(ranked.map((r) => r.item.id), ['i4', 'i1', 'i2', 'i5']);
    });
  });

  group('InvestorPulseClient', () {
    final week = ReportWeek.ofMonday(DateTime(2026, 9, 21));

    InvestorPulseClient client(_Adapter adapter) => InvestorPulseClient(
      dio: Dio()..httpClientAdapter = adapter,
      baseUrl: 'https://x.supabase.co/functions/v1/investor-pulse',
      accessToken: () async => 'jwt',
      anonKey: 'anon',
    );

    test(
      'asks for the covered week with the user JWT and parses items',
      () async {
        final adapter = _Adapter(200, {
          'week_start': '2026-09-21',
          'items': [
            {
              'id': 'i1',
              'investor_id': 'warren-buffett',
              'investor_name': 'Warren Buffett',
              'type': 'filing',
              'form': '4',
              'action': 'buy',
              'issuer_ticker': 'LEN',
              'date': '2026-09-25',
              'url': 'https://www.sec.gov/x-index.htm',
            },
            {'id': 'broken'},
          ],
        });
        final items = await client(adapter).fetch(week);
        expect(items!.single.issuerTicker, 'LEN');
        expect(adapter.last!.queryParameters['week'], '2026-09-21');
        expect(adapter.last!.headers['Authorization'], 'Bearer jwt');
      },
    );

    test('a server error is null (failed), not an empty week', () async {
      expect(await client(_Adapter(429, {'error': {}})).fetch(week), isNull);
    });
  });

  group('selectForReport (what the weekly report shows)', () {
    InvestorPulseItem filing(
      String id, {
      required String investor,
      String? org,
      String form = '4',
      String action = 'buy',
      String? ticker,
      String? issuer,
    }) =>
        InvestorPulseItem.tryParse({
          'id': id,
          'investor_id': investor,
          'investor_name': investor,
          'organization': org,
          'voice': 'investor',
          'type': 'filing',
          'form': form,
          'action': action,
          'issuer_ticker': ticker,
          'issuer_name': issuer,
          'date': '2026-09-24',
          'url': 'https://www.sec.gov/$id',
        })!;

    final holdings = {'VOO': 'Vanguard S&P 500 ETF', 'AMZN': 'Amazon.com Inc'};

    test('related to a holding: shown', () {
      final picked = InvestorPulseRelevance.selectForReport([
        filing('i1', investor: 'Warren Buffett', ticker: 'AMZN'),
      ], holdings: holdings);
      expect(picked.single.relatedTickers, ['AMZN']);
    });

    test('unrelated and not notable (Buffett buys Lennar): no section', () {
      final picked = InvestorPulseRelevance.selectForReport([
        filing(
          'i1',
          investor: 'Warren Buffett',
          ticker: 'LEN',
          issuer: 'Lennar',
        ),
        _news('i2', 'fed-chair', 'Fed Chair signals patience on rates'),
      ], holdings: holdings);
      expect(picked, isEmpty);
    });

    test('an investor filing about their own company never appears', () {
      final self = filing(
        'i1',
        investor: 'Carl Icahn',
        org: 'Icahn Enterprises',
        form: 'SCHEDULE 13D/A',
        action: 'stake_update',
        ticker: 'IEP',
        issuer: 'ICAHN ENTERPRISES L.P.',
      );
      expect(InvestorPulseRelevance.isSelfFiling(self), isTrue);
      expect(
        InvestorPulseRelevance.selectForReport([self], holdings: holdings),
        isEmpty,
      );
    });

    test('notable without relation: one new 13D (not an amendment)', () {
      final picked = InvestorPulseRelevance.selectForReport([
        filing(
          'i1',
          investor: 'Bill Ackman',
          form: 'SCHEDULE 13D/A',
          action: 'stake_update',
          ticker: 'XYZ',
          issuer: 'XYZ Corp',
        ),
        filing(
          'i2',
          investor: 'Bill Ackman',
          form: 'SCHEDULE 13D',
          action: 'stake',
          ticker: 'HHH',
          issuer: 'Howard Hughes',
        ),
        filing(
          'i3',
          investor: 'Carl Icahn',
          form: 'SCHEDULE 13D',
          action: 'stake',
          ticker: 'ABC',
          issuer: 'ABC Inc',
        ),
      ], holdings: holdings);
      expect(picked.map((r) => r.item.id), ['i2']);
    });
  });
}
