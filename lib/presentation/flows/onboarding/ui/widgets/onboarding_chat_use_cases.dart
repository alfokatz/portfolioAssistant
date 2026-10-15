import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_mockup_widgets.dart';
import 'package:portfolio_assistant/presentation/shared/charts/benchmark_dual_line_chart.dart';
import 'package:portfolio_assistant/presentation/shared/charts/diverging_bar.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/fade_through_switcher.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/segmented_choice.dart';

/// Lo que se le pregunta a Porty, en tres casos de uso que se eligen arriba:
/// la cartera propia (todos los planes), cualquier acción (Premium) y el
/// análisis de una empresa (Gold). Cada uno es una conversación de ejemplo
/// con la card que Porty mostraría.
class OnboardingChatUseCases extends StatefulWidget {
  const OnboardingChatUseCases({super.key});

  @override
  State<OnboardingChatUseCases> createState() => _OnboardingChatUseCasesState();
}

enum _UseCase { portfolio, market, analysis }

class _OnboardingChatUseCasesState extends State<OnboardingChatUseCases> {
  _UseCase _selected = _UseCase.portfolio;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedChoice<_UseCase>(
          options: [
            (
              value: _UseCase.portfolio,
              label: 'onboarding_use_case_portfolio'.tr(),
            ),
            (value: _UseCase.market, label: 'onboarding_use_case_market'.tr()),
            (
              value: _UseCase.analysis,
              label: 'onboarding_use_case_analysis'.tr(),
            ),
          ],
          selected: _selected,
          onChanged: (value) => setState(() => _selected = value),
        ),
        const SizedBox(height: AppDimens.sp20),
        FadeThroughSwitcher(
          index: _selected.index,
          builders: [
            (_) => _Conversation(
              question: 'onboarding_chat_portfolio_question'.tr(),
              answer: 'onboarding_chat_portfolio_answer'.tr(),
              card: const _MoversCard(),
            ),
            (_) => _Conversation(
              question: 'onboarding_chat_market_question'.tr(),
              answer: 'onboarding_chat_market_answer'.tr(),
              card: const _CompareCard(),
            ),
            (_) => _Conversation(
              question: 'onboarding_chat_analysis_question'.tr(),
              answer: 'onboarding_chat_analysis_answer'.tr(),
              card: const _AnalysisCard(),
            ),
          ],
        ),
      ],
    );
  }
}

class _Conversation extends StatelessWidget {
  const _Conversation({
    required this.question,
    required this.answer,
    required this.card,
  });

  final String question;
  final String answer;
  final Widget card;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OnboardingUserBubble(text: question),
        const SizedBox(height: AppDimens.sp16),
        OnboardingPortyReply(text: answer),
        const SizedBox(height: AppDimens.sp12),
        ExcludeSemantics(child: card),
      ],
    );
  }
}

/// Título de una card de ejemplo, con el plan que la incluye a la derecha.
class _CardTitle extends StatelessWidget {
  const _CardTitle({required this.title, this.tag});

  final String title;
  final String? tag;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (tag != null) OnboardingPlanTag(label: tag!),
      ],
    );
  }
}

/// "Qué movió tu cartera": la que más sumó y la que más restó, con la barra
/// de impacto del informe semanal.
class _MoversCard extends StatelessWidget {
  const _MoversCard();

  static const _movers = [('NVDA', 4.5, 1.8), ('AAPL', -1.2, -0.4)];

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return OnboardingMockCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardTitle(title: 'weekly_report_movers_section'.tr()),
          for (final (ticker, pct, impact) in _movers) ...[
            const SizedBox(height: AppDimens.sp12),
            Row(
              children: [
                OnboardingTickerAvatar(ticker: ticker),
                const SizedBox(width: AppDimens.sp12),
                Expanded(
                  child: Text(
                    ticker,
                    style: tt.titleSmall?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  QaFormat.signedPct(pct, digits: 1),
                  style: tt.titleSmall?.copyWith(
                    color: colors.pnlColor(impact),
                    fontWeight: FontWeight.w700,
                    fontFeatures: onboardingTabular,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.sp8),
            DivergingBar(value: impact, maxAbs: 1.8),
          ],
        ],
      ),
    );
  }
}

/// Dos acciones en el mismo gráfico, como la comparación del chat.
class _CompareCard extends StatelessWidget {
  const _CompareCard();

  static const _msft = <double>[
    100,
    101.5,
    100.8,
    103.2,
    104.9,
    104.1,
    106.8,
    108.2,
    107.5,
    109.9,
    111.4,
    110.6,
    112.8,
    114.0,
  ];
  static const _googl = <double>[
    100,
    99.2,
    100.4,
    101.1,
    100.3,
    102.6,
    103.4,
    102.1,
    104.0,
    105.2,
    104.6,
    106.9,
    108.1,
    109.0,
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return OnboardingMockCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardTitle(
            title: 'onboarding_chat_market_card_title'.tr(),
            tag: 'onboarding_tag_premium'.tr(),
          ),
          const SizedBox(height: AppDimens.sp12),
          Row(
            children: [
              Expanded(
                child: _LegendValue(
                  color: colors.chartLine,
                  ticker: 'MSFT',
                  pct: 14,
                ),
              ),
              Expanded(
                child: _LegendValue(
                  color: colors.benchmarkSp500,
                  ticker: 'GOOGL',
                  pct: 9,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.sp12),
          const BenchmarkDualLineChart(
            portfolioValues: _msft,
            sp500Values: _googl,
            height: 88,
            showYAxisLabels: false,
          ),
        ],
      ),
    );
  }
}

class _LegendValue extends StatelessWidget {
  const _LegendValue({
    required this.color,
    required this.ticker,
    required this.pct,
  });

  final Color color;
  final String ticker;
  final double pct;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppDimens.sp6),
        Text(
          ticker,
          style: tt.labelLarge?.copyWith(
            color: colors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: AppDimens.sp6),
        Text(
          QaFormat.signedPct(pct, digits: 0),
          style: tt.labelLarge?.copyWith(
            color: colors.pnlColor(pct),
            fontWeight: FontWeight.w700,
            fontFeatures: onboardingTabular,
          ),
        ),
      ],
    );
  }
}

/// El análisis de una empresa resumido: valuación, resultados y noticias,
/// en filas editoriales.
class _AnalysisCard extends StatelessWidget {
  const _AnalysisCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final rows = [
      (
        Icons.speed_outlined,
        'onboarding_chat_analysis_valuation_label'.tr(),
        'onboarding_chat_analysis_valuation_value'.tr(),
      ),
      (
        Icons.receipt_long_outlined,
        'onboarding_chat_analysis_earnings_label'.tr(),
        'onboarding_chat_analysis_earnings_value'.tr(),
      ),
      (
        Icons.article_outlined,
        'onboarding_chat_analysis_news_label'.tr(),
        'onboarding_chat_analysis_news_value'.tr(),
      ),
    ];
    return OnboardingMockCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const OnboardingTickerAvatar(ticker: 'AAPL'),
              const SizedBox(width: AppDimens.sp12),
              Expanded(
                child: _CardTitle(
                  title: 'onboarding_chat_analysis_card_title'.tr(),
                  tag: 'onboarding_tag_gold'.tr(),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.sp8),
          for (final (i, (icon, label, value)) in rows.indexed) ...[
            if (i > 0) Divider(height: 1, thickness: 0.5, color: colors.border),
            _AnalysisRow(icon: icon, label: label, value: value),
          ],
        ],
      ),
    );
  }
}

class _AnalysisRow extends StatelessWidget {
  const _AnalysisRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: AppDimens.iconMd - 2, color: colors.accentBlue),
          const SizedBox(width: AppDimens.sp12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: tt.labelMedium?.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: tt.bodyMedium?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
