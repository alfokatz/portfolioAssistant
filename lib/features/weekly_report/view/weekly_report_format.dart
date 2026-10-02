import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_report.dart';

/// Formatos del informe: los mismos del resto de la app (porcentaje con un
/// decimal y signo, dólares con dos decimales).
abstract final class WeeklyReportFormat {
  static String pct(double v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)}%';

  /// Puntos porcentuales ("+5.0 pts").
  static String pts(double v) => 'weekly_report_pts'.tr(
    namedArgs: {'value': '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)}'},
  );

  static String money(double v, {bool signed = false}) {
    final text = NumberFormat.currency(
      symbol: '\$',
      decimalDigits: 2,
    ).format(v.abs());
    if (!signed) return v < 0 ? '-$text' : text;
    return '${v >= 0 ? '+' : '-'}$text';
  }

  static String weight(double share) => '${(share * 100).toStringAsFixed(0)}%';

  /// "21 sept – 25 sept" en el idioma de la app.
  static String range(BuildContext context, WeeklyReport report) {
    final f = DateFormat.MMMd(_locale(context));
    return 'weekly_report_range'.tr(
      namedArgs: {
        'from': f.format(report.week.monday),
        'to': f.format(report.week.friday),
      },
    );
  }

  /// "jue 24" (día de la semana corto + día).
  static String day(BuildContext context, DateTime d) =>
      DateFormat.MEd(_locale(context)).format(d);

  /// El idioma del `MaterialApp` (EasyLocalization lo fija ahí).
  static String? _locale(BuildContext context) =>
      Localizations.maybeLocaleOf(context)?.toLanguageTag();

  /// El título de Porty o, sin texto (solo números), uno según la dirección.
  static String headline(WeeklyReport report) {
    final h = report.headline;
    if (h != null) return h;
    if (report.changePct > 0.15) return 'weekly_report_fallback_up'.tr();
    if (report.changePct < -0.15) return 'weekly_report_fallback_down'.tr();
    return 'weekly_report_fallback_flat'.tr();
  }
}
