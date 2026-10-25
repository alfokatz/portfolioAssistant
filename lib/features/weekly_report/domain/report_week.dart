import 'package:portfolio_assistant/domain/subscription/week_start.dart';

/// La semana bursátil que cubre el informe: lunes a viernes, ya cerrada.
///
/// El informe se habilita el sábado a las 00:00 (hora local) y se ve hasta
/// que sale el siguiente. Un sábado o domingo cubre la semana que acaba de
/// cerrar; de lunes a viernes, la anterior.
class ReportWeek {
  ReportWeek._(this.monday);

  /// La semana que corresponde mostrar en [now].
  factory ReportWeek.coveredAt(DateTime now) {
    final local = now.toLocal();
    final thisMonday = weekStartOf(local);
    final weekend =
        local.weekday == DateTime.saturday || local.weekday == DateTime.sunday;
    return ReportWeek._(
      weekend ? thisMonday : _addDays(thisMonday, -DateTime.daysPerWeek),
    );
  }

  /// La semana bursátil de [monday] (tiene que ser un lunes).
  factory ReportWeek.ofMonday(DateTime monday) {
    final day = DateTime(monday.year, monday.month, monday.day);
    assert(day.weekday == DateTime.monday, '$monday no es lunes');
    return ReportWeek._(day);
  }

  /// Lunes 00:00 local.
  final DateTime monday;

  /// Viernes (fecha, 00:00 local): último día de la semana bursátil.
  DateTime get friday => _addDays(monday, 4);

  /// Sábado 00:00: fin exclusivo de la semana y momento en que se habilita.
  DateTime get endExclusive => _addDays(monday, 5);

  /// Clave de la semana (`YYYY-MM-DD` del lunes), la misma que usa Supabase.
  String get key => weekStartKey(monday);

  /// La semana siguiente (la de "lo que viene").
  ReportWeek get next => ReportWeek._(_addDays(monday, DateTime.daysPerWeek));

  /// Suma días de calendario sin pasar por `Duration`: con un cambio de
  /// horario de verano en el medio, `add(Duration(days: n))` puede caer a
  /// las 23:00 del día anterior.
  static DateTime _addDays(DateTime d, int days) =>
      DateTime(d.year, d.month, d.day + days);

  @override
  bool operator ==(Object other) => other is ReportWeek && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => 'ReportWeek($key)';
}
