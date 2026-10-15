import 'dart:async';

import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_identity.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/nav/assistant_nav.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/notifications/view/push_permission_sheet.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_paywall_sheet.dart';
import 'package:portfolio_assistant/features/goals/providers/goals_provider.dart' show goalHoldingsProvider;
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_report.dart';
import 'package:portfolio_assistant/features/weekly_report/providers/weekly_report_controller.dart';
import 'package:portfolio_assistant/features/weekly_report/view/weekly_report_chart.dart';
import 'package:portfolio_assistant/features/weekly_report/view/weekly_report_format.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/flows/position/nav/position_nav.dart';
import 'package:portfolio_assistant/presentation/shared/loading/loader_timing.dart';
import 'package:portfolio_assistant/presentation/shared/loading/porty_loader.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/fade_slide_in.dart';
import 'package:url_launcher/url_launcher.dart';

/// El informe semanal. Responde tres preguntas, en orden: ¿cómo me fue?
/// (número, gráfico, mercado), ¿por qué? (qué movió la cartera) y ¿qué
/// viene? (resultados de la semana próxima). Después, solo si hay algo que
/// valga la pena: noticias, grandes inversores y un concepto. Una sección
/// sin nada relevante no aparece.
///
/// Título grande arriba ("Tu semana"), que pasa a la barra al scrollear.
/// Después, grupos por pregunta: una línea fina y secciones con título
/// propio. Entre grupos hay más aire que
/// entre filas, y las filas no llevan divisores: la cercanía agrupa. Sin
/// cajas por ítem. Los números los pone la app; el texto es de Porty.
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

  /// El título grande ya salió de pantalla: la barra muestra el chico.
  bool _titleInBar = false;

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final inBar = n.metrics.pixels > _Header.largeTitleHeight;
    if (inBar != _titleInBar) setState(() => _titleInBar = inBar);
    return false;
  }

  Timer? _pushPrompt;

  @override
  void dispose() {
    _pushPrompt?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(weeklyReportControllerProvider.notifier).markSeen();
    });
    // La primera vez que lo lee, después de un rato (no al abrir): "¿te
    // avisamos los sábados?" (plan de push §6).
    if (_animate) {
      _pushPrompt = Timer(const Duration(seconds: 3), () {
        if (!mounted) return;
        PushPermissionSheet.maybeShow(
          context,
          ref,
          reason: PushPromptReason.weeklyReport,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Los logos de las filas usan la paleta del kit de Porty.
    QaColors.resolve(Theme.of(context).brightness);
    final reportState = ref.watch(weeklyReportControllerProvider);
    final report = reportState.report;
    final benchmark = ref.watch(weeklyReportBenchmarkAllowedProvider);
    return Scaffold(
      appBar: AppBar(
        title: AnimatedOpacity(
          opacity: _titleInBar ? 1 : 0,
          duration:
              MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 160),
          child: ExcludeSemantics(
            excluding: !_titleInBar,
            child: Text('weekly_report_title'.tr()),
          ),
        ),
      ),
      // Sin informe todavía (se abrió antes de que Porty terminara): Porty
      // pensando en vez de una pantalla en blanco.
      body: LoadingSwitcher(
        loading: report == null,
        placeholder:
            (_) => PortyLoader(
              message:
                  reportState.generating
                      ? 'weekly_report_preparing'.tr()
                      : 'loader_one_moment'.tr(),
            ),
        child:
            (_) =>
                report == null
                    ? const SizedBox.shrink()
                    : SafeArea(
                        top: false,
                        // Column y no ListView: son pocas secciones y así se
                        // construyen todas al abrir (la entrada escalonada pasa una
                        // vez; un ListView las armaba al scrollear y las re-animaba).
                        child: NotificationListener<ScrollNotification>(
                        onNotification: _onScroll,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(
                            AppDimens.pageHorizontal,
                            0,
                            AppDimens.pageHorizontal,
                            AppDimens.sp40,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final (i, section)
                                  in _sections(context, report, benchmark).indexed)
                                FadeSlideIn(
                                  delay: WeeklyReportScreen.stagger * i,
                                  duration: WeeklyReportScreen.entrance,
                                  skipAnimation: !_animate,
                                  child: section,
                                ),
                            ],
                          ),
                        ),
                        ),
                      ),
      ),
    );
  }

  List<Widget> _sections(BuildContext context, WeeklyReport r, bool benchmark) {
    final questions = r.hasProse ? WeeklyReportFormat.questions(r) : const <String>[];
    final why = [
      if (r.movers.isNotEmpty) _Movers(report: r),
      if (r.variant == WeeklyReportVariant.numbersLocked) const _GoldTeaser(),
      if (r.variant == WeeklyReportVariant.numbersUnavailable)
        _Prose('weekly_report_unavailable'.tr(), muted: true),
    ];
    final deeper = [
      if (r.news.isNotEmpty)
        _Section(
          title: 'weekly_report_news_section'.tr(),
          rows: [for (final n in r.news) _NewsRow(n)],
        ),
      if (r.investors.isNotEmpty)
        _Section(
          title: 'weekly_report_investors_section'.tr(),
          rows: [for (final i in r.investors) _InvestorRow(i)],
        ),
      if (r.learn != null)
        _Section(
          title: 'weekly_report_learn_section'.tr(),
          child: _Learn(r.learn!),
        ),
    ];
    return [
      _Header(report: r),
      _Group(
        first: true,
        children: [_Week(report: r, benchmark: benchmark)],
      ),
      if (why.isNotEmpty)
        _Group(children: why),
      if (r.upcomingEarnings.isNotEmpty)
        _Group(
          children: [
            _Section(
              title: 'weekly_report_upcoming_section'.tr(),
              rows: [for (final e in r.upcomingEarnings) _EarningsRow(e)],
            ),
          ],
        ),
      if (deeper.isNotEmpty)
        _Group(children: deeper),
      if (questions.isNotEmpty) _Group(children: [_Questions(questions)]),
      const _Disclaimer(),
    ];
  }
}

// ---------------------------------------------------------------------------
// A. Encabezado
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.report});
  final WeeklyReport report;

  /// Scroll a partir del cual el título grande ya no se ve y pasa a la
  /// barra (alto del título más la fecha, aproximado).
  static const largeTitleHeight = 56.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Título grande al estilo iOS: manda en la pantalla; al scrollear
        // queda la versión chica en la barra.
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'weekly_report_title'.tr(),
                      style: tt.displaySmall?.copyWith(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.8,
                        height: 1.1,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppDimens.sp4),
                  Text(
                    WeeklyReportFormat.range(context, report),
                    style: tt.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppDimens.sp12),
            const PortyAvatar(size: 48),
          ],
        ),
        const SizedBox(height: AppDimens.sp24),
        // Nivel 1: la frase de lectura. La misma voz que el saludo del
        // login: texto suelto, sin burbuja.
        Text(
          WeeklyReportFormat.reading(report),
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
          _Meta(
            'weekly_report_courtesy'.tr(),
            leading: PortySpark(size: 12, color: colors.accentBlue),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// B. El número de la semana + gráfico + mercado
// ---------------------------------------------------------------------------

class _Week extends ConsumerStatefulWidget {
  const _Week({required this.report, required this.benchmark});
  final WeeklyReport report;
  final bool benchmark;

  @override
  ConsumerState<_Week> createState() => _WeekState();
}

/// Recorriendo el gráfico, el número grande sigue al dedo (como en la
/// Home): cómo venía la cartera al cierre de ese día.
class _WeekState extends ConsumerState<_Week> {
  int? _scrub;

  void _onScrub(int? index) {
    if (index == _scrub) return;
    if (index != null) PortyHapticsService.maybeOf(context)?.scrubTick();
    setState(() => _scrub = index);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final r = widget.report;
    final benchmark = widget.benchmark;
    final tabular = const [FontFeature.tabularFigures()];
    final comparison = benchmark ? WeeklyReportFormat.comparison(r) : null;
    final day = _scrub == null ? null : r.daily[_scrub!];
    final pct = day?.portfolioPct ?? r.changePct;
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Meta(
            day == null
                ? 'weekly_report_this_week_label'.tr()
                : 'weekly_report_scrub_day'.tr(
                  namedArgs: {
                    'day': DateFormat(
                      'EEEE d',
                      Localizations.localeOf(context).toLanguageTag(),
                    ).format(day.day),
                  },
                ),
          ),
          const SizedBox(height: AppDimens.sp4),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: AppDimens.sp12,
            children: [
              Text(
                WeeklyReportFormat.pct(pct),
                style: tt.displaySmall?.copyWith(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  height: 1.05,
                  letterSpacing: -0.8,
                  color: colors.pnlColor(pct),
                  fontFeatures: tabular,
                ),
              ),
              // El monto es de la semana entera: recorriendo, solo el %.
              if (day == null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    WeeklyReportFormat.signedMoney(r.changeAbs),
                    style: tt.bodyLarge?.copyWith(
                      color: colors.textSecondary,
                      fontFeatures: tabular,
                    ),
                  ),
                ),
            ],
          ),
          if (r.daily.length >= 2) ...[
            const SizedBox(height: AppDimens.sp20),
            WeeklyReportChart(
              points: r.daily,
              showSp500: benchmark,
              scrubIndex: _scrub,
              onScrub: _onScrub,
            ),
          ],
          const SizedBox(height: AppDimens.sp16),
          if (comparison != null)
            _Prose(comparison)
          else if (!benchmark && r.sp500Pct != null)
            _LockedRow(
              text: 'weekly_report_sp500_locked'.tr(),
              onTap:
                  () => SubscriptionPaywallSheet.show(
                    context,
                    ref,
                    reason: PaywallReason.modeLocked,
                    source: 'weekly_report_sp500',
                  ),
            ),
          const SizedBox(height: AppDimens.sp8),
          // El total de la Home es al precio actual; este, al cierre.
          _Meta(
            'weekly_report_value_friday'.tr(
              namedArgs: {'amount': WeeklyReportFormat.money(r.valueEnd)},
            ),
          ),
          if (r.newMoney > 0) ...[
            const SizedBox(height: AppDimens.sp4),
            _Meta(
              'weekly_report_new_money'.tr(
                namedArgs: {'amount': WeeklyReportFormat.money(r.newMoney)},
              ),
            ),
          ],
          if (r.tradingDays > 0 && r.tradingDays < 5) ...[
            const SizedBox(height: AppDimens.sp4),
            _Meta(
              'weekly_report_short_week'.tr(
                namedArgs: {'days': '${r.tradingDays}'},
              ),
            ),
          ],
        ],
    );
  }
}

// ---------------------------------------------------------------------------
// C. Qué movió tu cartera
// ---------------------------------------------------------------------------

class _Movers extends ConsumerWidget {
  const _Movers({required this.report});
  final WeeklyReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Cada fila cuenta qué hizo la ACCIÓN en la semana (viernes contra
    // viernes), no cómo le fue a la posición del usuario: el número, la
    // barra y el orden miden lo mismo. De la que más subió a la que más
    // bajó (también en los informes ya guardados: el movimiento de la
    // acción siempre se guardó).
    final movers = [...report.movers]
      ..sort((a, b) => b.movePct.compareTo(a.movePct));
    final maxAbs = movers.map((m) => m.movePct.abs()).fold(0.0, math.max);
    final upMost =
        movers.length >= 2 && movers.first.movePct > 0 ? movers.first : null;
    final downMost =
        movers.length >= 2 && movers.last.movePct < 0 ? movers.last : null;
    final held = ref.watch(goalHoldingsProvider);
    final others = WeeklyReportFormat.others(report);
    return _Section(
      title: 'weekly_report_movers_section'.tr(),
      rows: [
        for (final (i, m) in movers.indexed)
          _MoverRow(
            mover: m,
            maxAbs: maxAbs,
            index: i,
            role:
                identical(m, upMost)
                    ? 'weekly_report_role_up_most'.tr()
                    : identical(m, downMost)
                    ? 'weekly_report_role_down_most'.tr()
                    : null,
            // Si todavía la tiene, la fila abre la posición.
            onTap:
                (held[m.ticker.toUpperCase()] ?? 0) > 0
                    ? () => GotoPositionDetail(
                      ticker: m.ticker,
                    ).navigate(context: context)
                    : null,
          ),
        if (others != null) _Meta(others),
      ],
    );
  }
}

class _MoverRow extends StatelessWidget {
  const _MoverRow({
    required this.mover,
    required this.maxAbs,
    required this.index,
    this.role,
    this.onTap,
  });
  final ReportMover mover;
  final double maxAbs;

  /// "La que más subió" / "La que más bajó", si es la de arriba o la de
  /// abajo de la lista.
  final String? role;

  /// Posición en la lista: las barras crecen una detrás de otra.
  final int index;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final m = mover;
    final pct = m.movePct;
    final role = this.role;
    final subtitle = [
      if (role != null) role,
      if (m.boughtThisWeek) 'weekly_report_bought_this_week'.tr(),
    ].join(' · ');

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            QaTickerAvatar(ticker: m.ticker, size: 32),
            const SizedBox(width: AppDimens.sp12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.ticker,
                    style: tt.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: tt.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            Text(
              WeeklyReportFormat.pct(pct),
              style: tt.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.pnlColor(pct),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (this.onTap != null) ...[
              const SizedBox(width: AppDimens.sp4),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: colors.textSecondary,
              ),
            ],
          ],
        ),
        const SizedBox(height: AppDimens.sp8),
        _GrowingImpactBar(
          contribution: pct,
          maxAbs: maxAbs,
          index: index,
        ),
        if (m.why != null) ...[
          const SizedBox(height: AppDimens.sp8),
          _Prose(m.why!),
        ],
        if (m.source != null)
          _SourceLink(
            source: m.source!.source,
            date: m.source!.date,
            url: m.source!.url,
          ),
      ],
    );
    final onTap = this.onTap;
    if (onTap == null) return content;
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        onTap: () {
          PortyHapticsService.maybeOf(context)?.selectionTap();
          onTap();
        },
        child: content,
      ),
    );
  }
}

/// La barra de cuánto se movió la acción en la semana, que crece desde el
/// centro la primera vez que se ve: una detrás de otra, de arriba hacia
/// abajo. Comunica cuánto subió o bajó cada una, no decora. Con reduce
/// motion, aparece completa.
class _GrowingImpactBar extends StatelessWidget {
  const _GrowingImpactBar({
    required this.contribution,
    required this.maxAbs,
    required this.index,
  });

  final double contribution;
  final double maxAbs;
  final int index;

  static const _grow = Duration(milliseconds: 420);
  static const _stagger = 70;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return WeeklyImpactBar(contribution: contribution, maxAbs: maxAbs);
    }
    final total = _grow.inMilliseconds + _stagger * index;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(
        _stagger * index / total,
        1,
        curve: Curves.easeOutQuart,
      ),
      builder:
          (context, t, _) =>
              WeeklyImpactBar(contribution: contribution * t, maxAbs: maxAbs),
    );
  }
}

class _GoldTeaser extends ConsumerWidget {
  const _GoldTeaser();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Semantics(
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
    );
  }
}

// ---------------------------------------------------------------------------
// D–G. Lo que viene, noticias, inversores, para aprender
// ---------------------------------------------------------------------------

class _EarningsRow extends StatelessWidget {
  const _EarningsRow(this.earnings);
  final ReportEarnings earnings;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final when = [
      WeeklyReportFormat.day(context, earnings.date),
      if (earnings.timingLabel != null) earnings.timingLabel!.toLowerCase(),
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'weekly_report_upcoming_row'.tr(
            namedArgs: {'ticker': earnings.ticker},
          ),
          style: tt.bodyMedium?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppDimens.sp2),
        _Meta(when),
        if (earnings.epsEstimate != null) ...[
          const SizedBox(height: AppDimens.sp4),
          _Prose(
            'weekly_report_eps_estimate'.tr(
              namedArgs: {
                'amount': WeeklyReportFormat.money(earnings.epsEstimate!),
              },
            ),
            muted: true,
          ),
        ],
      ],
    );
  }
}

class _NewsRow extends StatelessWidget {
  const _NewsRow(this.news);
  final ReportNews news;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TickerTag(news.ticker),
        const SizedBox(height: AppDimens.sp6),
        Text(
          news.title,
          style: tt.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
            color: colors.textPrimary,
            height: 1.4,
          ),
        ),
        _SourceLink(source: news.source, date: news.date, url: news.url),
      ],
    );
  }
}

class _InvestorRow extends StatelessWidget {
  const _InvestorRow(this.investor);
  final ReportInvestor investor;

  @override
  Widget build(BuildContext context) {
    final i = investor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (i.relatedTickers.isNotEmpty) ...[
          Wrap(
            spacing: AppDimens.sp6,
            children: [for (final t in i.relatedTickers) _TickerTag(t)],
          ),
          const SizedBox(height: AppDimens.sp6),
        ],
        _Prose(i.take),
        _SourceLink(
          source: i.isFiling ? _filingLabel(i.form) : (i.source ?? ''),
          date: i.date,
          url: i.url,
        ),
      ],
    );
  }
}

class _Learn extends StatelessWidget {
  const _Learn(this.learn);
  final ReportLearn learn;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          learn.concept,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: AppDimens.sp4),
        _Prose(learn.text),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// H–I. Seguir con Porty y disclaimer
// ---------------------------------------------------------------------------

class _Questions extends StatelessWidget {
  const _Questions(this.questions);
  final List<String> questions;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return _Section(
      title: 'weekly_report_follow_section'.tr(),
      child: Wrap(
        spacing: AppDimens.sp8,
        runSpacing: AppDimens.sp8,
        children: [
          for (final q in questions)
            Semantics(
              button: true,
              child: Material(
                color: colors.surfaceCard,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppDimens.radiusPill),
                  side: BorderSide(
                    color: colors.accentBlue.withValues(alpha: 0.45),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    PortyHapticsService.maybeOf(context)?.selectionTap();
                    GotoAssistant(
                      initialQuestion: q,
                    ).navigate(context: context);
                  },
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: AppDimens.touchTarget,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimens.sp16,
                        vertical: AppDimens.sp8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          PortySpark(size: 12, color: colors.accentBlue),
                          const SizedBox(width: AppDimens.sp6),
                          Flexible(
                            child: Text(
                              q,
                              style: tt.bodyMedium?.copyWith(
                                color: colors.textPrimary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: _Group.gap),
    child: _Meta('weekly_report_disclaimer'.tr()),
  );
}

// ---------------------------------------------------------------------------
// Piezas
// ---------------------------------------------------------------------------

/// Un grupo por pregunta del informe (cómo te fue, por qué, qué viene…):
/// mucho aire arriba y una línea fina de lado a lado. Es el único divisor de
/// la pantalla: separa grupos, nunca filas. Sin etiqueta en mayúsculas
/// arriba (el andamiaje "POR QUÉ / QUÉ VIENE" que DESIGN.md prohíbe): cada
/// sección ya trae su título.
class _Group extends StatelessWidget {
  const _Group({required this.children, this.first = false});

  final List<Widget> children;

  /// El primero va pegado al encabezado, sin línea.
  final bool first;

  static const gap = 48.0;

  /// Entre secciones de un mismo grupo.
  static const sectionGap = 36.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Padding(
      padding: EdgeInsets.only(top: first ? AppDimens.sp32 : gap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!first) ...[
            Divider(height: 1, thickness: 1, color: colors.border),
            const SizedBox(height: AppDimens.sp24),
          ],
          for (final (i, child) in children.indexed) ...[
            if (i > 0) const SizedBox(height: sectionGap),
            child,
          ],
        ],
      ),
    );
  }
}

/// Una sección dentro de un grupo: título (nivel 2, más grande que todo lo
/// que tiene adentro) y filas separadas solo por espacio.
class _Section extends StatelessWidget {
  const _Section({this.title, this.rows, this.child})
    : assert(rows != null || child != null);
  final String? title;
  final List<Widget>? rows;
  final Widget? child;

  static const rowGap = AppDimens.sp16;

  @override
  Widget build(BuildContext context) {
    final items = rows ?? [child!];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          _SectionTitle(title!),
          const SizedBox(height: AppDimens.sp16),
        ],
        for (final (i, item) in items.indexed) ...[
          if (i > 0) const SizedBox(height: rowGap),
          item,
        ],
      ],
    );
  }
}

/// Nivel 2: título de sección.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        height: 1.25,
        color: context.customColors.textPrimary,
      ),
    ),
  );
}

/// Nivel 3: cuerpo.
class _Prose extends StatelessWidget {
  const _Prose(this.text, {this.muted = false});
  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: muted ? colors.textSecondary : colors.textPrimary,
        height: 1.5,
      ),
    );
  }
}

/// Nivel 4: metadata (etiquetas, fuentes, notas).
class _Meta extends StatelessWidget {
  const _Meta(this.text, {this.leading});
  final String text;

  /// Glifo a la izquierda, alineado con la primera línea.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final label = Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: colors.textSecondary, height: 1.4),
    );
    final leading = this.leading;
    if (leading == null) return label;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(top: 3), child: leading),
        const SizedBox(width: AppDimens.sp6),
        Expanded(child: label),
      ],
    );
  }
}

/// El ticker como etiqueta aparte (no como prefijo del titular).
class _TickerTag extends StatelessWidget {
  const _TickerTag(this.ticker);
  final String ticker;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppDimens.radiusSm),
      ),
      child: Text(
        ticker,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colors.textSecondary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
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

/// "Reuters · jue 24 sept ↗": fuente tocable, en gris (no compite con el
/// contenido; el terracota queda para Porty y las preguntas).
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
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ),
              const SizedBox(width: AppDimens.sp4),
              Icon(
                Icons.north_east_rounded,
                size: 12,
                color: colors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "SEC · Form 4", "SEC · 13F-HR", "SEC · Schedule 13D".
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
