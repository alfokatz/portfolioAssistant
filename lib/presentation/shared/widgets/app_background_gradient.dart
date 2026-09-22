import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Soft warm ambient wash painted once, behind every screen in the app
/// (see `MaterialApp.builder` in main.dart) — so pages read as part of one
/// lit surface instead of flat white panels. Screens keep the theme's
/// transparent scaffold background to let it show through; a screen that
/// wants to opt out (auth, onboarding) sets its own opaque
/// `Scaffold.backgroundColor`, which paints over this layer.
class AppBackgroundGradient extends StatelessWidget {
  const AppBackgroundGradient({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0.9, -0.9),
          radius: 1.5,
          colors: [
            Color.lerp(colors.background, colors.accentWarm, 0.18)!,
            colors.background,
          ],
          stops: const [0.0, 0.7],
        ),
      ),
    );
  }
}
