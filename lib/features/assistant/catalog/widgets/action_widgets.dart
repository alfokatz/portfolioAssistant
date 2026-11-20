import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/utils/position_draft_math.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_action_scope.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_evidence_scope.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_identity.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_primitives.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_time.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/qa_card_shell.dart';
import 'package:portfolio_assistant/features/assistant/models/action_proposal.dart';
import 'package:portfolio_assistant/features/assistant/models/manage_action.dart';
import 'package:portfolio_assistant/features/assistant/tools/action_tools.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';
import 'package:portfolio_assistant/presentation/shared/formatting/app_number_format.dart';
import 'package:portfolio_assistant/presentation/shared/loading/button_spinner.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/segmented_choice.dart';

/// La card de una operación que propuso Porty (compra, venta, borrado, una
/// alerta de precio o seguir un ticker), para que el usuario la revise, la
/// edite y la confirme.
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
      if (!ActionTools.proposalTools.contains(call.name)) continue;
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
  late bool _repeatDaily;
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
      _repeatDaily = saved.repeatDaily;
    } else {
      _unit = _p.unit;
      _amount.text = _plain(_unit == AmountUnit.usd ? _p.amountUsd : _p.shares);
      // Alerta: el campo editable es el objetivo; el precio de ahora es fijo.
      _price.text = _plain(_isAlert ? _p.alertTarget : _p.price);
      _date = _p.date;
      _repeatDaily = _isWatch ? _p.watchNotify : _p.alertRepeatDaily;
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
      repeatDaily: _repeatDaily,
    ),
  );

  bool get _isAlert => _p.kind == ActionKind.alert;

  bool get _isWatch => _p.kind == ActionKind.watch;

  bool get _isManage => _p.kind == ActionKind.manage;

  bool get _alertIsPercent => _p.alertCondition?.startsWith('pct_') ?? false;

  /// Por qué el objetivo de la alerta no sirve, o `null` si sirve.
  String? get _alertError {
    final target = _priceValue;
    final now = _p.price;
    if (target == null) return 'qa_act_err_positive'.tr();
    if (_alertIsPercent) {
      return target < 1 || target > 90
          ? 'qa_act_err_pct'.tr()
          : null;
    }
    if (now == null) return null;
    if (_p.alertCondition == 'above' && target <= now) {
      return 'qa_act_err_above'.tr();
    }
    if (_p.alertCondition == 'below' && target >= now) {
      return 'qa_act_err_below'.tr();
    }
    return null;
  }

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
    ActionKind.alert => _alertError == null,
    ActionKind.watch || ActionKind.manage => true,
    _ => _shares != null && _date != null && !_exceeds && !_loadingPrice,
  };

  ActionDraft _draft() =>
      _isManage
          ? ActionDraft(
            proposalId: _p.id,
            kind: _p.kind,
            ticker: _p.ticker,
            manageOp: _p.manageOp,
            targetId: _p.targetId,
            targetLabel: _p.targetLabel,
            params: _p.params,
          )
          : _isWatch
          ? ActionDraft(
            proposalId: _p.id,
            kind: _p.kind,
            ticker: _p.ticker,
            price: _p.price,
            watchNotify: _repeatDaily,
          )
          : _isAlert
          ? ActionDraft(
            proposalId: _p.id,
            kind: _p.kind,
            ticker: _p.ticker,
            price: _p.price,
            alertCondition: _p.alertCondition,
            alertTarget: _priceValue,
            alertRepeatDaily: _repeatDaily,
          )
          : _tradeDraft();

  ActionDraft _tradeDraft() => ActionDraft(
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
    // Una venta que se llevó todas las acciones: ya no hay nada en cartera,
    // así que el link va a la posición cerrada. Una parcial sigue en cartera.
    final sold = progress.draft?.shares;
    final held = _p.heldShares;
    final closed =
        sold != null && (held == null || sold >= held - _epsilon)
            ? progress.closedPosition
            : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_eyebrow.toUpperCase(), style: QaText.eyebrow),
        const SizedBox(height: QaSpace.gap),
        if (_p.ticker.isEmpty)
          QaCardTitle(
            title: _p.targetLabel ?? _eyebrow,
            icon: Icons.tune_rounded,
            trailing: _statusTag(progress.status),
          )
        else
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
                                  _p.kind != ActionKind.delete &&
                                  !_isAlert &&
                                  !_isWatch &&
                                  !_isManage &&
                                  closed == null
                              ? scope?.onOpenPosition
                              : null,
                      onOpenAlerts:
                          progress.status == ActionProposalStatus.done &&
                                  (_isAlert ||
                                      _p.manageOp?.link == ManageLink.alerts)
                              ? scope?.onOpenAlerts
                              : null,
                      onOpenWatchlist:
                          progress.status == ActionProposalStatus.done &&
                                  (_isWatch ||
                                      _p.manageOp?.link == ManageLink.watchlist)
                              ? scope?.onOpenWatchlist
                              : null,
                      onOpenManaged:
                          progress.status == ActionProposalStatus.done
                              ? _manageLink(scope)
                              : null,
                      closedPosition: closed,
                      onOpenClosedPosition: scope?.onOpenClosedPosition,
                    )
                    : _form(scope, progress),
          ),
        ),
      ],
    );
  }

  /// El link de una gestión de metas resuelta ("Ver la meta", "Ver mis
  /// metas"); las de lista y alertas usan los links de siempre.
  ({String label, VoidCallback onTap})? _manageLink(QaActionScope? scope) {
    final id = _p.targetId;
    final openGoal = scope?.onOpenGoal;
    final openGoals = scope?.onOpenGoals;
    final openAllocation = scope?.onOpenAllocation;
    final openSettings = scope?.onOpenSettings;
    final openMemory = scope?.onOpenMemory;
    final openBroker = scope?.onOpenBroker;
    final broker = switch (_p.params['broker']) {
      'binance' => 'binance',
      'snaptrade' => 'snaptrade',
      _ => 'etoro',
    };
    final touchesNotifications = _p.manageTarget.changes.keys.any(
      (k) =>
          k.startsWith('notif') ||
          k == AppSettingKeys.sensitivity ||
          k == AppSettingKeys.quietHours,
    );
    return switch (_p.manageOp?.link) {
      ManageLink.goal when openGoal != null && id != null => (
        label: 'qa_act_link_goal'.tr(),
        onTap: () => openGoal(id),
      ),
      ManageLink.goals when openGoals != null => (
        label: 'qa_act_link_goals'.tr(),
        onTap: openGoals,
      ),
      ManageLink.allocation when openAllocation != null => (
        label: 'qa_act_link_plan'.tr(),
        onTap: openAllocation,
      ),
      ManageLink.settings when openSettings != null => (
        label:
            touchesNotifications
                ? 'qa_act_link_notifications'.tr()
                : 'qa_act_link_settings'.tr(),
        onTap: () => openSettings(notifications: touchesNotifications),
      ),
      ManageLink.memory when openMemory != null => (
        label: 'qa_act_link_memory'.tr(),
        onTap: openMemory,
      ),
      ManageLink.broker when openBroker != null => (
        label: switch (broker) {
          'binance' => 'qa_act_link_binance'.tr(),
          'snaptrade' => 'qa_act_link_brokers'.tr(),
          _ => 'qa_act_link_etoro'.tr(),
        },
        onTap: () => openBroker(broker),
      ),
      _ => null,
    };
  }

  String get _eyebrow => switch (_p.kind) {
    ActionKind.buy => 'qa_act_eyebrow_buy'.tr(),
    ActionKind.sell => 'qa_act_eyebrow_sell'.tr(),
    ActionKind.delete => 'qa_act_eyebrow_delete'.tr(),
    ActionKind.alert => 'qa_act_eyebrow_alert'.tr(),
    ActionKind.watch => 'qa_act_eyebrow_watch'.tr(),
    ActionKind.manage => _p.manageOp?.eyebrow ?? 'qa_act_eyebrow_manage'.tr(),
  };

  Widget? _statusTag(ActionProposalStatus status) => switch (status) {
    ActionProposalStatus.done => QaTag(
      switch (_p.kind) {
        ActionKind.delete => 'qa_act_tag_deleted'.tr(),
        ActionKind.alert => 'qa_act_tag_created'.tr(),
        ActionKind.watch => 'qa_act_tag_following'.tr(),
        ActionKind.manage => _p.manageOp?.doneTag ?? 'qa_act_tag_done'.tr(),
        _ => 'qa_act_tag_recorded'.tr(),
      },
      color: QaColors.profit,
      icon: Icons.check_rounded,
    ),
    ActionProposalStatus.cancelled => QaTag('qa_act_tag_cancelled'.tr()),
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
        else if (_isAlert)
          ..._alertFields(enabled)
        else if (_isWatch)
          ..._watchFields(enabled)
        else if (_isManage)
          Text(
            _p.manageOp!.describe(_p.manageTarget),
            style: QaText.body.copyWith(color: QaColors.textSecondary),
          )
        else
          ..._tradeFields(scope, enabled),
        if (failed) ...[
          const SizedBox(height: QaSpace.gap),
          Text(
            progress.errorMessage ?? 'qa_act_save_failed'.tr(),
            style: QaText.body.copyWith(color: QaColors.loss),
          ),
        ],
        const SizedBox(height: QaSpace.sectionGap),
        PositionPrimaryButton(
          label:
              failed
                  ? 'qa_act_btn_retry'.tr()
                  : _p.kind == ActionKind.delete
                  ? 'qa_act_btn_confirm_delete'.tr()
                  : _isAlert
                  ? 'qa_act_btn_create_alert'.tr()
                  : _isWatch
                  ? 'qa_act_btn_follow'.tr(namedArgs: {'ticker': _p.ticker})
                  : _isManage
                  ? _p.manageOp!.confirmLabel(_p.manageTarget)
                  : 'qa_act_btn_confirm'.tr(),
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
                'qa_act_btn_cancel'.tr(),
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
        label:
            isSell ? 'qa_act_sell_date'.tr() : 'qa_act_buy_date'.tr(),
        date: _date,
        onTap: enabled ? () => _pickDate(scope!) : null,
      ),
      const SizedBox(height: QaSpace.gap),
      IgnorePointer(
        ignoring: !enabled,
        child: SegmentedChoice<AmountUnit>(
          selected: _unit,
          onChanged: _setUnit,
          options: [
            (value: AmountUnit.shares, label: 'qa_act_unit_shares'.tr()),
            (value: AmountUnit.usd, label: 'qa_act_unit_usd'.tr()),
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
                  ? 'qa_act_amount_shares'.tr()
                  : isSell
                  ? 'qa_act_amount_sold'.tr()
                  : 'qa_act_amount_invested'.tr(),
        ),
      ),
      if (_unit == AmountUnit.usd && shares != null) ...[
        const SizedBox(height: 6),
        Text(
          'qa_act_equals_shares'.tr(
            namedArgs: {'shares': AppNumberFormat.shares(shares)},
          ),
          style: QaText.label.copyWith(color: QaColors.accentBlue),
        ),
      ],
      if (isSell && held != null) ...[
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                'qa_act_you_hold'.tr(
                  namedArgs: {'shares': AppNumberFormat.shares(held)},
                ),
                style: QaText.label,
              ),
            ),
            TextButton(
              onPressed: enabled ? _sellAll : null,
              child: Text(
                'qa_act_sell_all'.tr(),
                style: QaText.valueSm.copyWith(color: QaColors.accentBlue),
              ),
            ),
          ],
        ),
      ],
      if (_exceeds)
        Text(
          'qa_act_cant_sell_more'.tr(),
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
          labelText:
              isSell
                  ? 'qa_act_sell_price'.tr()
                  : 'qa_act_buy_price'.tr(),
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
            ? 'qa_act_price_missing'.tr()
            : _priceEdited
            ? 'qa_act_price_yours'.tr()
            : 'qa_act_price_close'.tr(),
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
      return QaInset(
        child: QaStat(label: 'qa_act_total'.tr(), value: QaFormat.price(total)),
      );
    }
    final cost = _p.fifoCostBasis(shares);
    final pnl = cost == null ? null : total - cost;
    return QaInset(
      child: Row(
        children: [
          Expanded(
            child: QaStat(
              label: 'qa_act_received'.tr(),
              value: QaFormat.price(total),
            ),
          ),
          if (pnl != null)
            Expanded(
              child: QaStat(
                label: 'qa_act_est_result'.tr(),
                value: QaFormat.signedPrice(pnl),
                valueColor: QaPalette.trend(pnl),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _alertFields(bool enabled) {
    final now = _p.price;
    final target = _priceValue;
    final error = _price.text.trim().isEmpty ? null : _alertError;
    final label = switch (_p.alertCondition) {
      'above' => 'qa_act_alert_above'.tr(),
      'below' => 'qa_act_alert_below'.tr(),
      'pct_up' => 'qa_act_alert_pct_up'.tr(),
      _ => 'qa_act_alert_pct_down'.tr(),
    };
    final threshold =
        target == null || now == null || !_alertIsPercent
            ? null
            : now *
                (1 + (_p.alertCondition == 'pct_up' ? target : -target) / 100);
    return [
      TextField(
        key: const ValueKey('qa_action_alert_target'),
        controller: _price,
        enabled: enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          prefixText: _alertIsPercent ? null : r'$ ',
          suffixText: _alertIsPercent ? '%' : null,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        [
          if (now != null)
            'qa_act_alert_now'.tr(namedArgs: {'price': QaFormat.price(now)}),
          if (threshold != null)
            'qa_act_alert_threshold'.tr(
              namedArgs: {'price': QaFormat.price(threshold)},
            ),
        ].join(' · '),
        style: QaText.caption,
      ),
      if (error != null) ...[
        const SizedBox(height: 4),
        Text(error, style: QaText.label.copyWith(color: QaColors.loss)),
      ],
      const SizedBox(height: QaSpace.gap),
      Row(
        children: [
          Expanded(
            child: Text('qa_act_alert_repeat'.tr(), style: QaText.body),
          ),
          Switch.adaptive(
            key: const ValueKey('qa_action_alert_repeat'),
            value: _repeatDaily,
            activeTrackColor: QaColors.accentBlue,
            onChanged:
                enabled
                    ? (v) {
                      setState(() => _repeatDaily = v);
                      _saveForm();
                    }
                    : null,
          ),
        ],
      ),
      Text(
        'qa_act_alert_repeat_note'.tr(),
        style: QaText.caption,
      ),
    ];
  }

  List<Widget> _watchFields(bool enabled) {
    final now = _p.price;
    return [
      Text(
        'qa_act_watch_note'.tr(),
        style: QaText.body.copyWith(color: QaColors.textSecondary),
      ),
      if (now != null) ...[
        const SizedBox(height: QaSpace.gap),
        QaInset(
          child: QaStat(
            label: 'qa_act_today_price'.tr(),
            value: QaFormat.price(now),
          ),
        ),
      ],
      const SizedBox(height: QaSpace.gap),
      Row(
        children: [
          Expanded(
            child: Text(
              'qa_act_watch_notify'.tr(),
              style: QaText.body,
            ),
          ),
          Switch.adaptive(
            key: const ValueKey('qa_action_watch_notify'),
            value: _repeatDaily,
            activeTrackColor: QaColors.accentBlue,
            onChanged:
                enabled
                    ? (v) {
                      setState(() => _repeatDaily = v);
                      _saveForm();
                    }
                    : null,
          ),
        ],
      ),
    ];
  }

  List<Widget> _deleteFields(bool enabled) {
    return [
      Text(
        'qa_act_delete_note'.tr(),
        style: QaText.body.copyWith(color: QaColors.textSecondary),
      ),
      if (_p.lots.length > 1) ...[
        const SizedBox(height: QaSpace.gap),
        Text('qa_act_delete_which'.tr(), style: QaText.bodyStrong),
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
    return value.toStringAsFixed(6).replaceFirst(RegExp(r'\.?0+$'), '');
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
                      'qa_act_lot_shares_at'.tr(
                        namedArgs: {
                          'shares': AppNumberFormat.shares(lot.quantity),
                          'price': QaFormat.price(lot.purchasePrice),
                        },
                      ),
                      style: QaText.value,
                    ),
                    Text(
                      'qa_act_lot_bought_on'.tr(
                        namedArgs: {'date': QaTime.day(lot.purchaseDate)},
                      ),
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
                        date == null
                            ? 'qa_act_pick_date'.tr()
                            : QaTime.day(date!),
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
    this.closedPosition,
    this.onOpenClosedPosition,
    this.onOpenAlerts,
    this.onOpenWatchlist,
    this.onOpenManaged,
  });

  final ActionProposal proposal;
  final ActionDraft draft;
  final bool cancelled;
  final ValueChanged<String>? onOpenPosition;

  /// Alerta creada: "Ver mis alertas".
  final VoidCallback? onOpenAlerts;

  /// Ticker seguido: "Ver mi lista".
  final VoidCallback? onOpenWatchlist;

  /// Gestión de metas resuelta: su link.
  final ({String label, VoidCallback onTap})? onOpenManaged;

  /// Venta que cerró toda la posición: el link va a su detalle.
  final ClosedPosition? closedPosition;
  final ValueChanged<ClosedPosition>? onOpenClosedPosition;

  @override
  Widget build(BuildContext context) {
    final shares = draft.shares;
    final price = draft.price;
    final date = draft.date;

    final Widget body;
    final op = proposal.manageOp;
    if (proposal.kind == ActionKind.manage && op != null) {
      body = Text(
        cancelled
            ? 'qa_act_nothing_changed'.tr()
            : op.done(proposal.manageTarget),
        style: QaText.body,
      );
    } else if (proposal.kind == ActionKind.watch) {
      body = Text(
        cancelled
            ? 'qa_act_not_added'.tr()
            : draft.watchNotify
            ? 'qa_act_now_following_notify'.tr(
              namedArgs: {'ticker': proposal.ticker},
            )
            : 'qa_act_now_following'.tr(namedArgs: {'ticker': proposal.ticker}),
        style: QaText.body,
      );
    } else if (proposal.kind == ActionKind.alert) {
      final target = draft.alertTarget;
      final what = switch (draft.alertCondition) {
        'above' => 'qa_act_what_above'.tr(
          namedArgs: {'price': QaFormat.price(target ?? 0)},
        ),
        'below' => 'qa_act_what_below'.tr(
          namedArgs: {'price': QaFormat.price(target ?? 0)},
        ),
        'pct_up' => 'qa_act_what_pct_up'.tr(
          namedArgs: {'pct': QaFormat.pct(target ?? 0, digits: 0)},
        ),
        _ => 'qa_act_what_pct_down'.tr(
          namedArgs: {'pct': QaFormat.pct(target ?? 0, digits: 0)},
        ),
      };
      body = Text(
        cancelled
            ? 'qa_act_alert_not_created'.tr()
            : 'qa_act_alert_done'.tr(
              namedArgs: {
                'ticker': proposal.ticker,
                'what': what,
                'repeat':
                    draft.alertRepeatDaily
                        ? 'qa_act_alert_done_repeat'.tr()
                        : '',
              },
            ),
        style: QaText.body,
      );
    } else if (proposal.kind == ActionKind.delete) {
      final count = draft.lotIds.length;
      body = Text(
        cancelled
            ? 'qa_act_nothing_deleted'.tr()
            : '${QaFormat.units(count, 'qa_unit_lots_deleted')}'
                '${shares != null ? 'qa_act_shares_suffix'.tr(namedArgs: {'shares': AppNumberFormat.shares(shares)}) : ''}',
        style: QaText.body,
      );
    } else {
      body = QaStatGrid(
        stats: [
          if (date != null)
            QaStat(label: 'qa_act_date'.tr(), value: QaTime.day(date)),
          if (shares != null)
            QaStat(
              label: 'qa_act_shares'.tr(),
              value: AppNumberFormat.shares(shares),
            ),
          if (price != null)
            QaStat(label: 'qa_act_price'.tr(), value: QaFormat.price(price)),
          if (shares != null && price != null)
            QaStat(
              label:
                  proposal.kind == ActionKind.sell
                      ? 'qa_act_received'.tr()
                      : 'qa_act_total'.tr(),
              value: QaFormat.price(shares * price),
            ),
        ],
      );
    }

    final closed = closedPosition;
    final openClosed = onOpenClosedPosition;
    final VoidCallback? onLink;
    final String linkLabel;
    final managed = onOpenManaged;
    if (managed != null) {
      onLink = managed.onTap;
      linkLabel = managed.label;
    } else if (onOpenWatchlist != null) {
      onLink = onOpenWatchlist;
      linkLabel = 'qa_act_link_watchlist'.tr();
    } else if (onOpenAlerts != null) {
      onLink = onOpenAlerts;
      linkLabel = 'qa_act_link_alerts'.tr();
    } else if (closed != null && openClosed != null) {
      onLink = () => openClosed(closed);
      linkLabel = 'qa_act_link_closed'.tr();
    } else if (onOpenPosition != null) {
      onLink = () => onOpenPosition!(proposal.ticker);
      linkLabel = 'qa_act_link_portfolio'.tr();
    } else {
      onLink = null;
      linkLabel = '';
    }

    return Opacity(
      opacity: cancelled ? 0.55 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          body,
          if (onLink != null) ...[
            const SizedBox(height: QaSpace.gap),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onLink,
                // Alineado con el texto de la card, no con el padding del
                // botón.
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  linkLabel,
                  style: QaText.bodyStrong.copyWith(color: QaColors.accentBlue),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
