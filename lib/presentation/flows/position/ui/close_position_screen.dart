import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/use_cases/close_position_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_price_on_date_use_case.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';

enum _CloseScope { all, partial }

enum _SellInputMode { shares, usd }

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
  late final TextEditingController _priceController;
  late final TextEditingController _sellAmountController;
  DateTime _closeDate = DateTime.now();
  bool _saving = false;
  bool _loadingPrice = false;
  _CloseScope _scope = _CloseScope.all;
  _SellInputMode _sellMode = _SellInputMode.shares;

  @override
  void initState() {
    _priceController = TextEditingController();
    _sellAmountController = TextEditingController(
      text: widget.quantity.toString(),
    );
    super.initState();
    runAfterPostFrameCallback(_fetchPriceForDate);
  }

  @override
  void dispose() {
    _priceController.dispose();
    _sellAmountController.dispose();
    super.dispose();
  }

  double get _maxShares => widget.quantity;

  double? _closePrice() => double.tryParse(_priceController.text);

  double? _sharesToSell() {
    if (_scope == _CloseScope.all) return _maxShares;

    final closePrice = _closePrice();
    if (closePrice == null || closePrice <= 0) return null;

    final raw = double.tryParse(_sellAmountController.text);
    if (raw == null || raw <= 0) return null;

    return _sellMode == _SellInputMode.shares ? raw : (raw / closePrice);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _closeDate,
      firstDate: DateTime(1990),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() => _closeDate = picked);
    await _fetchPriceForDate();
  }

  Future<void> _fetchPriceForDate() async {
    setState(() => _loadingPrice = true);
    final result = await ref.read(getPriceOnDateUseCaseProvider).call(
          params: GetPriceOnDateParams(
            ticker: widget.ticker,
            date: _closeDate,
          ),
        );

    if (!mounted) return;
    setState(() => _loadingPrice = false);

    result.fold(
      (_) {},
      (price) {
        if (price > 0) {
          setState(() {
            _priceController.text = price.toStringAsFixed(2);
          });
        }
      },
    );
  }

  void _onScopeChanged(_CloseScope? value) {
    if (value == null) return;
    setState(() {
      _scope = value;
      if (value == _CloseScope.all) {
        _sellAmountController.text = _maxShares.toString();
      }
    });
  }

  Widget? _sharesEquivalentHint(BuildContext context) {
    if (_scope != _CloseScope.partial || _sellMode != _SellInputMode.usd) {
      return null;
    }

    final shares = _sharesToSell();
    if (shares == null) return null;

    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 4),
      child: Text(
        'position_shares_equivalent'.tr(
          namedArgs: {'shares': shares.toStringAsFixed(4)},
        ),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: PortfolioColors.accentBlue,
              fontWeight: FontWeight.w500,
            ),
      ),
    );
  }

  Widget _preview(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final closePrice = _closePrice();
    final shares = _sharesToSell();
    if (closePrice == null || closePrice <= 0 || shares == null) {
      return const SizedBox.shrink();
    }

    final costBasis = shares * widget.avgPurchasePrice;
    final proceeds = shares * closePrice;
    final pnlAbs = proceeds - costBasis;
    final pnlPct = costBasis > 0 ? (pnlAbs / costBasis) * 100 : 0.0;
    final sign = pnlAbs >= 0 ? '+' : '';

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PortfolioColors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PortfolioColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'close_position_preview_title'.tr(),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: PortfolioColors.textPrimary,
                ),
          ),
          const SizedBox(height: 10),
          _PreviewRow(
            label: 'close_position_preview_shares'.tr(),
            value: shares.toStringAsFixed(4),
          ),
          _PreviewRow(
            label: 'close_position_preview_cost'.tr(),
            value: currency.format(costBasis),
          ),
          _PreviewRow(
            label: 'close_position_preview_proceeds'.tr(),
            value: currency.format(proceeds),
          ),
          _PreviewRow(
            label: 'close_position_preview_pnl'.tr(),
            value:
                '$sign${currency.format(pnlAbs)} (${pnlPct.toStringAsFixed(2)}%)',
            valueColor: pnlAbs >= 0
                ? PortfolioColors.profit
                : PortfolioColors.loss,
          ),
        ],
      ),
    );
  }

  String? _validateSellAmount(String? value) {
    if (_scope == _CloseScope.all) return null;

    final closePrice = _closePrice();
    if (closePrice == null || closePrice <= 0) return 'invalid_number'.tr();

    final raw = double.tryParse(value ?? '');
    if (raw == null || raw <= 0) return 'invalid_number'.tr();

    final shares =
        _sellMode == _SellInputMode.shares ? raw : (raw / closePrice);
    if (shares > _maxShares + 1e-6) {
      return 'close_position_quantity_exceeds'.tr();
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final shares = _sharesToSell();
    final closePrice = _closePrice();
    if (shares == null ||
        closePrice == null ||
        shares <= 0 ||
        closePrice <= 0) {
      return;
    }

    setState(() => _saving = true);

    final result = await ref.read(closePositionUseCaseProvider).call(
          params: ClosePositionParams(
            positionId: widget.positionId,
            quantity: shares,
            closePrice: closePrice,
            closeDate: _closeDate,
          ),
        );

    if (!mounted) return;
    setState(() => _saving = false);

    await result.fold(
      (error) async {
        ref.read(alertProvider.notifier).showError(
              title: 'error'.tr(),
              message: error.message,
            );
      },
      (_) async {
        await ref.read(homeProvider.notifier).refresh(silent: true);
        if (!mounted) return;
        context.pop(true);
      },
    );
  }

  @override
  Widget buildView(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    return Scaffold(
      backgroundColor: PortfolioColors.background,
      appBar: AppBar(
        title: Text('close_position_title'.tr()),
        backgroundColor: PortfolioColors.background,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppDimens.mediumMargin),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: PortfolioColors.surfaceCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: PortfolioColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.ticker,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: PortfolioColors.textPrimary,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'position_shares'.tr(
                      namedArgs: {'count': widget.quantity.toString()},
                    ),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: PortfolioColors.textSecondary,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'close_position_avg_cost'.tr(
                      namedArgs: {
                        'price': currency.format(widget.avgPurchasePrice),
                      },
                    ),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: PortfolioColors.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: PortfolioColors.surfaceCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: PortfolioColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'close_position_scope'.tr(),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: PortfolioColors.textPrimary,
                        ),
                  ),
                  const SizedBox(height: 12),
                  _DualChoiceRow<_CloseScope>(
                    value: _scope,
                    leftValue: _CloseScope.all,
                    rightValue: _CloseScope.partial,
                    leftLabel: 'close_position_scope_all'.tr(),
                    rightLabel: 'close_position_scope_partial'.tr(),
                    onChanged: _onScopeChanged,
                  ),
                  if (_scope == _CloseScope.partial) ...[
                    const SizedBox(height: 20),
                    Text(
                      'close_position_sell_amount'.tr(),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: PortfolioColors.textPrimary,
                          ),
                    ),
                    const SizedBox(height: 12),
                    _DualChoiceRow<_SellInputMode>(
                      value: _sellMode,
                      leftValue: _SellInputMode.shares,
                      rightValue: _SellInputMode.usd,
                      leftLabel: 'position_amount_type_shares'.tr(),
                      rightLabel: 'position_amount_type_usd'.tr(),
                      onChanged: (mode) => setState(() => _sellMode = mode),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _sellAmountController,
                      decoration: InputDecoration(
                        labelText: _sellMode == _SellInputMode.shares
                            ? 'position_quantity'.tr()
                            : 'position_invested_amount'.tr(),
                        hintText: _sellMode == _SellInputMode.shares
                            ? _maxShares.toStringAsFixed(4)
                            : null,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style:
                          const TextStyle(color: PortfolioColors.textPrimary),
                      validator: _validateSellAmount,
                      onChanged: (_) => setState(() {}),
                    ),
                    if (_sharesEquivalentHint(context) != null)
                      _sharesEquivalentHint(context)!,
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'close_position_date'.tr(),
                style: const TextStyle(color: PortfolioColors.textPrimary),
              ),
              subtitle: Text(
                DateFormat.yMMMd().format(_closeDate),
                style: const TextStyle(color: PortfolioColors.textSecondary),
              ),
              trailing: const Icon(
                Icons.calendar_today,
                color: PortfolioColors.textSecondary,
              ),
              onTap: _pickDate,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _priceController,
              decoration: InputDecoration(
                labelText: 'close_position_price'.tr(),
                suffixIcon: _loadingPrice
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        tooltip: 'retry'.tr(),
                        onPressed: _fetchPriceForDate,
                        icon: const Icon(Icons.refresh),
                      ),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: const TextStyle(color: PortfolioColors.textPrimary),
              validator: (v) {
                final n = double.tryParse(v ?? '');
                if (n == null || n <= 0) return 'invalid_number'.tr();
                return null;
              },
              onChanged: (_) => setState(() {}),
            ),
            _preview(context),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('close_position_confirm'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

class _DualChoiceRow<T> extends StatelessWidget {
  const _DualChoiceRow({
    required this.value,
    required this.leftValue,
    required this.rightValue,
    required this.leftLabel,
    required this.rightLabel,
    required this.onChanged,
  });

  final T value;
  final T leftValue;
  final T rightValue;
  final String leftLabel;
  final String rightLabel;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ChoiceTile(
            label: leftLabel,
            selected: value == leftValue,
            onTap: () => onChanged(leftValue),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ChoiceTile(
            label: rightLabel,
            selected: value == rightValue,
            onTap: () => onChanged(rightValue),
          ),
        ),
      ],
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? PortfolioColors.accentBlue.withValues(alpha: 0.22)
                : PortfolioColors.surfaceElevated,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? PortfolioColors.accentBlue
                  : PortfolioColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? PortfolioColors.textPrimary
                      : PortfolioColors.textSecondary,
                ),
          ),
        ),
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _PreviewRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: PortfolioColors.textSecondary,
                  ),
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: valueColor ?? PortfolioColors.textPrimary,
                ),
          ),
        ],
      ),
    );
  }
}
