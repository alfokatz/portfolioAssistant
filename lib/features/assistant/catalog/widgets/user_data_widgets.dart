import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_evidence_scope.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_identity.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_primitives.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/qa_card_shell.dart';
import 'package:portfolio_assistant/features/assistant/data/user/user_data_cards.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';
import 'package:portfolio_assistant/features/watchlist/nav/watchlist_router.dart';
import 'package:portfolio_assistant/features/weekly_report/nav/weekly_report_router.dart';

/// Cards de lo que el usuario tiene armado en la app (lista de
/// seguimiento, informe semanal). Como `QaAllocationPlan`: el modelo no
/// pasa datos; todo sale del resultado de la tool del turno.
abstract final class UserDataWidgets {
  static Widget qaWatchlist(CatalogItemContext ctx) => _fromEvidence(
    ctx,
    (evidence) => switch (WatchlistCardData.from(evidence)) {
      final data? => _WatchlistBody(data: data, ctx: ctx),
      null => null,
    },
  );

  static Widget qaWeeklyReport(CatalogItemContext ctx) => _fromEvidence(
    ctx,
    (evidence) => switch (WeeklyReportCardData.from(evidence)) {
      final data? => _WeeklyReportBody(data: data, ctx: ctx),
      null => null,
    },
  );

  /// Sin el resultado de la tool no se dibuja nada (el chequeo de grounding
  /// ya rechaza esa respuesta).
  static Widget _fromEvidence(
    CatalogItemContext ctx,
    Widget? Function(TurnEvidence evidence) body,
  ) => Builder(
    builder:
        (context) => ValueListenableBuilder<TurnEvidence>(
          valueListenable: QaEvidenceScope.listenableOf(context, ctx.surfaceId),
          builder: (context, evidence, _) {
            final child = body(evidence);
            return child == null
                ? const SizedBox.shrink()
                : QaCardShell(child: child);
          },
        ),
  );
}

/// "Ver …" al pie de la card, si hay router (en tests aislados no).
class _OpenLink extends StatelessWidget {
  const _OpenLink({required this.label, required this.routeName});

  final String label;
  final String routeName;

  @override
  Widget build(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    if (router == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: QaSpace.sectionGap),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () => router.pushNamed(routeName),
          style: TextButton.styleFrom(
            foregroundColor: QaColors.accentBlue,
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 40),
          ),
          child: Text(label, style: QaText.bodyStrong),
        ),
      ),
    );
  }
}

class _WatchlistBody extends StatelessWidget {
  const _WatchlistBody({required this.data, required this.ctx});

  final WatchlistCardData data;
  final CatalogItemContext ctx;

  @override
  Widget build(BuildContext context) {
    final items = data.items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QaCardTitle(
          title: 'qa_ud_watchlist'.tr(),
          icon: Icons.visibility_outlined,
          trailing: QaTag(QaFormat.units(items.length, 'qa_unit_tickers')),
        ),
        const SizedBox(height: QaSpace.sectionGap),
        for (final (i, item) in items.indexed) ...[
          if (i > 0) const SizedBox(height: QaSpace.rowGap),
          QaTappable(
            question: 'qa_ud_watch_q'.tr(namedArgs: {'ticker': item.ticker}),
            child: _WatchRow(item: item),
          ),
        ],
        _OpenLink(
          label: 'qa_ud_view_list'.tr(),
          routeName: WatchlistRouter.routeName,
        ),
        QaFollowUpBar(
          surfaceId: ctx.surfaceId,
          items: [
            QaFollowUp(
              'qa_ud_follow_other'.tr(),
              'qa_ud_follow_other_q'.tr(),
              icon: Icons.add_rounded,
            ),
            QaFollowUp(
              'qa_ud_alert'.tr(),
              'qa_ud_alert_q'.tr(),
              icon: Icons.notifications_active_outlined,
            ),
          ],
        ),
      ],
    );
  }
}

class _WatchRow extends StatelessWidget {
  const _WatchRow({required this.item});

  final WatchlistCardItem item;

  @override
  Widget build(BuildContext context) {
    final since = item.sinceAddedPct;
    final day = item.dayPct;
    final price = item.price;
    return QaBrandBuilder(
      ticker: item.ticker,
      builder:
          (context, brand) => Row(
            children: [
              QaTickerAvatar(ticker: item.ticker, size: 36, brand: brand),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(item.ticker, style: QaText.bodyStrong),
                        if (!item.alertsOn) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.notifications_off_outlined,
                            size: 14,
                            color: QaColors.textSecondary,
                          ),
                        ],
                      ],
                    ),
                    Text(
                      since == null
                          ? (brand.name ?? '')
                          : 'qa_ud_since_added'.tr(
                            namedArgs: {
                              'pct': QaFormat.signedPct(since, digits: 1),
                            },
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: QaText.label.copyWith(
                        color:
                            since == null
                                ? QaColors.textSecondary
                                : QaPalette.trend(since),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    price == null ? '—' : QaFormat.price(price),
                    style: QaText.valueSm,
                  ),
                  if (day != null) ...[
                    const SizedBox(height: 4),
                    QaDeltaChip(value: day, digits: 1, dense: true),
                  ],
                ],
              ),
            ],
          ),
    );
  }
}

class _WeeklyReportBody extends StatelessWidget {
  const _WeeklyReportBody({required this.data, required this.ctx});

  final WeeklyReportCardData data;
  final CatalogItemContext ctx;

  static const _shownMovers = 3;

  /// "Semana del 19 de octubre".
  String get _week {
    final d = DateTime.tryParse(data.weekStart);
    if (d == null) return 'qa_ud_this_week'.tr();
    return 'qa_ud_week_of'.tr(
      namedArgs: {'day': '${d.day}', 'month': 'qa_month_long_${d.month}'.tr()},
    );
  }

  @override
  Widget build(BuildContext context) {
    final sp = data.sp500Pct;
    final movers = data.movers.take(_shownMovers).toList();
    final reading = data.reading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QaCardTitle(
          title: 'qa_ud_weekly_title'.tr(),
          icon: Icons.auto_awesome_outlined,
          subtitle: _week,
        ),
        const SizedBox(height: QaSpace.sectionGap),
        Text(QaFormat.signedMoney(data.changeAbs), style: QaText.display),
        const SizedBox(height: 8),
        Row(
          children: [
            QaDeltaChip(value: data.changePct, digits: 1),
            if (sp != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'qa_ud_sp500'.tr(
                    namedArgs: {'pct': QaFormat.signedPct(sp, digits: 1)},
                  ),
                  style: QaText.label,
                ),
              ),
            ],
          ],
        ),
        if (movers.isNotEmpty)
          QaSection(
            title: 'qa_ud_top_movers'.tr(),
            child: Column(
              children: [
                for (final (i, m) in movers.indexed) ...[
                  if (i > 0) const SizedBox(height: QaSpace.rowGap),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      QaTickerAvatar(ticker: m.ticker, size: 32),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.ticker, style: QaText.bodyStrong),
                            if (m.why != null)
                              Text(
                                m.why!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: QaText.label,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      QaDeltaChip(value: m.movePct, digits: 1, dense: true),
                    ],
                  ),
                ],
              ],
            ),
          ),
        if (reading != null && reading.trim().isNotEmpty)
          QaSection(
            title: 'qa_ud_porty_says'.tr(),
            child: Text(reading, style: QaText.body),
          ),
        _OpenLink(
          label: 'qa_ud_view_report'.tr(),
          routeName: WeeklyReportRouter.routeName,
        ),
      ],
    );
  }
}
