// El interruptor `daily_brief` apagado no cambia nada en el chat (spec
// 2026-11-20 §1 y §6): el prompt de sistema y la lista de tools son
// idénticos a los de antes del brief (commit 8e7ccf58). Con el interruptor
// prendido, el prompt trae las reglas y la card del brief y las tools
// aparecen. Los hashes de los prompts con el brief prendido tienen que estar
// en el allowlist de `ai-chat` (desplegarlo antes de publicar la app).
//
// Si cambiaste las reglas, el catálogo o las tools del brief:
//   UPDATE_PROMPT_ALLOWLIST=1 flutter test test/features/assistant/daily_brief_gate_test.dart
// Correr: flutter test test/features/assistant/daily_brief_gate_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/assistant/areas/area_specs.dart';
import 'package:portfolio_assistant/features/assistant/catalog/assistant_catalog.dart';
import 'package:portfolio_assistant/features/assistant/prompts/assistant_prompt_rules.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_openai_service.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_toolset.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_claim.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';

import 'fakes/assistant_fakes.dart';

const _allowlist = 'supabase/functions/ai-chat/allowed_system_prompts.json';

// Medidos en el commit base 8e7ccf58 (antes del brief diario) con el mismo
// armado: prompt clásico, prompt lean y las definiciones de tools de Gold.
const _baseClassic =
    '0c8907b31f8a5f83ebacb07a7c5151d2441b404e1c224b18c12f5e14d06157c4';
const _baseLean =
    '4b7e99ce3400adb6580db84a62acfb04919cc0bd2907f41ad814c842be324c65';
const _baseTools =
    'f232dc97efad09d9ffc71377812492e714387b4b208f15204c8f6abe7781932b';

String _sha(String text) => sha256.convert(utf8.encode(text)).toString();

Set<String> _allowed() =>
    ((jsonDecode(File(_allowlist).readAsStringSync()) as Map)['hashes'] as List)
        .cast<String>()
        .toSet();

/// Como el test de `test/security`: con UPDATE_PROMPT_ALLOWLIST=1 agrega el
/// hash (los viejos se conservan para las versiones en la calle).
void _expectAllowed(String prompt) {
  final hash = _sha(prompt);
  final hashes = [
    ...((jsonDecode(File(_allowlist).readAsStringSync()) as Map)['hashes']
            as List)
        .cast<String>(),
  ];
  if (Platform.environment['UPDATE_PROMPT_ALLOWLIST'] == '1' &&
      !hashes.contains(hash)) {
    hashes.add(hash);
    File(_allowlist).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({'hashes': hashes})}\n',
    );
  }
  expect(hashes, contains(hash), reason: _allowlist);
}

List<DataTool> _tools(DailyBriefStatus status) => AssistantToolset.build(
  AssistantToolContext(
    tier: SubscriptionTier.gold,
    data: fakeDataSources(),
    dailyBriefStatus: status,
  ),
);

String _defs(List<DataTool> tools) =>
    jsonEncode([for (final t in tools) t.toOpenAi().toMap()]);

void main() {
  const on = DailyBriefStatus(enabled: true);

  group('switch off = the chat before the daily brief', () {
    test('the system prompt is the base one (same hash, already in the '
        'allowlist)', () {
      final classic = AssistantOpenAiService.systemPromptFor(
        AssistantCatalog.build(),
      );
      final lean = AssistantOpenAiService.systemPromptFor(
        AssistantCatalog.build(variant: PromptVariant.lean),
      );
      expect(_sha(classic), _baseClassic);
      expect(_sha(lean), _baseLean);
      expect(_allowed(), containsAll([_baseClassic, _baseLean]));
      // El default es apagado: nadie lo prende sin decirlo.
      expect(
        AssistantOpenAiService.systemPromptFor(
          AssistantCatalog.build(dailyBrief: false),
        ),
        classic,
      );
    });

    test('the rules are the base rules, and the display catalog has no brief '
        'card', () {
      expect(assistantPromptRulesFor(dailyBrief: false), assistantPromptRules);
      final names =
          AssistantCatalog.build(forDisplay: true).items.map((i) => i.name);
      expect(
        names,
        isNot(contains('QaSourceComparison')),
        reason: 'ni siquiera para mostrar: el modelo no la conoce',
      );
    });

    test('the tool list is the base one (same definitions)', () {
      for (final status in [
        DailyBriefStatus.off,
        DailyBriefStatus.unreachable,
        // Apagado manda sobre las piezas.
        const DailyBriefStatus(
          enabled: false,
          pieces: {'compare': true, 'brief': true},
        ),
      ]) {
        final tools = _tools(status);
        expect(tools, hasLength(30));
        expect(_sha(_defs(tools)), _baseTools);
      }
      // Sin estado (el default del contexto) también.
      final bare = AssistantToolset.build(
        AssistantToolContext(
          tier: SubscriptionTier.gold,
          data: fakeDataSources(),
        ),
      );
      expect(_sha(_defs(bare)), _baseTools);
    });
  });

  group('switch on', () {
    test('both tools show up (after the base ones)', () {
      final names = [for (final t in _tools(on)) t.name];
      expect(names.take(30), [
        for (final t in _tools(DailyBriefStatus.off)) t.name,
      ]);
      expect(names.skip(30), ['get_daily_brief', 'compare_sources']);
    });

    test('the prompts carry the brief rules and card, and they are in the '
        'allowlist', () {
      final classic = AssistantOpenAiService.systemPromptFor(
        AssistantCatalog.build(dailyBrief: true),
      );
      final lean = AssistantOpenAiService.systemPromptFor(
        AssistantCatalog.build(variant: PromptVariant.lean, dailyBrief: true),
      );
      expect(_sha(classic), isNot(_baseClassic));
      expect(_sha(lean), isNot(_baseLean));
      expect(classic, contains('[W:SOURCES]'));
      expect(classic, contains('QaSourceComparison'));
      expect(classic, contains("today's brief → get_daily_brief"));
      // Estables entre construcciones (si no, el hash no sirve).
      expect(
        AssistantOpenAiService.systemPromptFor(
          AssistantCatalog.build(dailyBrief: true),
        ),
        classic,
      );
      _expectAllowed(classic);
      _expectAllowed(lean);
    });

    test('lean: the SOURCES section and the card travel with the tool result',
        () {
      final classic = AssistantOpenAiService.systemPromptFor(
        AssistantCatalog.build(dailyBrief: true),
      );
      final spec = AreaSpecs.specFor(
        'compare_sources',
        rules: assistantPromptRulesFor(dailyBrief: true),
        schemas: AreaSpecs.widgetSchemas(classic),
      )!;
      expect(spec['rules'], contains('SOURCES ([W:SOURCES])'));
      expect((spec['widgets'] as Map).keys, ['QaSourceComparison']);
      final extra = AreaSpecs.extraFor(
        const ToolCallRecord(name: 'compare_sources', args: {}, result: {}),
        rules: assistantPromptRulesFor(dailyBrief: true),
        schemas: AreaSpecs.widgetSchemas(classic),
      );
      expect(extra?.key, 'area_spec:compare_sources');
    });
  });
}
