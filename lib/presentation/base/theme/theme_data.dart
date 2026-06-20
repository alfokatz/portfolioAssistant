import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart' show Provider;
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/color_schema.dart'
    show colorSchemeDarkProvider, colorSchemeLightProvider;
import 'package:portfolio_assistant/presentation/base/theme/text_extension.dart'
    show customTextProvider;
import 'package:portfolio_assistant/presentation/base/theme/text_theme.dart'
    show textThemeProvider;
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart'
    show CustomColors;

ThemeData _buildThemeData({
  required ColorScheme scheme,
  required TextTheme textTheme,
  required CustomColors customColors,
  required dynamic customTexts,
}) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: textTheme,
    scaffoldBackgroundColor: customColors.background,
    appBarTheme: AppBarTheme(
      backgroundColor: customColors.background,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: textTheme.titleMedium?.copyWith(
        color: customColors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: IconThemeData(
        color: customColors.textPrimary,
        size: AppDimens.iconMd,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: customColors.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(AppDimens.radiusLg)),
        side: BorderSide(color: customColors.border),
      ),
      margin: EdgeInsets.zero,
    ),
    dividerTheme: DividerThemeData(
      color: customColors.border,
      thickness: 0.5,
      space: 0.5,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: customColors.surfaceCard,
      selectedColor: customColors.accentBlue,
      side: BorderSide(color: customColors.border),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusSm),
      ),
      labelStyle: textTheme.labelLarge?.copyWith(
        color: customColors.textSecondary,
      ),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: customColors.surfaceCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(AppDimens.radiusLg)),
        side: BorderSide(color: customColors.border),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: customColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppDimens.radiusXl),
        ),
      ),
      showDragHandle: true,
      dragHandleColor: customColors.border,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: customColors.surfaceElevated,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppDimens.sp16,
        vertical: 14,
      ),
      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      hintStyle: TextStyle(
        color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        borderSide: BorderSide(color: customColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        borderSide: BorderSide(color: customColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        borderSide: BorderSide(color: scheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        borderSide: BorderSide(color: scheme.error, width: 1.5),
      ),
    ),
    extensions: [customColors, customTexts],
  );
}

final themeDataLightProvider = Provider<ThemeData>((ref) {
  final scheme = ref.watch(colorSchemeLightProvider);
  final textTheme = ref.watch(textThemeProvider);
  final customTexts = ref.watch(customTextProvider);
  return _buildThemeData(
    scheme: scheme,
    textTheme: textTheme,
    customColors: CustomColors.light,
    customTexts: customTexts,
  );
});

final themeDataDarkProvider = Provider<ThemeData>((ref) {
  final scheme = ref.watch(colorSchemeDarkProvider);
  final textTheme = ref.watch(textThemeProvider);
  final customTexts = ref.watch(customTextProvider);
  return _buildThemeData(
    scheme: scheme,
    textTheme: textTheme,
    customColors: CustomColors.dark,
    customTexts: customTexts,
  );
});

/// Backward compatibility alias.
final themeDataProvider = themeDataLightProvider;
