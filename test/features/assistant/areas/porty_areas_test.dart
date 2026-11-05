// El registro de áreas (lib/features/assistant/areas/): cada tool y cada
// widget del chat es de un área, cada área entra en su presupuesto de
// tokens fijos y el prompt lean saca exactamente lo diferido.
//
// Con PRINT_AREA_TOKENS=1 imprime la tabla de tokens por área.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/assistant/areas/area_specs.dart';
import 'package:portfolio_assistant/features/assistant/areas/porty_areas.dart';
import 'package:portfolio_assistant/features/assistant/catalog/assistant_catalog.dart';
import 'package:portfolio_assistant/features/assistant/prompts/assistant_prompt_rules.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_openai_service.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_toolset.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';

import '../fakes/assistant_fakes.dart';

// Caracteres por token medidos con o200k (ver prompt_budget_test.dart).
const _toolCharsPerToken = 4.20;
const _schemaCharsPerToken = 4.16;
const _rulesCharsPerToken = 3.80;

void main() {
  final tools = AssistantToolset.build(
    AssistantToolContext(tier: SubscriptionTier.gold, data: fakeDataSources()),
  );
  final toolNames = [for (final t in tools) t.name];
  final classic = AssistantOpenAiService.systemPromptFor(
    AssistantCatalog.build(),
  );
  final lean = AssistantOpenAiService.systemPromptFor(
    AssistantCatalog.build(variant: PromptVariant.lean),
  );
  final schemas = AreaSpecs.widgetSchemas(classic);

  group('PortyAreas', () {
    test('every tool belongs to exactly one area, and no area names a tool '
        'that does not exist', () {
      for (final name in toolNames) {
        final owners = [
          for (final a in PortyAreas.all)
            if (a.tools.contains(name)) a.area,
        ];
        expect(owners, hasLength(1), reason: name);
      }
      for (final a in PortyAreas.all) {
        expect(toolNames, containsAll(a.tools), reason: '${a.area}');
      }
    });

    test('every catalog widget belongs to exactly one area', () {
      final widgets = [for (final i in AssistantCatalog.build().items) i.name];
      for (final name in widgets) {
        final owners = [
          for (final a in PortyAreas.all)
            if (a.widgets.contains(name)) a.area,
        ];
        expect(owners, hasLength(1), reason: name);
      }
      for (final a in PortyAreas.all) {
        expect(widgets, containsAll(a.widgets), reason: '${a.area}');
      }
    });

    test('what an area defers is its own: its tools and its widgets', () {
      for (final a in PortyAreas.all) {
        for (final d in a.deferred) {
          expect(a.tools, contains(d.tool), reason: '${a.area}');
          expect(a.widgets, containsAll(d.widgets), reason: '${a.area}');
        }
      }
    });

    test('every area fits its fixed token budget (its tools + the widgets '
        'that stay in the lean prompt)', () {
      final rows = <String>[];
      final over = <String>[];
      for (final a in PortyAreas.all) {
        final toolChars =
            jsonEncode([
              for (final t in tools)
                if (a.tools.contains(t.name)) t.toOpenAi().toMap(),
            ]).length;
        final widgetChars = [
          for (final w in a.widgets)
            if (!a.deferredWidgets.contains(w)) jsonEncode(schemas[w]).length,
        ].fold(0, (s, c) => s + c);
        final deferredChars = [
          for (final w in a.deferredWidgets) jsonEncode(schemas[w]).length,
        ].fold(0, (s, c) => s + c);
        final fixed =
            (toolChars / _toolCharsPerToken +
                    widgetChars / _schemaCharsPerToken)
                .round();
        rows.add(
          '${a.area.name.padRight(13)} fijos ${'$fixed'.padLeft(5)} / '
          '${'${a.budgetTokens}'.padLeft(5)}   diferidos '
          '${(deferredChars / _schemaCharsPerToken).round()}',
        );
        if (fixed > a.budgetTokens) {
          over.add(
            '${a.area.name} ≈ $fixed tokens fijos (presupuesto '
            '${a.budgetTokens})',
          );
        }
      }
      if (Platform.environment['PRINT_AREA_TOKENS'] == '1') {
        // ignore: avoid_print
        print(rows.join('\n'));
      }
      expect(
        over,
        isEmpty,
        reason:
            '¿Lo nuevo puede viajar con el resultado de su tool '
            '(DeferredSpec)? Si no, subir el presupuesto del área a '
            'conciencia.',
      );
    });
  });

  group('AreaSpecs', () {
    test('every deferred rule section is in the classic rules once and '
        'closes with a blank line', () {
      for (final h in PortyAreas.deferredRuleSections) {
        final section = AreaSpecs.section(assistantPromptRules, h);
        expect(section, startsWith(h));
        expect(section, isNot(contains('\n\n')));
      }
    });

    test('the lean rules are the classic ones without the deferred sections, '
        'plus the area_spec rule', () {
      final leanRules = AreaSpecs.leanRules(assistantPromptRules);
      expect(leanRules, contains(AreaSpecs.leanRule));
      for (final h in PortyAreas.deferredRuleSections) {
        expect(leanRules, isNot(contains('\n$h\n')), reason: h);
      }
      // Nada más cambia: sacar las secciones y la regla deja lo mismo.
      var rebuilt = assistantPromptRules;
      for (final h in PortyAreas.deferredRuleSections) {
        rebuilt = rebuilt.replaceFirst(
          '${AreaSpecs.section(rebuilt, h)}\n\n',
          '',
        );
      }
      expect(leanRules.replaceFirst(AreaSpecs.leanRule, ''), rebuilt);
      // Los intents del índice siguen: el modelo decide qué tool llamar
      // antes de ver el resultado.
      for (final id in ['[W:EARNINGS]', '[W:FUNDAMENTALS]', '[W:NEWS]']) {
        expect(leanRules, contains(id));
      }
    });

    test('the lean prompt drops exactly the deferred widget schemas', () {
      final leanSchemas = AreaSpecs.widgetSchemas(lean);
      expect(
        schemas.keys.toSet().difference(leanSchemas.keys.toSet()),
        PortyAreas.deferredWidgets,
      );
      expect(lean.length, lessThan(classic.length));
    });

    test('the lean prompt saves at least 2.500 tokens of fixed prefix', () {
      final rulesSaved =
          (assistantPromptRules.length -
              AreaSpecs.leanRules(assistantPromptRules).length) /
          _rulesCharsPerToken;
      final schemasSaved =
          [
            for (final w in PortyAreas.deferredWidgets)
              jsonEncode(schemas[w]).length,
          ].fold(0, (s, c) => s + c) /
          _schemaCharsPerToken;
      expect(rulesSaved + schemasSaved, greaterThan(2500));
    });

    test('each deferring tool brings its rules and complete schemas; the '
        'rest bring nothing', () {
      for (final name in toolNames) {
        final spec = AreaSpecs.specFor(
          name,
          rules: assistantPromptRules,
          schemas: schemas,
        );
        final deferred = PortyAreas.deferredFor(name);
        if (deferred == null) {
          expect(spec, isNull, reason: name);
          continue;
        }
        final widgets = (spec!['widgets'] as Map?) ?? const {};
        expect(widgets.keys, deferred.widgets, reason: name);
        expect(widgets.values, everyElement(isA<Map>()), reason: name);
        if (deferred.ruleSections.isNotEmpty) {
          expect(spec['rules'], startsWith(deferred.ruleSections.first));
        }
      }
    });

    test('the extra is keyed by tool, so it is not repeated while visible', () {
      const record = ToolCallRecord(
        name: 'get_news',
        args: {
          'tickers': ['NVDA'],
        },
        result: {'status': 'ok'},
      );
      final extra =
          AreaSpecs.extraFor(
            record,
            rules: assistantPromptRules,
            schemas: schemas,
          )!;
      expect(extra.key, 'area_spec:get_news');
      expect(extra.fields.keys, ['area_spec']);
      expect(
        AreaSpecs.extraFor(
          const ToolCallRecord(name: 'get_quote', args: {}, result: {}),
          rules: assistantPromptRules,
          schemas: schemas,
        ),
        isNull,
      );
    });
  });
}
