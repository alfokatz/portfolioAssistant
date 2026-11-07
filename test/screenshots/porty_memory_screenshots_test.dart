// Screenshots de "Lo que Porty sabe de vos" con lo que anotó y de qué
// acciones hablaron (porty_topics), en claro y oscuro, iPhone SE y Pro, con
// fuentes y textos reales. No corre en la suite normal (escribe PNGs):
//
//   RUN_SCREENSHOTS=1 SCREENSHOTS_OUT=/tmp/shots \
//     flutter test test/screenshots/porty_memory_screenshots_test.dart
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
import 'package:intl/date_symbol_data_local.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/porty_memory/data/porty_topics_repository.dart';
import 'package:portfolio_assistant/features/porty_memory/data/user_memory_repository.dart';
import 'package:portfolio_assistant/features/porty_memory/domain/porty_topic.dart';
import 'package:portfolio_assistant/features/porty_memory/domain/user_memory.dart';
import 'package:portfolio_assistant/features/porty_memory/view/porty_memory_screen.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/app_background_gradient.dart';

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

class _Memories implements UserMemoryRepository {
  @override
  Future<List<UserMemory>> list() async => [
    UserMemory(
      id: '1',
      content: 'Ahorra unos 500 dólares por mes',
      category: UserMemoryCategory.values.first,
      source: UserMemorySource.values.first,
      updatedAt: DateTime(2026, 10, 10),
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Topics implements PortyTopicsRepository {
  @override
  Future<List<PortyTopic>> list() async => [
    PortyTopic(
      ticker: 'AMZN',
      question: '¿Qué está pasando con Amazon después de los resultados?',
      lastAskedAt: DateTime(2026, 10, 21),
      priceAt: 182.5,
    ),
    PortyTopic(
      ticker: 'NVDA',
      question: '¿Por qué bajó?',
      lastAskedAt: DateTime(2026, 10, 14),
      priceAt: 178.4,
      held: true,
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(Brightness brightness) {
  final container = ProviderContainer();
  final theme = container.read(
    brightness == Brightness.light
        ? themeDataLightProvider
        : themeDataDarkProvider,
  );
  container.dispose();
  return ProviderScope(
    overrides: [
      userMemoryRepositoryProvider.overrideWithValue(_Memories()),
      portyTopicsRepositoryProvider.overrideWithValue(_Topics()),
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
      home: const PortyMemoryScreen(),
    ),
  );
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
    await _loadFonts();
  });

  for (final MapEntry(key: device, value: (size, dpr)) in _devices.entries) {
    for (final brightness in Brightness.values) {
      final id = 'porty_memory_${device}_${brightness.name}';
      testWidgets(id, (tester) async {
        tester.view.physicalSize = size * dpr;
        tester.view.devicePixelRatio = dpr;
        tester.view.padding = FakeViewPadding(top: 47 * dpr);
        tester.view.viewPadding = FakeViewPadding(top: 47 * dpr);
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(key: boundary, child: _app(brightness)),
        );
        for (var i = 0; i < 3; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 200)),
          );
          await tester.pump(const Duration(seconds: 1));
        }
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image =
            (await tester.runAsync(() => render.toImage(pixelRatio: dpr)))!;
        final bytes =
            (await tester.runAsync(
              () => image.toByteData(format: ui.ImageByteFormat.png),
            ))!;
        File('$_out/$id.png')
          ..createSync(recursive: true)
          ..writeAsBytesSync(bytes.buffer.asUint8List());
      }, skip: !_enabled);
    }
  }
}
