import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/features/assistant/models/portfolio_qa_message.dart';
import 'package:portfolio_assistant/features/assistant/utils/investor_profile_context.dart';

/// Decide qué avisos fijos van debajo de una respuesta de Invertir o
/// Planificar. Se evalúa sobre el snapshot ya armado (la misma fuente que ve
/// el modelo), así el aviso y la respuesta nunca discrepan sobre si hay
/// perfil o no.
abstract final class AdviceNoticePolicy {
  /// Invertir siempre sugiere algo. Planificar solo cuando hay una meta
  /// completa y por lo tanto una proyección (ahorro mensual, hitos); si
  /// falta monto o fecha, la respuesta solo los pide.
  static bool showsDisclaimer(
    AssistantMode mode,
    Map<String, dynamic> snapshot,
  ) {
    return switch (mode) {
      AssistantMode.invest => true,
      AssistantMode.plan => snapshot['has_complete_goal'] == true,
      _ => false,
    };
  }

  /// Solo en Invertir, y una vez por conversación: es un aviso puntual, no
  /// un recordatorio en cada turno.
  static InvestorProfileNudge? profileNudge(
    AssistantMode mode,
    Map<String, dynamic> snapshot, {
    required bool alreadyShown,
  }) {
    if (mode != AssistantMode.invest || alreadyShown) return null;
    final profile = snapshot['investor_profile'];
    final status = profile is Map ? profile['status'] : null;
    return switch (status) {
      InvestorProfileContext.statusMissing => InvestorProfileNudge.missing,
      InvestorProfileContext.statusStale => InvestorProfileNudge.stale,
      _ => null,
    };
  }
}
