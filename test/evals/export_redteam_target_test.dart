// Exporta lo que la app manda al proxy `ai-chat` en un turno de Porty —
// system prompt, contexto de cartera, prefijo del mensaje y tools — para que
// promptfoo (evals/redteam/) arme el mismo pedido. El proxy solo acepta el
// system prompt exacto de la app (por hash), y ese prompt sale de Dart.
//
//   EXPORT_REDTEAM_TARGET=1 flutter test test/evals/export_redteam_target_test.dart
//
// Escribe evals/redteam/.generated/porty_target.json (no se versiona: hay que
// regenerarlo cada vez que cambian el prompt o las tools).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/assistant/catalog/assistant_catalog.dart';
import 'package:portfolio_assistant/features/assistant/data/market/news_provider.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_openai_service.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_toolset.dart';
import 'package:portfolio_assistant/features/assistant/tools/portfolio_tools.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';

import '../features/assistant/fakes/assistant_fakes.dart';

const _out = 'evals/redteam/.generated/porty_target.json';

List<Map<String, Object?>> _tools(NewsProvider provider) => [
  for (final tool in AssistantToolset.build(
    AssistantToolContext(
      tier: SubscriptionTier.gold,
      summary: heldSummary,
      data: fakeDataSources(),
      newsProvider: provider,
    ),
  ))
    {
      'type': 'function',
      'function': {
        'name': tool.name,
        'description': tool.description,
        'parameters': tool.parameters,
      },
    },
];

void main() {
  test(
    'export the Porty request shape for promptfoo',
    () {
      final ctx = AssistantToolContext(
        tier: SubscriptionTier.gold,
        summary: heldSummary,
        data: fakeDataSources(),
      );
      final target = {
        'generated_at': DateTime.now().toUtc().toIso8601String(),
        'system_prompt': AssistantOpenAiService.systemPromptFor(
          AssistantCatalog.build(),
        ),
        // Mismo armado que AssistantOpenAiService.ask.
        'pinned_context': AssistantOpenAiService.pinnedContextFor(
          PortfolioBrief.build(ctx),
        ),
        'user_prefix_template':
            'SURFACE_ID (usar exactamente en createSurface y '
            'updateComponents): {surface_id}\n\n'
            'PREGUNTA DEL USUARIO:',
        'max_tool_rounds': OpenAIGenUiService.maxToolRounds,
        'tools': {
          'legacy': _tools(NewsProvider.legacy),
          'v2': _tools(NewsProvider.v2),
        },
      };
      File(_out)
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(target)}\n',
        );
    },
    skip:
        Platform.environment['EXPORT_REDTEAM_TARGET'] == '1'
            ? false
            : 'set EXPORT_REDTEAM_TARGET=1 to export the promptfoo target',
  );
}
