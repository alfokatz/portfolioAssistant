import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/features/assistant/data/porty_rollout_flag.dart';

/// Interruptores de conversión a pago (filas de `app_config`, formato de
/// [PortyRolloutFlag]): se apagan desde el servidor sin publicar la app.
abstract final class ConversionFlags {
  /// El selector Mensual / Anual del paywall. Igual solo aparece si la
  /// tienda devuelve los productos anuales.
  static final paywallAnnual = PortyRolloutFlag('paywall_annual');

  /// Salida "traela con una captura" en las pantallas bloqueadas de
  /// Binance y SnapTrade.
  static final brokerScreenshotExit = PortyRolloutFlag(
    'broker_screenshot_exit',
  );

  /// Las filas "que se actualice sola" y "¿te aviso el sábado?" al final
  /// del diagnóstico.
  static final diagnosisBridge = PortyRolloutFlag('diagnosis_bridge');

  /// La línea de cuota baja del chat (la lee el asistente).
  static final quotaNudge = PortyRolloutFlag('quota_nudge');
}

/// false sin sesión, sin red o sin la fila (falla cerrado).
final paywallAnnualEnabledProvider = FutureProvider<bool>((ref) async {
  try {
    final userId = ref.read(supabaseAuthServiceProvider).currentUser?.id;
    return await ConversionFlags.paywallAnnual.enabledFor(userId);
  } catch (_) {
    // Sin Supabase inicializado (tests de otras pantallas): apagado.
    return false;
  }
});

Future<bool> _flagEnabled(Ref ref, PortyRolloutFlag flag) async {
  try {
    final userId = ref.read(supabaseAuthServiceProvider).currentUser?.id;
    return await flag.enabledFor(userId);
  } catch (_) {
    return false;
  }
}

/// false sin sesión, sin red o sin la fila (falla cerrado).
final brokerScreenshotExitEnabledProvider = FutureProvider<bool>(
  (ref) => _flagEnabled(ref, ConversionFlags.brokerScreenshotExit),
);

final diagnosisBridgeEnabledProvider = FutureProvider<bool>(
  (ref) => _flagEnabled(ref, ConversionFlags.diagnosisBridge),
);

/// Lo lee el asistente para decidir la línea de cuota.
final quotaNudgeEnabledProvider = FutureProvider<bool>(
  (ref) => _flagEnabled(ref, ConversionFlags.quotaNudge),
);
