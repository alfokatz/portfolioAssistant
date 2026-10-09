// Screenshots de las pantallas de eToro (los cuatro estados de la conexión,
// el resultado de la importación, la hoja de desconectar y eToro en el
// onboarding) con fuentes y
// textos reales. No corre en la suite normal (escribe PNGs):
//
//   RUN_SCREENSHOTS=1 SCREENSHOTS_OUT=/tmp/shots \
//     flutter test test/screenshots/etoro_screenshots_test.dart
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
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/etoro/data/etoro_connection_repository.dart';
import 'package:portfolio_assistant/features/etoro/domain/etoro_connection.dart';
import 'package:portfolio_assistant/features/etoro/providers/etoro_connection_provider.dart';
import 'package:portfolio_assistant/features/etoro/view/etoro_connection_screen.dart';
import 'package:portfolio_assistant/features/etoro/view/etoro_import_result_screen.dart';
import 'package:portfolio_assistant/features/etoro/view/widgets/etoro_brand.dart';
import 'package:portfolio_assistant/features/etoro/view/widgets/etoro_disconnect_sheet.dart';
import 'package:portfolio_assistant/features/etoro/view/widgets/etoro_home_widgets.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/position_row_widget.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/onboarding_screen.dart';
import 'package:portfolio_assistant/presentation/flows/settings/ui/widgets/settings_nav_row.dart';
import 'package:portfolio_assistant/presentation/flows/settings/ui/widgets/settings_section_card.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/app_background_gradient.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class _Repo implements EtoroConnectionRepository {
  _Repo(this.connection);
  final EtoroConnection connection;

  @override
  Future<EtoroConnection> load() async => connection;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

EtoroImportResult _result() => EtoroImportResult.fromJson({
  'imported': 6,
  'closedImported': 2,
  'notImported': [
    {'ticker': 'TSLA', 'name': 'Tesla', 'reason': 'leveraged', 'count': 2},
    {'ticker': 'BTC', 'name': 'Bitcoin', 'reason': 'crypto', 'count': 1},
    {'ticker': 'ETH', 'name': 'Ethereum', 'reason': 'crypto', 'count': 1},
  ],
  'closedNotImported': [],
  'possibleDuplicates': ['VOO'],
  'syncedAt': '2026-10-09T12:00:00Z',
});

EtoroConnection _connection(EtoroConnectionStatus status) => EtoroConnection(
  status: status,
  lastSyncAt: DateTime.now().subtract(const Duration(minutes: 6)),
  lastResult: status == EtoroConnectionStatus.notConnected ? null : _result(),
);

Widget _app(
  Brightness brightness,
  Widget home,
  EtoroConnection connection, {
  List<Override> overrides = const [],
}) {
  final container = ProviderContainer();
  final theme = container.read(
    brightness == Brightness.light
        ? themeDataLightProvider
        : themeDataDarkProvider,
  );
  container.dispose();
  return ProviderScope(
    overrides: [
      etoroConnectionRepositoryProvider.overrideWithValue(_Repo(connection)),
      ...overrides,
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('es', 'ES')],
      locale: const Locale('es', 'ES'),
      // El fondo de la app se pinta detrás del Router.
      builder:
          (context, child) => Stack(
            children: [
              const Positioned.fill(child: AppBackgroundGradient()),
              child!,
            ],
          ),
      home: home,
    ),
  );
}

/// Carga la conexión antes de mostrar [child] (como al volver de conectar).
class _LoadThen extends ConsumerStatefulWidget {
  const _LoadThen({required this.child});
  final Widget child;

  @override
  ConsumerState<_LoadThen> createState() => _LoadThenState();
}

class _LoadThenState extends ConsumerState<_LoadThen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(etoroConnectionProvider.notifier).load(),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

void _noop() {}

Future<void> _capture(WidgetTester tester, GlobalKey boundary, String name) async {
  final render =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = (await tester.runAsync(() => render.toImage(pixelRatio: _dpr)))!;
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
    SharedPreferences.setMockInitialValues({});
    final es =
        jsonDecode(File('assets/translations/es-ES.json').readAsStringSync())
            as Map<String, dynamic>;
    Localization.load(const Locale('es', 'ES'), translations: Translations(es));
    await initializeDateFormatting('es_ES');
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

  /// Fuentes y SVG se cargan fuera del reloj falso.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
    }
  }

  for (final brightness in Brightness.values) {
    final b = brightness.name;

    for (final status in EtoroConnectionStatus.values) {
      testWidgets('etoro_${status.name}_$b', (tester) async {
        await setUp(tester, brightness);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: _app(
              brightness,
              const EtoroConnectionScreen(),
              _connection(status),
            ),
          ),
        );
        await settle(tester);
        await _capture(tester, boundary, 'etoro_${status.name}_$b');
      }, skip: !_enabled);
    }

    testWidgets('etoro_result_$b', (tester) async {
      await setUp(tester, brightness);
      final prefs = await SharedPreferences.getInstance();
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: _app(
            brightness,
            const _LoadThen(child: EtoroImportResultScreen()),
            _connection(EtoroConnectionStatus.connected),
            overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          ),
        ),
      );
      await settle(tester);
      await _capture(tester, boundary, 'etoro_result_$b');
    }, skip: !_enabled);

    testWidgets('etoro_disconnect_sheet_$b', (tester) async {
      await setUp(tester, brightness);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: _app(
            brightness,
            Builder(
              builder:
                  (context) => Scaffold(
                    body: Center(
                      child: TextButton(
                        onPressed:
                            () => EtoroDisconnectSheet.show(
                              context,
                              importedCount: 6,
                            ),
                        child: const Text('open'),
                      ),
                    ),
                  ),
            ),
            _connection(EtoroConnectionStatus.connected),
          ),
        ),
      );
      await settle(tester);
      await tester.tap(find.text('open'));
      await settle(tester);
      await _capture(tester, boundary, 'etoro_disconnect_sheet_$b');
    }, skip: !_enabled);

    testWidgets('etoro_home_banner_$b', (tester) async {
      await setUp(tester, brightness);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: _app(
            brightness,
            const Scaffold(
              body: SafeArea(
                child: Column(
                  children: [
                    SizedBox(height: 24),
                    EtoroReconnectBanner(),
                    Padding(
                      padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
                      child: SettingsSectionCard(
                        title: 'Cuentas conectadas',
                        children: [
                          SettingsNavRow(
                            icon: Icons.link_rounded,
                            leading: EtoroAppIcon(),
                            label: 'eToro',
                            subtitle: 'Conectada · actualizada hace 6 min',
                            onTap: _noop,
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: EtoroConnectButton(),
                    ),
                  ],
                ),
              ),
            ),
            _connection(EtoroConnectionStatus.connected),
          ),
        ),
      );
      await settle(tester);
      await _capture(tester, boundary, 'etoro_home_banner_$b');
    }, skip: !_enabled);

    for (final page in [1, 3]) {
      testWidgets('etoro_onboarding_${page}_$b', (tester) async {
        await setUp(tester, brightness);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: _app(
              brightness,
              const OnboardingScreen(),
              _connection(EtoroConnectionStatus.notConnected),
            ),
          ),
        );
        await settle(tester);
        for (var i = 0; i < page; i++) {
          await tester.tap(find.text('Siguiente'));
          await settle(tester);
        }
        await _capture(tester, boundary, 'etoro_onboarding_${page}_$b');
      }, skip: !_enabled);
    }

    testWidgets('etoro_position_rows_$b', (tester) async {
      await setUp(tester, brightness);
      final boundary = GlobalKey();
      Widget row(String ticker, double qty, double buy, double now, PositionSource source) =>
          PositionRowWidget(
            valuation: PortfolioCalculator.valuate(
              position: Position(
                id: ticker,
                ticker: ticker,
                quantity: qty,
                purchasePrice: buy,
                purchaseDate: DateTime(2026, 3, 1),
                source: source,
              ),
              currentPrice: now,
            ),
          );
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: _app(
            brightness,
            Scaffold(
              body: SafeArea(
                child: Column(
                  children: [
                    row('NVDA', 12, 96, 131.4, PositionSource.etoro),
                    row('KO', 20, 64, 61.9, PositionSource.etoro),
                    row('AAPL', 8, 189, 226.1, PositionSource.manual),
                    row('MSFT', 4, 430, 418.7, PositionSource.etoro),
                  ],
                ),
              ),
            ),
            _connection(EtoroConnectionStatus.connected),
          ),
        ),
      );
      await settle(tester);
      await _capture(tester, boundary, 'etoro_position_rows_$b');
    }, skip: !_enabled);
  }
}
