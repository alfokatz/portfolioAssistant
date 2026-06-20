import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart' show Provider;
import 'package:portfolio_assistant/presentation/base/theme/color_schema.dart'
    show colorSchemeProvider;

@immutable
class CustomTextStyles extends ThemeExtension<CustomTextStyles> {
  final TextStyle badge;
  final TextStyle link;

  const CustomTextStyles({required this.badge, required this.link});

  @override
  CustomTextStyles copyWith({TextStyle? badge, TextStyle? link}) {
    return CustomTextStyles(
      badge: badge ?? this.badge,
      link: link ?? this.link,
    );
  }

  @override
  CustomTextStyles lerp(ThemeExtension<CustomTextStyles>? other, double t) {
    if (other is! CustomTextStyles) return this;
    return CustomTextStyles(
      badge: TextStyle.lerp(badge, other.badge, t)!,
      link: TextStyle.lerp(link, other.link, t)!,
    );
  }
}

final customTextProvider = Provider<CustomTextStyles>((ref) {
  final scheme = ref.watch(colorSchemeProvider);
  return CustomTextStyles(
    badge: GoogleFonts.plusJakartaSans(
      fontSize: 10,
      fontWeight: FontWeight.w600,
      height: 1.2,
      letterSpacing: 0.6,
      color: scheme.onPrimary,
    ),
    link: GoogleFonts.plusJakartaSans(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      decoration: TextDecoration.underline,
      color: scheme.primary,
    ),
  );
});
