import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief.dart';
import 'package:portfolio_assistant/features/daily_brief/nav/daily_brief_router.dart';
import 'package:portfolio_assistant/features/daily_brief/providers/daily_brief_provider.dart';
import 'package:portfolio_assistant/features/daily_brief/view/daily_brief_format.dart';
import 'package:portfolio_assistant/features/home_widget/view/widget_news_sheet.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/motion_aware_size.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/news_chips.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/news_image.dart';

/// Una de las notas que la tarjeta muestra: el titular del medio, su ticker
/// (si es de la cartera), el medio y la foto.
class TodayNote {
  const TodayNote({
    required this.title,
    required this.source,
    this.ticker,
    this.publishedAt,
    this.imageUrl,
  });

  final String title;
  final String source;
  final String? ticker;
  final DateTime? publishedAt;
  final String? imageUrl;

  /// Las notas de la cartera del brief con su medio, sin repetir, en el orden
  /// del brief: primero las que explican lo que se movió, después los
  /// titulares de las posiciones y al final los de la watchlist.
  static List<TodayNote> allOf(DailyBrief brief) {
    final seen = <String>{};
    final notes = <TodayNote>[];
    for (final line in [...brief.why, ...brief.heldNews, ...brief.watchNews]) {
      final id = line.newsId;
      final source = brief.sourceOf(id);
      if (id == null || source == null || !seen.add(id)) continue;
      notes.add(
        TodayNote(
          title: source.title.trim().isEmpty ? line.text : source.title,
          source: source.source,
          ticker: line.ticker.isEmpty ? null : line.ticker,
          publishedAt: source.publishedAt,
          imageUrl: source.imageUrl,
        ),
      );
    }
    return notes;
  }
}

/// "Hoy en tu cartera": la tarjeta destacada de la Home, debajo del valor de
/// la cartera. Superficie oscura con Porty (cara según cómo cerró el día), su
/// frase, las dos notas principales y "Leer mi brief".
///
/// Cuándo aparece (decisión de producto, simple y coherente con el brief):
/// - Con el interruptor `daily_brief` apagado, sin cartera, en fin de semana,
///   en un día sin cierre nuevo o sin respuesta del servidor
///   (`DailyBriefPhase.hidden`): **no ocupa lugar**. No se muestra "la última
///   nota" de otro día: la tarjeta es de *hoy*; el resto de las noticias
///   están en la pestaña Noticias.
/// - Mientras se calcula (o Porty escribe): Porty pensando y "estoy
///   preparando tu brief", sin botón.
/// - Con brief: frase, hasta 2 notas y el botón. Sin notas (plan Free, día
///   sin titulares), Porty cuenta cómo cerró la cartera y queda el botón.
class DailyBriefTodayCard extends ConsumerStatefulWidget {
  const DailyBriefTodayCard({
    super.key,
    required this.history,
    required this.lots,
  });

  /// El historial de la Home (`HomeState.history`): de ahí sale el número.
  final List<PortfolioHistoryPoint> history;

  /// Las compras de la cartera (de `PortfolioSummary.lots`).
  final List<Position> lots;

  /// Cuántas notas se muestran.
  static const maxNotes = 2;

  @override
  ConsumerState<DailyBriefTodayCard> createState() =>
      _DailyBriefTodayCardState();
}

class _DailyBriefTodayCardState extends ConsumerState<DailyBriefTodayCard> {
  @override
  void initState() {
    super.initState();
    _ensure();
  }

  @override
  void didUpdateWidget(DailyBriefTodayCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.lots, widget.lots) ||
        !identical(oldWidget.history, widget.history)) {
      _ensure();
    }
  }

  /// Después del frame: un provider no se modifica en medio de un build.
  void _ensure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(dailyBriefControllerProvider.notifier)
          .ensureFor(widget.history, widget.lots);
    });
  }

  void _open(DailyBrief brief) {
    PortyHapticsService.maybeOf(context)?.selectionTap();
    context.pushNamed(
      DailyBriefRouter.routeName,
      extra: DailyBriefRouter.args(day: brief.day, source: 'home'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dailyBriefControllerProvider);
    if (state.phase == DailyBriefPhase.hidden) return const SizedBox.shrink();
    final brief = state.phase == DailyBriefPhase.ready ? state.brief : null;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageHorizontal,
        0,
        AppDimens.pageHorizontal,
        AppDimens.sectionGap,
      ),
      child: MotionAwareSize(
        duration: const Duration(milliseconds: 220),
        child: AnimatedSwitcher(
          duration:
              reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
          child: KeyedSubtree(
            key: ValueKey(brief == null ? 'loading' : 'ready-${brief.day}'),
            child:
                brief == null
                    ? const _TodayShell(child: _Preparing())
                    : _TodayShell(
                      child: _Ready(brief: brief, onOpen: () => _open(brief)),
                    ),
          ),
        ),
      ),
    );
  }
}

/// La superficie oscura de la tarjeta (token `inverse`: tinta en claro, un
/// escalón sobre la card en oscuro). Plana, sin sombra.
class _TodayShell extends StatelessWidget {
  const _TodayShell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDimens.cardPadding),
      decoration: BoxDecoration(
        color: colors.inverse,
        borderRadius: BorderRadius.circular(AppDimens.radiusXl),
        border: Border.all(color: colors.inverseLine),
      ),
      child: child,
    );
  }
}

class _Preparing extends StatelessWidget {
  const _Preparing();

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Semantics(
      liveRegion: true,
      child: Row(
        children: [
          const ExcludeSemantics(
            child: PortyAvatar(
              size: 44,
              state: PortyAvatarState.thinking,
              animated: true,
            ),
          ),
          const SizedBox(width: AppDimens.sp12),
          Expanded(
            child: Text(
              'daily_brief_home_preparing'.tr(),
              style: tt.bodyLarge?.copyWith(
                color: colors.onInverse,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Ready extends StatelessWidget {
  const _Ready({required this.brief, required this.onOpen});

  final DailyBrief brief;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final all = TodayNote.allOf(brief);
    final notes = all.take(DailyBriefTodayCard.maxNotes).toList();
    final minutes = DailyBriefFormat.readMinutes(brief);
    final phraseStyle = tt.bodyLarge?.copyWith(
      fontSize: 19,
      fontWeight: FontWeight.w500,
      height: 1.4,
      letterSpacing: -0.2,
      color: colors.onInverse,
    );
    final bold = const TextStyle(fontWeight: FontWeight.w700);
    final phrase =
        all.isEmpty
            ? 'today_card_phrase_none'.tr(
              namedArgs: {'pct': DailyBriefFormat.pct(brief.numbers.pct)},
            )
            : (all.length == 1 ? 'today_card_phrase_one' : 'today_card_phrase')
                .tr(namedArgs: {'n': '${all.length}'});
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: PortyAvatar(
                size: 44,
                state: DailyBriefFormat.moodOf(brief.numbers.pct),
                animated: true,
              ),
            ),
            const SizedBox(width: AppDimens.sp12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'today_card_eyebrow'.tr(namedArgs: {'min': '$minutes'}),
                    style: tt.labelMedium?.copyWith(
                      color: colors.accentWarm,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: AppDimens.sp4),
                  Semantics(
                    liveRegion: true,
                    child: Text.rich(
                      TextSpan(
                        children: DailyBriefFormat.markedSpans(phrase, bold),
                      ),
                      style: phraseStyle,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        for (var i = 0; i < notes.length; i++) ...[
          i == 0
              ? const SizedBox(height: AppDimens.sp16)
              : Padding(
                padding: const EdgeInsets.symmetric(vertical: AppDimens.sp12),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: colors.inverseLine,
                ),
              ),
          _NoteRow(note: notes[i], now: now, onTap: onOpen),
        ],
        const SizedBox(height: AppDimens.sp16),
        _ReadButton(onTap: onOpen),
      ],
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({required this.note, required this.now, required this.onTap});

  final TodayNote note;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final published = note.publishedAt;
    final meta = [
      note.source,
      if (published != null) WidgetNewsSheet.ageLabel(published, now),
    ].join(' · ');
    final hasPhoto = NewsPhoto.usable(note.imageUrl);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDimens.radiusMd),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (hasPhoto) ...[
              NewsPhoto(
                url: note.imageUrl,
                width: 64,
                height: 64,
                radius: AppDimens.radiusMd,
              ),
              const SizedBox(width: AppDimens.sp12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (note.ticker != null) TickerChip(note.ticker!),
                      Text(
                        meta,
                        style: tt.bodySmall?.copyWith(
                          color: colors.onInverseMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppDimens.sp4),
                  Text(
                    note.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: tt.titleSmall?.copyWith(
                      color: colors.onInverse,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadButton extends StatelessWidget {
  const _ReadButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Semantics(
      button: true,
      onTapHint: 'daily_brief_home_open_hint'.tr(),
      excludeSemantics: true,
      label: 'today_card_cta'.tr(),
      child: Material(
        color: colors.accentWarm,
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          child: SizedBox(
            height: 48,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'today_card_cta'.tr(),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colors.inverse,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: AppDimens.sp8),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: colors.inverse,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
