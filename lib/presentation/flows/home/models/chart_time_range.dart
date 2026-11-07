import 'package:easy_localization/easy_localization.dart';

enum ChartTimeRange {
  w1,
  m1,
  m3,
  m6,
  y1,
  all;

  /// Etiqueta del selector, en castellano y la misma que el gráfico de
  /// precio de una acción (S = semana, A = año).
  String get label => switch (this) {
        ChartTimeRange.w1 => '1S',
        ChartTimeRange.m1 => '1M',
        ChartTimeRange.m3 => '3M',
        ChartTimeRange.m6 => '6M',
        ChartTimeRange.y1 => '1A',
        ChartTimeRange.all => 'Todo',
      };

  /// "Último mes", "Desde tu primera compra"… (de qué período habla una
  /// variación).
  String get periodLabel => switch (this) {
        ChartTimeRange.w1 => 'home_range_w1'.tr(),
        ChartTimeRange.m1 => 'home_range_m1'.tr(),
        ChartTimeRange.m3 => 'home_range_m3'.tr(),
        ChartTimeRange.m6 => 'home_range_m6'.tr(),
        ChartTimeRange.y1 => 'home_range_y1'.tr(),
        ChartTimeRange.all => 'home_range_all'.tr(),
      };

  Duration? get duration => switch (this) {
        ChartTimeRange.w1 => const Duration(days: 7),
        ChartTimeRange.m1 => const Duration(days: 30),
        ChartTimeRange.m3 => const Duration(days: 90),
        ChartTimeRange.m6 => const Duration(days: 180),
        ChartTimeRange.y1 => const Duration(days: 365),
        ChartTimeRange.all => null,
      };
}
