import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/catalog/assistant_catalog.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_claim.dart';
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
  // Con el brief diario prendido: el prompt más completo (el que mide el
  // contrato). Apagado es el de antes del brief (daily_brief_gate_test).
  final catalog = AssistantCatalog.build(dailyBrief: true);
  final prompt = AssistantOpenAiService.systemPromptFor(catalog);
  final rules = assistantPromptRulesFor(dailyBrief: true);

  test('exposes every Porty widget plus only Column and Text from genui', () {
    final names = catalog.items.map((i) => i.name).toSet();
    expect(names, {
      ...AssistantCatalog.widgetNames,
      ...AssistantCatalog.basicComponentNames,
    });
  });

  test('without the daily brief the catalog has no outlet comparison', () {
    final names = AssistantCatalog.build().items.map((i) => i.name).toSet();
    expect(names, {
      ...AssistantCatalog.widgetNames.difference(
        AssistantCatalog.dailyBriefWidgetNames,
      ),
      ...AssistantCatalog.basicComponentNames,
    });
    final off = AssistantOpenAiService.systemPromptFor(
      AssistantCatalog.build(),
    );
    expect(off, isNot(contains('QaSourceComparison')));
    expect(off, isNot(contains('compare_sources')));
    expect(off, isNot(contains('get_daily_brief')));
    expect(prompt, contains('QaSourceComparison'));
  });

  test('our rules are sent once, not duplicated', () {
    const marker = 'PORTY — ASSISTANT RULES';
    expect(marker.allMatches(prompt).length, 1);
  });

  test(
    'the model only writes updateComponents: the app creates the surface '
    '(A2uiResponseNormalizer), so the prompt never asks for createSurface',
    () {
      expect(prompt, contains('Supported messages are: `updateComponents`.'));
      expect(prompt, isNot(contains('Output a `createSurface` message')));
      expect(prompt, isNot(contains('"createSurface": {')));
      expect(prompt, isNot(contains('"CreateSurfaceMessage"')));
      expect(prompt, contains('never output `createSurface`'));
    },
  );

  test('every [W:…] rule referenced is defined, and no step numbers', () {
    final ids = RegExp(r'\[W:([A-Z_]+)\]');
    final defined = {
      for (final line in rules.split('\n'))
        if (RegExp(r'^\[W:[A-Z_]+\]').hasMatch(line))
          ids.firstMatch(line)!.group(1),
    };
    final referenced = {
      for (final m in ids.allMatches(rules)) m.group(1),
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
      dailyBriefStatus: const DailyBriefStatus(enabled: true),
    );
    for (final tool in AssistantToolset.build(ctx)) {
      expect(rules, contains(tool.name));
    }
    expect(prompt, contains('DATA TOOLS vs. UI'));
    expect(prompt, isNot(contains('ASSISTANT_SNAPSHOT')));
  });

  // El tamaño del prompt lo controla prompt_budget_test.dart (tokens por
  // bloque), que reemplazó al tope global en caracteres.
}
