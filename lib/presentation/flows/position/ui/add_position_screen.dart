import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/use_cases/add_position_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_current_price_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_price_on_date_use_case.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';

enum _BuyInputMode { shares, usd }

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
  late final TextEditingController _tickerController;
  late final TextEditingController _quantityController; // shares or USD amount
  late final TextEditingController _priceController;
  DateTime _purchaseDate = DateTime.now();
  bool _saving = false;
  bool _loadingPrice = false;
  bool _datePicked = false;
  _BuyInputMode _mode = _BuyInputMode.shares;
  double? _currentPrice;
  bool _loadingCurrent = false;

  @override
  void initState() {
    _tickerController = TextEditingController(text: widget.prefilledTicker);
    _quantityController = TextEditingController(
      text: widget.prefilledQuantity?.toString() ?? '',
    );
    _priceController = TextEditingController(
      text: widget.prefilledPrice?.toString() ?? '',
    );
    if (widget.prefilledPrice != null) _datePicked = true;
    super.initState();
  }

  @override
  void dispose() {
    _tickerController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _purchaseDate,
      firstDate: DateTime(1990),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      _purchaseDate = picked;
      _datePicked = true;
    });
    await _fetchPriceForDate();
  }

  Future<void> _fetchPriceForDate() async {
    final ticker = _tickerController.text.trim();
    if (ticker.isEmpty || !_datePicked) return;

    setState(() => _loadingPrice = true);
    final result = await ref
        .read(getPriceOnDateUseCaseProvider)
        .call(
          params: GetPriceOnDateParams(ticker: ticker, date: _purchaseDate),
        );

    if (!mounted) return;
    setState(() => _loadingPrice = false);

    result.fold(
      (_) {
        // Keep user-editable field; just avoid overwriting.
      },
      (price) {
        if (price > 0) {
          setState(() {
            _priceController.text = price.toStringAsFixed(2);
          });
        }
      },
    );

    await _fetchCurrentPrice();
  }

  Future<void> _fetchCurrentPrice() async {
    final ticker = _tickerController.text.trim();
    if (ticker.isEmpty) return;

    setState(() => _loadingCurrent = true);
    final result = await ref
        .read(getCurrentPriceUseCaseProvider)
        .call(params: ticker);
    if (!mounted) return;
    setState(() => _loadingCurrent = false);

    result.fold(
      (_) => setState(() => _currentPrice = null),
      (price) => setState(() => _currentPrice = price),
    );
  }

  double? _purchasePrice() => double.tryParse(_priceController.text);

  double? _shares() {
    final p = _purchasePrice();
    if (p == null || p <= 0) return null;
    final raw = double.tryParse(_quantityController.text);
    if (raw == null || raw <= 0) return null;
    return _mode == _BuyInputMode.shares ? raw : (raw / p);
  }

  void _onFormInputsChanged() {
    if (mounted) setState(() {});
  }

  Widget? _sharesEquivalentHint(BuildContext context) {
    if (_mode != _BuyInputMode.usd) return null;

    final shares = _shares();
    if (shares == null) return null;

    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 4),
      child: Text(
        'position_shares_equivalent'.tr(
          namedArgs: {'shares': shares.toStringAsFixed(4)},
        ),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _preview(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final purchase = _purchasePrice();
    final shares = _shares();
    final current = _currentPrice;
    if (purchase == null || shares == null || current == null) {
      return const SizedBox.shrink();
    }

    final invested = shares * purchase;
    final marketValue = shares * current;
    final pnlAbs = marketValue - invested;
    final pnlPct = invested > 0 ? (pnlAbs / invested) * 100 : 0.0;
    final sign = pnlAbs >= 0 ? '+' : '';

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'position_preview_title'.tr(),
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          _PreviewRow(
            label: 'position_preview_current_price'.tr(),
            value: currency.format(current),
          ),
          _PreviewRow(
            label: 'position_preview_shares'.tr(),
            value: shares.toStringAsFixed(6),
          ),
          _PreviewRow(
            label: 'position_preview_market_value'.tr(),
            value: currency.format(marketValue),
          ),
          _PreviewRow(
            label: 'position_preview_pnl'.tr(),
            value:
                '$sign${currency.format(pnlAbs)} (${pnlPct.toStringAsFixed(2)}%)',
            valueStyle: TextStyle(
              color:
                  pnlAbs >= 0
                      ? Theme.of(context).colorScheme.tertiary
                      : Theme.of(context).colorScheme.error,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final shares = _shares() ?? 0;
    final purchasePrice = double.parse(_priceController.text);

    final result = await ref
        .read(addPositionUseCaseProvider)
        .call(
          params: AddPositionParams(
            ticker: _tickerController.text,
            quantity: shares,
            purchasePrice: purchasePrice,
            purchaseDate: _purchaseDate,
          ),
        );

    if (!mounted) return;
    setState(() => _saving = false);

    await result.fold(
      (error) async {
        ref
            .read(alertProvider.notifier)
            .showError(title: 'error'.tr(), message: error.message);
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
    return Scaffold(
      appBar: AppBar(title: Text('add_position'.tr())),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppDimens.mediumMargin),
          children: [
            TextFormField(
              controller: _tickerController,
              decoration: InputDecoration(
                labelText: 'position_ticker'.tr(),
                hintText: 'AAPL',
              ),
              textCapitalization: TextCapitalization.characters,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              validator:
                  (v) =>
                      v == null || v.trim().isEmpty
                          ? 'field_required'.tr()
                          : null,
              onFieldSubmitted: (_) => _fetchPriceForDate(),
            ),
            const SizedBox(height: 16),
            SegmentedButton<_BuyInputMode>(
              segments: [
                ButtonSegment(
                  value: _BuyInputMode.shares,
                  label: Text('position_amount_type_shares'.tr()),
                ),
                ButtonSegment(
                  value: _BuyInputMode.usd,
                  label: Text('position_amount_type_usd'.tr()),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (value) {
                setState(() => _mode = value.first);
                _onFormInputsChanged();
              },
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('position_purchase_date'.tr()),
              subtitle: Text(DateFormat.yMMMd().format(_purchaseDate)),
              trailing: const Icon(Icons.calendar_today),
              onTap: _pickDate,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _priceController,
              decoration: InputDecoration(
                labelText: 'position_purchase_price'.tr(),
                suffixIcon:
                    _loadingPrice
                        ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                        : IconButton(
                          tooltip: 'Recalcular',
                          onPressed: _fetchPriceForDate,
                          icon: const Icon(Icons.refresh),
                        ),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              validator: (v) {
                final n = double.tryParse(v ?? '');
                if (n == null || n <= 0) return 'invalid_number'.tr();
                return null;
              },
              onChanged: (_) {
                _onFormInputsChanged();
                _fetchCurrentPrice();
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _quantityController,
              decoration: InputDecoration(
                labelText:
                    _mode == _BuyInputMode.shares
                        ? 'position_quantity'.tr()
                        : 'position_invested_amount'.tr(),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              validator: (v) {
                final n = double.tryParse(v ?? '');
                if (n == null || n <= 0) return 'invalid_number'.tr();
                return null;
              },
              onChanged: (_) => _onFormInputsChanged(),
            ),
            _sharesEquivalentHint(context) ?? const SizedBox.shrink(),
            if (_loadingCurrent)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            _preview(context),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _saving ? null : _save,
              child:
                  _saving
                      ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : Text('save'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  final String label;
  final String value;
  final TextStyle? valueStyle;

  const _PreviewRow({
    required this.label,
    required this.value,
    this.valueStyle,
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
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style:
                valueStyle ??
                Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
