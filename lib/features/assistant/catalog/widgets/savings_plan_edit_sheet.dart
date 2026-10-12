import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:portfolio_assistant/domain/entities/investor_profile.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/savings_plan_calculator.dart';

/// Lo que el usuario cambió del plan en la card.
class SavingsPlanEdit {
  const SavingsPlanEdit({
    required this.label,
    required this.targetAmount,
    required this.targetDate,
    required this.currentAmount,
    required this.risk,
  });

  final String label;
  final double targetAmount;
  final DateTime targetDate;
  final double currentAmount;
  final RiskTolerance risk;
}

/// "Editar plan": nombre, monto, fecha, lo que ya tiene y el riesgo. Al
/// aplicar, la card recalcula el plan (mismo cálculo que Porty, sin una
/// consulta) y lo que confirme se guarda así.
class SavingsPlanEditSheet extends StatefulWidget {
  const SavingsPlanEditSheet({
    super.key,
    required this.label,
    required this.inputs,
    required this.targetDate,
  });

  final String label;
  final SavingsPlanInputs inputs;
  final DateTime targetDate;

  static Future<SavingsPlanEdit?> show(
    BuildContext context, {
    required String label,
    required SavingsPlanInputs inputs,
    required DateTime targetDate,
  }) => showModalBottomSheet<SavingsPlanEdit>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: QaColors.surfaceCard,
    builder:
        (_) => SavingsPlanEditSheet(
          label: label,
          inputs: inputs,
          targetDate: targetDate,
        ),
  );

  static const _months = [
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ];

  static String monthYear(DateTime d) => '${_months[d.month - 1]} de ${d.year}';

  @override
  State<SavingsPlanEditSheet> createState() => _SavingsPlanEditSheetState();
}

class _SavingsPlanEditSheetState extends State<SavingsPlanEditSheet> {
  late final _label = TextEditingController(text: widget.label);
  late final _amount = TextEditingController(
    text: widget.inputs.targetAmount.round().toString(),
  );
  late final _current = TextEditingController(
    text:
        widget.inputs.currentAmount > 0
            ? widget.inputs.currentAmount.round().toString()
            : '',
  );
  late DateTime _date = widget.targetDate;
  late RiskTolerance _risk = widget.inputs.risk;

  DateTime get _start => widget.inputs.startDate;

  @override
  void initState() {
    super.initState();
    for (final c in [_label, _amount, _current]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _label.dispose();
    _amount.dispose();
    _current.dispose();
    super.dispose();
  }

  /// Montos en dólares enteros (el campo solo acepta dígitos).
  static double? _number(String text) => double.tryParse(text.trim());

  double? get _amountValue {
    final v = _number(_amount.text);
    return v != null && v > 0 ? v : null;
  }

  double? get _currentValue {
    if (_current.text.trim().isEmpty) return 0;
    final v = _number(_current.text);
    return v != null && v >= 0 ? v : null;
  }

  int get _monthsAhead =>
      (_date.year - _start.year) * 12 + (_date.month - _start.month);

  /// Lo mismo que decide el plan: a 3 años o menos (y no es el retiro) va a
  /// liquidez y bonos cortos, sin importar el riesgo.
  bool get _shortTerm =>
      !widget.inputs.isRetirement &&
      _monthsAhead <= PlanAssumptions.shortHorizonMonths;

  bool get _valid =>
      _label.text.trim().isNotEmpty &&
      _amountValue != null &&
      _currentValue != null &&
      _monthsAhead >= 1;

  /// Los atajos cuentan desde hoy (en una meta guardada hace meses, "en 3
  /// años" es desde hoy, no desde que se creó).
  static DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime _inYears(int years) =>
      DateTime(_today.year + years, _today.month, _today.day);

  bool _isInYears(int years) {
    final d = _inYears(years);
    return _date.year == d.year && _date.month == d.month;
  }

  Future<void> _pickDate() async {
    final first = DateTime(_today.year, _today.month + 1, _today.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(first) ? first : _date,
      firstDate: first,
      lastDate: DateTime(_today.year + 60, _today.month, _today.day),
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'Para cuándo',
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _apply() {
    if (!_valid) return;
    Navigator.of(context).pop(
      SavingsPlanEdit(
        label: _label.text.trim(),
        targetAmount: _amountValue!,
        targetDate: _date,
        currentAmount: _currentValue!,
        risk: _risk,
      ),
    );
  }

  /// Chip con los colores de las cards de Porty (no los del tema).
  Widget _chip(
    String label, {
    required bool selected,
    required VoidCallback onTap,
  }) => ChoiceChip(
    label: Text(label),
    selected: selected,
    onSelected: (_) => onTap(),
    showCheckmark: false,
    labelStyle: QaText.label.copyWith(
      color: selected ? QaColors.accentBlue : QaColors.textPrimary,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
    ),
    backgroundColor: QaColors.surfaceCard,
    selectedColor: QaPalette.accentTint,
    side: BorderSide(color: selected ? QaColors.accentBlue : QaColors.border),
    shape: const StadiumBorder(),
  );

  InputDecoration _decoration(String label, {String? prefix, String? hint}) =>
      InputDecoration(
        labelText: label,
        prefixText: prefix,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: QaColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: QaColors.accentBlue, width: 1.5),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final digits = [FilteringTextInputFormatter.digitsOnly];
    const quickYears = [1, 2, 3, 5, 10];
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Editar plan', style: QaText.cardTitle),
            const SizedBox(height: 4),
            Text(
              'Cambiá lo que quieras y el plan se recalcula al toque.',
              style: QaText.caption,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _label,
              textCapitalization: TextCapitalization.sentences,
              decoration: _decoration('Nombre de la meta'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: digits,
              decoration: _decoration('Cuánto necesitás', prefix: r'$ '),
            ),
            const SizedBox(height: 16),
            Text('Para cuándo', style: QaText.label),
            const SizedBox(height: 8),
            Material(
              color: QaPalette.inset,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _pickDate,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.event_outlined,
                        size: 20,
                        color: QaColors.accentBlue,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          SavingsPlanEditSheet.monthYear(_date),
                          style: QaText.value,
                        ),
                      ),
                      Text(
                        'Cambiar',
                        style: QaText.label.copyWith(
                          color: QaColors.accentBlue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final y in quickYears)
                  _chip(
                    y == 1 ? 'En 1 año' : 'En $y años',
                    selected: _isInYears(y),
                    onTap: () => setState(() => _date = _inYears(y)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _current,
              keyboardType: TextInputType.number,
              inputFormatters: digits,
              decoration: _decoration(
                'Lo que ya tenés para esto',
                prefix: r'$ ',
                hint: '0',
              ),
            ),
            const SizedBox(height: 16),
            Text('Cómo invertir', style: QaText.label),
            const SizedBox(height: 8),
            if (_shortTerm)
              Text(
                'La necesitás en 3 años o menos: va a liquidez y bonos '
                'cortos, sin acciones, para que una caída no te agarre justo '
                'antes de usarla.',
                style: QaText.caption,
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (risk, name) in const [
                    (RiskTolerance.conservative, 'Conservadora'),
                    (RiskTolerance.moderate, 'Moderada'),
                    (RiskTolerance.aggressive, 'Agresiva'),
                  ])
                    _chip(
                      name,
                      selected: _risk == risk,
                      onTap: () => setState(() => _risk = risk),
                    ),
                ],
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _valid ? _apply : null,
              style: FilledButton.styleFrom(
                backgroundColor: QaColors.accentBlue,
                foregroundColor: QaColors.onAccent,
                minimumSize: const Size.fromHeight(48),
                shape: const StadiumBorder(),
              ),
              child: Text(
                'Aplicar cambios',
                style: QaText.label.copyWith(
                  color: QaColors.onAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
