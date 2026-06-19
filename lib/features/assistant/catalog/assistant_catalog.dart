import 'package:genui/genui.dart';
import 'package:portfolio_assistant/features/assistant/catalog/portfolio_qa_catalog.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/explore_prompt_rules.dart';
import 'package:portfolio_assistant/features/assistant/modes/invest/invest_prompt_rules.dart';
import 'package:portfolio_assistant/features/assistant/modes/learn/learn_prompt_rules.dart';
import 'package:portfolio_assistant/features/assistant/modes/plan/plan_prompt_rules.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/features/assistant/reliability/grounding_prompt_rules.dart';
import 'package:portfolio_assistant/features/genui_core/prompts/critical_output_rules.dart';

abstract final class AssistantCatalog {
  static Catalog buildFor(AssistantMode mode) {
    switch (mode) {
      case AssistantMode.portfolio:
        return PortfolioQaCatalog.build();
      case AssistantMode.learn:
        return _buildStub(learnPromptRules);
      case AssistantMode.explore:
        return _buildStub(explorePromptRules);
      case AssistantMode.invest:
        return _buildStub(investPromptRules);
      case AssistantMode.plan:
        return _buildStub(planPromptRules);
    }
  }

  static Catalog _buildStub(String modeRules) {
    final portfolio = PortfolioQaCatalog.build();
    const excluded = {criticalOutputFormatRules, groundingPromptRules};
    return portfolio.copyWith(
      systemPromptFragments: [
        criticalOutputFormatRules,
        groundingPromptRules,
        modeRules,
        ...portfolio.systemPromptFragments.where(
          (f) =>
              !excluded.contains(f) &&
              !f.contains('PORTFOLIO Q&A RULES'),
        ),
      ],
    );
  }
}
