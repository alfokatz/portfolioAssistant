import 'dart:convert';

import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/assistant/catalog/assistant_catalog.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_claim.dart';
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
///
/// [dailyBrief]: con el interruptor del brief diario prendido (el prefijo más
/// grande) o apagado (el de antes del brief).
Map<String, String> promptBlocks({bool dailyBrief = true}) {
  final prompt = AssistantOpenAiService.systemPromptFor(
    AssistantCatalog.build(dailyBrief: dailyBrief),
  );
  final rules = assistantPromptRulesFor(dailyBrief: dailyBrief);
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
  if (!rest.contains(rules.trim())) {
    throw StateError('las reglas no están enteras en el prompt');
  }
  rest = rest.replaceFirst(rules.trim(), '');

  final ctx = AssistantToolContext(
    tier: SubscriptionTier.gold,
    data: fakeDataSources(),
    dailyBriefStatus: DailyBriefStatus(enabled: dailyBrief),
  );
  final tools = jsonEncode([
    for (final t in AssistantToolset.build(ctx)) t.toOpenAi().toMap(),
  ]);

  return {
    'rules': rules.trim(),
    'schemas': schemas.join('\n'),
    'genui': rest,
    'tools': tools,
  };
}
