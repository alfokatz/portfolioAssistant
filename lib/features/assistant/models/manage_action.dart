import 'package:portfolio_assistant/presentation/shared/formatting/app_number_format.dart';

/// Operaciones de "gestión" que Porty propone y el usuario confirma en la
/// card `QaActionProposal` (kind `manage`): quitar, pausar, borrar, cambiar
/// un ajuste. No llevan montos ni fechas: la tool arma qué se hace y sobre
/// qué ([ManageTarget]) y la app escribe todos los textos de la card desde
/// acá (el modelo solo pasa el `proposal_id`).
///
/// Para sumar una operación: un valor acá con sus textos, la tool
/// `propose_*` que la arma y su caso en `AssistantProvider._manage`.
enum ManageOp {
  /// Dejar de seguir un ticker de la lista de seguimiento.
  unwatch('unwatch'),

  /// Prender los avisos de movimientos fuertes de un ticker seguido.
  watchNotifyOn('watch_notify_on'),

  /// Apagar los avisos de movimientos fuertes de un ticker seguido.
  watchNotifyOff('watch_notify_off'),

  /// Pausar una alerta de precio.
  alertPause('alert_pause'),

  /// Volver a activar una alerta pausada (o ya disparada).
  alertResume('alert_resume'),

  /// Borrar una alerta de precio.
  alertDelete('alert_delete'),

  /// Borrar una meta.
  goalDelete('goal_delete'),

  /// Marcar una meta como cumplida.
  goalAchieved('goal_achieved'),

  /// Qué inversiones cuentan para una meta (`params.tickers`, reemplaza).
  goalHoldings('goal_holdings'),

  /// Lo que tiene para una meta fuera de la app (`params.amount`, total).
  goalOutsideSavings('goal_outside_savings'),

  /// Guardar el plan de cartera: `params.targets` ({TICKER: %}, suman 100)
  /// y, si cambian, `params.threshold`, `params.notify`, `params.frequency`.
  /// Sin `targets`, solo cambian los avisos del plan que ya tiene.
  allocationSave('allocation_save'),

  /// Cambiar ajustes de la app: `params.changes` ({clave: valor}, ver
  /// [AppSettingKeys]).
  settingsChange('settings_change'),

  /// Borrar todo lo que Porty recuerda del usuario.
  memoryClear('memory_clear'),

  /// Traer ya lo último de una cuenta conectada (`params.broker`:
  /// `etoro` | `binance`).
  brokerSync('broker_sync'),

  /// Desconectar una cuenta (`params.broker`, `params.keep`: conservar lo
  /// importado como posiciones manuales o borrarlo).
  brokerDisconnect('broker_disconnect');

  const ManageOp(this.wire);

  /// Cómo viaja en el resultado de la tool.
  final String wire;

  static ManageOp? parse(Object? value) {
    for (final op in values) {
      if (op.wire == value) return op;
    }
    return null;
  }

  /// Borra o quita algo: el botón y el link lo dicen sin vueltas.
  bool get destructive => switch (this) {
    unwatch ||
    alertDelete ||
    goalDelete ||
    memoryClear ||
    brokerDisconnect => true,
    _ => false,
  };

  /// A qué pantalla lleva el link de la card resuelta.
  ManageLink get link => switch (this) {
    unwatch || watchNotifyOn || watchNotifyOff => ManageLink.watchlist,
    alertPause || alertResume || alertDelete => ManageLink.alerts,
    goalDelete => ManageLink.goals,
    goalAchieved || goalHoldings || goalOutsideSavings => ManageLink.goal,
    allocationSave => ManageLink.allocation,
    settingsChange => ManageLink.settings,
    memoryClear => ManageLink.memory,
    brokerSync || brokerDisconnect => ManageLink.broker,
  };

  /// El rótulo de arriba de la card.
  String get eyebrow => switch (this) {
    unwatch => 'Dejar de seguir',
    watchNotifyOn || watchNotifyOff => 'Avisos de tu lista',
    alertPause || alertResume || alertDelete => 'Alerta de precio',
    goalDelete || goalAchieved || goalHoldings || goalOutsideSavings => 'Meta',
    allocationSave => 'Plan de cartera',
    settingsChange => 'Ajustes',
    memoryClear => 'Lo que sé de vos',
    brokerSync || brokerDisconnect => 'Cuenta conectada',
  };

  /// Qué va a pasar, antes de confirmar.
  String describe(ManageTarget t) => switch (this) {
    unwatch =>
      'Saco ${t.ticker} de tu lista de seguimiento. Dejás de ver cómo se '
          'mueve y no te aviso más.',
    watchNotifyOn =>
      'Te aviso si ${t.ticker} se mueve fuerte en el día. Sigue en tu lista '
          'como está.',
    watchNotifyOff =>
      'Dejo de avisarte si ${t.ticker} se mueve fuerte. Sigue en tu lista.',
    alertPause =>
      'Pauso la alerta "${t.label}". No te aviso hasta que la vuelvas a '
          'activar.',
    alertResume =>
      'Vuelvo a activar la alerta "${t.label}": te aviso cuando se cumpla.',
    alertDelete => 'Borro la alerta "${t.label}". No te aviso más.',
    goalDelete =>
      'Borro la meta "${t.label}" y su plan. Tus inversiones quedan como '
          'están.',
    goalAchieved =>
      'Marco "${t.label}" como cumplida. Las inversiones que contaba quedan '
          'libres para tus otras metas.',
    goalHoldings =>
      t.tickers.isEmpty
          ? 'Dejo de contar tus inversiones para "${t.label}".'
          : 'Para "${t.label}" cuento ${_list(t.tickers)}. Si una cuenta '
              'para otra meta, se reparte entre las dos.',
    goalOutsideSavings =>
      'Anoto que tenés ${AppNumberFormat.money(t.amount ?? 0)} fuera de la '
          'app para "${t.label}" (reemplaza lo anterior) y rehago el plan.',
    allocationSave =>
      t.targets.isEmpty
          ? _onlyReminder(t)
              ? _reminder(t)
              : 'Cambio los avisos de tu plan: ${_alerts(t)}${_reminderSuffix(t)}'
          : 'Tu plan queda así: ${_split(t.targets)}. ${_alerts(t)}'
              '${_reminderSuffix(t)}',
    settingsChange => 'Cambio esto:\n${AppSettingKeys.describe(t.changes)}',
    memoryClear =>
      'Borro todo lo que anoté sobre vos. Tu cartera, tus metas y tu perfil '
          'de inversor no se tocan.',
    brokerSync =>
      'Traigo ya lo último de tu cuenta de ${_broker(t)} (sin esperar a la '
          'próxima actualización).',
    brokerDisconnect =>
      t.params['keep'] == false
          ? 'Desconecto ${_broker(t)}, borro la clave y también las '
              'posiciones que importé de ahí.'
          : 'Desconecto ${_broker(t)} y borro la clave. Lo que importé queda '
              'en tu cartera como posiciones manuales.',
  };

  /// El botón para confirmar.
  String confirmLabel(ManageTarget t) => switch (this) {
    unwatch => 'Dejar de seguir ${t.ticker}',
    watchNotifyOn => 'Prender avisos',
    watchNotifyOff => 'Apagar avisos',
    alertPause => 'Pausar alerta',
    alertResume => 'Activar alerta',
    alertDelete => 'Borrar alerta',
    goalDelete => 'Borrar meta',
    goalAchieved => 'Marcar como cumplida',
    goalHoldings || goalOutsideSavings => 'Guardar',
    allocationSave => 'Guardar plan',
    settingsChange => 'Guardar cambios',
    memoryClear => 'Borrar todo',
    brokerSync => 'Actualizar ahora',
    brokerDisconnect => 'Desconectar ${_broker(t)}',
  };

  /// Cómo queda la card después de confirmar.
  String done(ManageTarget t) => switch (this) {
    unwatch => 'Ya no seguís ${t.ticker}.',
    watchNotifyOn => 'Te aviso si ${t.ticker} se mueve fuerte en el día.',
    watchNotifyOff => 'No te aviso más por los movimientos de ${t.ticker}.',
    alertPause => 'Pausé la alerta "${t.label}".',
    alertResume => 'Activé la alerta "${t.label}".',
    alertDelete => 'Borré la alerta "${t.label}".',
    goalDelete => 'Borré la meta "${t.label}".',
    goalAchieved => '¡"${t.label}" cumplida!',
    goalHoldings =>
      t.tickers.isEmpty
          ? '"${t.label}" ya no cuenta inversiones.'
          : 'Para "${t.label}" cuento ${_list(t.tickers)}.',
    goalOutsideSavings =>
      'Anoté ${AppNumberFormat.money(t.amount ?? 0)} fuera de la app para '
          '"${t.label}".',
    allocationSave =>
      t.targets.isEmpty
          ? _onlyReminder(t)
              ? 'Listo. ${_reminder(t)}'
              : 'Listo: ${_alerts(t)}${_reminderSuffix(t)}'
          : 'Guardé tu plan: ${_split(t.targets)}.${_reminderSuffix(t)}',
    settingsChange => 'Listo:\n${AppSettingKeys.describe(t.changes)}',
    memoryClear => 'Borré todo lo que sabía de vos.',
    brokerSync => 'Actualicé tu cuenta de ${_broker(t)}.',
    brokerDisconnect => 'Desconecté ${_broker(t)}.',
  };

  /// La etiqueta de la card resuelta.
  String get doneTag => switch (this) {
    unwatch ||
    alertDelete ||
    goalDelete ||
    memoryClear ||
    brokerSync ||
    brokerDisconnect => 'Hecho',
    watchNotifyOn || alertResume => 'Activado',
    watchNotifyOff || alertPause => 'Pausado',
    goalAchieved => 'Cumplida',
    goalHoldings ||
    goalOutsideSavings ||
    allocationSave ||
    settingsChange => 'Guardado',
  };
}

String _broker(ManageTarget t) =>
    t.params['broker'] == 'binance' ? 'Binance' : 'eToro';

/// "VOO 60% · BND 40%", de mayor a menor.
String _split(Map<String, double> targets) {
  final entries =
      targets.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return [for (final e in entries) '${e.key} ${_pct(e.value)}'].join(' · ');
}

String _pct(double v) =>
    v == v.roundToDouble() ? '${v.round()}%' : '${v.toStringAsFixed(1)}%';

/// Cómo quedan los avisos del plan, en una frase.
String _alerts(ManageTarget t) {
  final p = t.params;
  final threshold = (p['threshold'] as num?)?.round();
  final margin = threshold == null ? '' : ' más de $threshold puntos';
  if (p['notify'] == false) {
    return 'sin notificaciones (lo vas a ver en tu inicio).';
  }
  return switch (p['frequency']) {
    'monthly' =>
      'te aviso el primer lunes de cada mes si algo se aleja$margin.',
    'weekly' => 'te aviso los lunes si algo se aleja$margin.',
    _ => threshold == null ? '' : 'te aviso si algo se aleja$margin.',
  };
}

/// Si la card solo cambia el recordatorio de aporte.
bool _onlyReminder(ManageTarget t) {
  final keys = t.params.keys.toSet();
  return keys.isNotEmpty &&
      keys.difference({'contribution_day', 'contribution_amount'}).isEmpty;
}

/// "El día 1 de cada mes te recuerdo aportar $500 y cómo repartirlo."
String _reminder(ManageTarget t) {
  final p = t.params;
  final day = (p['contribution_day'] as num?)?.round();
  final amount = (p['contribution_amount'] as num?)?.toDouble();
  if (day == 0) return 'Apago el recordatorio de aporte.';
  final money = amount == null ? '' : ' ${AppNumberFormat.money(amount)}';
  if (day == null) {
    return 'Tu aporte de cada mes pasa a ser de$money.';
  }
  return 'El día $day de cada mes te recuerdo aportar$money y cómo '
      'repartirlo según tu plan.';
}

String _reminderSuffix(ManageTarget t) =>
    t.params.containsKey('contribution_day') ||
            t.params.containsKey('contribution_amount')
        ? ' ${_reminder(t)}'
        : '';

/// "VOO, QQQ y BND".
String _list(List<String> items) => switch (items.length) {
  0 => '',
  1 => items.first,
  _ => '${items.sublist(0, items.length - 1).join(', ')} y ${items.last}',
};

/// Pantalla a la que lleva "Ver …" en una card de gestión resuelta.
enum ManageLink {
  watchlist,
  alerts,

  /// La pestaña Metas (la meta ya no existe).
  goals,

  /// Mi plan de cartera.
  allocation,

  /// Ajustes (o las notificaciones, si se tocó alguna).
  settings,

  /// Lo que Porty sabe de vos.
  memory,

  /// La pantalla de la cuenta conectada (`params.broker`).
  broker,

  /// El detalle de la meta ([ManageTarget.id]).
  goal,
}

/// Sobre qué actúa una operación de gestión.
class ManageTarget {
  const ManageTarget({
    required this.ticker,
    this.id,
    this.label,
    this.params = const {},
  });

  /// El ticker (lista, alerta). Vacío si la operación no es de un ticker.
  final String ticker;

  /// El id de lo que se toca (una alerta, una meta), si hace falta.
  final String? id;

  /// Cómo se nombra en los textos ("VOO sube a $750").
  final String? label;

  /// Datos propios de la operación (ver cada [ManageOp]).
  final Map<String, Object?> params;

  /// `params['tickers']` como lista de textos.
  List<String> get tickers => [
    for (final t in (params['tickers'] as List? ?? const [])) '$t',
  ];

  /// `params['amount']` como número.
  double? get amount => (params['amount'] as num?)?.toDouble();

  /// `params['changes']` ({clave de [AppSettingKeys]: valor}).
  Map<String, Object?> get changes => {
    if (params['changes'] case final Map<dynamic, dynamic> m)
      for (final e in m.entries) '${e.key}': e.value,
  };

  /// `params['targets']` ({TICKER: %}).
  Map<String, double> get targets => {
    if (params['targets'] case final Map<dynamic, dynamic> m)
      for (final e in m.entries)
        if (e.value is num) '${e.key}': (e.value as num).toDouble(),
  };
}

/// Los ajustes que Porty puede cambiar, con sus valores y cómo se nombran
/// en la card. El valor viaja tal cual en `params.changes`.
abstract final class AppSettingKeys {
  static const notifications = 'notifications';
  static const priceAlerts = 'notify_price_alerts';
  static const bigMoves = 'notify_big_moves';
  static const portfolioMoves = 'notify_portfolio_moves';
  static const weeklyReport = 'notify_weekly_report';
  static const earnings = 'notify_earnings';
  static const showAmounts = 'notify_show_amounts';

  /// `low` | `normal` | `high`.
  static const sensitivity = 'big_move_sensitivity';

  /// `off` o `HH:MM-HH:MM`.
  static const quietHours = 'quiet_hours';

  /// Código ISO de `DisplayCurrency` ("UYU").
  static const currency = 'currency';

  /// `system` | `light` | `dark`.
  static const theme = 'theme';
  static const haptics = 'haptics';

  /// `es` | `en`.
  static const language = 'language';

  /// Las de encendido/apagado.
  static const toggles = {
    notifications,
    priceAlerts,
    bigMoves,
    portfolioMoves,
    weeklyReport,
    earnings,
    showAmounts,
    haptics,
  };

  static const _names = {
    notifications: 'Notificaciones',
    priceAlerts: 'Avisos de alertas de precio',
    bigMoves: 'Avisos de movimientos fuertes de tus acciones',
    portfolioMoves: 'Avisos de movimientos de tu cartera',
    weeklyReport: 'Aviso del informe semanal',
    earnings: 'Avisos de resultados de tus empresas',
    showAmounts: 'Montos en la pantalla bloqueada',
    sensitivity: 'Qué cuenta como movimiento fuerte',
    quietHours: 'Horario de silencio',
    currency: 'Moneda para ver tu cartera',
    theme: 'Tema',
    haptics: 'Vibraciones',
    language: 'Idioma',
  };

  /// Una línea "• Nombre: valor" por cambio.
  static String describe(Map<String, Object?> changes) => [
    for (final e in changes.entries)
      '• ${_names[e.key] ?? e.key}: ${valueLabel(e.key, e.value)}',
  ].join('\n');

  static String valueLabel(String key, Object? value) => switch (key) {
    sensitivity => switch (value) {
      'low' => 'solo movimientos muy grandes',
      'high' => 'también movimientos más chicos',
      _ => 'lo normal',
    },
    quietHours =>
      value == 'off' ? 'sin silencio' : 'de ${'$value'.replaceAll('-', ' a ')}',
    theme => switch (value) {
      'light' => 'claro',
      'dark' => 'oscuro',
      _ => 'el del teléfono',
    },
    language => value == 'en' ? 'inglés' : 'español',
    currency => '$value',
    _ => value == true ? 'prendido' : 'apagado',
  };
}
