import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:portfolio_assistant/config/env/app_env.dart';
import 'package:portfolio_assistant/config/translate/app_language.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_draft.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_input.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_validator.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_writer.dart';
import 'package:portfolio_assistant/features/daily_brief/prompts/daily_brief_prompt.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/ai_proxy_client.dart';
import 'package:portfolio_assistant/features/genui_core/utils/porty_dashes.dart';

/// Resultado de generar la prosa de un brief (§3.9). Misma forma que
/// `WeeklyReportGeneration`.
class DailyBriefGeneration {
  const DailyBriefGeneration({
    required this.draft,
    required this.rounds,
    required this.remainingIssues,
    this.rewriteReasons = const [],
    this.removed = 0,
    this.error,
  });

  /// Siempre mostrable: lo que no pasó el validador ya no está.
  final DailyBriefDraft draft;

  /// Llamadas al LLM (0, 1 o 2).
  final int rounds;

  /// Lo que se tuvo que sacar después de la reescritura (logs/evals).
  final List<String> remainingIssues;

  /// Por qué se pidió la reescritura (problemas de la primera respuesta).
  final List<String> rewriteReasons;

  /// Ítems que el validador sacó del borrador final.
  final int removed;

  /// Tipo de error del proxy o de la red si no hubo respuesta usable
  /// (`not_claimed`, `too_many_rounds`, `http_500`…). Con error, [draft] es
  /// el que se haya podido salvar (o vacío).
  final String? error;

  bool get failed => error != null && draft.isEmpty;
}

/// Una llamada al LLM (vía `ai-chat` en modo `daily_brief`, que no cobra
/// cuota) con los datos ya calculados; si el validador encuentra problemas,
/// una reescritura; lo que siga fallando se descarta. Nunca lanza.
///
/// Implementa [DailyBriefWriter] (lo que conoce el controlador del brief):
/// arma el [DailyBriefInput] del pedido, genera y devuelve la prosa.
class DailyBriefGenerator implements DailyBriefWriter {
  DailyBriefGenerator({
    AiProxyConfig? config,
    http.Client? client,
    String? model,
  }) : _config = config ?? AiProxyConfig.fromEnvironment(),
       _client = client ?? http.Client(),
       _model = model ?? _envModel();

  final AiProxyConfig _config;
  final http.Client _client;
  final String _model;

  static const defaultModel = 'gpt-6-luna';
  static const temperature = 0.4;

  /// El tope del servidor (`maxBriefOutputTokens`): pedir más no sirve.
  static const maxOutputTokens = 900;
  static const timeout = Duration(seconds: 40);

  static String _envModel() => AppEnv.openAiModel ?? defaultModel;

  @override
  Future<DailyBriefWriting> write(DailyBriefWritingRequest request) async {
    final input = DailyBriefInput.fromRequest(request);
    final result = await generate(
      day: request.day,
      input: input,
      language: request.language,
    );
    return DailyBriefWriting(
      prose: result.draft.toProse(input),
      rounds: result.rounds,
      removedItems: result.removed,
      error: result.error,
    );
  }

  /// [language]: el de la app ('es' | 'en'); elige el prompt del brief.
  Future<DailyBriefGeneration> generate({
    required String day,
    required DailyBriefInput input,
    String? language,
  }) async {
    final lang = (language ?? AppLanguage.code) == 'en' ? 'en' : 'es';
    if (input.numbers.isEmpty || !input.hasWork) {
      return const DailyBriefGeneration(
        draft: DailyBriefDraft.empty,
        rounds: 0,
        remainingIssues: [],
      );
    }
    final turnId = _turnId();
    final messages = <Map<String, Object?>>[
      {'role': 'system', 'content': dailyBriefSystemPromptFor(lang)},
      {'role': 'user', 'content': userMessage(input)},
    ];

    final first = await _call(day, turnId, messages);
    if (first.error != null) {
      return DailyBriefGeneration(
        draft: DailyBriefDraft.empty,
        rounds: 1,
        remainingIssues: const [],
        error: first.error,
      );
    }
    final parsed = DailyBriefDraft.tryParse(first.content!);
    final review =
        parsed == null
            ? null
            : DailyBriefValidator.review(parsed, input, language: lang);
    if (review != null && review.isClean) {
      return DailyBriefGeneration(
        draft: review.draft,
        rounds: 1,
        remainingIssues: const [],
      );
    }

    // Una reescritura (el servidor corta en 2 rondas): con los problemas
    // concretos, o pidiendo JSON válido.
    final retry = await _call(day, turnId, [
      ...messages,
      {'role': 'assistant', 'content': first.content},
      {
        'role': 'user',
        'content':
            review == null
                ? (lang == 'en'
                    ? 'Your answer was not valid JSON. Return only the full '
                        'JSON with the requested schema.'
                    : 'Tu respuesta no fue un JSON válido. Devolvé solo el JSON '
                        'completo con el esquema pedido.')
                : rewriteRequest(review.issues, language: lang),
      },
    ]);
    final retried =
        retry.content == null ? null : DailyBriefDraft.tryParse(retry.content!);
    final second =
        retried == null
            ? null
            : DailyBriefValidator.review(retried, input, language: lang);
    // Lo mejor que haya: la reescritura validada, o la primera ya limpia.
    final best = second ?? review;
    return DailyBriefGeneration(
      draft: best?.draft ?? DailyBriefDraft.empty,
      rounds: 2,
      remainingIssues: best?.issues ?? const ['no_valid_json'],
      rewriteReasons: review?.issues ?? const ['invalid_json'],
      removed: best?.removed ?? 0,
      error: best == null ? (retry.error ?? 'invalid_json') : null,
    );
  }

  /// Los datos van delimitados y como JSON: los titulares son de terceros y
  /// el prompt los trata como texto (ver "INPUT" en el prompt).
  static String userMessage(DailyBriefInput input) =>
      '<brief_data>\n${jsonEncode(input.toPromptJson())}\n</brief_data>';

  static String rewriteRequest(List<String> issues, {String language = 'es'}) =>
      language == 'en'
          ? 'I reviewed your answer and this needs fixing:\n'
              '${issues.map((i) => '- $i').join('\n')}\n'
              'Return the full JSON again, with the same schema, fixing only '
              'that.'
          : 'Revisé tu respuesta y hay que corregir esto:\n'
              '${issues.map((i) => '- $i').join('\n')}\n'
              'Devolvé el JSON completo de nuevo, con el mismo esquema, '
              'corrigiendo solo eso.';

  Future<({String? content, String? error})> _call(
    String day,
    String turnId,
    List<Map<String, Object?>> messages,
  ) async {
    try {
      final token = await _config.accessToken();
      if (token == null || token.isEmpty) {
        return (content: null, error: 'unauthorized');
      }
      final response = await _client
          .post(
            _config.endpoint,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
              if (_config.anonKey != null) 'apikey': _config.anonKey!,
              'x-porty-turn-id': turnId,
              'x-porty-purpose': 'daily_brief',
              'x-porty-brief-day': day,
            },
            body: jsonEncode({
              'model': _model,
              'messages': messages,
              'temperature': temperature,
              'max_completion_tokens': maxOutputTokens,
              'response_format': {
                'type': 'json_schema',
                'json_schema': {
                  'name': 'daily_brief',
                  'strict': true,
                  'schema': dailyBriefResponseSchema,
                },
              },
            }),
          )
          .timeout(timeout);
      final body = utf8.decode(response.bodyBytes, allowMalformed: true);
      if (response.statusCode != 200) {
        return (content: null, error: _errorType(body, response.statusCode));
      }
      final content =
          ((jsonDecode(body) as Map)['choices'] as List?)?.firstOrNull;
      final text = (content as Map?)?['message']?['content'];
      return text is String && text.isNotEmpty
          ? (content: PortyDashes.clean(text), error: null)
          : (content: null, error: 'empty_response');
    } catch (_) {
      return (content: null, error: 'network');
    }
  }

  static String _errorType(String body, int status) {
    try {
      final type = (jsonDecode(body) as Map)['error']?['type'];
      if (type is String && type.isNotEmpty) return type;
    } catch (_) {}
    return 'http_$status';
  }

  static String _turnId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random.secure();
    return 'db-${List.generate(20, (_) => chars[r.nextInt(chars.length)]).join()}';
  }
}
