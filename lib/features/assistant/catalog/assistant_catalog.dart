import 'package:genui/genui.dart';
import 'package:portfolio_assistant/features/assistant/catalog/portfolio_qa_catalog.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/explore_prompt_rules.dart';
import 'package:portfolio_assistant/features/assistant/modes/invest/invest_prompt_rules.dart';
import 'package:portfolio_assistant/features/assistant/modes/learn/learn_prompt_rules.dart';
import 'package:portfolio_assistant/features/assistant/modes/plan/plan_prompt_rules.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/features/assistant/reliability/portfolio_context_prompt_rules.dart';

abstract final class AssistantCatalog {
  static Catalog buildFor(AssistantMode mode) {
    switch (mode) {
      case AssistantMode.portfolio:
        return PortfolioQaCatalog.build();
      case AssistantMode.learn:
        return _buildForMode(mode, learnPromptRules);
      case AssistantMode.explore:
        return _buildForMode(mode, explorePromptRules);
      case AssistantMode.invest:
        return _buildForMode(mode, investPromptRules);
      case AssistantMode.plan:
        return _buildForMode(mode, planPromptRules);
    }
  }

  /// `PortfolioQaCatalog.buildFor` ya arma un catálogo acotado a los
  /// widgets que este modo realmente usa (ver ese archivo) — acá solo se
  /// le agrega `portfolioContextPromptRules`, ya que los modos no-portfolio
  /// necesitan que se les diga explícitamente que tienen acceso a la
  /// cartera real del usuario (de cara al usuario Porty es un solo chat,
  /// sin pestañas).
  static Catalog _buildForMode(AssistantMode mode, String modeRules) {
    return PortfolioQaCatalog.buildFor(
      mode,
      '$portfolioContextPromptRules\n\n$modeRules',
    );
  }
}
