import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/binance/data/binance_repository.dart';
import 'package:portfolio_assistant/features/binance/providers/binance_provider.dart';
import 'package:portfolio_assistant/features/broker_connect/view/widgets/brokers_auto_sync.dart';
import 'package:portfolio_assistant/features/etoro/data/etoro_connection_repository.dart';
import 'package:portfolio_assistant/features/etoro/providers/etoro_connection_provider.dart';
import 'package:portfolio_assistant/features/snaptrade/data/snaptrade_repository.dart';
import 'package:portfolio_assistant/features/snaptrade/providers/snaptrade_provider.dart';

class _Unused {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _EtoroRepo extends _Unused implements EtoroConnectionRepository {}

class _EtoroLauncher extends _Unused implements EtoroAuthLauncher {}

class _BinanceRepo extends _Unused implements BinanceRepository {}

class _SnapRepo extends _Unused implements SnaptradeRepository {}

class _SnapPortal extends _Unused implements SnaptradePortalLauncher {}

class _Etoro extends EtoroConnectionNotifier {
  _Etoro() : super(repository: _EtoroRepo(), launcher: _EtoroLauncher());
  var checks = 0;

  @override
  Future<bool> syncIfStale() async {
    checks++;
    return false;
  }
}

class _Binance extends BinanceNotifier {
  _Binance() : super(_BinanceRepo());
  var checks = 0;

  @override
  Future<void> syncIfStale({DateTime? now}) async => checks++;
}

class _Snaptrade extends SnaptradeNotifier {
  _Snaptrade() : super(_SnapRepo(), _SnapPortal());
  var checks = 0;

  @override
  Future<void> syncIfStale({DateTime? now}) async => checks++;
}

void main() {
  testWidgets('on open and on resume it checks every broker', (tester) async {
    final etoro = _Etoro();
    final binance = _Binance();
    final snaptrade = _Snaptrade();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          etoroConnectionProvider.overrideWith((_) => etoro),
          binanceProvider.overrideWith((_) => binance),
          snaptradeProvider.overrideWith((_) => snaptrade),
        ],
        child: const BrokersAutoSync(child: SizedBox()),
      ),
    );
    await tester.pump();
    expect([etoro.checks, binance.checks, snaptrade.checks], [1, 1, 1]);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect([etoro.checks, binance.checks, snaptrade.checks], [2, 2, 2]);
  });
}
