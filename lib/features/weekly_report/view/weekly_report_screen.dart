import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/nav/assistant_nav.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_paywall_sheet.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_report.dart';
import 'package:portfolio_assistant/features/weekly_report/providers/weekly_report_controller.dart';
import 'package:portfolio_assistant/features/weekly_report/view/weekly_report_format.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/fade_slide_in.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/pnl_badge.dart';
import 'package:url_launcher/url_launcher.dart';

/// El informe semanal completo. Secciones editoriales planas (título,
/// filas, divisores), sin cards anidadas: los números los pone la app y el
/// texto es de Porty.
class WeeklyReportScreen extends ConsumerStatefulWidget {
  const WeeklyReportScreen({super.key});

  /// Escalonado de la primera vez que se abre el informe de la semana.
  static const stagger = Duration(milliseconds: 60);
  static const entrance = Duration(milliseconds: 240);

  @override
  ConsumerState<WeeklyReportScreen> createState() => _WeeklyReportScreenState();
}

class _WeeklyReportScreenState extends ConsumerState<WeeklyReportScreen> {
  /// Se decide al abrir: si ya se vio, entra sin animación.
  late final bool _animate = !ref.read(weeklyReportControllerProvider).seen;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(weeklyReportControllerProvider.notifier).markSeen();
    });
  }

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(weeklyReportControllerProvider).report;
    final colors = context.customColors;
    return Scaffold(
      appBar: AppBar(title: Text('weekly_report_screen_title'.tr())),
      body:
          report == null
              ? const SizedBox.shrink()
              : SafeArea(
                top: false,
                // Column y no ListView: son pocas secciones y así se
                // construyen todas al abrir (la entrada escalonada pasa una
                // vez; un ListView las armaba al scrollear y las re-animaba).
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppDimens.pageHorizontal,
                    AppDimens.sp8,
                    AppDimens.pageHorizontal,
                    AppDimens.sp40,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, section)
                          in _sections(context, report).indexed)
                        FadeSlideIn(
                          delay: WeeklyReportScreen.stagger * i,
                          duration: WeeklyReportScreen.entrance,
                          skipAnimation: !_animate,
                          child: section,
                        ),
                      const SizedBox(height: AppDimens.sp24),
                      Text(
                        'weekly_report_disclaimer'.tr(),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
    );
  }

  List<Widget> _sections(BuildContext context, WeeklyReport r) => [
    _Header(report: r),
    _Numbers(report: r),
    if (r.variant == WeeklyReportVariant.numbersLocked) const _GoldTeaser(),
    if (r.variant == WeeklyReportVariant.numbersUnavailable)
      _Note(text: 'weekly_report_unavailable'.tr()),
    if (r.news.isNotEmpty)
      _Section(
        title: 'weekly_report_news_section'.tr(),
        children: [for (final n in r.news) _NewsRow(news: n)],
      ),
    if (r.investors.isNotEmpty)
      _Section(
        title: 'weekly_report_investors_section'.tr(),
        children: [for (final i in r.investors) _InvestorRow(investor: i)],
      ),
    if (r.upcomingEarnings.isNotEmpty || r.closing != null)
      _Section(
        title: 'weekly_report_upcoming_section'.tr(),
        children: [
          for (final e in r.upcomingEarnings) _EarningsRow(earnings: e),
          if (r.closing != null) _Prose(r.closing!),
        ],
      ),
    if (r.learn != null)
      _Section(
        title: 'weekly_report_learn_section'.tr(),
        children: [_Learn(learn: r.learn!)],
      ),
    if (r.followUpQuestion != null) _AskPorty(question: r.followUpQuestion!),
  ];
}

// ---------------------------------------------------------------------------
// Secciones
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.report});
  final WeeklyReport report;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const PortyAvatar(size: 40),
            const SizedBox(width: AppDimens.sp12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'weekly_report_title'.tr(),
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  Text(
                    WeeklyReportFormat.range(context, report),
                    style: tt.bodySmall?.copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.sp20),
        // La misma voz que el saludo del login: texto suelto, sin burbuja.
        Text(
          WeeklyReportFormat.headline(report),
          style: tt.bodyLarge?.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w500,
            height: 1.4,
            letterSpacing: -0.2,
            color: colors.textPrimary,
          ),
        ),
        if (report.courtesy) ...[
          const SizedBox(height: AppDimens.sp12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                size: 16,
                color: colors.accentBlue,
              ),
              const SizedBox(width: AppDimens.sp8),
              Expanded(
                child: Text(
                  'weekly_report_courtesy'.tr(),
                  style: tt.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Numbers extends ConsumerWidget {
  const _Numbers({required this.report});
  final WeeklyReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final r = report;
    final benchmarkAllowed = ref.watch(weeklyReportBenchmarkAllowedProvider);
    final tabular = const [FontFeature.tabularFigures()];
    return _Section(
      title: 'weekly_report_numbers_section'.tr(),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              WeeklyReportFormat.pct(r.changePct),
              style: tt.displaySmall?.copyWith(
                fontSize: 34,
                fontWeight: FontWeight.w700,
                height: 1.05,
                letterSpacing: -0.8,
                color: colors.pnlColor(r.changePct),
                fontFeatures: tabular,
              ),
            ),
            const SizedBox(height: AppDimens.sp4),
            Text(
              '${WeeklyReportFormat.money(r.changeAbs, signed: true)} · '
              '${WeeklyReportFormat.money(r.valueEnd)}',
              style: tt.bodyMedium?.copyWith(
                color: colors.textSecondary,
                fontFeatures: tabular,
              ),
            ),
            if (r.newMoney > 0) ...[
              const SizedBox(height: AppDimens.sp8),
              Text(
                'weekly_report_new_money'.tr(
                  namedArgs: {'amount': WeeklyReportFormat.money(r.newMoney)},
                ),
                style: tt.bodySmall?.copyWith(color: colors.textSecondary),
              ),
            ],
            if (r.tradingDays > 0 && r.tradingDays < 5) ...[
              const SizedBox(height: AppDimens.sp4),
              Text(
                'weekly_report_short_week'.tr(
                  namedArgs: {'days': '${r.tradingDays}'},
                ),
                style: tt.bodySmall?.copyWith(color: colors.textSecondary),
              ),
            ],
          ],
        ),
        if (r.sp500Pct != null)
          benchmarkAllowed
              ? Column(
                children: [
                  _ValueRow(
                    label: 'weekly_report_sp500_row'.tr(),
                    value: WeeklyReportFormat.pct(r.sp500Pct!),
                    color: colors.pnlColor(r.sp500Pct!),
                  ),
                  const SizedBox(height: AppDimens.sp8),
                  _ValueRow(
                    label: 'weekly_report_difference_row'.tr(),
                    value: WeeklyReportFormat.pts(r.vsSp500Pp!),
                    color: colors.pnlColor(r.vsSp500Pp!),
                  ),
                ],
              )
              : _LockedRow(
                text: 'weekly_report_sp500_locked'.tr(),
                onTap:
                    () => SubscriptionPaywallSheet.show(
                      context,
                      ref,
                      reason: PaywallReason.modeLocked,
                      source: 'weekly_report_sp500',
                    ),
              ),
        for (final m in r.movers) _MoverRow(mover: m),
        if (r.concentration != null)
          _Prose(
            r.concentration!.weightFourWeeksAgo == null
                ? 'weekly_report_concentration'.tr(
                  namedArgs: {
                    'ticker': r.concentration!.ticker,
                    'now': WeeklyReportFormat.weight(
                      r.concentration!.weightNow,
                    ),
                  },
                )
                : 'weekly_report_concentration_before'.tr(
                  namedArgs: {
                    'ticker': r.concentration!.ticker,
                    'now': WeeklyReportFormat.weight(
                      r.concentration!.weightNow,
                    ),
                    'before': WeeklyReportFormat.weight(
                      r.concentration!.weightFourWeeksAgo!,
                    ),
                  },
                ),
          ),
      ],
    );
  }
}

class _GoldTeaser extends ConsumerWidget {
  const _GoldTeaser();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppDimens.sectionGap),
      child: Semantics(
        button: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          onTap: () {
            PortyHapticsService.maybeOf(context)?.lockedTap();
            SubscriptionPaywallSheet.show(
              context,
              ref,
              reason: PaywallReason.goldRequired,
              source: 'weekly_report',
            );
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppDimens.sp8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.lock_outline,
                      size: 18,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: AppDimens.sp12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'weekly_report_locked_title'.tr(),
                          style: tt.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: AppDimens.sp4),
                        Text(
                          'weekly_report_locked_body'.tr(),
                          style: tt.bodyMedium?.copyWith(
                            color: colors.textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppDimens.sp8),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: colors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filas
// ---------------------------------------------------------------------------

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Padding(
      padding: const EdgeInsets.only(top: AppDimens.sectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: AppDimens.sp12),
          for (final (i, child) in children.indexed) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppDimens.sp12),
                child: Divider(
                  height: 0.5,
                  thickness: 0.5,
                  color: colors.border,
                ),
              ),
            child,
          ],
        ],
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final colors = context.customColors;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: tt.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
        ),
        Text(
          value,
          style: tt.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _LockedRow extends StatelessWidget {
  const _LockedRow({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return InkWell(
      onTap: () {
        PortyHapticsService.maybeOf(context)?.lockedTap();
        onTap();
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
        child: Row(
          children: [
            Icon(Icons.lock_outline, size: 16, color: colors.textSecondary),
            const SizedBox(width: AppDimens.sp8),
            Expanded(
              child: Text(
                text,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: colors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _MoverRow extends StatelessWidget {
  const _MoverRow({required this.mover});
  final ReportMover mover;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final m = mover;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              m.ticker,
              style: tt.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(width: AppDimens.sp8),
            if (m.pricePct != null)
              PnlBadge(percent: m.pricePct!, compact: true),
            const Spacer(),
            Text(
              'weekly_report_contribution'.tr(
                namedArgs: {
                  'value':
                      '${m.contributionPp >= 0 ? '+' : ''}${m.contributionPp.toStringAsFixed(1)}',
                },
              ),
              style: tt.bodySmall?.copyWith(
                color: colors.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        if (m.boughtThisWeek) ...[
          const SizedBox(height: AppDimens.sp4),
          Text(
            'weekly_report_bought_this_week'.tr(),
            style: tt.labelSmall?.copyWith(color: colors.textSecondary),
          ),
        ],
        if (m.why != null) ...[
          const SizedBox(height: AppDimens.sp6),
          _Prose(m.why!),
        ],
        if (m.news != null) ...[
          const SizedBox(height: AppDimens.sp4),
          _SourceLink(
            source: m.news!.source,
            date: m.news!.date,
            url: m.news!.url,
          ),
        ],
      ],
    );
  }
}

class _NewsRow extends StatelessWidget {
  const _NewsRow({required this.news});
  final ReportNews news;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${news.ticker} · ${news.headline}',
          style: tt.titleSmall?.copyWith(
            fontWeight: FontWeight.w500,
            color: colors.textPrimary,
            height: 1.35,
          ),
        ),
        if (news.take != null) ...[
          const SizedBox(height: AppDimens.sp6),
          _Prose(news.take!, secondary: true),
        ],
        const SizedBox(height: AppDimens.sp4),
        _SourceLink(source: news.source, date: news.date, url: news.url),
      ],
    );
  }
}

class _InvestorRow extends StatelessWidget {
  const _InvestorRow({required this.investor});
  final ReportInvestor investor;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final i = investor;
    final meta = [
      if (i.organization != null) i.organization!,
      if (i.isMarketVoice) 'weekly_report_market_voice'.tr(),
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          i.who,
          style: tt.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        if (meta.isNotEmpty)
          Text(
            meta,
            style: tt.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        const SizedBox(height: AppDimens.sp6),
        _Prose(i.take),
        // Si Porty ya lo dijo ("Tenés MSFT en tu cartera"), no repetirlo.
        if (i.relatedTickers.isNotEmpty &&
            !i.take.toLowerCase().contains('tenés')) ...[
          const SizedBox(height: AppDimens.sp4),
          Text(
            'weekly_report_you_hold'.tr(
              namedArgs: {'tickers': i.relatedTickers.join(', ')},
            ),
            style: tt.labelSmall?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: AppDimens.sp4),
        _SourceLink(
          source: i.isFiling ? _filingLabel(i.form) : (i.source ?? ''),
          date: i.date,
          url: i.url,
        ),
      ],
    );
  }
}

class _EarningsRow extends StatelessWidget {
  const _EarningsRow({required this.earnings});
  final ReportEarnings earnings;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final when = [
      WeeklyReportFormat.day(context, earnings.date),
      if (earnings.timingLabel != null) earnings.timingLabel!,
    ].join(' · ');
    // Una debajo de la otra: con la fecha a la derecha el nombre se cortaba.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'weekly_report_upcoming_row'.tr(
            namedArgs: {'ticker': earnings.ticker},
          ),
          style: tt.bodyMedium?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: AppDimens.sp2),
        Text(when, style: tt.bodySmall?.copyWith(color: colors.textSecondary)),
      ],
    );
  }
}

class _Learn extends StatelessWidget {
  const _Learn({required this.learn});
  final ReportLearn learn;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          learn.concept,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: AppDimens.sp6),
        _Prose(learn.text),
      ],
    );
  }
}

class _AskPorty extends StatelessWidget {
  const _AskPorty({required this.question});
  final String question;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppDimens.sectionGap),
      child: Material(
        color: colors.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusPill),
          side: BorderSide(color: colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            PortyHapticsService.maybeOf(context)?.selectionTap();
            GotoAssistant(initialQuestion: question).navigate(context: context);
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppDimens.composerHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.sp20,
                vertical: AppDimens.sp12,
              ),
              child: Row(
                children: [
                  const PortyAvatar(size: 24),
                  const SizedBox(width: AppDimens.sp12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'weekly_report_ask_porty'.tr(),
                          style: tt.labelSmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                        Text(
                          question,
                          style: tt.bodyMedium?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: colors.accentBlue,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppDimens.sectionGap),
    child: _Prose(text, secondary: true),
  );
}

class _Prose extends StatelessWidget {
  const _Prose(this.text, {this.secondary = false});
  final String text;
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: secondary ? colors.textSecondary : colors.textPrimary,
        height: 1.5,
      ),
    );
  }
}

/// "Reuters · jue 24 ↗": link a la nota (terracota: es un link).
class _SourceLink extends StatelessWidget {
  const _SourceLink({
    required this.source,
    required this.date,
    required this.url,
  });
  final String source;
  final DateTime date;
  final String url;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final label = [
      if (source.isNotEmpty) source,
      WeeklyReportFormat.day(context, date),
    ].join(' · ');
    return Semantics(
      link: true,
      label: 'weekly_report_link_semantics'.tr(namedArgs: {'source': source}),
      excludeSemantics: true,
      child: InkWell(
        onTap:
            () =>
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.accentBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: AppDimens.sp4),
              Icon(
                Icons.north_east_rounded,
                size: 14,
                color: colors.accentBlue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "SEC · Form 4", "SEC · 13F-HR", "SEC · Schedule 13G".
String _filingLabel(String? form) {
  if (form == null || form.isEmpty) return 'SEC';
  final name = switch (form) {
    '4' => 'Form 4',
    final f when f.startsWith('SCHEDULE ') =>
      'Schedule ${f.substring('SCHEDULE '.length)}',
    final f => f,
  };
  return 'SEC · $name';
}
