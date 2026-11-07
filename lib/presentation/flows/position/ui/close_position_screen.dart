import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/use_cases/close_position_use_case.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_identity.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/home/nav/home_router.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';
import 'package:portfolio_assistant/presentation/flows/position/providers/close_position_provider.dart';
import 'package:portfolio_assistant/presentation/flows/position/states/close_position_state.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_date_field.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';
import 'package:portfolio_assistant/presentation/shared/formatting/app_number_format.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/motion_aware_size.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/segmented_choice.dart';
import 'package:portfolio_assistant/presentation/shared/loading/button_spinner.dart';
import 'package:portfolio_assistant/presentation/shared/loading/loader_timing.dart';

class ClosePositionScreen extends StatefulHookConsumerWidget {
  final String positionId;
  final String ticker;
  final double quantity;
  final double avgPurchasePrice;

  const ClosePositionScreen({
    super.key,
    required this.positionId,
    required this.ticker,
    required this.quantity,
    required this.avgPurchasePrice,
  });

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _ClosePositionScreenState();
}

class _ClosePositionScreenState extends BaseStatefulWidget<ClosePositionScreen> {
  final _formKey = GlobalKey<FormState>();
  late final ClosePositionArgs _args;
  late final TextEditingController _priceController;
  late final TextEditingController _sellAmountController;

  /// La venta ya guardada: la pantalla pasa a la confirmación (y de ahí,
  /// a la Home). Antes volvía al detalle, que seguía mostrando la posición
  /// como abierta.
  ClosedPosition? _closed;

  @override
  void initState() {
    _args = ClosePositionArgs(
      positionId: widget.positionId,
      ticker: widget.ticker,
      quantity: widget.quantity,
      avgPurchasePrice: widget.avgPurchasePrice,
    );
    _priceController = TextEditingController();
    _sellAmountController = TextEditingController(
      text: widget.quantity.toString(),
    );
    super.initState();
    runAfterPostFrameCallback(
      () => ref.read(closePositionProvider(_args).notifier).init(),
    );
  }

  @override
  void dispose() {
    _priceController.dispose();
    _sellAmountController.dispose();
    super.dispose();
  }

  void _syncControllers(ClosePositionState state) {
    if (_priceController.text != state.priceText) {
      _priceController.text = state.priceText;
    }
    if (_sellAmountController.text != state.sellAmountText) {
      _sellAmountController.text = state.sellAmountText;
    }
  }

  Future<void> _pickDate(ClosePositionProvider notifier) async {
    final current = ref.read(closePositionProvider(_args)).closeDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(1990),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    await notifier.setCloseDate(picked);
  }

  Future<void> _save(ClosePositionProvider notifier) async {
    if (!_formKey.currentState!.validate()) return;

    final result = await notifier.save(
      closePositionUseCase: ref.read(closePositionUseCaseProvider),
    );

    if (!mounted) return;

    switch (result) {
      case ClosePositionInvalidInputResult():
        return;
      case ClosePositionFailureResult(:final error):
        ref.read(alertProvider.notifier).showError(
              title: 'error'.tr(),
              message: error.message,
            );
      case ClosePositionSuccessResult(:final closed):
        PortyHapticsService.maybeOf(context)?.answerRevealCompleted();
        setState(() => _closed = closed);
        // La Home se actualiza mientras se ve la confirmación. Si falla, la
        // venta igual quedó guardada: la confirmación no depende de esto.
        try {
          await ref.read(homeProvider.notifier).refresh(silent: true);
        } catch (_) {}
    }
  }

  Widget? _sharesEquivalentHint(
    BuildContext context,
    ClosePositionProvider notifier,
  ) {
    final colors = context.customColors;
    final state = ref.watch(closePositionProvider(_args));
    if (state.scope != CloseScope.partial ||
        state.sellMode != SellInputMode.usd) {
      return null;
    }

    final shares = notifier.sharesToSell();
    if (shares == null) return null;

    return Padding(
      padding: const EdgeInsets.only(
        top: AppDimens.sp8,
        left: AppDimens.sp4,
      ),
      child: Text(
        'position_shares_equivalent'.tr(
          namedArgs: {'shares': AppNumberFormat.shares(shares)},
        ),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.accentBlue,
              fontWeight: FontWeight.w500,
            ),
      ),
    );
  }

  /// Resultado del cierre: lo que ganás o perdés con la venta es el número
  /// protagonista; abajo, de dónde sale.
  Widget _preview(
    BuildContext context,
    ClosePositionProvider notifier,
  ) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final closePrice = notifier.closePrice();
    final shares = notifier.sharesToSell();
    if (closePrice == null || closePrice <= 0 || shares == null) {
      return const SizedBox.shrink();
    }

    final costBasis = shares * widget.avgPurchasePrice;
    final proceeds = shares * closePrice;
    final pnlAbs = proceeds - costBasis;
    final pnlPct = costBasis > 0 ? (pnlAbs / costBasis) * 100 : 0.0;
    const tabular = [FontFeature.tabularFigures()];

    return Padding(
      padding: const EdgeInsets.only(top: AppDimens.sp16),
      child: _Card(
        title: 'close_position_preview_title'.tr(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppNumberFormat.signedMoney(pnlAbs),
              style: tt.displaySmall?.copyWith(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.8,
                height: 1.1,
                color: colors.pnlColor(pnlAbs),
                fontFeatures: tabular,
              ),
            ),
            const SizedBox(height: AppDimens.sp6),
            Text(
              'close_position_preview_pnl_detail'.tr(
                namedArgs: {'pct': AppNumberFormat.percent(pnlPct)},
              ),
              style: tt.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppDimens.sp20),
            Row(
              children: [
                Expanded(
                  child: _Stat(
                    label: 'close_position_preview_shares'.tr(),
                    value: AppNumberFormat.shares(shares),
                  ),
                ),
                Expanded(
                  child: _Stat(
                    label: 'close_position_preview_proceeds'.tr(),
                    value: AppNumberFormat.money(proceeds),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _Stat(
              label: 'close_position_preview_cost'.tr(),
              value: AppNumberFormat.money(costBasis),
            ),
          ],
        ),
      ),
    );
  }

  String? _validateSellAmount(String? value, ClosePositionProvider notifier) {
    final state = ref.read(closePositionProvider(_args));
    if (state.scope == CloseScope.all) return null;

    final closePrice = notifier.closePrice();
    if (closePrice == null || closePrice <= 0) return 'invalid_number'.tr();

    final raw = double.tryParse(value ?? '');
    if (raw == null || raw <= 0) return 'invalid_number'.tr();

    final shares =
        state.sellMode == SellInputMode.shares ? raw : (raw / closePrice);
    if (shares > widget.quantity + 1e-6) {
      return 'close_position_quantity_exceeds'.tr();
    }
    return null;
  }

  /// A la Home, reemplazando la pila: "atrás" no puede volver al detalle de
  /// una posición que ya no existe.
  void _goHome() => context.goNamed(HomeRouter.homeRouteName);

  @override
  Widget buildView(BuildContext context) {
    final closed = _closed;
    if (closed != null) {
      return _CloseSuccess(
        closed: closed,
        closedEverything: closed.quantity >= widget.quantity - 1e-6,
        onDone: _goHome,
      );
    }
    final colors = context.customColors;
    final state = ref.watch(closePositionProvider(_args));
    final notifier = ref.read(closePositionProvider(_args).notifier);

    ref.listen(closePositionProvider(_args), (previous, next) {
      _syncControllers(next);
    });
    _syncControllers(state);

    final tt = Theme.of(context).textTheme;
    final quantity = widget.quantity;
    final shares =
        quantity == 1
            ? 'position_shares_one'.tr()
            : 'position_shares'.tr(
              namedArgs: {'count': AppNumberFormat.shares(quantity)},
            );
    // Los logos usan la paleta del kit de Porty.
    QaColors.resolve(Theme.of(context).brightness);

    return Scaffold(
      appBar: AppBar(title: Text('close_position_title'.tr())),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.pageHorizontal,
            AppDimens.sp8,
            AppDimens.pageHorizontal,
            AppDimens.sp48,
          ),
          children: [
            // Qué se cierra: logo, ticker, cuántas acciones y a qué precio
            // promedio se compraron.
            Row(
              children: [
                QaTickerAvatar(ticker: widget.ticker, size: 48),
                const SizedBox(width: AppDimens.sp12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.ticker,
                        style: tt.displaySmall?.copyWith(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.6,
                          height: 1.1,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'close_position_holding'.tr(
                          namedArgs: {
                            'shares': shares,
                            'price': AppNumberFormat.money(
                              widget.avgPurchasePrice,
                            ),
                          },
                        ),
                        style: tt.bodyMedium?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.sp24),
            _Card(
              title: 'close_position_scope'.tr(),
              child: MotionAwareSize(
                duration: const Duration(milliseconds: 220),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedChoice<CloseScope>(
                      selected: state.scope,
                      onChanged: notifier.setScope,
                      options: [
                        (
                          value: CloseScope.all,
                          label: 'close_position_scope_all'.tr(),
                        ),
                        (
                          value: CloseScope.partial,
                          label: 'close_position_scope_partial'.tr(),
                        ),
                      ],
                    ),
                    if (state.scope == CloseScope.partial) ...[
                      const SizedBox(height: AppDimens.sp20),
                      Text(
                        'close_position_sell_amount'.tr(),
                        style: tt.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AppDimens.sp12),
                      SegmentedChoice<SellInputMode>(
                        selected: state.sellMode,
                        onChanged: notifier.setSellMode,
                        options: [
                          (
                            value: SellInputMode.shares,
                            label: 'position_amount_type_shares'.tr(),
                          ),
                          (
                            value: SellInputMode.usd,
                            label: 'position_amount_type_usd'.tr(),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppDimens.sp12),
                      TextFormField(
                        controller: _sellAmountController,
                        decoration: InputDecoration(
                          labelText:
                              state.sellMode == SellInputMode.shares
                                  ? 'position_quantity'.tr()
                                  : 'close_position_sell_usd'.tr(),
                          hintText:
                              state.sellMode == SellInputMode.shares
                                  ? AppNumberFormat.shares(quantity)
                                  : null,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator:
                            (value) => _validateSellAmount(value, notifier),
                        onChanged: notifier.setSellAmountText,
                      ),
                      if (_sharesEquivalentHint(context, notifier) != null)
                        _sharesEquivalentHint(context, notifier)!,
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppDimens.sp16),
            _Card(
              title: 'close_position_details'.tr(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PositionDateField(
                    label: 'close_position_date'.tr(),
                    date: state.closeDate,
                    onTap: () => _pickDate(notifier),
                  ),
                  const SizedBox(height: AppDimens.sp12),
                  TextFormField(
                    controller: _priceController,
                    decoration: InputDecoration(
                      labelText: 'close_position_price'.tr(),
                      prefixText: r'$ ',
                      suffixIcon: DelayedLoaderVisibility(
                        loading: state.loadingPrice,
                        builder:
                            (context, showSpinner) =>
                                showSpinner
                                    ? Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: ButtonSpinner.small(
                                        color: colors.accentBlue,
                                      ),
                                    )
                                    : IconButton(
                                      tooltip: 'close_position_price_refresh'
                                          .tr(),
                                      onPressed:
                                          state.loadingPrice
                                              ? null
                                              : notifier.fetchPriceForDate,
                                      icon: const Icon(Icons.refresh_rounded),
                                    ),
                      ),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (v) {
                      final n = double.tryParse(v ?? '');
                      if (n == null || n <= 0) return 'invalid_number'.tr();
                      return null;
                    },
                    onChanged: notifier.setPriceText,
                  ),
                  const SizedBox(height: AppDimens.sp8),
                  Text(
                    'close_position_price_hint'.tr(),
                    style: tt.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            _preview(context, notifier),
            const SizedBox(height: AppDimens.sp32),
            PositionPrimaryButton(
              label: 'close_position_confirm'.tr(),
              loading: state.saving,
              onPressed: () => _save(notifier),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card con título fuerte, como las del resto de la app.
class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});

  final String title;
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
      padding: const EdgeInsets.all(AppDimens.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
          const SizedBox(height: AppDimens.sp16),
          child,
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: tt.bodySmall?.copyWith(color: colors.textSecondary)),
        const SizedBox(height: 2),
        Text(
          value,
          style: tt.titleSmall?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 15,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// La confirmación de la venta: Porty (contento, o apenas triste si fue a
/// pérdida), el resultado y de dónde sale. El botón y el gesto de "atrás"
/// llevan a la Home.
class _CloseSuccess extends StatelessWidget {
  const _CloseSuccess({
    required this.closed,
    required this.closedEverything,
    required this.onDone,
  });

  final ClosedPosition closed;

  /// Se vendió toda la posición (y no solo una parte).
  final bool closedEverything;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final pnl = closed.pnlAbsolute;
    const tabular = [FontFeature.tabularFigures()];
    final shares =
        closed.quantity == 1
            ? 'position_shares_one'.tr()
            : 'position_shares'.tr(
              namedArgs: {'count': AppNumberFormat.shares(closed.quantity)},
            );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onDone();
      },
      child: Scaffold(
        appBar: AppBar(automaticallyImplyLeading: false),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.pageHorizontal,
              AppDimens.sp24,
              AppDimens.pageHorizontal,
              AppDimens.sp32,
            ),
            children: [
              Center(
                child: ExcludeSemantics(
                  child: PortyAvatar(
                    size: 72,
                    state:
                        pnl >= 0
                            ? PortyAvatarState.answered
                            : PortyAvatarState.concerned,
                    animated: true,
                  ),
                ),
              ),
              const SizedBox(height: AppDimens.sp20),
              Semantics(
                header: true,
                child: Text(
                  (closedEverything
                          ? 'close_position_success_all'
                          : 'close_position_success_partial')
                      .tr(namedArgs: {'ticker': closed.ticker}),
                  textAlign: TextAlign.center,
                  style: tt.titleLarge?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              const SizedBox(height: AppDimens.sp8),
              Text(
                'close_position_success_body'.tr(),
                textAlign: TextAlign.center,
                style: tt.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: AppDimens.sp24),
              _Card(
                title: 'close_position_preview_title'.tr(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppNumberFormat.signedMoney(pnl),
                      style: tt.displaySmall?.copyWith(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.8,
                        height: 1.1,
                        color: colors.pnlColor(pnl),
                        fontFeatures: tabular,
                      ),
                    ),
                    const SizedBox(height: AppDimens.sp6),
                    Text(
                      'close_position_preview_pnl_detail'.tr(
                        namedArgs: {
                          'pct': AppNumberFormat.percent(closed.pnlPercent),
                        },
                      ),
                      style: tt.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppDimens.sp20),
                    Row(
                      children: [
                        Expanded(
                          child: _Stat(
                            label: 'close_position_preview_shares'.tr(),
                            value: shares,
                          ),
                        ),
                        Expanded(
                          child: _Stat(
                            label: 'close_position_preview_proceeds'.tr(),
                            value: AppNumberFormat.money(closed.proceeds),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _Stat(
                            label: 'close_position_price'.tr(),
                            value: AppNumberFormat.money(closed.closePrice),
                          ),
                        ),
                        Expanded(
                          child: _Stat(
                            label: 'close_position_date'.tr(),
                            value: DateFormat.yMMMd().format(closed.closeDate),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppDimens.sp32),
              PositionPrimaryButton(
                label: 'close_position_success_done'.tr(),
                onPressed: onDone,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
