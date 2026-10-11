import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/assistant/tools/tool_args.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';

/// Búsqueda web, para lo que ninguna otra tool cubre — sobre todo el precio
/// de lo que el usuario quiere comprar ("la MacBook Neo rosa"). Corre en el
/// servidor (`web-search`): caché compartida y tope diario por plan.
class SearchWebTool implements DataTool {
  SearchWebTool(this.ctx);

  final AssistantToolContext ctx;

  static const toolName = 'search_web';

  @override
  String get name => toolName;

  @override
  String get description =>
      'Searches the web for a personal-finance FACT no other tool has: '
      'mainly the current price of something the user wants to buy for a '
      'purchase goal ("MacBook Neo rosa", "PlayStation 6", "pasaje a '
      'Madrid"), or a fee, rate or cost they ask about. Returns answer (a '
      'short summary) and sources [{title, url}]. NEVER for stock prices, '
      'news or company data (use the market tools), never for off-topic '
      'questions, and only once per thing per conversation (reuse the '
      'result). status limit = daily search limit reached: ask the user '
      'for the price instead.';

  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': {
      'query': {
        'type': 'string',
        'description':
            'Specific search, in Spanish or English, with the exact product '
            'or item ("precio MacBook Neo rosa en USD").',
      },
    },
    'required': ['query'],
    'additionalProperties': false,
  };

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async {
    final query = ToolArgs.string(args, 'query');
    if (query == null || query.length < 3) return ToolArgs.invalid();
    final clipped = query.length > 200 ? query.substring(0, 200) : query;
    return {...await ctx.data.webSearch.search(clipped), 'as_of': ctx.asOf};
  }
}
