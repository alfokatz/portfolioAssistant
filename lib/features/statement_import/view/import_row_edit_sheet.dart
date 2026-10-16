import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:portfolio_assistant/features/statement_import/domain/import_row.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';
import 'package:portfolio_assistant/shared/utils/user_number.dart';

/// Lo que el usuario corrigió de una fila.
class ImportRowEdit {
  const ImportRowEdit({
    required this.ticker,
    required this.quantity,
    required this.purchasePrice,
    required this.purchaseDate,
  });

  final String ticker;
  final double quantity;
  final double? purchasePrice;
  final DateTime? purchaseDate;
}

/// Corregir una fila de la vista previa: ticker, cantidad, precio y fecha.
class ImportRowEditSheet extends StatefulWidget {
  const ImportRowEditSheet({super.key, required this.row});

  final ImportRow row;

  static Future<void> show(
    BuildContext context, {
    required ImportRow row,
    required ValueChanged<ImportRowEdit> onSave,
  }) async {
    final edit = await showModalBottomSheet<ImportRowEdit>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ImportRowEditSheet(row: row),
    );
    if (edit != null) onSave(edit);
  }

  @override
  State<ImportRowEditSheet> createState() => _ImportRowEditSheetState();
}

class _ImportRowEditSheetState extends State<ImportRowEditSheet> {
  late final _ticker = TextEditingController(text: widget.row.ticker);
  late final _quantity = TextEditingController(
    text: _plain(widget.row.quantity),
  );
  late final _price = TextEditingController(
    text:
        widget.row.purchasePrice == null
            ? ''
            : _plain(widget.row.purchasePrice!),
  );
  late DateTime? _date = widget.row.purchaseDate;
  String? _error;

  static String _plain(double v) {
    final s = v.toStringAsFixed(6);
    return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _quantity.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(1990),
      lastDate: now,
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  void _save() {
    final ticker = _ticker.text.trim().toUpperCase();
    final quantity = parseUserNumber(_quantity.text);
    final price = parseUserNumber(_price.text);
    if (ticker.isEmpty) {
      setState(() => _error = 'import_edit_error_ticker'.tr());
      return;
    }
    if (quantity == null || quantity <= 0) {
      setState(() => _error = 'import_edit_error_quantity'.tr());
      return;
    }
    if (_price.text.trim().isNotEmpty && (price == null || price <= 0)) {
      setState(() => _error = 'import_edit_error_price'.tr());
      return;
    }
    Navigator.of(context).pop(
      ImportRowEdit(
        ticker: ticker,
        quantity: quantity,
        purchasePrice: price,
        purchaseDate: _date,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final numberFormatters = [
      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
    ];
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
              Semantics(
                header: true,
                child: Text(
                  'import_edit_title'.tr(),
                  style: tt.titleLarge?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              if (widget.row.name != null) ...[
                const SizedBox(height: AppDimens.sp4),
                Text(
                  widget.row.name!,
                  style: tt.bodyMedium?.copyWith(color: colors.textSecondary),
                ),
              ],
              const SizedBox(height: AppDimens.sp20),
              TextField(
                controller: _ticker,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'import_edit_ticker'.tr(),
                  helperText: 'import_edit_ticker_help'.tr(),
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: AppDimens.sp12),
              TextField(
                controller: _quantity,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: numberFormatters,
                decoration: InputDecoration(
                  labelText: 'import_edit_quantity'.tr(),
                ),
              ),
              const SizedBox(height: AppDimens.sp12),
              TextField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: numberFormatters,
                decoration: InputDecoration(
                  labelText: 'import_edit_price'.tr(),
                  prefixText: '\$ ',
                ),
              ),
              const SizedBox(height: AppDimens.sp12),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'import_edit_date'.tr(),
                    suffixIcon: const Icon(Icons.calendar_today_outlined),
                  ),
                  child: Text(
                    _date == null
                        ? 'import_edit_date_missing'.tr()
                        : DateFormat.yMMMd().format(_date!),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppDimens.sp12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: tt.bodySmall?.copyWith(color: colors.loss),
                  ),
                ),
              ],
              const SizedBox(height: AppDimens.sp20),
              PositionPrimaryButton(
                label: 'import_edit_save'.tr(),
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
