import 'package:portfolio_assistant/domain/subscription/subscription_policy.dart';
import 'package:portfolio_assistant/features/assistant/models/portfolio_qa_message.dart';
import 'package:portfolio_assistant/features/assistant/tools/action_tools.dart';
import 'package:portfolio_assistant/features/assistant/tools/advice_tools.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/assistant/tools/market_tools.dart';
import 'package:portfolio_assistant/features/assistant/tools/portfolio_tools.dart';
import 'package:portfolio_assistant/features/assistant/utils/investor_profile_context.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';

/// Las tools de datos del asistente, en un orden fijo: la lista completa
/// viaja en cada request (el plan se aplica al ejecutar, no ocultando
/// tools), así el prefijo que cachea OpenAI no cambia entre turnos.
abstract final class AssistantToolset {
  static List<DataTool> build(AssistantToolContext ctx) => [
    GetQuoteTool(ctx),
    SearchSymbolTool(ctx),
    GetFundamentalsTool(ctx),
    GetEarningsTool(ctx),
    GetNewsTool(ctx),
    GetEtfHoldingsTool(ctx),
    GetPortfolioDetailsTool(ctx),
    GetInvestCandidatesTool(ctx),
    GetGoalProjectionTool(ctx),
    SaveGoalTool(ctx),
    // Al final: proponen operaciones, nunca escriben (ver ActionTools).
    ...ActionTools.build(ctx),
  ];
}

/// Avisos que la app agrega debajo de una respuesta (no los escribe el
/// modelo, así no dependen de que se acuerde).
class AdviceNotice {
  const AdviceNotice({this.showsDisclaimer = false, this.profileNudge});

  final bool showsDisclaimer;
  final InvestorProfileNudge? profileNudge;
}

/// Decisiones de la app sobre un turno, a partir de las tools que corrieron.
abstract final class AssistantTurnPolicy {
  /// Paywall a mostrar en vez de responder: solo si todo lo que pidió el
  /// modelo en la primera ronda está fuera del plan y alguna de esas cosas
  /// tiene una hoja de upgrade. Si parte sí se pudo traer, el turno sigue y
  /// el modelo explica qué no incluye el plan.
  ///
  /// Los datos de Gold NO cortan el turno: la respuesta sigue y la app le
  /// agrega un bloque "Gold" tocable (`QaGoldTeaser`) que abre el paywall
  /// desde ahí — mostrar lo bloqueado en vez de interrumpir con una hoja.
  /// Lo de Premium (mercado ajeno, simulaciones, metas) sí corta, como antes.
  static PaywallReason? paywallFor(
    List<ToolCallRecord> firstRound,
    AssistantToolContext ctx,
  ) {
    if (firstRound.isEmpty) return null;
    if (!firstRound.every((c) => c.status == 'locked')) return null;
    for (final reason in const [
      PaywallReason.modeLocked,
      PaywallReason.marketDataLocked,
    ]) {
      if (ctx.lockedReasons.contains(reason)) return reason;
    }
    return null;
  }

  /// Peso del turno en la cuota: `newsQueryWeight` si se buscaron noticias
  /// (hoy 1, igual que el resto — ver `AiUsageLimits`), si no 1.
  static int quotaWeight(TurnOutcome outcome) {
    // Todo lo que se pidió estaba fuera del plan: la respuesta solo explica
    // qué incluye Gold. No se cobra una consulta por algo que no se mostró.
    if (outcome.toolCalls.isNotEmpty &&
        outcome.toolCalls.every((c) => c.status == 'locked')) {
      return 0;
    }
    final searchedNews = outcome.toolCalls.any(
      (c) => c.name == 'get_news' && (c.status == 'ok' || c.status == 'empty'),
    );
    return SubscriptionPolicy.queryWeight(isNewsQuery: searchedNews);
  }

  /// Disclaimer cuando hubo una sugerencia (simulación de inversión, o una
  /// meta completa con proyección); aviso de perfil una vez por
  /// conversación, solo junto a una simulación de inversión.
  static AdviceNotice noticesFor(
    TurnOutcome outcome, {
    required bool profileNudgeAlreadyShown,
  }) {
    ToolCallRecord? invest;
    var completeGoal = false;
    for (final call in outcome.toolCalls) {
      if (call.status != 'ok') continue;
      if (call.name == GetInvestCandidatesTool.toolName) invest = call;
      if (call.name == GetGoalProjectionTool.toolName &&
          call.result['has_complete_goal'] == true) {
        completeGoal = true;
      }
    }

    InvestorProfileNudge? nudge;
    if (invest != null && !profileNudgeAlreadyShown) {
      nudge = switch (GetInvestCandidatesTool.profileStatusOf(invest.result)) {
        InvestorProfileContext.statusMissing => InvestorProfileNudge.missing,
        InvestorProfileContext.statusStale => InvestorProfileNudge.stale,
        _ => null,
      };
    }
    return AdviceNotice(
      showsDisclaimer: invest != null || completeGoal,
      profileNudge: nudge,
    );
  }
}
