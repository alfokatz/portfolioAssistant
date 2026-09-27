import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/company_ticker_resolver.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/explore_earnings_enricher.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/explore_fundamentals_enricher.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/explore_news_enricher.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_openai_service.dart';

/// Dependencias externas del pipeline unificado, como fábricas: todas tocan
/// dotenv/red al construirse (OpenAI, Finnhub), así que se crean recién
/// cuando `_sendUnified` las necesita — y los tests de punta a punta las
/// reemplazan sin tocar el cableado real (flag → needs → gating → contexto
/// → servicio → surface).
class UnifiedPipelineDeps {
  const UnifiedPipelineDeps({
    required this.createService,
    required this.createTickerResolver,
    required this.createNewsEnricher,
    required this.createEarningsEnricher,
    required this.createFundamentalsEnricher,
  });

  final AssistantOpenAiService Function() createService;
  final CompanyTickerResolver Function() createTickerResolver;
  final ExploreNewsEnricher Function() createNewsEnricher;
  final ExploreEarningsEnricher Function() createEarningsEnricher;
  final ExploreFundamentalsEnricher Function() createFundamentalsEnricher;
}

final unifiedPipelineDepsProvider = Provider<UnifiedPipelineDeps>(
  (ref) => UnifiedPipelineDeps(
    createService: AssistantOpenAiService.unified,
    createTickerResolver: CompanyTickerResolver.new,
    createNewsEnricher: ExploreNewsEnricher.new,
    createEarningsEnricher: ExploreEarningsEnricher.new,
    createFundamentalsEnricher: ExploreFundamentalsEnricher.new,
  ),
);
