import 'package:easy_localization/easy_localization.dart';
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
  /// `etoro` | `binance` | `snaptrade`).
  brokerSync('broker_sync'),

  /// Conectar un bróker por SnapTrade (`params.broker` = `snaptrade`): abre
  /// el portal de solo lectura, como la pantalla de otros brókers.
  brokerConnect('broker_connect'),

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
    brokerSync || brokerConnect || brokerDisconnect => ManageLink.broker,
  };

  /// El rótulo de arriba de la card.
  String get eyebrow => switch (this) {
    unwatch => 'qa_ma_eyebrow_unwatch'.tr(),
    watchNotifyOn || watchNotifyOff => 'qa_ma_eyebrow_watch'.tr(),
    alertPause || alertResume || alertDelete => 'qa_ma_eyebrow_alert'.tr(),
    goalDelete || goalAchieved || goalHoldings || goalOutsideSavings =>
      'qa_ma_eyebrow_goal'.tr(),
    allocationSave => 'qa_ma_eyebrow_allocation'.tr(),
    settingsChange => 'qa_ma_eyebrow_settings'.tr(),
    memoryClear => 'qa_ma_eyebrow_memory'.tr(),
    brokerSync || brokerConnect || brokerDisconnect =>
      'qa_ma_eyebrow_broker'.tr(),
  };

  /// Qué va a pasar, antes de confirmar.
  String describe(ManageTarget t) => switch (this) {
    unwatch => 'qa_ma_d_unwatch'.tr(namedArgs: {'ticker': t.ticker}),
    watchNotifyOn => 'qa_ma_d_notify_on'.tr(namedArgs: {'ticker': t.ticker}),
    watchNotifyOff => 'qa_ma_d_notify_off'.tr(namedArgs: {'ticker': t.ticker}),
    alertPause => 'qa_ma_d_alert_pause'.tr(namedArgs: {'label': '${t.label}'}),
    alertResume => 'qa_ma_d_alert_resume'.tr(namedArgs: {'label': '${t.label}'}),
    alertDelete => 'qa_ma_d_alert_delete'.tr(namedArgs: {'label': '${t.label}'}),
    goalDelete => 'qa_ma_d_goal_delete'.tr(namedArgs: {'label': '${t.label}'}),
    goalAchieved => 'qa_ma_d_goal_achieved'.tr(namedArgs: {'label': '${t.label}'}),
    goalHoldings =>
      t.tickers.isEmpty
          ? 'qa_ma_d_holdings_none'.tr(namedArgs: {'label': '${t.label}'})
          : 'qa_ma_d_holdings'.tr(namedArgs: {'label': '${t.label}', 'list': _list(t.tickers)}),
    goalOutsideSavings =>
      'qa_ma_d_outside'.tr(namedArgs: {'amount': AppNumberFormat.money(t.amount ?? 0), 'label': '${t.label}'}),
    allocationSave =>
      t.targets.isEmpty
          ? _onlyReminder(t)
              ? _reminder(t)
              : 'qa_ma_d_alloc_alerts'.tr(namedArgs: {'alerts': _alerts(t), 'suffix': _reminderSuffix(t)})
          : 'qa_ma_d_alloc_plan'.tr(namedArgs: {'split': _split(t.targets), 'alerts': _alerts(t), 'suffix': _reminderSuffix(t)}),
    settingsChange =>
      'qa_ma_d_settings'.tr(namedArgs: {'list': AppSettingKeys.describe(t.changes)}),
    memoryClear => 'qa_ma_d_memory'.tr(),
    brokerSync =>
      _isSnaptrade(t)
          ? 'qa_ma_d_sync_snap'.tr()
          : 'qa_ma_d_sync'.tr(namedArgs: {'broker': _broker(t)}),
    brokerConnect => 'qa_ma_d_connect'.tr(),
    brokerDisconnect =>
      t.params['keep'] == false
          ? 'qa_ma_d_disconnect_all'.tr(namedArgs: {'broker': _broker(t), 'credential': _credential(t)})
          : 'qa_ma_d_disconnect'.tr(namedArgs: {'broker': _broker(t), 'credential': _credential(t)}),
  };

  /// El botón para confirmar.
  String confirmLabel(ManageTarget t) => switch (this) {
    unwatch => 'qa_ma_c_unwatch'.tr(namedArgs: {'ticker': t.ticker}),
    watchNotifyOn => 'qa_ma_c_notify_on'.tr(),
    watchNotifyOff => 'qa_ma_c_notify_off'.tr(),
    alertPause => 'qa_ma_c_alert_pause'.tr(),
    alertResume => 'qa_ma_c_alert_resume'.tr(),
    alertDelete => 'qa_ma_c_alert_delete'.tr(),
    goalDelete => 'qa_ma_c_goal_delete'.tr(),
    goalAchieved => 'qa_ma_c_goal_achieved'.tr(),
    goalHoldings || goalOutsideSavings => 'qa_ma_c_save'.tr(),
    allocationSave => 'qa_ma_c_save_plan'.tr(),
    settingsChange => 'qa_ma_c_save_changes'.tr(),
    memoryClear => 'qa_ma_c_memory'.tr(),
    brokerSync => 'qa_ma_c_sync'.tr(),
    brokerConnect => 'qa_ma_c_connect'.tr(),
    brokerDisconnect =>
      _isSnaptrade(t)
          ? 'qa_ma_c_disconnect_all'.tr()
          : 'qa_ma_c_disconnect'.tr(namedArgs: {'broker': _broker(t)}),
  };

  /// Cómo queda la card después de confirmar.
  String done(ManageTarget t) => switch (this) {
    unwatch => 'qa_ma_o_unwatch'.tr(namedArgs: {'ticker': t.ticker}),
    watchNotifyOn => 'qa_ma_o_notify_on'.tr(namedArgs: {'ticker': t.ticker}),
    watchNotifyOff => 'qa_ma_o_notify_off'.tr(namedArgs: {'ticker': t.ticker}),
    alertPause => 'qa_ma_o_alert_pause'.tr(namedArgs: {'label': '${t.label}'}),
    alertResume => 'qa_ma_o_alert_resume'.tr(namedArgs: {'label': '${t.label}'}),
    alertDelete => 'qa_ma_o_alert_delete'.tr(namedArgs: {'label': '${t.label}'}),
    goalDelete => 'qa_ma_o_goal_delete'.tr(namedArgs: {'label': '${t.label}'}),
    goalAchieved => 'qa_ma_o_goal_achieved'.tr(namedArgs: {'label': '${t.label}'}),
    goalHoldings =>
      t.tickers.isEmpty
          ? 'qa_ma_o_holdings_none'.tr(namedArgs: {'label': '${t.label}'})
          : 'qa_ma_o_holdings'.tr(namedArgs: {'label': '${t.label}', 'list': _list(t.tickers)}),
    goalOutsideSavings =>
      'qa_ma_o_outside'.tr(namedArgs: {'amount': AppNumberFormat.money(t.amount ?? 0), 'label': '${t.label}'}),
    allocationSave =>
      t.targets.isEmpty
          ? _onlyReminder(t)
              ? 'qa_ma_o_alloc_reminder'.tr(namedArgs: {'reminder': _reminder(t)})
              : 'qa_ma_o_alloc_alerts'.tr(namedArgs: {'alerts': _alerts(t), 'suffix': _reminderSuffix(t)})
          : 'qa_ma_o_alloc_plan'.tr(namedArgs: {'split': _split(t.targets), 'suffix': _reminderSuffix(t)}),
    settingsChange =>
      'qa_ma_o_settings'.tr(namedArgs: {'list': AppSettingKeys.describe(t.changes)}),
    memoryClear => 'qa_ma_o_memory'.tr(),
    brokerSync =>
      _isSnaptrade(t)
          ? 'qa_ma_o_sync_snap'.tr()
          : 'qa_ma_o_sync'.tr(namedArgs: {'broker': _broker(t)}),
    brokerConnect => 'qa_ma_o_connect'.tr(),
    brokerDisconnect => 'qa_ma_o_disconnect'.tr(namedArgs: {'broker': _broker(t)}),
  };

  /// La etiqueta de la card resuelta.
  String get doneTag => switch (this) {
    unwatch ||
    alertDelete ||
    goalDelete ||
    memoryClear ||
    brokerSync ||
    brokerConnect ||
    brokerDisconnect => 'qa_ma_tag_done'.tr(),
    watchNotifyOn || alertResume => 'qa_ma_tag_on'.tr(),
    watchNotifyOff || alertPause => 'qa_ma_tag_paused'.tr(),
    goalAchieved => 'qa_ma_tag_achieved'.tr(),
    goalHoldings ||
    goalOutsideSavings ||
    allocationSave ||
    settingsChange => 'qa_ma_tag_saved'.tr(),
  };
}

String _broker(ManageTarget t) => switch (t.params['broker']) {
  'binance' => 'Binance',
  'snaptrade' => 'qa_ma_broker_others'.tr(),
  _ => 'eToro',
};

bool _isSnaptrade(ManageTarget t) => t.params['broker'] == 'snaptrade';

/// Lo que se borra al desconectar: la clave (eToro, Binance) o la conexión.
String _credential(ManageTarget t) =>
    _isSnaptrade(t) ? 'qa_ma_cred_connection'.tr() : 'qa_ma_cred_key'.tr();

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
  final margin =
      threshold == null ? '' : 'qa_ma_al_margin'.tr(namedArgs: {'n': '$threshold'});
  if (p['notify'] == false) {
    return 'qa_ma_al_no_notify'.tr();
  }
  return switch (p['frequency']) {
    'monthly' => 'qa_ma_al_monthly'.tr(namedArgs: {'margin': margin}),
    'weekly' => 'qa_ma_al_weekly'.tr(namedArgs: {'margin': margin}),
    _ => threshold == null ? '' : 'qa_ma_al_default'.tr(namedArgs: {'margin': margin}),
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
  if (day == 0) return 'qa_ma_rem_off'.tr();
  final money = amount == null ? '' : ' ${AppNumberFormat.money(amount)}';
  if (day == null) {
    return 'qa_ma_rem_amount'.tr(namedArgs: {'money': money});
  }
  return 'qa_ma_rem_day'.tr(namedArgs: {'day': '$day', 'money': money});
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
  _ => 'qa_list_and'.tr(
    namedArgs: {
      'list': items.sublist(0, items.length - 1).join(', '),
      'last': items.last,
    },
  ),
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

  static String _name(String key) => switch (key) {
    notifications => 'qa_ma_s_notifications'.tr(),
    priceAlerts => 'qa_ma_s_notify_price_alerts'.tr(),
    bigMoves => 'qa_ma_s_notify_big_moves'.tr(),
    portfolioMoves => 'qa_ma_s_notify_portfolio_moves'.tr(),
    weeklyReport => 'qa_ma_s_notify_weekly_report'.tr(),
    earnings => 'qa_ma_s_notify_earnings'.tr(),
    showAmounts => 'qa_ma_s_notify_show_amounts'.tr(),
    sensitivity => 'qa_ma_s_big_move_sensitivity'.tr(),
    quietHours => 'qa_ma_s_quiet_hours'.tr(),
    currency => 'qa_ma_s_currency'.tr(),
    theme => 'qa_ma_s_theme'.tr(),
    haptics => 'qa_ma_s_haptics'.tr(),
    language => 'qa_ma_s_language'.tr(),
    _ => key,
  };

  /// Una línea "• Nombre: valor" por cambio.
  static String describe(Map<String, Object?> changes) => [
    for (final e in changes.entries)
      '• ${_name(e.key)}: ${valueLabel(e.key, e.value)}',
  ].join('\n');

  static String valueLabel(String key, Object? value) => switch (key) {
    sensitivity => switch (value) {
      'low' => 'qa_ma_v_low'.tr(),
      'high' => 'qa_ma_v_high'.tr(),
      _ => 'qa_ma_v_normal'.tr(),
    },
    quietHours =>
      value == 'off'
          ? 'qa_ma_v_quiet_off'.tr()
          : 'qa_ma_v_quiet_range'.tr(
            namedArgs: {
              'range': '$value'.replaceAll('-', ' ${'qa_ma_v_to'.tr()} '),
            },
          ),
    theme => switch (value) {
      'light' => 'qa_ma_v_light'.tr(),
      'dark' => 'qa_ma_v_dark'.tr(),
      _ => 'qa_ma_v_system'.tr(),
    },
    language => value == 'en' ? 'qa_ma_v_en'.tr() : 'qa_ma_v_es'.tr(),
    currency => '$value',
    _ => value == true ? 'qa_ma_v_on'.tr() : 'qa_ma_v_off'.tr(),
  };
}
