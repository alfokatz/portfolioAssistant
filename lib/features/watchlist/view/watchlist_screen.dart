import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/features/assistant/nav/assistant_nav.dart';
import 'package:portfolio_assistant/features/notifications/view/create_price_alert_sheet.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_paywall_sheet.dart';
import 'package:portfolio_assistant/features/watchlist/data/watchlist_repository.dart';
import 'package:portfolio_assistant/features/watchlist/domain/watchlist_item.dart';
import 'package:portfolio_assistant/features/watchlist/providers/watchlist_provider.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';
import 'package:portfolio_assistant/presentation/shared/formatting/app_number_format.dart';

/// Tickers que el usuario sigue sin tenerlos: precio, variación del día y
/// desde que los agregó. Por cada uno, alerta de precio, preguntarle a
/// Porty o quitarlo.
class WatchlistScreen extends ConsumerStatefulWidget {
  const WatchlistScreen({super.key});

  @override
  ConsumerState<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends ConsumerState<WatchlistScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(watchlistProvider.notifier).load();
    });
  }

  void _paywall() => SubscriptionPaywallSheet.show(
    context,
    ref,
    reason: PaywallReason.marketDataLocked,
  );

  Future<void> _add() async {
    final tier = ref.read(subscriptionProvider).tier;
    final limit = PlanMatrix.of(tier).watchlistLimit;
    if (ref.read(watchlistProvider).items.length >= limit) {
      _paywall();
      return;
    }
    final added = await AddToWatchlistSheet.show(context);
    if (added == null || !mounted) return;
    ref
        .read(alertProvider.notifier)
        .showSuccess(
          message: 'watchlist_added'.tr(namedArgs: {'ticker': added.symbol}),
        );
  }

  Future<void> _actions(WatchlistItem item) async {
    final quote = ref.read(watchlistProvider).quotes[item.symbol];
    final action = await showModalBottomSheet<_Action>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _ActionsSheet(item: item),
    );
    if (action == null || !mounted) return;
    final notifier = ref.read(watchlistProvider.notifier);
    try {
      switch (action) {
        case _Action.alert:
          await CreatePriceAlertSheet.show(
            context,
            ref,
            symbol: item.symbol,
            currentPrice: quote?.price,
          );
        case _Action.ask:
          GotoAssistant(
            initialQuestion: 'watchlist_ask_question'.tr(
              namedArgs: {'ticker': item.symbol},
            ),
          ).navigate(context: context);
        case _Action.toggleNotify:
          await notifier.setNotify(item, !item.notify);
        case _Action.remove:
          await notifier.remove(item);
      }
    } on WatchlistFailure {
      if (mounted) {
        ref
            .read(alertProvider.notifier)
            .showError(message: 'watchlist_error_network'.tr());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final tier = ref.watch(subscriptionProvider).tier;
    final limit = PlanMatrix.of(tier).watchlistLimit;
    final state = ref.watch(watchlistProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('watchlist_title'.tr()),
        actions: [
          if (limit > 0)
            IconButton(
              tooltip: 'watchlist_add'.tr(),
              onPressed: _add,
              icon: const Icon(Icons.add_rounded),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child:
            limit == 0
                ? _Empty(
                  title: 'watchlist_locked_title'.tr(),
                  body: 'watchlist_locked_body'.tr(),
                  cta: 'watchlist_see_plans'.tr(),
                  onCta: _paywall,
                )
                : !state.loaded
                ? const Center(
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
                : state.items.isEmpty
                ? _Empty(
                  title: 'watchlist_empty_title'.tr(),
                  body:
                      state.loadFailed
                          ? 'watchlist_error_network'.tr()
                          : 'watchlist_empty_body'.tr(),
                  cta: 'watchlist_add'.tr(),
                  onCta: _add,
                )
                : RefreshIndicator(
                  onRefresh: ref.read(watchlistProvider.notifier).load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppDimens.pageHorizontal,
                      AppDimens.sp8,
                      AppDimens.pageHorizontal,
                      AppDimens.sp24,
                    ),
                    children: [
                      for (final item in state.items)
                        _ItemTile(
                          item: item,
                          quote: state.quotes[item.symbol],
                          onTap: () => _actions(item),
                        ),
                      const SizedBox(height: AppDimens.sp8),
                      Text(
                        'watchlist_footer'.tr(
                          namedArgs: {
                            'count': '${state.items.length}',
                            'limit': '$limit',
                          },
                        ),
                        textAlign: TextAlign.center,
                        style: tt.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.title,
    required this.body,
    required this.cta,
    required this.onCta,
  });

  final String title;
  final String body;
  final String cta;
  final VoidCallback onCta;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(AppDimens.pageHorizontal),
      children: [
        Icon(Icons.visibility_outlined, size: 40, color: colors.textSecondary),
        const SizedBox(height: AppDimens.sp16),
        Semantics(
          header: true,
          child: Text(
            title,
            style: tt.headlineSmall?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
        ),
        const SizedBox(height: AppDimens.sp8),
        Text(
          body,
          style: tt.bodyLarge?.copyWith(
            color: colors.textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: AppDimens.sp24),
        PositionPrimaryButton(label: cta, onPressed: onCta),
      ],
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.item,
    required this.quote,
    required this.onTap,
  });

  final WatchlistItem item;
  final WatchQuote? quote;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final q = quote;
    final day = q?.dayChangePct;
    final since = q?.sinceAddedPct(item.addedPrice);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimens.sp8),
      child: Material(
        color: colors.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          side: BorderSide(color: colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.sp16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              item.symbol,
                              overflow: TextOverflow.ellipsis,
                              style: tt.titleSmall?.copyWith(
                                color: colors.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (!item.notify) ...[
                            const SizedBox(width: AppDimens.sp6),
                            Icon(
                              Icons.notifications_off_outlined,
                              size: AppDimens.iconSm,
                              color: colors.textSecondary,
                              semanticLabel: 'watchlist_notify_off'.tr(),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        since == null
                            ? 'watchlist_added_on'.tr(
                              namedArgs: {
                                'date': DateFormat.yMMMd().format(
                                  item.createdAt,
                                ),
                              },
                            )
                            : 'watchlist_since_added'.tr(
                              namedArgs: {
                                'pct': AppNumberFormat.percent(since),
                              },
                            ),
                        style: tt.bodySmall?.copyWith(
                          color: colors.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppDimens.sp12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      q == null ? '—' : AppNumberFormat.money(q.price),
                      style: tt.titleSmall?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      day == null ? '' : AppNumberFormat.percent(day),
                      style: tt.bodySmall?.copyWith(
                        color:
                            day == null
                                ? colors.textSecondary
                                : colors.pnlColor(day),
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _Action { alert, ask, toggleNotify, remove }

class _ActionsSheet extends StatelessWidget {
  const _ActionsSheet({required this.item});

  final WatchlistItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    Widget tile(_Action a, IconData icon, String label) => ListTile(
      leading: Icon(icon, color: colors.textPrimary),
      title: Text(
        label,
        style: tt.bodyLarge?.copyWith(color: colors.textPrimary),
      ),
      onTap: () => Navigator.of(context).pop(a),
    );
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.pageHorizontal,
                0,
                AppDimens.pageHorizontal,
                AppDimens.sp8,
              ),
              child: Text(
                item.symbol,
                style: tt.titleLarge?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            tile(
              _Action.alert,
              Icons.notifications_active_outlined,
              'watchlist_action_alert'.tr(),
            ),
            tile(
              _Action.ask,
              Icons.chat_bubble_outline_rounded,
              'watchlist_action_ask'.tr(),
            ),
            tile(
              _Action.toggleNotify,
              item.notify
                  ? Icons.notifications_off_outlined
                  : Icons.notifications_none_rounded,
              (item.notify
                      ? 'watchlist_action_notify_off'
                      : 'watchlist_action_notify_on')
                  .tr(),
            ),
            tile(
              _Action.remove,
              Icons.delete_outline_rounded,
              'watchlist_action_remove'.tr(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Agregar un ticker: lo busca en Yahoo para confirmar que existe y guarda
/// su precio de hoy.
class AddToWatchlistSheet extends ConsumerStatefulWidget {
  const AddToWatchlistSheet({super.key});

  static Future<WatchlistItem?> show(BuildContext context) =>
      showModalBottomSheet<WatchlistItem>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => const AddToWatchlistSheet(),
      );

  @override
  ConsumerState<AddToWatchlistSheet> createState() =>
      _AddToWatchlistSheetState();
}

class _AddToWatchlistSheetState extends ConsumerState<AddToWatchlistSheet> {
  final _ticker = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final symbol = _ticker.text.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9.\-^=]{1,15}$').hasMatch(symbol)) {
      setState(() => _error = 'watchlist_error_ticker'.tr());
      return;
    }
    if (ref.read(watchlistProvider).contains(symbol)) {
      setState(() => _error = 'watchlist_error_duplicate'.tr());
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final item = await ref.read(watchlistProvider.notifier).add(symbol);
      if (mounted) Navigator.of(context).pop(item);
    } catch (e) {
      if (!mounted) return;
      if (e is WatchlistLimitReached) {
        Navigator.of(context).pop();
        SubscriptionPaywallSheet.show(
          context,
          ref,
          reason: PaywallReason.marketDataLocked,
        );
        return;
      }
      setState(() {
        _saving = false;
        _error =
            (e is WatchlistUnknownSymbol
                    ? 'watchlist_error_unknown'
                    : e is WatchlistDuplicate
                    ? 'watchlist_error_duplicate'
                    : 'watchlist_error_network')
                .tr();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.pageHorizontal,
            0,
            AppDimens.pageHorizontal,
            AppDimens.sp16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'watchlist_add'.tr(),
                style: tt.titleLarge?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppDimens.sp16),
              TextField(
                controller: _ticker,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  labelText: 'import_edit_ticker'.tr(),
                  helperText: 'import_edit_ticker_help'.tr(),
                  errorText: _error,
                  errorMaxLines: 2,
                ),
              ),
              const SizedBox(height: AppDimens.sp20),
              PositionPrimaryButton(
                label: 'watchlist_add_cta'.tr(),
                loading: _saving,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
