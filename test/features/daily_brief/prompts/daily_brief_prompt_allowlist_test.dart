// El proxy `ai-chat` en modo `daily_brief` solo acepta prompts cuyo hash está
// en `allowed_brief_prompts.json`. Este test vive acá y no en `test/security/`
// porque ese archivo es de CODEOWNERS y no se toca en el mismo cambio (spec
// del brief, D8); moverlo allá va en un PR aparte.
//
// Si cambiaste el prompt del brief y este test falla:
//   UPDATE_PROMPT_ALLOWLIST=1 flutter test test/features/daily_brief/prompts/daily_brief_prompt_allowlist_test.dart
// y desplegá `ai-chat` ANTES de publicar la app (los hashes viejos se
// conservan para las versiones que siguen en la calle).
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/daily_brief/prompts/daily_brief_prompt.dart';

const _briefAllowlist = 'supabase/functions/ai-chat/allowed_brief_prompts.json';
const _chatAllowlist = 'supabase/functions/ai-chat/allowed_system_prompts.json';
const _reportAllowlist =
    'supabase/functions/ai-chat/allowed_report_prompts.json';

String _hash(String prompt) => sha256.convert(utf8.encode(prompt)).toString();

List<String> _hashes(String path) =>
    ((jsonDecode(File(path).readAsStringSync()) as Map)['hashes'] as List)
        .cast<String>();

/// Con UPDATE_PROMPT_ALLOWLIST=1 agrega el hash (los viejos se conservan).
void _expectAllowed(String path, String prompt) {
  final hash = _hash(prompt);
  final hashes = [..._hashes(path)];
  if (Platform.environment['UPDATE_PROMPT_ALLOWLIST'] == '1' &&
      !hashes.contains(hash)) {
    hashes.add(hash);
    File(path).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({'hashes': hashes})}\n',
    );
  }
  expect(hashes, contains(hash), reason: path);
}

void main() {
  test('the daily brief prompts (es and en) are in the brief allowlist', () {
    _expectAllowed(_briefAllowlist, dailyBriefSystemPrompt);
    _expectAllowed(_briefAllowlist, dailyBriefSystemPromptEn);
  });

  test(
    'the brief prompts are NOT in the chat or the weekly report allowlists',
    () {
      // El prompt del brief no tiene que servir en el chat ni en el informe, ni
      // al revés (cada modo tiene su claim, su tope y su costo).
      for (final prompt in [dailyBriefSystemPrompt, dailyBriefSystemPromptEn]) {
        expect(_hashes(_chatAllowlist), isNot(contains(_hash(prompt))));
        expect(_hashes(_reportAllowlist), isNot(contains(_hash(prompt))));
      }
    },
  );

  test('the brief allowlist has no duplicates and shares nothing with the '
      'other modes', () {
    final hashes = _hashes(_briefAllowlist);
    expect(hashes.toSet(), hasLength(hashes.length));
    final others = {..._hashes(_chatAllowlist), ..._hashes(_reportAllowlist)};
    expect(hashes.where(others.contains), isEmpty);
  });

  test('the two prompts have different hashes', () {
    expect(
      _hash(dailyBriefSystemPrompt),
      isNot(_hash(dailyBriefSystemPromptEn)),
    );
  });
}
