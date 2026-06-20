import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/use_cases/add_position_use_case.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';
import 'package:portfolio_assistant/presentation/flows/position/providers/add_position_provider.dart';
import 'package:portfolio_assistant/presentation/flows/position/states/add_position_state.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_date_field.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/labeled_value_row.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/surface_card.dart';

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
    if (widget.prefilledPrice != null) {
      runAfterPostFrameCallback(
        () => ref.read(addPositionProvider(_args).notifier).fetchCurrentPrice(),
      );
    }
  }

  @override
  void dispose() {
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
          namedArgs: {'shares': shares.toStringAsFixed(4)},
        ),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.accentBlue,
              fontWeight: FontWeight.w500,
            ),
      ),
    );
  }

  Widget _preview(BuildContext context, AddPositionProvider notifier) {
    final colors = context.customColors;
    final state = ref.watch(addPositionProvider(_args));
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final shares = notifier.shares();
    final price = notifier.purchasePrice();
    if (shares == null || price == null || state.currentPrice == null) {
      return const SizedBox.shrink();
    }

    final marketValue = shares * state.currentPrice!;
    final costBasis = shares * price;
    final pnlAbs = marketValue - costBasis;
    final pnlPct = costBasis > 0 ? (pnlAbs / costBasis) * 100 : 0.0;
    final sign = pnlAbs >= 0 ? '+' : '';

    return SurfaceCard(
      margin: const EdgeInsets.only(top: AppDimens.sp16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'position_preview_title'.tr(),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: AppDimens.sp12),
          LabeledValueRow(
            label: 'position_preview_current_price'.tr(),
            value: currency.format(state.currentPrice),
            dense: true,
          ),
          LabeledValueRow(
            label: 'position_preview_shares'.tr(),
            value: shares.toStringAsFixed(6),
            dense: true,
          ),
          LabeledValueRow(
            label: 'position_preview_market_value'.tr(),
            value: currency.format(marketValue),
            dense: true,
          ),
          LabeledValueRow(
            label: 'position_preview_pnl'.tr(),
            value:
                '$sign${currency.format(pnlAbs)} (${pnlPct.toStringAsFixed(2)}%)',
            valueColor: colors.pnlColor(pnlAbs),
            dense: true,
          ),
        ],
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

    return Scaffold(
      appBar: AppBar(title: Text('add_position'.tr())),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.pageHorizontal,
            AppDimens.sp16,
            AppDimens.pageHorizontal,
            AppDimens.sp48,
          ),
          children: [
            TextFormField(
              controller: _tickerController,
              decoration: InputDecoration(
                labelText: 'position_ticker'.tr(),
                hintText: 'AAPL',
              ),
              textCapitalization: TextCapitalization.characters,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'field_required'.tr() : null,
              onFieldSubmitted: (_) => notifier.fetchPriceForDate(),
              onChanged: notifier.setTickerText,
            ),
            const SizedBox(height: AppDimens.sp16),
            SegmentedButton<BuyInputMode>(
              segments: [
                ButtonSegment(
                  value: BuyInputMode.shares,
                  label: Text('position_amount_type_shares'.tr()),
                ),
                ButtonSegment(
                  value: BuyInputMode.usd,
                  label: Text('position_amount_type_usd'.tr()),
                ),
              ],
              selected: {state.mode},
              onSelectionChanged: (value) => notifier.setMode(value.first),
            ),
            const SizedBox(height: AppDimens.sp16),
            PositionDateField(
              label: 'position_purchase_date'.tr(),
              date: state.purchaseDate,
              onTap: () => _pickDate(notifier),
            ),
            const SizedBox(height: AppDimens.sp16),
            TextFormField(
              controller: _priceController,
              decoration: InputDecoration(
                labelText: 'position_purchase_price'.tr(),
                suffixIcon: state.loadingPrice
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.accentBlue,
                          ),
                        ),
                      )
                    : IconButton(
                        tooltip: 'retry'.tr(),
                        onPressed: notifier.fetchPriceForDate,
                        icon: const Icon(Icons.refresh_rounded),
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
            const SizedBox(height: AppDimens.sp16),
            TextFormField(
              controller: _quantityController,
              decoration: InputDecoration(
                labelText: state.mode == BuyInputMode.shares
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
            if (state.loadingCurrent)
              Padding(
                padding: const EdgeInsets.only(top: AppDimens.sp12),
                child: LinearProgressIndicator(
                  minHeight: 2,
                  color: colors.accentBlue,
                  backgroundColor: colors.border,
                ),
              ),
            _preview(context, notifier),
            const SizedBox(height: AppDimens.sp32),
            PositionPrimaryButton(
              label: 'save'.tr(),
              loading: state.saving,
              onPressed: () => _save(notifier),
            ),
          ],
        ),
      ),
    );
  }
}
