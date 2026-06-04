import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart' show Provider;
import 'package:portfolio_assistant/presentation/base/theme/color_schema.dart'
    show colorSchemeProvider;
import 'package:portfolio_assistant/presentation/base/theme/text_extension.dart'
    show customTextProvider;
import 'package:portfolio_assistant/presentation/base/theme/text_theme.dart'
    show textThemeProvider;
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart'
    show customColorsProvider;

final themeDataProvider = Provider<ThemeData>((ref) {
  final scheme = ref.watch(colorSchemeProvider);
  final textTheme = ref.watch(textThemeProvider);
  final customColors = ref.watch(customColorsProvider);
  final customTexts = ref.watch(customTextProvider);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: textTheme,
    inputDecorationTheme: InputDecorationTheme(
      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.primary, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.error, width: 1.4),
      ),
    ),
    extensions: [customColors, customTexts],
  );
});
