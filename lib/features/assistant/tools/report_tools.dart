import 'package:portfolio_assistant/features/assistant/tools/answer_guide.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';

/// El informe semanal desde el chat: lo mismo que el usuario ve en la Home
/// (números de la semana, lo que más se movió y por qué, noticias, lo que
/// viene). Solo lectura: el informe lo arma la app (ver `weekly_report`).
abstract final class ReportTools {
  static const getWeeklyReport = 'get_weekly_report';

  static List<DataTool> build(AssistantToolContext ctx) => [
    GetWeeklyReportTool(ctx),
  ];
}

abstract final class ReportGuides {
  static const ok =
      'QaAnswerText only: answer from THIS report (what they see on Home); '
      'cite its numbers and its reading, never recalculate.';
  static const notReady =
      'QaAnswerText: this week\'s report isn\'t ready yet; it shows up on '
      'their Home when it is. Offer what you can answer now from the '
      'portfolio.';
}

class GetWeeklyReportTool implements DataTool {
  GetWeeklyReportTool(this.ctx);

  final AssistantToolContext ctx;

  @override
  String get name => ReportTools.getWeeklyReport;

  @override
  String get description =>
      'Their weekly report as shown on Home. status: ok | not_ready.';

  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': {},
    'additionalProperties': false,
  };

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async {
    final load = ctx.loadWeeklyReport;
    if (load == null) return {'status': 'failed', 'reason': 'unavailable'};
    try {
      final report = await load();
      if (report == null) {
        return AnswerGuide.attach({
          'status': 'not_ready',
        }, ReportGuides.notReady);
      }
      return AnswerGuide.attach({
        'status': 'ok',
        'report': report,
      }, ReportGuides.ok);
    } catch (_) {
      return {'status': 'failed', 'reason': 'unavailable'};
    }
  }
}
