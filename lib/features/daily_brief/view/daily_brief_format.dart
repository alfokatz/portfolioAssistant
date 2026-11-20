import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_bundle.dart';
import 'package:portfolio_assistant/features/home_widget/view/widget_news_sheet.dart';
import 'package:portfolio_assistant/presentation/shared/formatting/app_number_format.dart';

/// Textos y formatos del brief. Los números van con [AppNumberFormat] (el
/// mismo formato que la Home); las frases fijas salen de acá y no del
/// modelo.
abstract final class DailyBriefFormat {
  static String pct(double v) => AppNumberFormat.percent(v);

  static String weight(double v) => AppNumberFormat.percent(v, signed: false);

  /// El idioma del `MaterialApp` (EasyLocalization lo fija ahí).
  static String? locale(BuildContext context) =>
      Localizations.maybeLocaleOf(context)?.toLanguageTag();

  /// "jue 24 sept" del cierre (o de cualquier fecha).
  static String day(BuildContext context, DateTime d) =>
      DateFormat.MMMEd(locale(context)).format(d);

  static String shortDate(BuildContext context, DateTime d) =>
      DateFormat.MMMd(locale(context)).format(d);

  /// "Datos de las 08:03".
  static String asOf(BuildContext context, DateTime asOf) =>
      'daily_brief_as_of'.tr(
        namedArgs: {
          'time': DateFormat.Hm(locale(context)).format(asOf.toLocal()),
        },
      );

  /// "NVDA · Reuters · hace 3 h" (o sin ticker / sin hora si faltan).
  static String sourceLine(
    BriefSource source, {
    String? ticker,
    required DateTime now,
  }) {
    final published = source.publishedAt;
    final parts = [
      if (ticker != null) ticker,
      source.source,
      if (published != null) WidgetNewsSheet.ageLabel(published, now),
    ];
    return parts.join(' · ');
  }

  /// La línea de un resultado de Gold.
  static String earnings(BuildContext context, BriefEarning e) => (e.reported
          ? 'daily_brief_earnings_reported'
          : 'daily_brief_earnings_estimated')
      .tr(namedArgs: {'ticker': e.ticker, 'date': shortDate(context, e.date)});
}
