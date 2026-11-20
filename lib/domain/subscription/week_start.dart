/// Lunes (00:00, hora local del usuario) de la semana de [now]. Es la clave
/// del análisis de cortesía semanal: lunes a domingo en la zona horaria del
/// usuario, no en UTC.
DateTime weekStartOf(DateTime now) {
  final local = now.toLocal();
  final day = DateTime(local.year, local.month, local.day);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

/// `YYYY-MM-DD` del lunes, como lo espera Supabase (`date`).
String weekStartKey(DateTime now) {
  final d = weekStartOf(now);
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}
