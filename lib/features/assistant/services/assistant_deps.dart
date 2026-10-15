import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_openai_service.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:portfolio_assistant/infraestructure/repositories/quote_repository_impl.dart';

/// Dependencias externas del asistente, como fábricas: tocan dotenv/red al
/// construirse (OpenAI, Finnhub), así que se crean recién cuando hace falta
/// — y los tests las reemplazan (OpenAI falso a nivel HTTP, repos fake)
/// sin tocar el cableado real.
class AssistantDeps {
  const AssistantDeps({required this.createService, required this.createData});

  final AssistantOpenAiService Function() createService;
  final AssistantDataSources Function() createData;
}

final assistantDepsProvider = Provider<AssistantDeps>(
  (ref) => AssistantDeps(
    createService: AssistantOpenAiService.new,
    createData:
        () => AssistantDataSources(
          quoteRepository: ref.read(quoteRepositoryProvider),
          preferences: ref.read(preferenceManagerProvider),
        ),
  ),
);
