// Lámina para elegir el ícono de "Preguntale a Porty" de la barra de arriba:
// cada diseño (filas) con Porty vestido de distintas formas (columnas), en
// claro y oscuro, con el avatar real. No corre en la suite normal:
//
//   RUN_SCREENSHOTS=1 SCREENSHOTS_OUT=/tmp/shots \
//     flutter test test/screenshots/porty_icon_options_screenshots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/porty_outfit/domain/porty_outfit.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/app_background_gradient.dart';

final _out = Platform.environment['SCREENSHOTS_OUT'] ?? 'build/screenshots';
final _enabled = Platform.environment['RUN_SCREENSHOTS'] == '1';

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

const _outfits = <String, PortyOutfit>{
  'Sin ropa': PortyOutfit.none,
  'Galera': PortyOutfit({PortyOutfitSlot.head: PortyAccessory.topHat}),
  'Cowboy': PortyOutfit({PortyOutfitSlot.head: PortyAccessory.cowboyHat}),
  'Corona': PortyOutfit({PortyOutfitSlot.head: PortyAccessory.crown}),
  'Moño + lentes': PortyOutfit({
    PortyOutfitSlot.head: PortyAccessory.bow,
    PortyOutfitSlot.face: PortyAccessory.glasses,
  }),
  'Gorro + anteojos': PortyOutfit({
    PortyOutfitSlot.head: PortyAccessory.beanie,
    PortyOutfitSlot.face: PortyAccessory.sunglasses,
  }),
};

/// Un diseño: su nombre y cómo se dibuja con un [PortyOutfit].
typedef _Design = ({
  String name,
  String note,
  Widget Function(PortyOutfit) build,
});

final _designs = <_Design>[
  (
    name: 'A · Actual',
    note: 'Pensando + globito "?"',
    build: (o) => _Badged(outfit: o, badge: const _QuestionBadge()),
  ),
  (
    name: 'B · Solo Porty pensando',
    note: 'Sin agregados, un poco más grande',
    build: (o) => _Fit(child: PortyAvatar(size: 32, state: PortyAvatarState.thinking, outfit: o)),
  ),
  (
    name: 'C · Porty dentro de un globo de chat',
    note: 'El globo dice "chat"; Porty sin ropa (no entra)',
    build: (_) => const _ChatBubblePorty(),
  ),
  (
    name: 'D · Porty + "escribiendo…"',
    note: 'Globito con tres puntos',
    build: (o) => _Badged(outfit: o, badge: const _DotsBadge(), state: PortyAvatarState.idle),
  ),
  (
    name: 'E · Porty en un círculo',
    note: 'Aro terracota, como un botón',
    build: (o) => _Ringed(outfit: o),
  ),
  (
    name: 'F · Píldora "Preguntale"',
    note: 'Porty + texto: lo más claro, ocupa más',
    build: (o) => _AskPill(outfit: o),
  ),
];

void main() {
  setUpAll(() async {
    if (!_enabled) return;
    PortyAvatar.ambientMotion = false;
    await _loadFonts();
  });

  for (final brightness in Brightness.values) {
    final id = 'porty_icon_options_${brightness.name}';
    testWidgets(id, (tester) async {
      const width = 1330.0;
      const height = 1140.0;
      tester.view.physicalSize = const Size(width, height) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final themes = ProviderContainer();
      final theme = themes.read(
        brightness == Brightness.light
            ? themeDataLightProvider
            : themeDataDarkProvider,
      );
      themes.dispose();
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme,
            home: Stack(
              children: [
                const Positioned.fill(child: AppBackgroundGradient()),
                const _Sheet(),
              ],
            ),
          ),
        ),
      );
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 500));
      }
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image =
          (await tester.runAsync(() => render.toImage(pixelRatio: 2)))!;
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

class _Sheet extends StatelessWidget {
  const _Sheet();

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(width: 290),
                SizedBox(
                  width: 185,
                  child: Center(
                    child: Text(
                      'En la barra',
                      style: tt.labelLarge?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                for (final name in _outfits.keys)
                  SizedBox(
                    width: 130,
                    child: Center(
                      child: Text(
                        name,
                        style: tt.labelLarge?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            for (final d in _designs)
              Container(
                height: 150,
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: colors.border)),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 290,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d.name,
                            style: tt.titleMedium?.copyWith(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            d.note,
                            style: tt.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 185,
                      child: _BarMock(child: d.build(PortyOutfit.none)),
                    ),
                    for (final outfit in _outfits.values)
                      SizedBox(
                        width: 130,
                        child: _Zoom(
                          wide: d.name.startsWith('F'),
                          child: d.build(outfit),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// El ícono en una barra de arriba de verdad (título + campana al lado),
/// a tamaño real dentro de la celda.
class _BarMock extends StatelessWidget {
  const _BarMock({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Center(
      child: Container(
        height: 72,
        padding: const EdgeInsets.only(left: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            child,
            const SizedBox(width: 6),
            Icon(
              Icons.notifications_none_rounded,
              color: colors.textPrimary,
              size: 24,
            ),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

/// El ícono ampliado ×2,5 (para ver cómo convive con la ropa).
class _Zoom extends StatelessWidget {
  const _Zoom({required this.child, this.wide = false});

  final Widget child;

  /// La píldora es más ancha: entra entera (se amplía menos).
  final bool wide;

  @override
  Widget build(BuildContext context) => Center(
    child: SizedBox(
      width: 124,
      height: 124,
      child: FittedBox(
        child: SizedBox(
          width: wide ? 120 : 50,
          height: 50,
          child: OverflowBox(
            maxWidth: 120,
            child: Center(child: child),
          ),
        ),
      ),
    ),
  );
}

/// Lo que ocupa un IconButton (48 × 48).
class _Fit extends StatelessWidget {
  const _Fit({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      SizedBox.square(dimension: 48, child: Center(child: child));
}

class _Badged extends StatelessWidget {
  const _Badged({
    required this.outfit,
    required this.badge,
    this.state = PortyAvatarState.thinking,
  });

  final PortyOutfit outfit;
  final Widget badge;
  final PortyAvatarState state;

  @override
  Widget build(BuildContext context) => _Fit(
    child: SizedBox.square(
      dimension: 34,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            bottom: 0,
            child: PortyAvatar(size: 30, state: state, outfit: outfit),
          ),
          Positioned(right: -2, top: -3, child: badge),
        ],
      ),
    ),
  );
}

class _QuestionBadge extends StatelessWidget {
  const _QuestionBadge();

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Container(
      width: 15,
      height: 15,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        shape: BoxShape.circle,
        border: Border.all(color: colors.border),
      ),
      child: Text(
        '?',
        style: TextStyle(
          fontSize: 10,
          height: 1,
          fontWeight: FontWeight.w800,
          color: colors.accentBlue,
        ),
      ),
    );
  }
}

class _DotsBadge extends StatelessWidget {
  const _DotsBadge();

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Container(
      width: 20,
      height: 13,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            Container(
              width: 3,
              height: 3,
              decoration: BoxDecoration(
                color: colors.accentBlue,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Un globo de chat (con su colita) con la cara de Porty adentro.
class _ChatBubblePorty extends StatelessWidget {
  const _ChatBubblePorty();

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return _Fit(
      child: SizedBox(
        width: 36,
        height: 34,
        child: CustomPaint(
          painter: _BubblePainter(
            fill: colors.chip,
            stroke: colors.accentBlue,
          ),
          child: const Padding(
            padding: EdgeInsets.only(bottom: 5),
            child: Center(
              child: PortyAvatar(
                size: 22,
                state: PortyAvatarState.idle,
                outfit: PortyOutfit.none,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BubblePainter extends CustomPainter {
  _BubblePainter({required this.fill, required this.stroke});

  final Color fill;
  final Color stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height - 6),
      const Radius.circular(12),
    );
    final path =
        Path()
          ..addRRect(body)
          ..moveTo(8, size.height - 7)
          ..lineTo(6, size.height)
          ..lineTo(15, size.height - 7)
          ..close();
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_BubblePainter old) =>
      old.fill != fill || old.stroke != stroke;
}

class _Ringed extends StatelessWidget {
  const _Ringed({required this.outfit});

  final PortyOutfit outfit;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return _Fit(
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.chip,
          shape: BoxShape.circle,
          border: Border.all(color: colors.accentBlue, width: 1.5),
        ),
        child: PortyAvatar(
          size: 26,
          state: PortyAvatarState.thinking,
          outfit: outfit,
        ),
      ),
    );
  }
}

class _AskPill extends StatelessWidget {
  const _AskPill({required this.outfit});

  final PortyOutfit outfit;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Container(
      height: 34,
      padding: const EdgeInsets.only(left: 3, right: 10),
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: colors.accentBlue.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PortyAvatar(size: 24, state: PortyAvatarState.idle, outfit: outfit),
          const SizedBox(width: 5),
          Text(
            'Preguntale',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
