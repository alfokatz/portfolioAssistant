// Screenshots del rediseño de Noticias: tarjeta "Hoy en tu cartera" de la
// Home con la barra de 5 pestañas, "Para vos", el brief y un tema, en claro
// y oscuro, con fuentes y textos reales y fotos de mentira (degradés). No
// corre en la suite normal (escribe PNGs):
//
//   RUN_SCREENSHOTS=1 SCREENSHOTS_OUT=/tmp/shots \
//     flutter test test/screenshots/news_screenshots_test.dart
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
// ignore: depend_on_referenced_packages
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/daily_brief/data/daily_brief_numbers_loader.dart';
import 'package:portfolio_assistant/features/daily_brief/data/daily_brief_repository.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_claim.dart';
import 'package:portfolio_assistant/features/daily_brief/providers/daily_brief_provider.dart';
import 'package:portfolio_assistant/features/daily_brief/view/daily_brief_screen.dart';
import 'package:portfolio_assistant/features/daily_brief/view/daily_brief_today_card.dart';
import 'package:portfolio_assistant/features/news_feed/view/news_feed_screen.dart';
import 'package:portfolio_assistant/features/news_feed/view/news_topic_screen.dart';
import 'package:portfolio_assistant/features/news_preferences/data/news_preferences_repository.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/app_background_gradient.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/app_bottom_nav_bar.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/news_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/daily_brief/fakes/daily_brief_fakes.dart';
import '../features/news_preferences/fakes/news_preferences_fakes.dart';
import '../features/subscription/paywall_test_harness.dart';

final _out = Platform.environment['SCREENSHOTS_OUT'] ?? 'build/screenshots';
final _enabled = Platform.environment['RUN_SCREENSHOTS'] == '1';

const _devices = {'se': (Size(375, 667), 2.0), 'pro': (Size(402, 874), 3.0)};

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

/// Un degradé como "foto": la imagen de mentira de cada URL.
Future<ui.Image> _photo(int seed) async {
  const colors = [
    [Color(0xFF3D5A80), Color(0xFFE0A96D)],
    [Color(0xFF2F4B3C), Color(0xFFB7C9A8)],
    [Color(0xFF6B4E71), Color(0xFFE8C4B8)],
  ];
  final pair = colors[seed % colors.length];
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const size = Size(400, 300);
  canvas.drawRect(
    Offset.zero & size,
    Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(400, 300), pair),
  );
  return recorder.endRecording().toImage(400, 300);
}

Map<String, Object?> _withImages(Map<String, Object?> body) {
  final copy = (jsonDecode(jsonEncode(body)) as Map).cast<String, Object?>();
  var n = 0;
  final ids = <String>{};
  for (final key in ['mine', 'topic_news']) {
    final list = copy[key];
    if (list is! List) continue;
    for (final a in list.cast<Map>()) {
      // Una nota sin foto: el layout no deja hueco.
      if (n++ == 2) continue;
      a['image_url'] = 'https://img.example.com/$n.jpg';
      ids.add('${a['id']}');
    }
  }
  final sources = copy['sources'];
  if (sources is Map) {
    for (final e in sources.entries) {
      if (ids.contains(e.key)) {
        (e.value as Map)['image_url'] = 'https://img.example.com/${e.key}.jpg';
      }
    }
  }
  return copy;
}

class _Store extends FakeDailyBriefStore {
  _Store(this.bodies, {super.claims, super.bundleBody});
  final Map<String, Map<String, Object?>> bodies;

  @override
  Future<Map<String, Object?>> bundle(
    String scope, {
    required String day,
    required String lang,
    String? topic,
  }) async => bodies[scope] ?? bodies['brief']!;
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
  double dpr,
) async {
  final render =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = (await tester.runAsync(() => render.toImage(pixelRatio: dpr)))!;
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

  Future<DailyBriefController> controllerFor(_Store store) async {
    final c = DailyBriefController(
      store: store,
      numbers: DailyBriefNumbersLoader(quotes: FakeQuotes()),
      writer: FakeDailyBriefWriter(),
      userId: () => 'u',
      clock: briefNow,
      language: () => 'es',
    );
    await c.ensureFor(history(), lots);
    return c;
  }

  for (final MapEntry(key: device, value: spec) in _devices.entries) {
    for (final brightness in Brightness.values) {
      for (final screen in ['home', 'para_vos', 'brief', 'tema']) {
        final id = 'news_${screen}_${device}_${brightness.name}';
        testWidgets(id, (tester) async {
          final (size, dpr) = spec;
          tester.view.physicalSize = size * dpr;
          tester.view.devicePixelRatio = dpr;
          tester.view.padding = const FakeViewPadding(top: 47 * 2);
          tester.view.viewPadding = const FakeViewPadding(top: 47 * 2);
          tester.platformDispatcher.platformBrightnessTestValue = brightness;
          addTearDown(tester.view.reset);
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );

          final images = <String, ui.Image>{};
          for (var i = 0; i < 3; i++) {
            images['$i'] = (await tester.runAsync(() => _photo(i)))!;
          }
          final bytes = <String, Uint8List>{};
          for (final e in images.entries) {
            bytes[e.key] =
                (await tester.runAsync(
                  () => e.value.toByteData(format: ui.ImageByteFormat.png),
                ))!.buffer.asUint8List();
          }
          NewsPhoto.debugProvider =
              (url) => MemoryImage(bytes['${url.hashCode % 3}']!);
          addTearDown(() => NewsPhoto.debugProvider = null);

          SharedPreferences.setMockInitialValues({});
          final prefs = await SharedPreferences.getInstance();
          final feed = _withImages(bundleFixture('bundle_feed_premium'));
          final briefBody = _withImages(bundleFixture('bundle_brief_full'));
          final store = _Store(
            {
              'brief': briefBody,
              'feed': feed,
              'topic': _withImages(bundleFixture('bundle_topic')),
            },
            claims: const [BriefClaimGranted(courtesy: false, attempt: 1)],
            bundleBody: briefBody,
          );
          final controller = await controllerFor(store);
          final container = ProviderContainer();
          final theme = container.read(
            brightness == Brightness.light
                ? themeDataLightProvider
                : themeDataDarkProvider,
          );
          container.dispose();

          final Widget home = switch (screen) {
            'home' => Scaffold(
              extendBody: true,
              bottomNavigationBar: AppBottomNavBar(
                current: AppNavDestination.home,
                showNews: true,
                newsBadge: true,
                onSelect: (_) {},
              ),
              body: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      const Text('Domingo 22 de noviembre'),
                      const Text(
                        'US\$ 48.210',
                        style: TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 24),
                      DailyBriefTodayCard(history: history(), lots: lots),
                      const Text('Posiciones'),
                    ],
                  ),
                ),
              ),
            ),
            'para_vos' => Scaffold(
              extendBody: true,
              bottomNavigationBar: AppBottomNavBar(
                current: AppNavDestination.news,
                showNews: true,
                onSelect: (_) {},
              ),
              body: const NewsFeedScreen(),
            ),
            'brief' => const DailyBriefScreen(day: briefDay),
            _ => const NewsTopicScreen(topicId: 'fed_rates'),
          };
          final boundary = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: ProviderScope(
                overrides: [
                  ...PaywallHarness().overrides,
                  sharedPreferencesProvider.overrideWithValue(prefs),
                  dailyBriefRepositoryProvider.overrideWithValue(store),
                  dailyBriefControllerProvider.overrideWith(
                    (ref) => controller,
                  ),
                  newsFeedAvailableProvider.overrideWithValue(true),
                  newsPreferencesStoreProvider.overrideWithValue(
                    FakeNewsPreferencesStore(),
                  ),
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
                  home: home,
                ),
              ),
            ),
          );
          for (var i = 0; i < 3; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 200)),
            );
            await tester.pump(const Duration(seconds: 2));
          }
          await _capture(tester, boundary, id, dpr);
        }, skip: !_enabled);
      }
    }
  }
}
