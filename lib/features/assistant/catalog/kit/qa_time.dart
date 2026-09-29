/// Fechas relativas en español para las cards ("hace 2 h", "ayer", "en 21
/// días"). Reciben `now` inyectable para que los tests no dependan del
/// reloj.
abstract final class QaTime {
  static const _months = [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];

  /// Antigüedad de algo ya publicado. Pasada la semana se muestra la fecha
  /// ("18 sep"), con año solo si no es el actual: "hace 23 días" se lee
  /// peor que una fecha concreta.
  static String ago(DateTime date, {DateTime? now}) {
    final current = (now ?? DateTime.now()).toLocal();
    final local = date.toLocal();
    final diff = current.difference(local);
    if (diff.isNegative || diff.inMinutes < 1) return 'recién';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    final days = _dayDiff(local, current);
    if (days == 0) return 'hace ${diff.inHours} h';
    if (days == 1) return 'ayer';
    if (days < 7) return 'hace $days días';
    final base = '${local.day} ${_months[local.month - 1]}';
    return local.year == current.year ? base : '$base ${local.year}';
  }

  /// Cuenta regresiva a una fecha futura ("hoy", "mañana", "en 21 días").
  /// `null` si la fecha ya pasó.
  static String? countdown(DateTime date, {DateTime? now}) {
    final days = _dayDiff((now ?? DateTime.now()).toLocal(), date);
    if (days < 0) return null;
    if (days == 0) return 'hoy';
    if (days == 1) return 'mañana';
    return 'en $days días';
  }

  /// `true` si el texto ya viene como fecha relativa ("hoy", "hace 2
  /// días") — en ese caso se respeta tal cual lo escribió el modelo.
  static bool looksRelative(String label) {
    final l = label.trim().toLowerCase();
    return l.startsWith('hace') ||
        l.startsWith('hoy') ||
        l.startsWith('ayer') ||
        l.startsWith('recién');
  }

  /// Días de calendario entre [from] y [to] (ignora la hora).
  static int _dayDiff(DateTime from, DateTime to) {
    final a = DateTime.utc(from.year, from.month, from.day);
    final b = DateTime.utc(to.year, to.month, to.day);
    return b.difference(a).inDays;
  }
}
