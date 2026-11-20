import 'dart:convert';

import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/assistant/catalog/assistant_catalog.dart';
import 'package:portfolio_assistant/features/assistant/prompts/assistant_prompt_rules.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_openai_service.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_toolset.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';

import '../fakes/assistant_fakes.dart';

/// El prefijo fijo de cada pedido, separado en los bloques que tienen
/// presupuesto propio (`prompt_budget_test.dart`):
/// - `rules`: las reglas de Porty (`assistantPromptRules`);
/// - `schemas`: los esquemas JSON de la UI (tipos comunes, catálogo y
///   mensajes A2UI);
/// - `genui`: el resto del system prompt (texto fijo de genui y formato);
/// - `tools`: las definiciones de las tools, como viajan en `tools`
///   (plan Gold: el que más tools tiene).
Map<String, String> promptBlocks() {
  final prompt = AssistantOpenAiService.systemPromptFor(
    AssistantCatalog.build(),
  );
  final schemas = <String>[];
  var rest = prompt;
  for (final name in const ['COMMON_TYPES', 'CATALOG_SCHEMA', 'MESSAGE_SCHEMA']) {
    final section = RegExp(
      '-----${name}_START-----\n(.*?)\n-----${name}_END-----',
      dotAll: true,
    ).firstMatch(rest);
    if (section == null) throw StateError('falta la sección $name');
    schemas.add(section.group(1)!);
    rest = rest.replaceFirst(section.group(0)!, '');
  }
  if (!rest.contains(assistantPromptRules.trim())) {
    throw StateError('las reglas no están enteras en el prompt');
  }
  rest = rest.replaceFirst(assistantPromptRules.trim(), '');

  final ctx = AssistantToolContext(
    tier: SubscriptionTier.gold,
    data: fakeDataSources(),
  );
  final tools = jsonEncode([
    for (final t in AssistantToolset.build(ctx)) t.toOpenAi().toMap(),
  ]);

  return {
    'rules': assistantPromptRules.trim(),
    'schemas': schemas.join('\n'),
    'genui': rest,
    'tools': tools,
  };
}
