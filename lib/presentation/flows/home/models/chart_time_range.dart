enum ChartTimeRange {
  w1,
  m1,
  m3,
  m6,
  y1,
  all;

  String get label => switch (this) {
        ChartTimeRange.w1 => '1W',
        ChartTimeRange.m1 => '1M',
        ChartTimeRange.m3 => '3M',
        ChartTimeRange.m6 => '6M',
        ChartTimeRange.y1 => '1Y',
        ChartTimeRange.all => 'ALL',
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
