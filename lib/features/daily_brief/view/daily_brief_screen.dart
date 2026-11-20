import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/nav/assistant_nav.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_bundle.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_numbers.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_writer.dart';
import 'package:portfolio_assistant/features/daily_brief/providers/daily_brief_provider.dart';
import 'package:portfolio_assistant/features/daily_brief/view/daily_brief_format.dart';
import 'package:portfolio_assistant/features/daily_brief/view/widgets/daily_brief_feedback.dart';
import 'package:portfolio_assistant/features/display_currency/view/display_money_scope.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:portfolio_assistant/features/subscription/config/paywall_source.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_paywall_sheet.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/loading/loader_timing.dart';
import 'package:portfolio_assistant/presentation/shared/loading/porty_loader.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/news_headline_row.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/porty_says.dart';

/// El brief del día: ¿cómo cerró mi cartera?, ¿qué pesó?, ¿con qué noticias
/// coincidió? y ¿qué pasa en el mercado? Una sección sin nada que contar no
/// aparece, y nada se muestra sin medio y link. Los números los pone la app
/// (los mismos de la línea 1D de la Home); el texto es de Porty.
class DailyBriefScreen extends ConsumerStatefulWidget {
  const DailyBriefScreen({super.key, this.day, this.source = 'home'});

  /// `YYYY-MM-DD`; sin valor, el de hoy.
  final String? day;

  /// De dónde se abrió (`push` | `home` | `feed`), para el evento.
  final String source;

  @override
  ConsumerState<DailyBriefScreen> createState() => _DailyBriefScreenState();
}

class _DailyBriefScreenState extends ConsumerState<DailyBriefScreen> {
  bool _opened = false;

  void _logOpened(DailyBrief brief) {
    if (_opened) return;
    _opened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(productEventsProvider).log(ProductEvent.dailyBriefOpened, {
        'source': widget.source,
        'variant': brief.variant.name,
        'courtesy': brief.courtesy,
        'tier': ref.read(dailyBriefTierProvider).name,
      });
    });
  }

  void _tapped(String kind) => ref.read(productEventsProvider).log(
    ProductEvent.dailyBriefItemTapped,
    {'kind': kind},
  );

  void _read(String kind, BriefSource? source) {
    final uri = Uri.tryParse(source?.url ?? '');
    if (uri == null) return;
    _tapped(kind);
    ref.read(dailyBriefUrlLauncherProvider)(uri).catchError((_) => false);
  }

  void _ask(String question, {required String from}) {
    ref.read(productEventsProvider).log(ProductEvent.dailyBriefAskPorty, {
      'from': from,
    });
    GotoAssistant(initialQuestion: question).navigate(context: context);
  }

  void _askAffects(String title) {
    ref.read(productEventsProvider).log(ProductEvent.newsHowAffectsTapped, {
      'from': 'brief',
    });
    GotoAssistant(
      initialQuestion: 'daily_brief_ask_affects'.tr(
        namedArgs: {'title': title},
      ),
    ).navigate(context: context);
  }

  void _openPaywall() {
    PortyHapticsService.maybeOf(context)?.lockedTap();
    _tapped('teaser');
    SubscriptionPaywallSheet.show(
      context,
      ref,
      reason: PaywallReason.heldNews,
      source: PaywallSource.dailyBrief,
      onUpgraded: () => ref.read(subscriptionProvider.notifier).refresh(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dailyBriefControllerProvider);
    final today = DailyBriefNumbers.dayKey(DateTime.now());
    final wanted = widget.day ?? today;
    final brief = state.brief?.day == wanted ? state.brief : null;
    if (brief != null) _logOpened(brief);
    final loading = brief == null && state.phase == DailyBriefPhase.loading;
    return Scaffold(
      appBar: AppBar(),
      body: LoadingSwitcher(
        loading: loading,
        placeholder:
            (_) => PortyLoader(
              message:
                  state.generating
                      ? 'daily_brief_generating'.tr()
                      : 'loader_one_moment'.tr(),
            ),
        child:
            (_) =>
                brief == null
                    ? _Empty(
                      failed: state.failed,
                      onRetry:
                          () =>
                              ref
                                  .read(dailyBriefControllerProvider.notifier)
                                  .retry(),
                    )
                    : SafeArea(
                      top: false,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(
                          AppDimens.pageHorizontal,
                          0,
                          AppDimens.pageHorizontal,
                          AppDimens.sp40,
                        ),
                        child: _Body(
                          brief: brief,
                          feedAvailable: ref.watch(newsFeedAvailableProvider),
                          onRead: _read,
                          onAskAffects: _askAffects,
                          onAskPorty:
                              () => _ask(
                                'daily_brief_ask_question'.tr(),
                                from: 'footer',
                              ),
                          onTeaser: _openPaywall,
                          onSeeAll: () => _tapped('see_all'),
                        ),
                      ),
                    ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.brief,
    required this.feedAvailable,
    required this.onRead,
    required this.onAskAffects,
    required this.onAskPorty,
    required this.onTeaser,
    required this.onSeeAll,
  });

  final DailyBrief brief;
  final bool feedAvailable;
  final void Function(String kind, BriefSource? source) onRead;
  final void Function(String title) onAskAffects;
  final VoidCallback onAskPorty;
  final VoidCallback onTeaser;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final n = brief.numbers;
    final whyByTicker = <String, List<BriefLine>>{};
    for (final w in brief.why) {
      whyByTicker.putIfAbsent(w.ticker, () => []).add(w);
    }
    final moverTickers = {for (final m in n.movers) m.ticker};
    final extraWhy = [
      for (final w in brief.why)
        if (!moverTickers.contains(w.ticker)) w,
    ];

    Widget newsRow(BriefLine line, String kind, {bool withTicker = true}) {
      final source = brief.sourceOf(line.newsId);
      return NewsHeadlineRow(
        meta:
            source == null
                ? null
                : DailyBriefFormat.sourceLine(
                  source,
                  ticker: withTicker ? line.ticker : null,
                  now: now,
                ),
        title: line.text,
        actions: NewsHeadlineActions(
          readLabel:
              source == null
                  ? null
                  : 'daily_brief_read_on'.tr(
                    namedArgs: {'source': source.source},
                  ),
          onRead: () => onRead(kind, source),
          askLabel: 'daily_brief_how_affects'.tr(),
          onAsk: () => onAskAffects(source?.title ?? line.text),
        ),
      );
    }

    final sections = <Widget>[
      _Header(brief: brief),
      const SizedBox(height: AppDimens.sp24),
      _Hero(brief: brief),
      if (n.movers.isNotEmpty || extraWhy.isNotEmpty)
        _Section(
          title: 'daily_brief_section_weighed'.tr(),
          children: [
            for (final m in n.movers) ...[
              _MoverRow(mover: m),
              for (final w in whyByTicker[m.ticker] ?? const <BriefLine>[])
                newsRow(w, 'why', withTicker: false),
            ],
            for (final w in extraWhy) newsRow(w, 'why'),
          ],
        ),
      if (brief.heldNews.isNotEmpty)
        _Section(
          title: 'daily_brief_section_held'.tr(),
          children: [for (final l in brief.heldNews) newsRow(l, 'headline')],
        ),
      if (brief.watchNews.isNotEmpty)
        _Section(
          title: 'daily_brief_section_watch'.tr(),
          children: [for (final l in brief.watchNews) newsRow(l, 'watch')],
        ),
      if (brief.market.isNotEmpty)
        _Section(
          title: 'daily_brief_section_market'.tr(),
          children: [for (final m in brief.market) _marketRow(context, m, now)],
        ),
      if (brief.earnings.isNotEmpty)
        _Section(
          title: 'daily_brief_section_earnings'.tr(),
          children: [
            for (final e in brief.earnings)
              _EarningsRow(
                earning: e,
                onOpen:
                    () => onRead(
                      'earnings',
                      BriefSource(
                        title: e.ticker,
                        source: 'SEC',
                        domain: 'sec.gov',
                        url: e.url ?? '',
                      ),
                    ),
              ),
          ],
        ),
      if (brief.signals.any((s) => s.kind == 'concentration'))
        _Section(
          title: 'daily_brief_section_signals'.tr(),
          children: [
            for (final s in brief.signals)
              if (s.kind == 'concentration' &&
                  s.ticker != null &&
                  s.weightPct != null)
                _Prose(
                  'daily_brief_signal_concentration'.tr(
                    namedArgs: {
                      'ticker': s.ticker!,
                      'pct': DailyBriefFormat.weight(s.weightPct!),
                    },
                  ),
                ),
          ],
        ),
      if (brief.teaser != null) _Teaser(onTap: onTeaser),
      _Footer(
        brief: brief,
        feedAvailable: feedAvailable,
        onAskPorty: onAskPorty,
        onSeeAll: onSeeAll,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: sections,
    );
  }

  Widget _marketRow(BuildContext context, BriefMarketLine m, DateTime now) {
    final source = brief.sourceOf(m.sourceIds.firstOrNull);
    return NewsHeadlineRow(
      meta:
          source == null ? null : DailyBriefFormat.sourceLine(source, now: now),
      title: m.text,
      detail: m.connection,
      actions: NewsHeadlineActions(
        readLabel:
            source == null
                ? null
                : 'daily_brief_read_on'.tr(
                  namedArgs: {'source': source.source},
                ),
        onRead: () => onRead('macro', source),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.brief});
  final DailyBrief brief;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final date = DateTime.tryParse(brief.day);
    final courtesyText =
        !brief.courtesy
            ? null
            : brief.courtesyNumber != null && brief.courtesyTotal != null
            ? 'daily_brief_courtesy_n'.tr(
              namedArgs: {
                'n': '${brief.courtesyNumber}',
                'total': '${brief.courtesyTotal}',
              },
            )
            : 'daily_brief_courtesy'.tr();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            'daily_brief_title'.tr(),
            style: tt.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: colors.textPrimary,
            ),
          ),
        ),
        if (date != null) ...[
          const SizedBox(height: AppDimens.sp4),
          Text(
            DailyBriefFormat.day(context, date),
            style: tt.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
        ],
        if (courtesyText != null) ...[
          const SizedBox(height: AppDimens.sp12),
          PortySays(
            messageKey: 'courtesy',
            mood: PortyAvatarState.answered,
            message: Text(courtesyText, style: PortySays.style(context)),
          ),
        ],
      ],
    );
  }
}

/// El número del día: variación del último cierre, en grande, con el monto
/// en la moneda que eligió (igual que la Home).
class _Hero extends StatelessWidget {
  const _Hero({required this.brief});
  final DailyBrief brief;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final n = brief.numbers;
    final asOf = n.asOfDay;
    final money = DisplayMoneyScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          DailyBriefFormat.pct(n.pct),
          style: tt.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -1,
            color: colors.pnlColor(n.pct),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: AppDimens.sp4),
        Text(
          'daily_brief_amount_closed'.tr(
            namedArgs: {'amount': money.signedMoney(n.abs)},
          ),
          style: tt.titleSmall?.copyWith(
            color: colors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (asOf != null)
          Text(
            'daily_brief_closing_of'.tr(
              namedArgs: {'date': DailyBriefFormat.day(context, asOf)},
            ),
            style: tt.bodySmall?.copyWith(color: colors.textSecondary),
          ),
      ],
    );
  }
}

class _MoverRow extends StatelessWidget {
  const _MoverRow({required this.mover});
  final BriefMover mover;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final money = DisplayMoneyScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppDimens.sp12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  mover.ticker,
                  style: tt.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              Text(
                DailyBriefFormat.pct(mover.pct),
                style: tt.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.pnlColor(mover.pct),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          Text(
            'daily_brief_mover_detail'.tr(
              namedArgs: {
                'contribution': money.signedMoney(mover.contributionAbs),
                'weight': DailyBriefFormat.weight(mover.weightPct),
              },
            ),
            style: tt.bodySmall?.copyWith(
              color: colors.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _EarningsRow extends StatelessWidget {
  const _EarningsRow({required this.earning, required this.onOpen});
  final BriefEarning earning;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final hasLink = earning.reported && (earning.url ?? '').isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.sp8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DailyBriefFormat.earnings(context, earning),
            style: tt.bodyLarge?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          if (!earning.reported)
            Text(
              'daily_brief_estimated'.tr(),
              style: tt.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          if (hasLink)
            TextButton(
              onPressed: onOpen,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, AppDimens.touchTarget),
                padding: EdgeInsets.zero,
                foregroundColor: colors.accentBlue,
              ),
              child: Text('daily_brief_earnings_source'.tr()),
            ),
        ],
      ),
    );
  }
}

/// El aviso de plan de Free: dice qué trae el plan siguiente, sin ticker ni
/// cifras de lo que se pierde.
class _Teaser extends StatelessWidget {
  const _Teaser({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: _Section.gap),
      child: Semantics(
        button: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          onTap: onTap,
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
                          'daily_brief_teaser_premium'.tr(),
                          style: tt.bodyMedium?.copyWith(
                            color: colors.textPrimary,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: AppDimens.sp4),
                        Text(
                          'daily_brief_teaser_cta'.tr(),
                          style: tt.labelLarge?.copyWith(
                            color: colors.accentBlue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
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

class _Footer extends ConsumerWidget {
  const _Footer({
    required this.brief,
    required this.feedAvailable,
    required this.onAskPorty,
    required this.onSeeAll,
  });

  final DailyBrief brief;
  final bool feedAvailable;
  final VoidCallback onAskPorty;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: _Section.gap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(height: 1, thickness: 1, color: colors.border),
          const SizedBox(height: AppDimens.sp16),
          Text(
            DailyBriefFormat.asOf(context, brief.asOf),
            style: tt.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          Text(
            'daily_brief_footer_disclaimer'.tr(),
            style: tt.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppDimens.sp16),
          Align(
            alignment: Alignment.centerLeft,
            child: NewsHeadlineActions(
              askLabel: 'daily_brief_ask_porty'.tr(),
              onAsk: onAskPorty,
            ),
          ),
          const SizedBox(height: AppDimens.sp16),
          DailyBriefFeedback(
            onAnswer:
                (useful, reason) => ref.read(productEventsProvider).log(
                  ProductEvent.dailyBriefFeedback,
                  {'useful': useful, if (reason != null) 'reason': reason},
                ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  static const gap = 36.0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: gap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                height: 1.25,
                color: context.customColors.textPrimary,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _Prose extends StatelessWidget {
  const _Prose(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppDimens.sp12),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
        color: context.customColors.textPrimary,
        height: 1.4,
      ),
    ),
  );
}

/// Sin brief de hoy (o no se pudo armar): Porty lo dice, sin caja vacía.
class _Empty extends StatelessWidget {
  const _Empty({required this.failed, required this.onRetry});
  final bool failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(AppDimens.pageHorizontal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PortySays(
            messageKey: failed ? 'error' : 'empty',
            mood: failed ? PortyAvatarState.concerned : PortyAvatarState.idle,
            message: Text(
              (failed ? 'daily_brief_error_title' : 'daily_brief_empty_title')
                  .tr(),
              style: PortySays.style(context),
            ),
          ),
          const SizedBox(height: AppDimens.sp12),
          Text(
            (failed ? 'daily_brief_error_body' : 'daily_brief_empty_body').tr(),
            style: tt.bodyMedium?.copyWith(
              color: colors.textSecondary,
              height: 1.4,
            ),
          ),
          if (failed) ...[
            const SizedBox(height: AppDimens.sp16),
            NewsHeadlineActions(readLabel: 'retry'.tr(), onRead: onRetry),
          ],
        ],
      ),
    );
  }
}
