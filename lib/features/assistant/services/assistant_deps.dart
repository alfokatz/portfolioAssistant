import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/areas/area_specs.dart';
import 'package:portfolio_assistant/features/assistant/data/porty_rollout_flag.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_openai_service.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/daily_brief/data/daily_brief_repository.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_claim.dart';
import 'package:portfolio_assistant/features/daily_brief/providers/daily_brief_provider.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:portfolio_assistant/infraestructure/repositories/quote_repository_impl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Dependencias externas del asistente, como fábricas: tocan config/red al
/// construirse (OpenAI, Finnhub), así que se crean recién cuando hace falta
/// — y los tests las reemplazan (OpenAI falso a nivel HTTP, repos fake)
/// sin tocar el cableado real.
class AssistantDeps {
  const AssistantDeps({
    required this.createService,
    required this.createData,
    this.streamingEnabled,
    this.warmUpOnOpen = false,
    this.leanPromptEnabled,
    this.createLeanService,
    this.dailyBriefStatus,
    this.createDailyBriefService,
  });

  final AssistantOpenAiService Function() createService;

  /// Si la conversación usa el prompt lean (ver [PromptVariant]); se
  /// decide una vez, al abrir el chat. Sin esto, nunca (tests).
  final Future<bool> Function()? leanPromptEnabled;

  /// El servicio con el prompt lean. Sin esto, siempre [createService].
  final AssistantOpenAiService Function()? createLeanService;
  final AssistantDataSources Function() createData;

  /// El interruptor del brief diario y sus piezas (`daily_brief_status`); se
  /// lee una vez, al abrir el chat. Sin esto, apagado (tests): el chat es el
  /// de antes del brief.
  final Future<DailyBriefStatus> Function()? dailyBriefStatus;

  /// El servicio con las reglas y la card del brief diario, para el prompt
  /// [PromptVariant] dado. Solo se usa con el interruptor prendido; sin esto,
  /// siempre [createService] / [createLeanService].
  final AssistantOpenAiService Function(PromptVariant variant)?
  createDailyBriefService;

  /// Si el turno se pide con streaming (texto visible mientras se escribe).
  /// Sin esto, nunca (tests): la respuesta llega entera, como siempre.
  final Future<bool> Function()? streamingEnabled;

  /// Despertar el proxy al abrir Porty (ver `AiProxyClient.warmUp`).
  final bool warmUpOnOpen;
}

String? _currentUserId() {
  try {
    return Supabase.instance.client.auth.currentUser?.id;
  } catch (_) {
    return null; // Supabase sin inicializar
  }
}

final assistantDepsProvider = Provider<AssistantDeps>(
  (ref) => AssistantDeps(
    createService: AssistantOpenAiService.new,
    createData:
        () => AssistantDataSources(
          quoteRepository: ref.read(quoteRepositoryProvider),
          preferences: ref.read(preferenceManagerProvider),
        ),
    streamingEnabled:
        () => PortyRolloutFlag.streaming.enabledFor(_currentUserId()),
    warmUpOnOpen: true,
    leanPromptEnabled:
        () => PortyRolloutFlag.leanPrompt.enabledFor(_currentUserId()),
    createLeanService:
        () => AssistantOpenAiService(variant: PromptVariant.lean),
    dailyBriefStatus: () => _dailyBriefStatus(ref),
    createDailyBriefService:
        (variant) => AssistantOpenAiService(variant: variant, dailyBrief: true),
  ),
);

/// Cuánto se espera la consulta del interruptor al abrir el chat: sin
/// respuesta, apagado (el chat de siempre).
const _dailyBriefStatusTimeout = Duration(seconds: 2);

/// El interruptor del brief diario para esta conversación. Si la Home ya lo
/// preguntó y está prendido se usa eso; si no (apagado, o la Home todavía no
/// cargó) se pregunta a `daily_brief_status`. Cualquier falla = apagado.
Future<DailyBriefStatus> _dailyBriefStatus(Ref ref) async {
  try {
    final known = ref.read(dailyBriefControllerProvider).status;
    if (known.enabled) return known;
    final fresh = await ref
        .read(dailyBriefRepositoryProvider)
        .status()
        .timeout(_dailyBriefStatusTimeout);
    return fresh.enabled ? fresh : DailyBriefStatus.off;
  } catch (_) {
    return DailyBriefStatus.off;
  }
}
