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

class ClosePositionScreen extends StatefulHookConsumerWidget {
  final String ticker;
  final double quantity;
  final double avgPurchasePrice;

  const ClosePositionScreen({
    super.key,
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
  DateTime _closeDate = DateTime.now();
  bool _saving = false;
  bool _loadingPrice = false;
  @override
  void initState() {
    _priceController = TextEditingController();
    super.initState();
    runAfterPostFrameCallback(_fetchPriceForDate);
  }

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
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

  double? _closePrice() => double.tryParse(_priceController.text);

  Widget _preview(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final closePrice = _closePrice();
    if (closePrice == null || closePrice <= 0) {
      return const SizedBox.shrink();
    }

    final costBasis = widget.quantity * widget.avgPurchasePrice;
    final proceeds = widget.quantity * closePrice;
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final result = await ref.read(closePositionUseCaseProvider).call(
          params: ClosePositionParams(
            ticker: widget.ticker,
            quantity: widget.quantity,
            avgPurchasePrice: widget.avgPurchasePrice,
            closePrice: double.parse(_priceController.text),
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
