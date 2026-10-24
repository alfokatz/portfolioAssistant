import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/presentation/shared/loading/button_spinner.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_identity.dart';
import 'package:portfolio_assistant/features/assistant/nav/assistant_nav.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/goals/providers/goals_provider.dart';
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
import 'package:portfolio_assistant/presentation/shared/loading/porty_loader.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/porty_says.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/porty_status_message.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/ticker_search_sheet.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_ask_sheet.dart';
import 'package:portfolio_assistant/features/assistant/models/porty_screen_context.dart';

/// Tickers que el usuario sigue sin tenerlos, con la forma de Metas: el
/// título grande, Porty contando cómo se movió la lista hoy y una fila por
/// ticker (logo, nombre, desde que la agregó, precio y día). Agregar busca
/// por nombre o ticker ([TickerSearchSheet]); tocar una fila abre sus
/// acciones (alerta de precio, preguntarle a Porty, avisos, quitar).
class WatchlistScreen extends ConsumerStatefulWidget {
  const WatchlistScreen({super.key});

  /// Desde este movimiento del día (en %, para arriba o para abajo) Porty
  /// lo cuenta arriba; menos, la lista "está tranquila".
  static const notableMovePct = 2.0;

  @override
  ConsumerState<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends ConsumerState<WatchlistScreen> {
  /// El ticker que se está agregando (su fila aparece mientras tanto).
  String? _adding;

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
    final state = ref.read(watchlistProvider);
    if (state.items.length >= limit) {
      _paywall();
      return;
    }
    final held = ref.read(goalHoldingsProvider);
    final symbol = await TickerSearchSheet.show(
      context,
      title: 'watchlist_add'.tr(),
      existing: {for (final i in state.items) i.symbol},
      existingLabel: 'watchlist_taken'.tr(),
      takenReasons: {
        for (final e in held.entries)
          if (e.value > 0) e.key.toUpperCase(): 'watchlist_taken_held'.tr(),
      },
    );
    if (symbol == null || !mounted) return;
    setState(() => _adding = symbol);
    final alerts = ref.read(alertProvider.notifier);
    try {
      await ref.read(watchlistProvider.notifier).add(symbol);
      alerts.showSuccess(
        message: 'watchlist_added'.tr(namedArgs: {'ticker': symbol}),
      );
    } on WatchlistUnknownSymbol {
      alerts.showError(
        message: 'watchlist_error_unknown'.tr(namedArgs: {'ticker': symbol}),
      );
    } on WatchlistLimitReached {
      if (mounted) _paywall();
    } on WatchlistDuplicate {
      alerts.showError(message: 'watchlist_error_duplicate'.tr());
    } on WatchlistFailure {
      alerts.showError(message: 'watchlist_error_network'.tr());
    } finally {
      if (mounted) setState(() => _adding = null);
    }
  }

  Future<void> _actions(WatchlistItem item) async {
    final quote = ref.read(watchlistProvider).quotes[item.symbol];
    final action = await showModalBottomSheet<_Action>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _ActionsSheet(item: item, quote: quote),
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
            screen: PortyScreenContext(
              PortyScreen.watchlist,
              ticker: item.symbol,
            ),
          ).navigate(context: context);
        case _Action.toggleNotify:
          await notifier.setNotify(item, !item.notify);
        case _Action.remove:
          await notifier.remove(item);
          if (mounted) {
            ref
                .read(alertProvider.notifier)
                .showSuccess(
                  message: 'watchlist_removed'.tr(
                    namedArgs: {'ticker': item.symbol},
                  ),
                );
          }
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
    final tier = ref.watch(subscriptionProvider).tier;
    final limit = PlanMatrix.of(tier).watchlistLimit;
    final state = ref.watch(watchlistProvider);

    final Widget body;
    if (limit == 0) {
      body = _Intro(locked: true, onCta: _paywall);
    } else if (!state.loaded) {
      body = Center(child: PortyLoader(message: 'loader_one_moment'.tr()));
    } else if (state.items.isEmpty && state.loadFailed) {
      body = PortyStatusMessage(
        title: 'watchlist_error_load_title'.tr(),
        body: 'watchlist_error_network'.tr(),
        actionLabel: 'watchlist_retry'.tr(),
        onAction: ref.read(watchlistProvider.notifier).load,
      );
    } else if (state.items.isEmpty && _adding == null) {
      body = _Intro(locked: false, onCta: _add);
    } else {
      body = RefreshIndicator(
        color: context.customColors.accentBlue,
        backgroundColor: context.customColors.surfaceCard,
        onRefresh: ref.read(watchlistProvider.notifier).load,
        child: _List(
          state: state,
          limit: limit,
          adding: _adding,
          onTap: _actions,
          onAdd: _add,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        actions: [
          if (state.items.isNotEmpty)
            const PortyAskButton(
              screen: PortyScreenContext(PortyScreen.watchlist),
            ),
          if (limit > 0 && state.items.isNotEmpty)
            IconButton(
              tooltip: 'watchlist_add'.tr(),
              onPressed: _adding == null ? _add : null,
              icon: const Icon(Icons.add_rounded),
            ),
        ],
      ),
      body: SafeArea(top: false, child: body),
    );
  }
}

/// Sin lista (o sin el plan): Porty cuenta para qué sirve, en tres puntos.
class _Intro extends StatelessWidget {
  const _Intro({required this.locked, required this.onCta});

  final bool locked;
  final VoidCallback onCta;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final points = [
      (
        Icons.show_chart_rounded,
        'watchlist_point_moves_title'.tr(),
        'watchlist_point_moves_body'.tr(),
      ),
      (
        Icons.notifications_active_outlined,
        'watchlist_point_alerts_title'.tr(),
        'watchlist_point_alerts_body'.tr(),
      ),
      (
        Icons.chat_bubble_outline_rounded,
        'watchlist_point_ask_title'.tr(),
        'watchlist_point_ask_body'.tr(),
      ),
    ];
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.pageHorizontal,
              0,
              AppDimens.pageHorizontal,
              AppDimens.sp24,
            ),
            children: [
              const _Title(),
              const SizedBox(height: AppDimens.sp20),
              PortySays(
                messageKey: locked ? 'locked' : 'empty',
                message: Text('watchlist_intro_porty'.tr()),
                footnote: Text(
                  (locked ? 'watchlist_locked_body' : 'watchlist_empty_body')
                      .tr(),
                ),
              ),
              const SizedBox(height: AppDimens.sp24),
              _Card(
                child: Column(
                  children: [
                    for (final (i, (icon, title, body)) in points.indexed) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          indent: 64,
                          endIndent: AppDimens.sp16,
                          color: colors.border,
                        ),
                      Padding(
                        padding: const EdgeInsets.all(AppDimens.sp16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Bubble(icon: icon),
                            const SizedBox(width: AppDimens.sp12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: tt.titleSmall?.copyWith(
                                      color: colors.textPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    body,
                                    style: tt.bodySmall?.copyWith(
                                      color: colors.textSecondary,
                                      height: 1.45,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.pageHorizontal,
            AppDimens.sp8,
            AppDimens.pageHorizontal,
            AppDimens.sp16,
          ),
          child: PositionPrimaryButton(
            label:
                (locked ? 'watchlist_see_plans' : 'watchlist_add_first').tr(),
            onPressed: onCta,
          ),
        ),
      ],
    );
  }
}

/// El título grande de la pantalla (como Metas).
class _Title extends StatelessWidget {
  const _Title();

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      'watchlist_title'.tr(),
      style: Theme.of(context).textTheme.displaySmall?.copyWith(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        color: context.customColors.textPrimary,
      ),
    ),
  );
}

/// La lista: Porty con lo que más se movió hoy y una fila por ticker.
class _List extends StatelessWidget {
  const _List({
    required this.state,
    required this.limit,
    required this.adding,
    required this.onTap,
    required this.onAdd,
  });

  final WatchlistState state;
  final int limit;
  final String? adding;
  final ValueChanged<WatchlistItem> onTap;
  final VoidCallback onAdd;

  /// Lo que dice Porty: el ticker que más se movió hoy (si pasa
  /// [WatchlistScreen.notableMovePct]), o que la lista está tranquila.
  ({String text, PortyAvatarState mood}) _verdict() {
    if (state.items.isEmpty) {
      return (
        text: 'watchlist_porty_loading'.tr(),
        mood: PortyAvatarState.idle,
      );
    }
    final moves = [
      for (final i in state.items)
        if (state.quotes[i.symbol]?.dayChangePct case final pct?)
          (symbol: i.symbol, pct: pct),
    ];
    if (moves.isEmpty) {
      return (
        text: 'watchlist_porty_loading'.tr(),
        mood: PortyAvatarState.thinking,
      );
    }
    moves.sort((a, b) => b.pct.abs().compareTo(a.pct.abs()));
    final top = moves.first;
    if (top.pct.abs() < WatchlistScreen.notableMovePct) {
      return (
        text: 'watchlist_porty_calm'.tr(
          namedArgs: {
            'pct': AppNumberFormat.percent(
              WatchlistScreen.notableMovePct,
              decimals: 0,
              signed: false,
            ),
          },
        ),
        mood: PortyAvatarState.idle,
      );
    }
    return (
      text: (top.pct > 0 ? 'watchlist_porty_up' : 'watchlist_porty_down').tr(
        namedArgs: {
          'ticker': top.symbol,
          'pct': AppNumberFormat.percent(top.pct),
        },
      ),
      // Cara de siempre: lo que se mueve en la lista no es su plata (la cara
      // contenta o triste es solo para la semana de la cartera).
      mood: PortyAvatarState.idle,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final verdict = _verdict();
    final adding = this.adding;
    final rows = <Widget>[
      if (adding != null) _AddingRow(symbol: adding),
      for (final item in state.items)
        _ItemRow(
          item: item,
          quote: state.quotes[item.symbol],
          onTap: () => onTap(item),
        ),
      if (state.items.length < limit && adding == null) _AddRow(onTap: onAdd),
    ];
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageHorizontal,
        0,
        AppDimens.pageHorizontal,
        AppDimens.sp32,
      ),
      children: [
        const _Title(),
        const SizedBox(height: AppDimens.sp20),
        PortySays(
          messageKey: verdict.text,
          mood: verdict.mood,
          message: Text(verdict.text),
          footnote: Text('watchlist_porty_note'.tr()),
        ),
        const SizedBox(height: AppDimens.sp32),
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  'watchlist_group_title'.tr(),
                  style: tt.labelLarge?.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Text(
              'watchlist_count'.tr(
                namedArgs: {
                  'count': '${state.items.length}',
                  'limit': '$limit',
                },
              ),
              style: tt.labelLarge?.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.sp4),
        for (final (i, row) in rows.indexed) ...[
          if (i > 0)
            Divider(
              height: 1,
              thickness: 1,
              indent: _avatarSize + AppDimens.sp12,
              color: colors.border,
            ),
          row,
        ],
      ],
    );
  }
}

const _avatarSize = 44.0;

/// Un ticker: logo, símbolo y nombre, cuánto se movió desde que lo agregó;
/// a la derecha el precio y el día. Directo sobre el fondo, como Metas.
class _ItemRow extends StatelessWidget {
  const _ItemRow({
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
    const tabular = [FontFeature.tabularFigures()];
    final q = quote;
    final day = q?.dayChangePct;
    final since = q?.sinceAddedPct(item.addedPrice);

    return Semantics(
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppDimens.sp16),
            child: QaBrandBuilder(
              ticker: item.symbol,
              builder: (context, brand) {
                final name = brand.name?.trim();
                return Row(
                  children: [
                    QaTickerAvatar(
                      ticker: item.symbol,
                      size: _avatarSize,
                      brand: brand,
                    ),
                    const SizedBox(width: AppDimens.sp12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: item.symbol,
                                        style: TextStyle(
                                          color: colors.textPrimary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      if (name != null && name.isNotEmpty)
                                        TextSpan(
                                          text: '  $name',
                                          style: TextStyle(
                                            color: colors.textSecondary,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                    ],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: tt.bodyLarge,
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
                          if (since == null)
                            Text(
                              'watchlist_added_on'.tr(
                                namedArgs: {
                                  'date': DateFormat.yMMMd().format(
                                    item.createdAt,
                                  ),
                                },
                              ),
                              style: tt.bodySmall?.copyWith(
                                color: colors.textSecondary,
                              ),
                            )
                          else
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: AppNumberFormat.percent(since),
                                    style: TextStyle(
                                      color: colors.pnlColor(since),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  TextSpan(
                                    text: ' ${'watchlist_since_added'.tr()}',
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tt.bodySmall?.copyWith(
                                color: colors.textSecondary,
                                fontFeatures: tabular,
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
                          style: tt.bodyLarge?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontFeatures: tabular,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (day != null)
                          _DayPill(pct: day)
                        else
                          const SizedBox(height: 20),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// La variación del día en una píldora de su color.
class _DayPill extends StatelessWidget {
  const _DayPill({required this.pct});

  final double pct;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final color = colors.pnlColor(pct);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.sp6,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: pct >= 0 ? colors.profitContainer : colors.lossContainer,
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
      ),
      child: Text(
        AppNumberFormat.percent(pct),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Mientras se agrega un ticker: su logo y "Agregando…".
class _AddingRow extends StatelessWidget {
  const _AddingRow({required this.symbol});

  final String symbol;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.sp16),
      child: Row(
        children: [
          Opacity(
            opacity: 0.6,
            child: QaTickerAvatar(ticker: symbol, size: _avatarSize),
          ),
          const SizedBox(width: AppDimens.sp12),
          Expanded(
            child: Text(
              'watchlist_adding'.tr(namedArgs: {'ticker': symbol}),
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: colors.textSecondary),
            ),
          ),
          ButtonSpinner.small(color: colors.textSecondary),
        ],
      ),
    );
  }
}

/// Al final de la lista: sumar otro (en terracota, como "Armar una meta").
class _AddRow extends StatelessWidget {
  const _AddRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final light = Theme.of(context).brightness == Brightness.light;
    return Semantics(
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppDimens.sp12),
            child: Row(
              children: [
                Container(
                  width: _avatarSize,
                  height: _avatarSize,
                  decoration: BoxDecoration(
                    color:
                        light
                            ? colors.accentBlue.withValues(alpha: 0.12)
                            : colors.chip,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.add_rounded,
                    size: AppDimens.iconMd,
                    color: colors.accentBlue,
                  ),
                ),
                const SizedBox(width: AppDimens.sp12),
                Expanded(
                  child: Text(
                    'watchlist_add_more'.tr(),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  Icons.search_rounded,
                  size: AppDimens.iconMd,
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

enum _Action { alert, ask, toggleNotify, remove }

/// Las acciones de un ticker: arriba su logo, nombre, precio y día; abajo
/// cada acción como una fila de Ajustes (quitar, en rojo).
class _ActionsSheet extends StatelessWidget {
  const _ActionsSheet({required this.item, required this.quote});

  final WatchlistItem item;
  final WatchQuote? quote;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final q = quote;
    final day = q?.dayChangePct;

    Widget tile(
      _Action a,
      IconData icon,
      String label, {
      String? subtitle,
      bool destructive = false,
    }) => InkWell(
      onTap: () => Navigator.of(context).pop(a),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.pageHorizontal,
          vertical: AppDimens.sp12,
        ),
        child: Row(
          children: [
            _Bubble(icon: icon, destructive: destructive),
            const SizedBox(width: AppDimens.sp12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: tt.bodyLarge?.copyWith(
                      color: destructive ? colors.loss : colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: tt.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.pageHorizontal,
                0,
                AppDimens.pageHorizontal,
                AppDimens.sp16,
              ),
              child: QaBrandBuilder(
                ticker: item.symbol,
                builder:
                    (context, brand) => Row(
                      children: [
                        QaTickerAvatar(
                          ticker: item.symbol,
                          size: 48,
                          brand: brand,
                        ),
                        const SizedBox(width: AppDimens.sp12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.symbol,
                                style: tt.titleLarge?.copyWith(
                                  color: colors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (brand.name?.isNotEmpty == true)
                                Text(
                                  brand.name!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: tt.bodyMedium?.copyWith(
                                    color: colors.textSecondary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (q != null)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                AppNumberFormat.money(q.price),
                                style: tt.titleMedium?.copyWith(
                                  color: colors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (day != null) ...[
                                const SizedBox(height: 4),
                                _DayPill(pct: day),
                              ],
                            ],
                          ),
                      ],
                    ),
              ),
            ),
            Divider(height: 1, color: colors.border),
            const SizedBox(height: AppDimens.sp4),
            tile(
              _Action.ask,
              Icons.chat_bubble_outline_rounded,
              'watchlist_action_ask'.tr(),
              subtitle: 'watchlist_action_ask_body'.tr(),
            ),
            tile(
              _Action.alert,
              Icons.notifications_active_outlined,
              'watchlist_action_alert'.tr(),
              subtitle: 'watchlist_action_alert_body'.tr(),
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
              destructive: true,
            ),
            const SizedBox(height: AppDimens.sp8),
          ],
        ),
      ),
    );
  }
}

/// Un ícono en un círculo teñido, como en Ajustes.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.icon, this.destructive = false});

  final IconData icon;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: destructive ? colors.lossContainer : colors.chip,
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        size: 18,
        color: destructive ? colors.loss : colors.onChip,
      ),
    );
  }
}

/// La card de la app: blanca, borde fino, radio grande.
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        border: Border.all(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
