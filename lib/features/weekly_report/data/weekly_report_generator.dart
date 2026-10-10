import 'dart:convert';
import 'dart:math';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:portfolio_assistant/features/genui_core/tool_calling/ai_proxy_client.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/report_week.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_report_draft.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_report_input.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_report_validator.dart';
import 'package:portfolio_assistant/features/weekly_report/prompts/weekly_report_prompt.dart';

/// Resultado de generar la prosa de un informe.
class WeeklyReportGeneration {
  const WeeklyReportGeneration({
    required this.draft,
    required this.rounds,
    required this.remainingIssues,
    this.rewriteReasons = const [],
    this.error,
  });

  /// Siempre mostrable: lo que no pasó el validador ya no está.
  final WeeklyReportDraft draft;

  /// Llamadas al LLM (1 o 2).
  final int rounds;

  /// Lo que se tuvo que sacar después de la reescritura (para logs/evals).
  final List<String> remainingIssues;

  /// Por qué se pidió la reescritura (problemas de la primera respuesta).
  final List<String> rewriteReasons;

  /// Tipo de error del proxy o de la red si no hubo respuesta usable
  /// (`not_claimed`, `too_many_rounds`, `http_500`…). Con error, [draft] es
  /// el que se haya podido salvar (o vacío).
  final String? error;

  bool get failed => error != null && draft.isEmpty;
}

/// Una llamada al LLM (vía `ai-chat` en modo informe, que no cobra cuota)
/// con los datos ya calculados; si el validador encuentra problemas, una
/// reescritura; lo que siga fallando se descarta. Nunca lanza.
class WeeklyReportGenerator {
  WeeklyReportGenerator({
    AiProxyConfig? config,
    http.Client? client,
    String? model,
  }) : _config = config ?? AiProxyConfig.fromEnvironment(),
       _client = client ?? http.Client(),
       _model = model ?? _envModel();

  final AiProxyConfig _config;
  final http.Client _client;
  final String _model;

  static const defaultModel = 'gpt-4.1-mini';
  static const temperature = 0.4;
  static const maxOutputTokens = 1500;
  static const timeout = Duration(seconds: 40);

  static String _envModel() {
    try {
      final m = dotenv.maybeGet('OPENAI_MODEL')?.trim();
      return m == null || m.isEmpty ? defaultModel : m;
    } catch (_) {
      return defaultModel;
    }
  }

  Future<WeeklyReportGeneration> generate({
    required ReportWeek week,
    required WeeklyReportInput input,
  }) async {
    if (input.numbers.isEmpty) {
      return const WeeklyReportGeneration(
        draft: WeeklyReportDraft.empty,
        rounds: 0,
        remainingIssues: [],
      );
    }
    final turnId = _turnId();
    final messages = <Map<String, Object?>>[
      {'role': 'system', 'content': weeklyReportSystemPrompt},
      {'role': 'user', 'content': userMessage(input)},
    ];

    final first = await _call(week, turnId, messages);
    if (first.error != null) {
      return WeeklyReportGeneration(
        draft: WeeklyReportDraft.empty,
        rounds: 1,
        remainingIssues: const [],
        error: first.error,
      );
    }
    final parsed = WeeklyReportDraft.tryParse(first.content!);
    final review =
        parsed == null ? null : WeeklyReportValidator.review(parsed, input);
    if (review != null && review.isClean) {
      return WeeklyReportGeneration(
        draft: review.draft,
        rounds: 1,
        remainingIssues: const [],
      );
    }

    // Una reescritura: con los problemas concretos, o pidiendo JSON válido.
    final retry = await _call(week, turnId, [
      ...messages,
      {'role': 'assistant', 'content': first.content},
      {
        'role': 'user',
        'content':
            review == null
                ? 'Tu respuesta no fue un JSON válido. Devolvé solo el JSON '
                    'completo con el esquema pedido.'
                : rewriteRequest(review.issues),
      },
    ]);
    final retried =
        retry.content == null
            ? null
            : WeeklyReportDraft.tryParse(retry.content!);
    final second =
        retried == null ? null : WeeklyReportValidator.review(retried, input);
    // Lo mejor que haya: la reescritura validada, o la primera ya limpia.
    final best = second ?? review;
    return WeeklyReportGeneration(
      draft: best?.draft ?? WeeklyReportDraft.empty,
      rounds: 2,
      remainingIssues: best?.issues ?? const ['no_valid_json'],
      rewriteReasons: review?.issues ?? const ['invalid_json'],
      error: best == null ? (retry.error ?? 'invalid_json') : null,
    );
  }

  /// Los datos van delimitados y como JSON: los titulares son de terceros y
  /// el prompt los trata como texto (ver "INPUT" en el prompt).
  static String userMessage(WeeklyReportInput input) =>
      '<weekly_data>\n${jsonEncode(input.toPromptJson())}\n</weekly_data>';

  static String rewriteRequest(List<String> issues) =>
      'Revisé tu respuesta y hay que corregir esto:\n'
      '${issues.map((i) => '- $i').join('\n')}\n'
      'Devolvé el JSON completo de nuevo, con el mismo esquema, corrigiendo '
      'solo eso.';

  Future<({String? content, String? error})> _call(
    ReportWeek week,
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
              'x-porty-purpose': 'weekly_report',
              'x-porty-report-week': week.key,
            },
            body: jsonEncode({
              'model': _model,
              'messages': messages,
              'temperature': temperature,
              'max_completion_tokens': maxOutputTokens,
              'response_format': {
                'type': 'json_schema',
                'json_schema': {
                  'name': 'weekly_report',
                  'strict': true,
                  'schema': weeklyReportResponseSchema,
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
          ? (content: text, error: null)
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
    return 'wr-${List.generate(20, (_) => chars[r.nextInt(chars.length)]).join()}';
  }
}
