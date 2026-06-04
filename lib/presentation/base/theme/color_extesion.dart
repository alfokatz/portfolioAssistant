import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart' show Provider;

@immutable
class CustomColors extends ThemeExtension<CustomColors> {
  final Color primaryFixed;
  final Color primaryFixedDim;
  final Color errorContainer;
  final Color info;

  const CustomColors({
    required this.primaryFixed,
    required this.primaryFixedDim,
    required this.errorContainer,
    required this.info,
  });

  @override
  CustomColors copyWith({
    Color? primaryFixed,
    Color? primaryFixedDim,
    Color? errorContainer,
    Color? info,
  }) {
    return CustomColors(
      primaryFixed: primaryFixed ?? this.primaryFixed,
      primaryFixedDim: primaryFixedDim ?? this.primaryFixedDim,
      errorContainer: errorContainer ?? this.errorContainer,
      info: info ?? this.info,
    );
  }

  @override
  CustomColors lerp(ThemeExtension<CustomColors>? other, double t) {
    if (other is! CustomColors) return this;
    return CustomColors(
      primaryFixed: Color.lerp(primaryFixed, other.primaryFixed, t)!,
      primaryFixedDim: Color.lerp(primaryFixedDim, other.primaryFixedDim, t)!,
      errorContainer: Color.lerp(errorContainer, other.errorContainer, t)!,
      info: Color.lerp(info, other.info, t)!,
    );
  }
}

final customColorsProvider = Provider<CustomColors>((ref) {
  return const CustomColors(
    primaryFixed: Color(0xFF5B8100),
    primaryFixedDim: Color(0xFFE0F3B2),
    errorContainer: Color(0xFF66091B),
    info: Color(0xFF2979FF),
  );
});
