import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Faint warm hint painted once, behind every screen in the app (see
/// `MaterialApp.builder` in main.dart) — just enough that pages don't read
/// as flat white, without becoming a colored surface of their own. Screens
/// keep the theme's transparent scaffold background to let it show
/// through; a screen that wants to opt out (auth, onboarding) sets its own
/// opaque `Scaffold.backgroundColor`, which paints over this layer.
///
/// Kept deliberately restrained: it fades out within the top ~28% of the
/// screen, well before body copy, chips or list rows would ever sit on
/// top of a visibly tinted background — this app is a financial dashboard
/// (product register), not a marketing surface, so the accent stays a
/// hint at the very top rather than a wash across the whole page.
class AppBackgroundGradient extends StatelessWidget {
  const AppBackgroundGradient({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(colors.background, colors.accentWarm, 0.32)!,
            colors.background,
          ],
          stops: const [0.0, 0.28],
        ),
      ),
    );
  }
}
