import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_report.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_report_input.dart';
import 'package:portfolio_assistant/presentation/shared/formatting/app_number_format.dart';

/// Textos y formatos del informe. Los números van con [AppNumberFormat] (el
/// mismo formato que la Home); las frases fijas salen de acá y no del
/// modelo, así nunca hay jerga ni cifras inventadas.
abstract final class WeeklyReportFormat {
  static String pct(double v) => AppNumberFormat.percent(v);
  static String money(double v) => AppNumberFormat.money(v);
  static String signedMoney(double v) => AppNumberFormat.signedMoney(v);

  /// "21 al 25 de septiembre"; cruzando de mes, "29 de septiembre al 3 de
  /// octubre". En inglés, "September 21–25".
  static String range(BuildContext context, WeeklyReport report) {
    final locale = _locale(context);
    final from = report.week.monday;
    final to = report.week.friday;
    final month = DateFormat.MMMM(locale);
    if (from.month == to.month) {
      return 'weekly_report_range_same_month'.tr(
        namedArgs: {
          'from': '${from.day}',
          'to': '${to.day}',
          'month': month.format(to),
        },
      );
    }
    return 'weekly_report_range_cross_month'.tr(
      namedArgs: {
        'from': '${from.day}',
        'fromMonth': month.format(from),
        'to': '${to.day}',
        'toMonth': month.format(to),
      },
    );
  }

  /// "jue 24 sept" (día de la semana corto + fecha).
  static String day(BuildContext context, DateTime d) =>
      DateFormat.MMMEd(_locale(context)).format(d);

  /// El idioma del `MaterialApp` (EasyLocalization lo fija ahí).
  static String? _locale(BuildContext context) =>
      Localizations.maybeLocaleOf(context)?.toLanguageTag();

  /// La frase de lectura de Porty o, sin texto (solo números), una según la
  /// dirección y el mercado.
  static String reading(WeeklyReport report) {
    final r = report.reading;
    if (r != null) return r;
    if (report.changePct > 0.15) return 'weekly_report_fallback_up'.tr();
    if (report.changePct < -0.15) return 'weekly_report_fallback_down'.tr();
    return 'weekly_report_fallback_flat'.tr();
  }

  /// "El S&P 500 subió 1,2%" (o bajó / casi no se movió).
  static String? market(WeeklyReport report) {
    final sp = report.sp500Pct;
    if (sp == null) return null;
    if (sp.abs() < 0.1) return 'weekly_report_market_flat'.tr();
    return (sp > 0 ? 'weekly_report_market_up' : 'weekly_report_market_down')
        .tr(
          namedArgs: {'pct': AppNumberFormat.percent(sp.abs(), signed: false)},
        );
  }

  /// "El S&P 500 subió 1,2%: a tu cartera le fue un poco peor que al
  /// mercado." Sin rojo ni "pts": es contexto, no un resultado.
  static String? comparison(WeeklyReport report) {
    final m = market(report);
    final c = report.comparison;
    if (m == null || c == null) return null;
    final relation = switch (c) {
      MarketComparison.better => 'weekly_report_vs_better',
      MarketComparison.slightlyBetter => 'weekly_report_vs_slightly_better',
      MarketComparison.similar => 'weekly_report_vs_similar',
      MarketComparison.slightlyWorse => 'weekly_report_vs_slightly_worse',
      MarketComparison.worse => 'weekly_report_vs_worse',
    };
    return 'weekly_report_comparison'.tr(
      namedArgs: {'market': m, 'relation': relation.tr()},
    );
  }

  /// "El resto se movió menos de 0,5%." o "Y 3 posiciones más…".
  static String? others(WeeklyReport report) {
    if (report.othersCount <= 0) return null;
    if (report.othersAllSmall) {
      return 'weekly_report_others_small'.tr(
        namedArgs: {
          'pct': AppNumberFormat.percent(
            WeeklyReportInput.smallMovePct,
            signed: false,
          ),
        },
      );
    }
    return report.othersCount == 1
        ? 'weekly_report_others_more_one'.tr()
        : 'weekly_report_others_more'.tr(
          namedArgs: {'count': '${report.othersCount}'},
        );
  }

  /// Preguntas para seguir con Porty. Las arma la app con plantillas
  /// neutrales (nunca afirman nada): el reporte que viene, la posición que
  /// más movió y cómo va en el año.
  static List<String> questions(WeeklyReport report) {
    final earnings = report.upcomingEarnings.firstOrNull;
    final top = report.movers.firstOrNull;
    return [
      if (earnings != null)
        'weekly_report_q_earnings'.tr(namedArgs: {'ticker': earnings.ticker}),
      if (top != null && top.ticker != earnings?.ticker)
        'weekly_report_q_mover'.tr(namedArgs: {'ticker': top.ticker}),
      if (top == null) 'weekly_report_q_market'.tr(),
      'weekly_report_q_year'.tr(),
    ].take(3).toList();
  }
}
