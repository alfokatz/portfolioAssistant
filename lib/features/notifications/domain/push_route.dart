/// A dónde lleva una notificación al tocarla. Sale del `data` del mensaje
/// de FCM, que arma `notify-dispatch` (templates.ts: `route` + args).
sealed class PushRoute {
  const PushRoute();

  /// `null` si el mensaje no trae una ruta que la app conozca (una versión
  /// vieja de la app con un tipo nuevo): se abre la app y nada más.
  static PushRoute? fromData(Map<String, dynamic> data) {
    String? arg(String key) {
      final value = data[key];
      if (value is! String) return null;
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    return switch (arg('route')) {
      'home' => const PushRouteHome(),
      'weekly_report' => const PushRouteWeeklyReport(),
      'etoro' => const PushRouteEtoro(),
      'notification_settings' => const PushRouteNotificationSettings(),
      'alerts' => const PushRoutePriceAlerts(),
      'ticker' when arg('ticker') != null => PushRouteTicker(
        arg('ticker')!,
        alertId: arg('alert_id'),
      ),
      'assistant' => PushRouteAssistant(arg('question')),
      _ => null,
    };
  }
}

class PushRouteHome extends PushRoute {
  const PushRouteHome();
}

class PushRouteWeeklyReport extends PushRoute {
  const PushRouteWeeklyReport();
}

class PushRouteEtoro extends PushRoute {
  const PushRouteEtoro();
}

class PushRouteNotificationSettings extends PushRoute {
  const PushRouteNotificationSettings();
}

class PushRoutePriceAlerts extends PushRoute {
  const PushRoutePriceAlerts();
}

/// El detalle de la posición si la tiene; si no, la lista de alertas.
class PushRouteTicker extends PushRoute {
  const PushRouteTicker(this.ticker, {this.alertId});

  final String ticker;
  final String? alertId;
}

/// El chat con una pregunta cargada ("¿Por qué se mueve NVDA hoy?").
class PushRouteAssistant extends PushRoute {
  const PushRouteAssistant(this.question);

  final String? question;
}

/// Un mensaje recibido: lo que hace falta para mostrarlo dentro de la app y
/// para abrirlo.
class PushMessage {
  const PushMessage({
    required this.data,
    this.title,
    this.body,
  });

  final Map<String, dynamic> data;
  final String? title;
  final String? body;

  String? get kind => data['kind'] as String?;

  /// Id del registro en `notification_log` (métrica de apertura).
  int? get logId => int.tryParse('${data['log_id'] ?? ''}');

  PushRoute? get route => PushRoute.fromData(data);
}
