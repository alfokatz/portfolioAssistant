// El proxy `ai-chat` solo acepta requests cuyo primer mensaje de sistema es
// un prompt de la app (por hash): sin esto, cualquiera con una sesión podría
// usar el proxy como GPT gratis con su propio prompt.
//
// Si cambiaste el prompt o el catálogo y este test falla:
//   UPDATE_PROMPT_ALLOWLIST=1 flutter test test/security/system_prompt_allowlist_test.dart
// y desplegá `ai-chat` ANTES de publicar la versión de la app (los hashes
// viejos se conservan para las versiones que siguen en la calle).
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/catalog/assistant_catalog.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_openai_service.dart';

const _allowlist = 'supabase/functions/ai-chat/allowed_system_prompts.json';

void main() {
  test('the current Porty system prompt is in the ai-chat allowlist', () {
    final prompt = AssistantOpenAiService.systemPromptFor(
      AssistantCatalog.build(),
    );
    // Estable entre construcciones: si dependiera de la fecha o de datos del
    // usuario, el hash no serviría (y tampoco la caché de prompts de OpenAI).
    expect(
      AssistantOpenAiService.systemPromptFor(AssistantCatalog.build()),
      prompt,
    );
    final hash = sha256.convert(utf8.encode(prompt)).toString();

    final file = File(_allowlist);
    final hashes = [
      ...((jsonDecode(file.readAsStringSync()) as Map)['hashes'] as List)
          .cast<String>(),
    ];
    if (Platform.environment['UPDATE_PROMPT_ALLOWLIST'] == '1' &&
        !hashes.contains(hash)) {
      hashes.add(hash);
      file.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert({'hashes': hashes})}\n',
      );
    }
    expect(hashes, contains(hash));
  });
}
