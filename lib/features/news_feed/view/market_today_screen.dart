import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/daily_brief/view/daily_brief_format.dart';
import 'package:portfolio_assistant/features/home_widget/view/widget_news_sheet.dart';
import 'package:portfolio_assistant/features/news_feed/domain/news_bundle.dart';
import 'package:portfolio_assistant/features/news_feed/providers/news_feed_provider.dart';
import 'package:portfolio_assistant/features/news_feed/view/news_actions.dart';
import 'package:portfolio_assistant/features/news_feed/view/widgets/news_article_row.dart';
import 'package:portfolio_assistant/features/news_feed/view/widgets/news_states.dart';
import 'package:portfolio_assistant/features/news_feed/view/widgets/news_video_sheet.dart';
import 'package:portfolio_assistant/features/news_feed/view/widgets/news_videos_section.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/formatting/app_number_format.dart';
import 'package:portfolio_assistant/presentation/shared/loading/loader_timing.dart';
import 'package:portfolio_assistant/presentation/shared/loading/porty_loader.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/news_headline_row.dart';

/// "Mercado hoy" con ruta propia. El contenido es [MarketTodayBody], el mismo
/// de la pestaña del feed.
class MarketTodayScreen extends ConsumerStatefulWidget {
  const MarketTodayScreen({super.key, this.source = 'route'});

  /// De dónde se abrió (prop `source` de `market_today_opened`).
  final String source;

  @override
  ConsumerState<MarketTodayScreen> createState() => _MarketTodayScreenState();
}

class _MarketTodayScreenState extends ConsumerState<MarketTodayScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(productEventsProvider).log(ProductEvent.marketTodayOpened, {
        'source': widget.source,
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('market_today_title'.tr())),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.pageHorizontal,
            AppDimens.sp8,
            AppDimens.pageHorizontal,
            AppDimens.sp40,
          ),
          child: const MarketTodayBody(),
        ),
      ),
    );
  }
}

/// Primero el "por qué" en prosa, con medio y link; después las referencias
/// en el orden del catálogo (nunca por tamaño del movimiento) y sin colores
/// de alarma; al final los videos del mercado.
class MarketTodayBody extends ConsumerStatefulWidget {
  const MarketTodayBody({super.key});

  @override
  ConsumerState<MarketTodayBody> createState() => _MarketTodayBodyState();
}

class _MarketTodayBodyState extends ConsumerState<MarketTodayBody> {
  @override
  void initState() {
    super.initState();
    // Ya cargado antes (el feed lo trajo): se refresca sin borrar lo que hay.
    Future.microtask(() {
      if (!mounted) return;
      if (ref.read(marketTodayProvider).phase != NewsLoadPhase.loading) {
        ref.read(marketTodayProvider.notifier).load();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(marketTodayProvider);
    final bundle = state.bundle;
    return LoadingSwitcher(
      loading: bundle == null && state.phase == NewsLoadPhase.loading,
      placeholder: (_) => const SizedBox(height: 240, child: PortyLoader()),
      child: (context) {
        if (state.disabled) {
          return NewsMessage(
            messageKey: 'market_off',
            text: 'market_today_error'.tr(),
          );
        }
        if (bundle == null) {
          return NewsMessage(
            messageKey: 'market_error',
            failed: true,
            text: 'market_today_error'.tr(),
            actionLabel: 'retry'.tr(),
            onAction: () => ref.read(marketTodayProvider.notifier).load(),
          );
        }
        return _Loaded(bundle: bundle);
      },
    );
  }
}

class _Loaded extends ConsumerWidget {
  const _Loaded({required this.bundle});
  final NewsBundle bundle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final now = DateTime.now();
    final empty = bundle.pulse.isEmpty && bundle.instruments.isEmpty;
    final asOf = bundle.asOf;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (empty && bundle.videos.isEmpty)
          NewsMessage(
            messageKey: 'market_empty',
            text: 'market_today_empty'.tr(),
          ),
        if (bundle.pulse.isNotEmpty) ...[
          NewsSectionTitle('market_today_why_title'.tr()),
          for (final fact in bundle.pulse)
            Builder(
              builder: (context) {
                final source = bundle.sourceOf(fact.sourceIds);
                final published = source?.publishedAt;
                return NewsHeadlineRow(
                  meta:
                      source == null
                          ? null
                          : [
                            source.source,
                            if (published != null)
                              WidgetNewsSheet.ageLabel(published, now),
                          ].join(' · '),
                  title: fact.text,
                  actions:
                      source == null
                          ? null
                          : NewsHeadlineActions(
                            readLabel: 'news_feed_read_on'.tr(
                              namedArgs: {'source': source.source},
                            ),
                            onRead:
                                () => NewsActions.read(
                                  ref,
                                  source.url,
                                  kind: 'market',
                                ),
                          ),
                );
              },
            ),
        ],
        if (bundle.instruments.isNotEmpty) ...[
          if (bundle.pulse.isNotEmpty) newsBlockGap,
          NewsSectionTitle('market_today_instruments_title'.tr()),
          const SizedBox(height: AppDimens.sp8),
          for (var i = 0; i < bundle.instruments.length; i++) ...[
            if (i > 0) const NewsDivider(),
            _InstrumentRow(instrument: bundle.instruments[i]),
          ],
        ],
        if (bundle.videos.isNotEmpty) ...[
          newsBlockGap,
          NewsVideosSection(
            videos: bundle.videos,
            onOpen: (video) {
              NewsActions.videoOpened(ref, video);
              NewsVideoSheet.show(context, video);
            },
          ),
        ],
        if (asOf != null) ...[
          const SizedBox(height: AppDimens.sp24),
          Text(
            DailyBriefFormat.asOf(context, asOf),
            style: tt.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ],
        const NewsDisclaimer(),
      ],
    );
  }
}

class _InstrumentRow extends StatelessWidget {
  const _InstrumentRow({required this.instrument});
  final NewsInstrument instrument;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final pct = instrument.pct;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppDimens.sp12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                instrument.label,
                style: tt.bodyLarge?.copyWith(color: colors.textPrimary),
              ),
            ),
            Text(
              pct == null ? '—' : AppNumberFormat.percent(pct),
              style: tt.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: pct == null ? colors.textSecondary : colors.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
