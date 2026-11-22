import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief.dart';
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

  /// "Domingo 22" (el día de la semana y el número, con mayúscula inicial).
  static String weekdayDay(BuildContext context, DateTime d) {
    final text = DateFormat('EEEE d', locale(context)).format(d);
    return text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
  }

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

  /// La cara de Porty según cómo cerró el día: contento si subió, preocupado
  /// si bajó, serio si quedó plano (menos de 0,05 % para cualquier lado).
  static PortyAvatarState moodOf(double pct) {
    if (!pct.isFinite || pct.abs() < 0.05) return PortyAvatarState.serious;
    return pct > 0 ? PortyAvatarState.answered : PortyAvatarState.concerned;
  }

  /// Minutos de lectura del brief (200 palabras por minuto, al menos 1).
  static int readMinutes(DailyBrief brief) {
    final text = [
      for (final l in [...brief.why, ...brief.heldNews, ...brief.watchNews])
        l.text,
      for (final m in brief.market) ...[
        m.text,
        if (m.connection != null) m.connection!,
      ],
    ].join(' ');
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    return (words / 200).ceil().clamp(1, 99);
  }

  /// Parte [text] en los tramos que van en negrita: lo que está entre `**`
  /// (las frases fijas de la app, traducidas con `**dato**`).
  static List<InlineSpan> markedSpans(String text, TextStyle bold) {
    final parts = text.split('**');
    return [
      for (var i = 0; i < parts.length; i++)
        if (parts[i].isNotEmpty)
          TextSpan(text: parts[i], style: i.isOdd ? bold : null),
    ];
  }

  static final _figure = RegExp(
    r'[+\-\u2212]?(?:US\$|\$)?\s?\d[\d.,]*(?:\s?%|\s?(?:pb|bps|M|B|mil)\b)?',
  );

  /// Pone en negrita los números del texto de Porty (el dato clave de cada
  /// viñeta: "subió 3,4 %", "US$ 48.210"). Es una regla de formato, no una
  /// lista de palabras: lo que no es cifra queda como vino.
  static List<InlineSpan> boldFigures(String text, TextStyle bold) {
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _figure.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      spans.add(TextSpan(text: m.group(0), style: bold));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return spans;
  }
}
