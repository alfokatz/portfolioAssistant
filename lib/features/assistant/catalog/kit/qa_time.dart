import 'package:easy_localization/easy_localization.dart';

/// Fechas relativas para las cards (según el idioma de la app) ("hace 2 h", "ayer", "en 21
/// días"). Reciben `now` inyectable para que los tests no dependan del
/// reloj.
abstract final class QaTime {
  static String _month(DateTime d) => 'qa_time_month_${d.month}'.tr();

  /// Antigüedad de algo ya publicado. Pasada la semana se muestra la fecha
  /// ("18 sep"), con año solo si no es el actual: "hace 23 días" se lee
  /// peor que una fecha concreta.
  static String ago(DateTime date, {DateTime? now}) {
    final current = (now ?? DateTime.now()).toLocal();
    final local = date.toLocal();
    final diff = current.difference(local);
    if (diff.isNegative || diff.inMinutes < 1) return 'qa_time_just_now'.tr();
    if (diff.inMinutes < 60) {
      return 'qa_time_ago_min'.tr(namedArgs: {'n': '${diff.inMinutes}'});
    }
    final days = _dayDiff(local, current);
    if (days == 0) {
      return 'qa_time_ago_hours'.tr(namedArgs: {'n': '${diff.inHours}'});
    }
    if (days == 1) return 'qa_time_yesterday'.tr();
    if (days < 7) return 'qa_time_ago_days'.tr(namedArgs: {'n': '$days'});
    if (local.year == current.year) {
      return 'qa_time_date_short'.tr(
        namedArgs: {'day': '${local.day}', 'month': _month(local)},
      );
    }
    return day(local);
  }

  /// Fecha de calendario completa ("5 oct 2026"): la de una operación, que
  /// se lee como fecha y no como antigüedad.
  static String day(DateTime date) => 'qa_time_date_full'.tr(
    namedArgs: {
      'day': '${date.day}',
      'month': _month(date),
      'year': '${date.year}',
    },
  );

  /// Cuenta regresiva a una fecha futura ("hoy", "mañana", "en 21 días").
  /// `null` si la fecha ya pasó.
  static String? countdown(DateTime date, {DateTime? now}) {
    final days = _dayDiff((now ?? DateTime.now()).toLocal(), date);
    if (days < 0) return null;
    if (days == 0) return 'qa_time_today'.tr();
    if (days == 1) return 'qa_time_tomorrow'.tr();
    return 'qa_time_in_days'.tr(namedArgs: {'n': '$days'});
  }

  /// `true` si el texto ya viene como fecha relativa ("hoy", "hace 2
  /// días") — en ese caso se respeta tal cual lo escribió el modelo.
  static bool looksRelative(String label) {
    final l = label.trim().toLowerCase();
    return l.startsWith('hace') ||
        l.startsWith('hoy') ||
        l.startsWith('ayer') ||
        l.startsWith('recién') ||
        l.startsWith('today') ||
        l.startsWith('yesterday') ||
        l.startsWith('just now') ||
        RegExp(r'^\d+\s*\w+ ago').hasMatch(l);
  }

  /// Días de calendario entre [from] y [to] (ignora la hora).
  static int _dayDiff(DateTime from, DateTime to) {
    final a = DateTime.utc(from.year, from.month, from.day);
    final b = DateTime.utc(to.year, to.month, to.day);
    return b.difference(a).inDays;
  }
}
