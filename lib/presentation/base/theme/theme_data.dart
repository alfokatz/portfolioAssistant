import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart' show Provider;
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/color_schema.dart'
    show colorSchemeProvider;
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
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
    scaffoldBackgroundColor: PortfolioColors.background,

    // ── App Bar ─────────────────────────────────────────────────────────
    appBarTheme: AppBarTheme(
      backgroundColor: PortfolioColors.background,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: textTheme.titleMedium?.copyWith(
        color: PortfolioColors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: const IconThemeData(
        color: PortfolioColors.textPrimary,
        size: AppDimens.iconMd,
      ),
    ),

    // ── Cards ────────────────────────────────────────────────────────────
    cardTheme: const CardThemeData(
      elevation: 0,
      color: PortfolioColors.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppDimens.radiusLg)),
        side: BorderSide(color: PortfolioColors.border),
      ),
      margin: EdgeInsets.zero,
    ),

    // ── Dividers ─────────────────────────────────────────────────────────
    dividerTheme: const DividerThemeData(
      color: PortfolioColors.border,
      thickness: 0.5,
      space: 0.5,
    ),

    // ── Chips ────────────────────────────────────────────────────────────
    chipTheme: ChipThemeData(
      backgroundColor: PortfolioColors.surfaceCard,
      selectedColor: PortfolioColors.accentBlue,
      side: const BorderSide(color: PortfolioColors.border),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusSm),
      ),
      labelStyle: textTheme.labelLarge?.copyWith(
        color: PortfolioColors.textSecondary,
      ),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
    ),

    // ── Dialogs ──────────────────────────────────────────────────────────
    dialogTheme: const DialogThemeData(
      backgroundColor: PortfolioColors.surfaceCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppDimens.radiusLg)),
        side: BorderSide(color: PortfolioColors.border),
      ),
    ),

    // ── Bottom Sheet ─────────────────────────────────────────────────────
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: PortfolioColors.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppDimens.radiusXl),
        ),
      ),
      showDragHandle: true,
      dragHandleColor: PortfolioColors.border,
    ),

    // ── Inputs ───────────────────────────────────────────────────────────
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: PortfolioColors.surfaceElevated,
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
        borderSide: const BorderSide(color: PortfolioColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        borderSide: const BorderSide(color: PortfolioColors.border),
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
});
