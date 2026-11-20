// Screenshots de "Conectá tu bróker" (la pantalla y la card de Ajustes),
// sin nada conectado y con brókers conectados, en claro y oscuro, con
// fuentes y textos reales. No corre en la suite normal (escribe PNGs):
//
//   RUN_SCREENSHOTS=1 SCREENSHOTS_OUT=/tmp/shots \
//     flutter test test/screenshots/connect_broker_screenshots_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
// Viene con el SDK (y con easy_localization); solo para estos screenshots.
// ignore: depend_on_referenced_packages
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/binance/data/binance_repository.dart';
import 'package:portfolio_assistant/features/binance/domain/binance_connection.dart';
import 'package:portfolio_assistant/features/broker_connect/view/connect_broker_screen.dart';
import 'package:portfolio_assistant/features/broker_connect/view/widgets/connect_broker_card.dart';
import 'package:portfolio_assistant/features/etoro/data/etoro_connection_repository.dart';
import 'package:portfolio_assistant/features/etoro/data/etoro_sync_client.dart';
import 'package:portfolio_assistant/features/snaptrade/data/snaptrade_repository.dart';
import 'package:portfolio_assistant/features/snaptrade/domain/snaptrade_connection.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/features/binance/providers/binance_provider.dart';
import 'package:portfolio_assistant/features/snaptrade/providers/snaptrade_provider.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/app_background_gradient.dart';

final _out = Platform.environment['SCREENSHOTS_OUT'] ?? 'build/screenshots';
final _enabled = Platform.environment['RUN_SCREENSHOTS'] == '1';

const _size = Size(402, 874);
const _dpr = 3.0;

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(
        File(f).readAsBytes().then((b) => ByteData.view(b.buffer)),
      );
    }
    await loader.load();
  }

  final sdk =
      Platform.environment['FLUTTER_ROOT'] ??
      '${Platform.environment['HOME']}/Development/flutter';
  await load('MaterialIcons', [
    '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ]);
  const weights = {'Regular': 400, 'Medium': 500, 'SemiBold': 600, 'Bold': 700};
  for (final MapEntry(key: name, value: w) in weights.entries) {
    final file = 'assets/fonts/PlusJakartaSans-$name.ttf';
    await load('PlusJakartaSans_${w == 400 ? 'regular' : w}', [file]);
    await load('Plus Jakarta Sans', [file]);
  }
}

class _Binance implements BinanceRepository {
  _Binance(this.connection);

  final BinanceConnection connection;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<BinanceConnection> load() async => connection;
}

class _Repo implements SnaptradeRepository {
  _Repo(this.connection);

  final SnaptradeConnection connection;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<SnaptradeConnection> load() async => connection;
}

class _Subscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _Subscription()
    : super(
        const SubscriptionState(
          tier: SubscriptionTier.premium,
          queriesUsed: 0,
          queriesLimit: 100,
        ),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(Brightness brightness, (bool, bool) scenario) {
  final (connected, card) = scenario;
  final container = ProviderContainer();
  final theme = container.read(
    brightness == Brightness.light
        ? themeDataLightProvider
        : themeDataDarkProvider,
  );
  container.dispose();
  return ProviderScope(
    overrides: [
      etoroConnectionRepositoryProvider.overrideWithValue(
        EtoroConnectionRepository(
          client: () => null,
          syncClient: EtoroSyncClient(),
        ),
      ),
      binanceRepositoryProvider.overrideWithValue(
        _Binance(
          connected
              ? BinanceConnection(
                status: BinanceStatus.connected,
                lastSyncAt: DateTime.now().subtract(
                  const Duration(minutes: 20),
                ),
              )
              : const BinanceConnection(),
        ),
      ),
      snaptradeRepositoryProvider.overrideWithValue(
        _Repo(
          connected
              ? const SnaptradeConnection(
                status: SnaptradeStatus.connected,
                brokerages: [
                  SnaptradeBrokerage(id: 'a1', name: 'Interactive Brokers'),
                ],
              )
              : const SnaptradeConnection(),
        ),
      ),
      subscriptionProvider.overrideWith((ref) => _Subscription()),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('es', 'ES')],
      locale: const Locale('es', 'ES'),
      builder:
          (context, child) => Stack(
            children: [
              const Positioned.fill(child: AppBackgroundGradient()),
              child!,
            ],
          ),
      home:
          card
              ? const Scaffold(
                backgroundColor: Colors.transparent,
                body: Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppDimens.pageHorizontal,
                    80,
                    AppDimens.pageHorizontal,
                    0,
                  ),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: _CardLoader(),
                  ),
                ),
              )
              : const ConnectBrokerScreen(),
    ),
  );
}

/// Ajustes carga las conexiones al abrir; acá, igual.
class _CardLoader extends ConsumerStatefulWidget {
  const _CardLoader();

  @override
  ConsumerState<_CardLoader> createState() => _CardLoaderState();
}

class _CardLoaderState extends ConsumerState<_CardLoader> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(binanceProvider.notifier).load();
      ref.read(snaptradeProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) => const ConnectBrokerCard();
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  final render =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image =
      (await tester.runAsync(() => render.toImage(pixelRatio: _dpr)))!;
  final bytes =
      (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.png),
      ))!;
  File('$_out/$name.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes.buffer.asUint8List());
}

void main() {
  setUpAll(() async {
    if (!_enabled) return;
    PortyAvatar.ambientMotion = false;
    GoogleFonts.config.allowRuntimeFetching = false;
    final es =
        jsonDecode(File('assets/translations/es-ES.json').readAsStringSync())
            as Map<String, dynamic>;
    Localization.load(const Locale('es', 'ES'), translations: Translations(es));
    await initializeDateFormatting('es_ES');
    Intl.defaultLocale = 'es_ES';
    await _loadFonts();
  });

  Future<void> setUp(WidgetTester tester, Brightness brightness) async {
    tester.view.physicalSize = _size * _dpr;
    tester.view.devicePixelRatio = _dpr;
    tester.view.padding = const FakeViewPadding(top: 47 * _dpr);
    tester.view.viewPadding = const FakeViewPadding(top: 47 * _dpr);
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump(const Duration(seconds: 2));
    }
  }

  final scenarios = <String, (bool, bool)>{
    'screen_empty': (false, false),
    'screen_connected': (true, false),
    'card_empty': (false, true),
    'card_connected': (true, true),
  };

  for (final brightness in Brightness.values) {
    for (final MapEntry(key: name, value: connection) in scenarios.entries) {
      final id = 'connect_broker_${name}_${brightness.name}';
      testWidgets(id, (tester) async {
        await setUp(tester, brightness);
        tester.view.physicalSize = const Size(402, 874) * _dpr;
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(key: boundary, child: _app(brightness, connection)),
        );
        await settle(tester);
        await _capture(tester, boundary, id);
      }, skip: !_enabled);
    }
  }
}
