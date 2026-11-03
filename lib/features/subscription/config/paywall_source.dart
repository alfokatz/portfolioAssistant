import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';

/// Desde dónde se abrió el paywall: el `source` de `paywall_viewed`,
/// `paywall_plan_tapped`, `purchase_result` y `paywall_dismissed` en
/// `product_events`, y el atributo `paywall_source` del suscriptor en
/// RevenueCat.
///
/// Un source dice el lugar exacto (no el motivo: eso es `PaywallReason`).
/// Formato: `^[a-z][a-z0-9_]{2,59}$` y nunca igual a un `PaywallReason.name`.
/// Ver docs/superpowers/specs/2026-11-02-paywall-medible-y-anual.md §3.1.
abstract final class PaywallSource {
  /// Ajustes → "Mejorar plan".
  static const settings = 'settings';

  /// FAB de "agregar posición" con el tope del plan.
  static const addPositionLimit = 'add_position_limit';

  /// Importar resumen: el archivo trae más posiciones que el tope.
  static const importPositionLimit = 'statement_import_position_limit';

  /// Importar resumen sin consultas para leer el archivo.
  static const importQuota = 'statement_import_quota';

  static const allocation = 'allocation';
  static const allocationWizard = 'allocation_wizard';
  static const watchlist = 'watchlist';

  /// Binance: el botón de conectar o el error de plan al conectar.
  static const binanceConnect = 'binance_connect';

  /// SnapTrade: el botón de conectar o `snaptrade_plan_required`.
  static const snaptradeConnect = 'snaptrade_connect';

  /// SnapTrade: otro bróker más (`_addAnother`, `snaptrade_connection_limit`).
  static const snaptradeMulti = 'snaptrade_multi';

  /// Diagnóstico: la fila "que se actualice sola" (plan sin `brokerSync`).
  static const diagnosisSync = 'diagnosis_sync';

  /// Chat: la línea "te quedan N consultas".
  static const quotaSoft = 'quota_soft';

  /// Chat: el turno se rechazó por cuota.
  static const quotaZero = 'quota_zero';

  /// Chat: tocó el contador de consultas en 0.
  static const quotaZeroHeader = 'quota_zero_header';

  static const chatActionWatchlist = 'chat_action_watchlist';
  static const chatActionBroker = 'chat_action_broker';
  static const chatActionMultiBroker = 'chat_action_multi_broker';
  static const chatActionAllocation = 'chat_action_allocation';
  static const chatActionPortfolio = 'chat_action_portfolio';

  /// Chat: guardar el plan de cartera que armó Porty.
  static const chatPlanSave = 'chat_plan_save';

  /// Chat: crear una alerta con el tope de alertas lleno.
  static const chatAlertLimit = 'chat_alert_limit';

  /// Chat: el aviso "Ver Premium" de un turno de mercado sin consultas
  /// gratis.
  static const chatMarketTeaser = 'chat_market_teaser';

  /// Las constantes fijas (los tests chequean que sean únicas y válidas).
  static const values = <String>[
    settings,
    addPositionLimit,
    importPositionLimit,
    importQuota,
    allocation,
    allocationWizard,
    watchlist,
    binanceConnect,
    snaptradeConnect,
    snaptradeMulti,
    diagnosisSync,
    quotaSoft,
    quotaZero,
    quotaZeroHeader,
    chatActionWatchlist,
    chatActionBroker,
    chatActionMultiBroker,
    chatActionAllocation,
    chatActionPortfolio,
    chatPlanSave,
    chatAlertLimit,
    chatMarketTeaser,
  ];

  static final _format = RegExp(r'^[a-z][a-z0-9_]{2,59}$');

  /// Turno del chat cortado porque todo lo pedido estaba fuera del plan.
  /// PlanFeature.investSimulation → "chat_turn_locked_invest_simulation".
  static String chatTurnLocked(PlanFeature feature) =>
      'chat_turn_locked_${snake(feature.name)}';

  /// Valida el formato (lo usan el assert de `show` y los tests).
  static bool isValid(String source) => _format.hasMatch(source);

  /// `companyAnalysis` → `company_analysis`; cualquier otro carácter que no
  /// entra en el formato pasa a `_`. Para armar sources a partir de nombres
  /// de enums o listas.
  static String snake(String value) => value
      .replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}')
      .replaceAll(RegExp('[^a-z0-9_]'), '_');
}
