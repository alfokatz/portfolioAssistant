import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/features/assistant/data/porty_rollout_flag.dart';

/// Interruptores de conversión a pago (filas de `app_config`, formato de
/// [PortyRolloutFlag]): se apagan desde el servidor sin publicar la app.
abstract final class ConversionFlags {
  /// El selector Mensual / Anual del paywall. Igual solo aparece si la
  /// tienda devuelve los productos anuales.
  static final paywallAnnual = PortyRolloutFlag('paywall_annual');
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
