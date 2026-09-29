import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/catalog/assistant_catalog.dart';
import 'package:portfolio_assistant/features/assistant/prompts/assistant_prompt_rules.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_openai_service.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_toolset.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';

import '../fakes/assistant_fakes.dart';

/// Contrato del catálogo y del prompt: lo que se puede verificar sin el
/// modelo. Qué widget elige el modelo con estas reglas lo miden las evals
/// contra la API real (`tool/assistant_evals/`).
void main() {
  final catalog = AssistantCatalog.build();
  final prompt = AssistantOpenAiService.systemPromptFor(catalog);

  test('exposes every Porty widget plus only Column and Text from genui', () {
    final names = catalog.items.map((i) => i.name).toSet();
    expect(names, {
      ...AssistantCatalog.widgetNames,
      ...AssistantCatalog.basicComponentNames,
    });
  });

  test('our rules are sent once, not duplicated', () {
    const marker = 'PORTY — ASSISTANT RULES';
    expect(marker.allMatches(prompt).length, 1);
  });

  test('every [W:…] rule referenced is defined, and no step numbers', () {
    final ids = RegExp(r'\[W:([A-Z_]+)\]');
    final defined = {
      for (final line in assistantPromptRules.split('\n'))
        if (RegExp(r'^\[W:[A-Z_]+\]').hasMatch(line))
          ids.firstMatch(line)!.group(1),
    };
    final referenced = {
      for (final m in ids.allMatches(assistantPromptRules)) m.group(1),
    };
    expect(referenced.difference(defined), isEmpty);
    expect(
      RegExp(r'\bstep \d', caseSensitive: false).hasMatch(prompt),
      isFalse,
    );
  });

  test('the prompt names every data tool and separates data tools from UI', () {
    final ctx = AssistantToolContext(
      tier: SubscriptionTier.gold,
      data: fakeDataSources(),
    );
    for (final tool in AssistantToolset.build(ctx)) {
      expect(assistantPromptRules, contains(tool.name));
    }
    expect(prompt, contains('DATA TOOLS vs. UI'));
    expect(prompt, isNot(contains('ASSISTANT_SNAPSHOT')));
  });

  // ~4 caracteres por token en este prompt (JSON schema + inglés): el
  // unificado anterior medía 173.767 caracteres / 32.086 tokens. Si esto
  // falla, alguien volvió a inflar el prompt — medirlo antes de subir el
  // límite.
  // 2026-09-29: subido de 95.000 a 100.000 para QaCompanyAnalysis (+3,9K
  // caracteres ≈ +1K tokens). Medido con la eval real: 98.660 caracteres =
  // 24.310 prompt tokens; ~92% se cachea, así que son < US$0,0004 por turno.
  test('the system prompt stays small', () {
    expect(prompt.length, lessThan(100000));
  });
}
