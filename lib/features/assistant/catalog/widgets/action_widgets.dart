import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/domain/utils/position_draft_math.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_action_scope.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_evidence_scope.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_identity.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_primitives.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_time.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/qa_card_shell.dart';
import 'package:portfolio_assistant/features/assistant/models/action_proposal.dart';
import 'package:portfolio_assistant/features/assistant/tools/action_tools.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';
import 'package:portfolio_assistant/presentation/shared/formatting/app_number_format.dart';
import 'package:portfolio_assistant/presentation/shared/loading/button_spinner.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/segmented_choice.dart';

/// La card de una operación que propuso Porty (compra, venta o borrado),
/// para que el usuario la revise, la edite y la confirme.
///
/// El modelo solo pasa `proposalId`: los datos salen del resultado de la
/// tool `propose_*` ([QaEvidenceScope]), así ningún número de la card puede
/// ser inventado. Confirmar y cancelar van por [QaActionScope], fuera del
/// modelo.
abstract final class ActionWidgets {
  static Widget qaActionProposal(CatalogItemContext ctx) {
    final id = '${(ctx.data as JsonMap)['proposalId'] ?? ''}';
    return Builder(
      builder:
          (context) => ValueListenableBuilder<TurnEvidence>(
            valueListenable: QaEvidenceScope.listenableOf(
              context,
              ctx.surfaceId,
            ),
            builder: (context, evidence, _) {
              final proposal = proposalFrom(evidence.calls, id);
              if (proposal == null) return const SizedBox.shrink();
              return QaCardShell(
                child: QaActionProposalCard(
                  key: ValueKey(proposal.id),
                  proposal: proposal,
                ),
              );
            },
          ),
    );
  }

  /// La propuesta [proposalId] entre las tool calls a la vista, o `null`.
  static ActionProposal? proposalFrom(
    List<ToolCallRecord> calls,
    String proposalId,
  ) {
    if (proposalId.isEmpty) return null;
    for (final call in calls.reversed) {
      if (!ActionTools.names.contains(call.name)) continue;
      if (call.result[ActionProposal.toolResultIdKey] != proposalId) continue;
      return ActionProposal.fromToolResult(call.result);
    }
    return null;
  }
}

/// El cuerpo de la card. El borrador (lo que el usuario edita) vive en este
/// `State`; en qué quedó la propuesta, en [QaActionScope], así una card ya
/// guardada no vuelve a ofrecer Confirmar si se desmonta al scrollear.
class QaActionProposalCard extends StatefulWidget {
  const QaActionProposalCard({super.key, required this.proposal});

  final ActionProposal proposal;

  @override
  State<QaActionProposalCard> createState() => _QaActionProposalCardState();
}

class _QaActionProposalCardState extends State<QaActionProposalCard> {
  static const _epsilon = 1e-6;

  final _amount = TextEditingController();
  final _price = TextEditingController();
  late AmountUnit _unit;
  DateTime? _date;
  late bool _priceEdited;
  bool _loadingPrice = false;
  late Set<String> _selectedLots;
  bool _initialized = false;

  ActionProposal get _p => widget.proposal;

  /// Sin registrar dependencia: para leer o guardar el formulario no hace
  /// falta redibujar (el `build` ya depende del scope).
  QaActionScope? get _scope =>
      context.getInheritedWidgetOfExactType<QaActionScope>();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    // Si la card se desmontó al scrollear, vuelve con lo que el usuario ya
    // había editado; si no, con lo que propuso Porty.
    final saved = _scope?.formOf?.call(_p.id);
    if (saved != null) {
      _unit = saved.unit;
      _amount.text = saved.amountText;
      _price.text = saved.priceText;
      _date = saved.date;
      _priceEdited = saved.priceEdited;
      _selectedLots = {...saved.selectedLots};
    } else {
      _unit = _p.unit;
      _amount.text = _plain(
        _unit == AmountUnit.usd ? _p.amountUsd : _p.shares,
      );
      _price.text = _plain(_p.price);
      _date = _p.date;
      _priceEdited = _p.priceSource == PriceSource.user;
      // Con una sola compra, esa; con varias, que elija (borrar todo por
      // defecto es fácil de confirmar sin querer).
      _selectedLots = _p.lots.length == 1 ? {_p.lots.first.id} : {};
    }
    _amount.addListener(_changed);
    _price.addListener(_changed);
  }

  @override
  void dispose() {
    _amount.dispose();
    _price.dispose();
    super.dispose();
  }

  void _changed() {
    setState(() {});
    _saveForm();
  }

  void _saveForm() => _scope?.onFormChanged?.call(
    _p.id,
    ActionForm(
      amountText: _amount.text,
      unit: _unit,
      priceText: _price.text,
      priceEdited: _priceEdited,
      date: _date,
      selectedLots: {..._selectedLots},
    ),
  );

  // ------------------------------------------------------------ cuentas

  double? get _priceValue => PositionDraftMath.positive(_norm(_price.text));

  double? get _shares => switch (_p.kind) {
    ActionKind.delete => _selectedLotShares,
    _ => PositionDraftMath.shares(
      amountText: _norm(_amount.text),
      isUsd: _unit == AmountUnit.usd,
      price: _priceValue,
    ),
  };

  double get _selectedLotShares => _p.lots
      .where((l) => _selectedLots.contains(l.id))
      .fold(0.0, (sum, l) => sum + l.quantity);

  bool get _exceeds {
    final shares = _shares;
    final held = _p.heldShares;
    return _p.kind == ActionKind.sell &&
        shares != null &&
        held != null &&
        shares > held + _epsilon;
  }

  bool get _valid => switch (_p.kind) {
    ActionKind.delete => _selectedLots.isNotEmpty,
    _ => _shares != null && _date != null && !_exceeds && !_loadingPrice,
  };

  ActionDraft _draft() => ActionDraft(
    proposalId: _p.id,
    kind: _p.kind,
    ticker: _p.ticker,
    shares: _shares,
    price: _p.kind == ActionKind.delete ? null : _priceValue,
    date: _p.kind == ActionKind.delete ? null : _date,
    lotIds: [
      if (_p.kind == ActionKind.delete)
        for (final lot in _p.lots)
          if (_selectedLots.contains(lot.id)) lot.id,
    ],
  );

  // ------------------------------------------------------------ acciones

  Future<void> _pickDate(QaActionScope scope) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final first =
        _p.kind == ActionKind.sell && _p.lots.isNotEmpty
            ? DateUtils.dateOnly(_p.lots.first.purchaseDate)
            : DateTime(1990);
    final current = _date ?? today;
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isBefore(first) ? first : current,
      firstDate: first,
      lastDate: today,
    );
    if (picked == null || !mounted) return;
    setState(() => _date = picked);
    _saveForm();
    if (_priceEdited) return;
    setState(() => _loadingPrice = true);
    final price = await scope.priceOn(_p.ticker, picked);
    if (!mounted) return;
    setState(() {
      _loadingPrice = false;
      // Si mientras tanto escribió un precio, ese manda.
      if (price != null &&
          PositionDraftMath.acceptsFetchedPrice(
            fetched: price,
            editedByUser: _priceEdited,
          )) {
        _price.text = _plain(price);
      }
    });
  }

  /// Al cambiar de unidad, el monto se convierte (si se puede) en vez de
  /// quedar el mismo número con otro significado.
  void _setUnit(AmountUnit unit) {
    final shares = _shares;
    final price = _priceValue;
    setState(() {
      _unit = unit;
      if (shares == null || price == null) return;
      _amount.text =
          unit == AmountUnit.usd
              ? (shares * price).toStringAsFixed(2)
              : _plain(shares);
    });
    _saveForm();
  }

  void _sellAll() {
    setState(() {
      _unit = AmountUnit.shares;
      _amount.text = _plain(_p.heldShares);
    });
    _saveForm();
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final scope = QaActionScope.maybeOf(context);
    final progress = scope?.progressOf(_p.id) ?? ActionProposalProgress.pending;
    final settled =
        progress.status == ActionProposalStatus.done ||
        progress.status == ActionProposalStatus.cancelled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_eyebrow.toUpperCase(), style: QaText.eyebrow),
        const SizedBox(height: QaSpace.gap),
        QaTickerHeader(
          ticker: _p.ticker,
          tappable: false,
          trailing: _statusTag(progress.status),
        ),
        const SizedBox(height: QaSpace.sectionGap),
        QaStateSwitcher(
          child: KeyedSubtree(
            key: ValueKey(settled),
            child:
                settled
                    ? _Summary(
                      proposal: _p,
                      draft: progress.draft ?? _draft(),
                      cancelled:
                          progress.status == ActionProposalStatus.cancelled,
                      onOpenPosition:
                          progress.status == ActionProposalStatus.done &&
                                  _p.kind != ActionKind.delete
                              ? scope?.onOpenPosition
                              : null,
                    )
                    : _form(scope, progress),
          ),
        ),
      ],
    );
  }

  String get _eyebrow => switch (_p.kind) {
    ActionKind.buy => 'Registrar compra',
    ActionKind.sell => 'Registrar venta',
    ActionKind.delete => 'Borrar posición',
  };

  Widget? _statusTag(ActionProposalStatus status) => switch (status) {
    ActionProposalStatus.done => QaTag(
      _p.kind == ActionKind.delete ? 'Borrada' : 'Registrada',
      color: QaColors.profit,
      icon: Icons.check_rounded,
    ),
    ActionProposalStatus.cancelled => const QaTag('Cancelada'),
    _ => null,
  };

  Widget _form(QaActionScope? scope, ActionProposalProgress progress) {
    final saving = progress.status == ActionProposalStatus.saving;
    final enabled = scope != null && !saving;
    final failed = progress.status == ActionProposalStatus.failed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_p.kind == ActionKind.delete)
          ..._deleteFields(enabled)
        else
          ..._tradeFields(scope, enabled),
        if (failed) ...[
          const SizedBox(height: QaSpace.gap),
          Text(
            progress.errorMessage ?? 'No se pudo guardar. Probá de nuevo.',
            style: QaText.body.copyWith(color: QaColors.loss),
          ),
        ],
        const SizedBox(height: QaSpace.sectionGap),
        PositionPrimaryButton(
          label:
              failed
                  ? 'Reintentar'
                  : _p.kind == ActionKind.delete
                  ? 'Confirmar borrado'
                  : 'Confirmar',
          loading: saving,
          onPressed:
              scope != null && _valid && progress.canConfirm
                  ? () => scope.onConfirm(_draft())
                  : null,
        ),
        if (!saving)
          Center(
            child: TextButton(
              onPressed: scope == null ? null : () => scope.onCancel(_draft()),
              child: Text(
                'Cancelar',
                style: QaText.bodyStrong.copyWith(
                  color: QaColors.textSecondary,
                ),
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _tradeFields(QaActionScope? scope, bool enabled) {
    final isSell = _p.kind == ActionKind.sell;
    final shares = _shares;
    final price = _priceValue;
    final held = _p.heldShares;
    return [
      _DateField(
        label: isSell ? 'Fecha de venta' : 'Fecha de compra',
        date: _date,
        onTap: enabled ? () => _pickDate(scope!) : null,
      ),
      const SizedBox(height: QaSpace.gap),
      IgnorePointer(
        ignoring: !enabled,
        child: SegmentedChoice<AmountUnit>(
          selected: _unit,
          onChanged: _setUnit,
          options: const [
            (value: AmountUnit.shares, label: 'Acciones'),
            (value: AmountUnit.usd, label: 'USD'),
          ],
        ),
      ),
      const SizedBox(height: QaSpace.gap),
      TextField(
        key: const ValueKey('qa_action_amount'),
        controller: _amount,
        enabled: enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText:
              _unit == AmountUnit.shares
                  ? 'Cantidad de acciones'
                  : isSell
                  ? 'Monto vendido (USD)'
                  : 'Monto invertido (USD)',
        ),
      ),
      if (_unit == AmountUnit.usd && shares != null) ...[
        const SizedBox(height: 6),
        Text(
          'Equivale a ${AppNumberFormat.shares(shares)} acciones',
          style: QaText.label.copyWith(color: QaColors.accentBlue),
        ),
      ],
      if (isSell && held != null) ...[
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                'Tenés ${AppNumberFormat.shares(held)} acciones',
                style: QaText.label,
              ),
            ),
            TextButton(
              onPressed: enabled ? _sellAll : null,
              child: Text(
                'Vender todo',
                style: QaText.valueSm.copyWith(color: QaColors.accentBlue),
              ),
            ),
          ],
        ),
      ],
      if (_exceeds)
        Text(
          'No podés vender más acciones de las que tenés',
          style: QaText.label.copyWith(color: QaColors.loss),
        ),
      const SizedBox(height: QaSpace.gap),
      TextField(
        key: const ValueKey('qa_action_price'),
        controller: _price,
        enabled: enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) {
          _priceEdited = true;
          _saveForm();
        },
        decoration: InputDecoration(
          labelText: isSell ? 'Precio de venta' : 'Precio de compra',
          prefixText: r'$ ',
          suffixIcon:
              _loadingPrice
                  ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: ButtonSpinner.small(color: QaColors.accentBlue),
                  )
                  : null,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        price == null && !_loadingPrice
            ? 'No encontramos el precio de ese día: completalo para confirmar.'
            : _priceEdited
            ? 'El precio que nos dijiste.'
            : 'Cierre de ese día. Cambialo si operaste a otro precio.',
        style: QaText.caption,
      ),
      if (shares != null && price != null) ...[
        const SizedBox(height: QaSpace.sectionGap),
        _totals(shares, price),
      ],
    ];
  }

  Widget _totals(double shares, double price) {
    final total = shares * price;
    if (_p.kind == ActionKind.buy) {
      return QaInset(child: QaStat(label: 'Total', value: QaFormat.price(total)));
    }
    final cost = _p.fifoCostBasis(shares);
    final pnl = cost == null ? null : total - cost;
    return QaInset(
      child: Row(
        children: [
          Expanded(
            child: QaStat(
              label: 'Monto recibido',
              value: QaFormat.price(total),
            ),
          ),
          if (pnl != null)
            Expanded(
              child: QaStat(
                label: 'Resultado estimado',
                value: QaFormat.signedPrice(pnl),
                valueColor: QaPalette.trend(pnl),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _deleteFields(bool enabled) {
    return [
      Text(
        'Borrar no registra una venta: la compra desaparece de tu cartera. '
        'Si la vendiste, pedile a Porty que registre la venta.',
        style: QaText.body.copyWith(color: QaColors.textSecondary),
      ),
      if (_p.lots.length > 1) ...[
        const SizedBox(height: QaSpace.gap),
        Text('¿Qué compra querés borrar?', style: QaText.bodyStrong),
      ],
      const SizedBox(height: 4),
      for (final lot in _p.lots)
        _LotRow(
          key: ValueKey('qa_action_lot_${lot.id}'),
          lot: lot,
          selected: _selectedLots.contains(lot.id),
          onChanged:
              enabled
                  ? (checked) {
                    setState(() {
                      checked
                          ? _selectedLots.add(lot.id)
                          : _selectedLots.remove(lot.id);
                    });
                    _saveForm();
                  }
                  : null,
        ),
    ];
  }

  /// Número para un campo editable: sin ceros de más ("2.5", "10").
  static String _plain(double? value) {
    if (value == null) return '';
    return value
        .toStringAsFixed(6)
        .replaceFirst(RegExp(r'\.?0+$'), '');
  }

  /// Acepta coma decimal (teclado en español).
  static String _norm(String text) => text.trim().replaceAll(',', '.');
}

/// Una compra para elegir en un borrado. Fila propia y no
/// `CheckboxListTile`: el ListTile pinta sobre el `Material` más cercano, que
/// queda debajo del fondo de la card.
class _LotRow extends StatelessWidget {
  const _LotRow({
    super.key,
    required this.lot,
    required this.selected,
    required this.onChanged,
  });

  final ActionLot lot;
  final bool selected;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    return Semantics(
      checked: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onChanged == null ? null : () => onChanged(!selected),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Checkbox(
                value: selected,
                activeColor: QaColors.accentBlue,
                onChanged:
                    onChanged == null ? null : (v) => onChanged(v ?? false),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${AppNumberFormat.shares(lot.quantity)} acciones a '
                      '${QaFormat.price(lot.purchasePrice)}',
                      style: QaText.value,
                    ),
                    Text(
                      'Compradas el ${QaTime.day(lot.purchaseDate)}',
                      style: QaText.label,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fecha de la operación, con el aspecto de los campos de texto del tema.
class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.date, this.onTap});

  final String label;
  final DateTime? date;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: Material(
        color: QaColors.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(QaSpace.insetRadius),
          side: BorderSide(color: QaColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('qa_action_date'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: QaText.label),
                      const SizedBox(height: 2),
                      Text(
                        date == null ? 'Elegí la fecha' : QaTime.day(date!),
                        style: QaText.value,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.calendar_today_outlined,
                  size: 18,
                  color: QaColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// La operación ya resuelta (guardada o cancelada), de solo lectura.
class _Summary extends StatelessWidget {
  const _Summary({
    required this.proposal,
    required this.draft,
    required this.cancelled,
    this.onOpenPosition,
  });

  final ActionProposal proposal;
  final ActionDraft draft;
  final bool cancelled;
  final ValueChanged<String>? onOpenPosition;

  @override
  Widget build(BuildContext context) {
    final shares = draft.shares;
    final price = draft.price;
    final date = draft.date;

    final Widget body;
    if (proposal.kind == ActionKind.delete) {
      final count = draft.lotIds.length;
      body = Text(
        cancelled
            ? 'No se borró nada.'
            : '${QaFormat.plural(count, 'compra borrada', 'compras borradas')}'
                '${shares != null ? ' · ${AppNumberFormat.shares(shares)} acciones' : ''}',
        style: QaText.body,
      );
    } else {
      body = QaStatGrid(
        stats: [
          if (date != null) QaStat(label: 'Fecha', value: QaTime.day(date)),
          if (shares != null)
            QaStat(label: 'Acciones', value: AppNumberFormat.shares(shares)),
          if (price != null)
            QaStat(label: 'Precio', value: QaFormat.price(price)),
          if (shares != null && price != null)
            QaStat(
              label:
                  proposal.kind == ActionKind.sell ? 'Monto recibido' : 'Total',
              value: QaFormat.price(shares * price),
            ),
        ],
      );
    }

    return Opacity(
      opacity: cancelled ? 0.55 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          body,
          if (onOpenPosition != null) ...[
            const SizedBox(height: QaSpace.gap),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => onOpenPosition!(proposal.ticker),
                // Alineado con el texto de la card, no con el padding del
                // botón.
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Ver en cartera',
                  style: QaText.bodyStrong.copyWith(
                    color: QaColors.accentBlue,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
