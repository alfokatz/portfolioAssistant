import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/use_cases/add_position_use_case.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_identity.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';
import 'package:portfolio_assistant/presentation/flows/position/providers/add_position_provider.dart';
import 'package:portfolio_assistant/presentation/flows/position/states/add_position_state.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_date_field.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';
import 'package:portfolio_assistant/presentation/shared/formatting/app_number_format.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/motion_aware_size.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/segmented_choice.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/skeleton_text.dart';
import 'package:portfolio_assistant/presentation/shared/loading/button_spinner.dart';
import 'package:portfolio_assistant/presentation/shared/loading/loader_timing.dart';
import 'package:portfolio_assistant/presentation/shared/loading/skeleton.dart';

class AddPositionScreen extends StatefulHookConsumerWidget {
  final String? prefilledTicker;
  final double? prefilledQuantity;
  final double? prefilledPrice;

  const AddPositionScreen({
    super.key,
    this.prefilledTicker,
    this.prefilledQuantity,
    this.prefilledPrice,
  });

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _AddPositionScreenState();
}

class _AddPositionScreenState extends BaseStatefulWidget<AddPositionScreen> {
  final _formKey = GlobalKey<FormState>();
  late final AddPositionArgs _args;
  late final TextEditingController _tickerController;
  late final TextEditingController _quantityController;
  late final TextEditingController _priceController;

  /// Al salir del ticker (no solo con "listo" en el teclado) se busca el
  /// precio: así aparece la confirmación con el logo y el nombre.
  final _tickerFocus = FocusNode();

  @override
  void initState() {
    _args = AddPositionArgs(
      prefilledTicker: widget.prefilledTicker,
      prefilledQuantity: widget.prefilledQuantity,
      prefilledPrice: widget.prefilledPrice,
    );
    _tickerController = TextEditingController(text: widget.prefilledTicker);
    _quantityController = TextEditingController(
      text: widget.prefilledQuantity?.toString() ?? '',
    );
    _priceController = TextEditingController(
      text: widget.prefilledPrice?.toString() ?? '',
    );
    super.initState();
    _tickerFocus.addListener(() {
      if (!_tickerFocus.hasFocus) _lookUpTicker();
    });
    if (widget.prefilledPrice != null) {
      runAfterPostFrameCallback(
        () => ref.read(addPositionProvider(_args).notifier).fetchCurrentPrice(),
      );
    }
  }

  /// El precio de la fecha si ya se eligió una; si no, al menos el de hoy
  /// (para confirmar que el ticker existe y para la vista previa).
  Future<void> _lookUpTicker() async {
    final notifier = ref.read(addPositionProvider(_args).notifier);
    if (ref.read(addPositionProvider(_args)).datePicked) {
      await notifier.fetchPriceForDate();
    } else {
      await notifier.fetchCurrentPrice();
    }
  }

  @override
  void dispose() {
    _tickerFocus.dispose();
    _tickerController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _pickDate(AddPositionProvider notifier) async {
    final current = ref.read(addPositionProvider(_args)).purchaseDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(1990),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    await notifier.setPurchaseDate(picked);
  }

  Future<void> _save(AddPositionProvider notifier) async {
    if (!_formKey.currentState!.validate()) return;

    final result = await notifier.save(
      addPositionUseCase: ref.read(addPositionUseCaseProvider),
    );

    if (!mounted) return;

    switch (result) {
      case AddPositionInvalidInputResult():
        return;
      case AddPositionFailureResult(:final error):
        ref.read(alertProvider.notifier).showError(
              title: 'error'.tr(),
              message: error.message,
            );
      case AddPositionSuccessResult():
        await ref.read(homeProvider.notifier).refresh(silent: true);
        if (!mounted) return;
        context.pop(true);
    }
  }

  Widget? _sharesEquivalentHint(
    BuildContext context,
    AddPositionProvider notifier,
  ) {
    final colors = context.customColors;
    final state = ref.watch(addPositionProvider(_args));
    if (state.mode != BuyInputMode.usd) return null;

    final shares = notifier.shares();
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

  Widget _preview(
    BuildContext context,
    AddPositionProvider notifier, {
    bool skeleton = false,
  }) {
    final state = ref.watch(addPositionProvider(_args));
    final shares = notifier.shares();
    final price = notifier.purchasePrice();
    final current = state.currentPrice;
    if (shares == null || price == null || (current == null && !skeleton)) {
      return const SizedBox.shrink();
    }
    if (current == null) {
      return SkeletonScope(child: _previewCard(context, values: null));
    }

    final marketValue = shares * current;
    final costBasis = shares * price;
    final pnlAbs = marketValue - costBasis;
    final pnlPct = costBasis > 0 ? (pnlAbs / costBasis) * 100 : 0.0;
    return _previewCard(
      context,
      values: (
        current: AppNumberFormat.money(current),
        shares: AppNumberFormat.shares(shares),
        marketValue: AppNumberFormat.money(marketValue),
        pnl:
            '${AppNumberFormat.signedMoney(pnlAbs)} · '
            '${AppNumberFormat.percent(pnlPct)}',
        pnlValue: pnlAbs,
      ),
    );
  }

  /// Así quedaría la posición hoy: lo que vale (el número protagonista) y lo
  /// que ganó o perdió desde la compra. Con [values] en `null`, los valores
  /// van en skeleton (mismos títulos y alturas).
  Widget _previewCard(
    BuildContext context, {
    required ({
      String current,
      String shares,
      String marketValue,
      String pnl,
      double pnlValue,
    })?
    values,
  }) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    const tabular = [FontFeature.tabularFigures()];
    return Padding(
      padding: const EdgeInsets.only(top: AppDimens.sp16),
      child: _Card(
        title: 'position_preview_title'.tr(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonText(
              values?.marketValue,
              placeholder: '\$0,000.00',
              style: tt.displaySmall?.copyWith(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.8,
                height: 1.1,
                color: colors.textPrimary,
                fontFeatures: tabular,
              ),
            ),
            const SizedBox(height: AppDimens.sp6),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppDimens.sp6,
              children: [
                SkeletonText(
                  values?.pnl,
                  placeholder: '+\$000.00 · +00.0%',
                  style: tt.bodyMedium?.copyWith(
                    color: colors.pnlColor(values?.pnlValue ?? 0),
                    fontWeight: FontWeight.w600,
                    fontFeatures: tabular,
                  ),
                ),
                Text(
                  'position_detail_since_purchase'.tr(),
                  style: tt.bodyMedium?.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.sp20),
            Row(
              children: [
                Expanded(
                  child: _Stat(
                    label: 'position_preview_shares'.tr(),
                    value: values?.shares,
                  ),
                ),
                Expanded(
                  child: _Stat(
                    label: 'position_preview_current_price'.tr(),
                    value: values?.current,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _syncPriceController(AddPositionState state) {
    if (_priceController.text != state.priceText && state.priceText.isNotEmpty) {
      _priceController.text = state.priceText;
    }
  }

  @override
  Widget buildView(BuildContext context) {
    final colors = context.customColors;
    final state = ref.watch(addPositionProvider(_args));
    final notifier = ref.read(addPositionProvider(_args).notifier);

    ref.listen(addPositionProvider(_args), (previous, next) {
      _syncPriceController(next);
    });
    _syncPriceController(state);

    final tt = Theme.of(context).textTheme;
    final ticker = state.tickerText.trim().toUpperCase();
    // Los logos usan la paleta del kit de Porty.
    QaColors.resolve(Theme.of(context).brightness);

    return Scaffold(
      appBar: AppBar(title: Text('add_position'.tr())),
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
            _Card(
              title: 'add_position_what'.tr(),
              child: MotionAwareSize(
                duration: const Duration(milliseconds: 220),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _tickerController,
                      focusNode: _tickerFocus,
                      decoration: InputDecoration(
                        labelText: 'position_ticker'.tr(),
                        hintText: 'AAPL',
                      ),
                      textCapitalization: TextCapitalization.characters,
                      textInputAction: TextInputAction.next,
                      validator:
                          (v) =>
                              v == null || v.trim().isEmpty
                                  ? 'field_required'.tr()
                                  : null,
                      onChanged: notifier.setTickerText,
                    ),
                    // Confirmación: el ticker existe (hay precio) y es esta
                    // compañía.
                    if (ticker.isNotEmpty && state.currentPrice != null) ...[
                      const SizedBox(height: AppDimens.sp12),
                      _TickerConfirmation(
                        key: ValueKey(ticker),
                        ticker: ticker,
                        price: state.currentPrice!,
                      ),
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
                    label: 'position_purchase_date'.tr(),
                    date: state.purchaseDate,
                    onTap: () => _pickDate(notifier),
                  ),
                  const SizedBox(height: AppDimens.sp12),
                  TextFormField(
                    controller: _priceController,
                    decoration: InputDecoration(
                      labelText: 'position_purchase_price'.tr(),
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
                    onChanged: (value) {
                      notifier.setPriceText(value);
                      notifier.fetchCurrentPrice();
                    },
                  ),
                  const SizedBox(height: AppDimens.sp8),
                  Text(
                    'add_position_price_hint'.tr(),
                    style: tt.bodySmall?.copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppDimens.sp16),
            _Card(
              title: 'add_position_how_much'.tr(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedChoice<BuyInputMode>(
                    selected: state.mode,
                    onChanged: notifier.setMode,
                    options: [
                      (
                        value: BuyInputMode.shares,
                        label: 'position_amount_type_shares'.tr(),
                      ),
                      (
                        value: BuyInputMode.usd,
                        label: 'position_amount_type_usd'.tr(),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppDimens.sp12),
                  TextFormField(
                    controller: _quantityController,
                    decoration: InputDecoration(
                      labelText:
                          state.mode == BuyInputMode.shares
                              ? 'position_quantity'.tr()
                              : 'position_invested_amount'.tr(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (v) {
                      final n = double.tryParse(v ?? '');
                      if (n == null || n <= 0) return 'invalid_number'.tr();
                      return null;
                    },
                    onChanged: notifier.setQuantityText,
                  ),
                  if (_sharesEquivalentHint(context, notifier) != null)
                    _sharesEquivalentHint(context, notifier)!,
                ],
              ),
            ),
            // Mientras llega el precio actual, la vista previa misma con los
            // valores en skeleton (no una barra de progreso aparte).
            DelayedLoaderVisibility(
              loading: state.loadingCurrent && state.currentPrice == null,
              builder:
                  (context, showSkeleton) => AnimatedSwitcher(
                    duration:
                        MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : LoaderTiming.swap,
                    child: KeyedSubtree(
                      key: ValueKey(showSkeleton),
                      child: _preview(
                        context,
                        notifier,
                        skeleton: showSkeleton,
                      ),
                    ),
                  ),
            ),
            const SizedBox(height: AppDimens.sp32),
            PositionPrimaryButton(
              label: 'add_position_confirm'.tr(),
              loading: state.saving,
              onPressed: () => _save(notifier),
            ),
          ],
        ),
      ),
    );
  }
}

/// Logo, nombre y precio de hoy del ticker escrito: confirma que existe y
/// que es la compañía que el usuario quería.
class _TickerConfirmation extends StatelessWidget {
  const _TickerConfirmation({
    super.key,
    required this.ticker,
    required this.price,
  });

  final String ticker;
  final double price;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return QaBrandBuilder(
      ticker: ticker,
      builder:
          (context, brand) => Row(
            children: [
              QaTickerAvatar(ticker: ticker, brand: brand, size: 32),
              const SizedBox(width: AppDimens.sp12),
              Expanded(
                child: Text(
                  brand.name?.isNotEmpty == true ? brand.name! : ticker,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodyMedium?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: AppDimens.sp8),
              Text(
                'add_position_price_today'.tr(
                  namedArgs: {'price': AppNumberFormat.money(price)},
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
  final String? value;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: tt.bodySmall?.copyWith(color: colors.textSecondary)),
        const SizedBox(height: 2),
        SkeletonText(
          value,
          placeholder: '\$000.00',
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
