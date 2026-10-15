/// Qué tan fuerte tiene que moverse una posición para avisar (plan §4.3).
enum BigMoveSensitivity {
  low,
  normal,
  high;

  static BigMoveSensitivity parse(Object? value) => switch (value) {
    'low' => low,
    'high' => high,
    _ => normal,
  };
}

/// Fila de `notification_preferences`. Los defaults son los de la tabla.
class NotificationPreferences {
  const NotificationPreferences({
    this.enabled = true,
    this.priceAlerts = true,
    this.bigMoves = true,
    this.portfolioMoves = true,
    this.weeklyReport = true,
    this.earnings = true,
    this.service = true,
    this.bigMoveSensitivity = BigMoveSensitivity.normal,
    this.quietStartMinutes = 22 * 60,
    this.quietEndMinutes = 8 * 60,
    this.showAmounts = false,
  });

  final bool enabled;
  final bool priceAlerts;
  final bool bigMoves;
  final bool portfolioMoves;
  final bool weeklyReport;
  final bool earnings;

  /// Avisos de la cuenta (eToro desconectado).
  final bool service;
  final BigMoveSensitivity bigMoveSensitivity;

  /// Horario de silencio en minutos desde la medianoche (hora local).
  /// Inicio == fin: sin silencio.
  final int quietStartMinutes;
  final int quietEndMinutes;

  /// Montos en $ en la pantalla bloqueada.
  final bool showAmounts;

  bool get hasQuietHours => quietStartMinutes != quietEndMinutes;

  static int _parseClock(Object? value, int fallback) {
    if (value is! String) return fallback;
    final parts = value.split(':');
    if (parts.length < 2) return fallback;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      return fallback;
    }
    return h * 60 + m;
  }

  static String formatClock(int minutes) {
    final h = (minutes ~/ 60) % 24;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  factory NotificationPreferences.fromRow(Map<String, dynamic> row) {
    const d = NotificationPreferences();
    bool flag(String key, bool fallback) =>
        row[key] is bool ? row[key] as bool : fallback;
    return NotificationPreferences(
      enabled: flag('enabled', d.enabled),
      priceAlerts: flag('price_alerts', d.priceAlerts),
      bigMoves: flag('big_moves', d.bigMoves),
      portfolioMoves: flag('portfolio_moves', d.portfolioMoves),
      weeklyReport: flag('weekly_report', d.weeklyReport),
      earnings: flag('earnings', d.earnings),
      service: flag('service', d.service),
      bigMoveSensitivity: BigMoveSensitivity.parse(
        row['big_move_sensitivity'],
      ),
      quietStartMinutes: _parseClock(row['quiet_start'], d.quietStartMinutes),
      quietEndMinutes: _parseClock(row['quiet_end'], d.quietEndMinutes),
      showAmounts: flag('show_amounts', d.showAmounts),
    );
  }

  Map<String, dynamic> toRow() => {
    'enabled': enabled,
    'price_alerts': priceAlerts,
    'big_moves': bigMoves,
    'portfolio_moves': portfolioMoves,
    'weekly_report': weeklyReport,
    'earnings': earnings,
    'service': service,
    'big_move_sensitivity': bigMoveSensitivity.name,
    'quiet_start': formatClock(quietStartMinutes),
    'quiet_end': formatClock(quietEndMinutes),
    'show_amounts': showAmounts,
  };

  NotificationPreferences copyWith({
    bool? enabled,
    bool? priceAlerts,
    bool? bigMoves,
    bool? portfolioMoves,
    bool? weeklyReport,
    bool? earnings,
    bool? service,
    BigMoveSensitivity? bigMoveSensitivity,
    int? quietStartMinutes,
    int? quietEndMinutes,
    bool? showAmounts,
  }) {
    return NotificationPreferences(
      enabled: enabled ?? this.enabled,
      priceAlerts: priceAlerts ?? this.priceAlerts,
      bigMoves: bigMoves ?? this.bigMoves,
      portfolioMoves: portfolioMoves ?? this.portfolioMoves,
      weeklyReport: weeklyReport ?? this.weeklyReport,
      earnings: earnings ?? this.earnings,
      service: service ?? this.service,
      bigMoveSensitivity: bigMoveSensitivity ?? this.bigMoveSensitivity,
      quietStartMinutes: quietStartMinutes ?? this.quietStartMinutes,
      quietEndMinutes: quietEndMinutes ?? this.quietEndMinutes,
      showAmounts: showAmounts ?? this.showAmounts,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NotificationPreferences &&
      other.toRow().toString() == toRow().toString();

  @override
  int get hashCode => toRow().toString().hashCode;
}
