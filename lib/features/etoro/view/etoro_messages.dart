import 'package:easy_localization/easy_localization.dart';

/// Textos para errores tipados de eToro, en lenguaje simple (nunca el
/// código crudo).
abstract final class EtoroMessages {
  /// Por qué no se pudo conectar (`reason` del deep link o error de la
  /// edge function). `null` si no hay nada que decir (el usuario canceló).
  static String? connectError(String reason) => switch (reason) {
    'cancelled' => null,
    'write_scope' => 'etoro_error_write_scope'.tr(),
    'missing_scope' => 'etoro_error_missing_scope'.tr(),
    'expired' || 'invalid_state' => 'etoro_error_expired'.tr(),
    'network' => 'etoro_error_network'.tr(),
    'not_configured' ||
    'etoro_not_configured' ||
    'unavailable' => 'etoro_error_unavailable'.tr(),
    'busy' => 'etoro_error_busy'.tr(),
    _ => 'etoro_error_connect'.tr(),
  };

  /// Por qué no se pudo sincronizar.
  static String syncError(String type) => switch (type) {
    'etoro_rate_limited' => 'etoro_error_rate_limited'.tr(),
    'etoro_unavailable' || 'network' => 'etoro_error_sync_unavailable'.tr(),
    'etoro_sync_in_progress' => 'etoro_error_busy'.tr(),
    'etoro_plan_required' => 'etoro_error_plan'.tr(),
    _ => 'etoro_error_sync'.tr(),
  };
}
