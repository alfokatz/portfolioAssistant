// "Abrir en tu bróker": los links por bróker y el botón (abre, avisa si no
// pudo, no aparece sin link).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/features/broker_links/domain/broker_link.dart';
import 'package:portfolio_assistant/features/broker_links/view/open_in_broker_links.dart';
import 'package:portfolio_assistant/features/snaptrade/domain/snaptrade_connection.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';

void main() {
  group('BrokerLinks', () {
    test('eToro: the instrument page; crypto without -USD', () {
      expect(
        BrokerLinks.etoro('AAPL').toString(),
        'https://www.etoro.com/markets/aapl',
      );
      expect(
        BrokerLinks.etoro('BRK.B').toString(),
        'https://www.etoro.com/markets/brk.b',
      );
      expect(
        BrokerLinks.etoro('BTC-USD').toString(),
        'https://www.etoro.com/markets/btc',
      );
      expect(BrokerLinks.etoro('A B/C'), isNull);
    });

    test('Binance: the spot pair against USDT', () {
      expect(
        BrokerLinks.binance('ETH-USD').toString(),
        'https://www.binance.com/en/trade/ETH_USDT?type=spot',
      );
      expect(BrokerLinks.binance('BRK.B'), isNull);
    });

    test('SnapTrade: the broker site, only with a single imported broker', () {
      final ibkr = SnaptradeBrokerage(
        id: 'a1',
        name: 'Interactive Brokers',
        url: Uri.parse('https://www.interactivebrokers.com'),
      );
      final one = BrokerLinks.forPosition(
        ticker: 'VOO',
        sources: {PositionSource.snaptrade},
        snaptradeImported: [ibkr],
      );
      expect(one.single.broker, 'Interactive Brokers');
      expect(one.single.instrumentPage, isFalse);
      expect(
        BrokerLinks.forPosition(
          ticker: 'VOO',
          sources: {PositionSource.snaptrade},
          snaptradeImported: [
            ibkr,
            SnaptradeBrokerage(
              id: 'a2',
              name: 'Schwab',
              url: Uri.parse('https://www.schwab.com'),
            ),
          ],
        ),
        isEmpty,
      );
    });

    test('several sources: one link per broker; manual adds nothing', () {
      final links = BrokerLinks.forPosition(
        ticker: 'BTC-USD',
        sources: {
          PositionSource.manual,
          PositionSource.etoro,
          PositionSource.binance,
        },
      );
      expect(links.map((l) => l.broker), ['eToro', 'Binance']);
      expect(
        BrokerLinks.forPosition(
          ticker: 'AAPL',
          sources: {PositionSource.manual},
        ),
        isEmpty,
      );
    });

    test('a brokerage url that is not https is ignored', () {
      final b = SnaptradeBrokerage.fromJson({
        'id': 'a1',
        'name': 'X',
        'url': 'http://insecure.example',
      });
      expect(b!.url, isNull);
    });
  });

  group('OpenInBrokerLinks', () {
    Future<List<Uri>> pump(
      WidgetTester tester,
      Set<PositionSource> sources, {
      bool launchOk = true,
    }) async {
      final opened = <Uri>[];
      for (final brightness in Brightness.values) {
        final theme = ProviderContainer().read(
          brightness == Brightness.light
              ? themeDataLightProvider
              : themeDataDarkProvider,
        );
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: theme,
              home: Scaffold(
                body: OpenInBrokerLinks(
                  ticker: 'AAPL',
                  sources: sources,
                  launch: (u) async {
                    opened.add(u);
                    return launchOk;
                  },
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      }
      return opened;
    }

    testWidgets('opens the eToro page', (tester) async {
      final opened = await pump(tester, {PositionSource.etoro});
      await tester.tap(find.text('broker_open_in'));
      await tester.pump();
      expect(opened.single.host, 'www.etoro.com');
    });

    testWidgets('nothing for a manual position', (tester) async {
      await pump(tester, {PositionSource.manual});
      expect(find.byType(TextButton), findsNothing);
    });
  });
}
