import 'package:fl_chart/fl_chart.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

/// Helpers for Y-axis reference labels on fl_chart widgets.
abstract final class ChartAxisHelper {
  static String formatCurrency(double value) {
    final abs = value.abs();
    final sign = value < 0 ? '-' : '';
    if (abs >= 1e6) {
      return '$sign\$${(abs / 1e6).toStringAsFixed(1)}M';
    }
    if (abs >= 1000) {
      return '$sign\$${(abs / 1000).toStringAsFixed(1)}k';
    }
    if (abs >= 100) {
      return '$sign\$${abs.toStringAsFixed(0)}';
    }
    return '$sign\$${abs.toStringAsFixed(2)}';
  }

  static String formatIndex(double value, {double? range}) {
    if (range != null && range < 40) {
      return value.toStringAsFixed(1);
    }
    return value.toStringAsFixed(0);
  }

  static String formatSignedCurrency(double value) {
    if (value == 0) return '\$0';
    final sign = value > 0 ? '+' : '';
    return '$sign${formatCurrency(value)}';
  }

  static List<double> yTicks(
    double minY,
    double maxY, {
    int divisions = 4,
  }) {
    if (divisions <= 0) return [minY];
    if ((maxY - minY).abs() < 1e-9) return [minY];
    final step = (maxY - minY) / divisions;
    return List<double>.generate(
      divisions + 1,
      (i) => minY + step * i,
    );
  }

  static FlGridData horizontalGrid({
    required double minY,
    required double maxY,
    int divisions = 4,
  }) {
    final interval = (maxY - minY) / divisions;
    return FlGridData(
      show: true,
      drawVerticalLine: false,
      horizontalInterval: interval > 0 ? interval : 1,
      getDrawingHorizontalLine: (_) => const FlLine(
        color: PortfolioColors.chartGrid,
        strokeWidth: 1,
      ),
    );
  }

}
