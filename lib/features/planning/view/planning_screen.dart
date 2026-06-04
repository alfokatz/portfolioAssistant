import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:genui/genui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/analysis/catalog/analysis_colors.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_error_message.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_flow_screen_helpers.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_request_tracker.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_send_guard.dart';
import 'package:portfolio_assistant/features/genui_core/widgets/gen_ui_flow_body.dart';
import 'package:portfolio_assistant/features/investment/models/investment_flow_args.dart';
import 'package:portfolio_assistant/features/planning/catalog/planning_catalog.dart';
import 'package:portfolio_assistant/features/planning/models/planning_data_bindings.dart';
import 'package:portfolio_assistant/features/planning/models/planning_flow_args.dart';
import 'package:portfolio_assistant/features/planning/models/saved_goal.dart';
import 'package:portfolio_assistant/features/planning/view/planning_action_delegate.dart';
import 'package:portfolio_assistant/features/genui_core/models/gen_ui_flow_type.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/presentation/flows/genui/nav/genui_router.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';

class PlanningScreen extends StatefulHookConsumerWidget {
  const PlanningScreen({super.key, this.args});

  final PlanningFlowArgs? args;

  @override
  ConsumerState<PlanningScreen> createState() => _PlanningScreenState();
}

class _PlanningScreenState extends BaseStatefulWidget<PlanningScreen> {
  late final Catalog _catalog;
  late final PlanningDataBindings _bindings;
  OpenAIGenUiService? _service;
  final _conversationEvents = GenUiConversationSubscription();
  final _sendGuard = GenUiSendGuard();
  final _textController = TextEditingController();
  final _surfaceIds = <String>[];
  bool _isWaiting = false;
  String? _error;
  bool _bindingsAttached = false;
  bool _bootstrapping = false;
  String _lastMessage = '';

  @override
  void initState() {
    _catalog = PlanningCatalog.build();
    _bindings = PlanningDataBindings();
    super.initState();
    runAfterPostFrameCallback(_bootstrap);
  }

  Future<void> _bootstrap() async {
    if (_bootstrapping) return;
    _bootstrapping = true;
    try {
      final prefs = ref.read(preferenceManagerProvider);
      final savedGoal = await prefs.getSavedGoal();
      final savedContribution = await prefs.getMonthlyContribution();

      if (ref.read(homeProvider).summary == null) {
        await ref.read(homeProvider.notifier).refresh();
      }

      final home = ref.read(homeProvider);
      _bindings.updateFromPortfolio(
        summary: home.summary,
        history: home.history,
        savedMonthlyContribution: savedContribution,
      );

      if (savedGoal != null) {
        _bindings.updateGoal(
          label: savedGoal.label,
          amount: savedGoal.targetAmount,
          date: savedGoal.targetDate,
        );
      } else if (widget.args != null) {
        _bindings.updateGoal(
          label: widget.args!.goalLabel,
          amount: widget.args!.targetAmount,
          date: widget.args!.targetDate,
        );
      }

      await _initService();
      await _sendMessage(
        widget.args?.resolveInitialPrompt() ??
            PlanningFlowArgs().resolveInitialPrompt(),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = genUiErrorMessage(e);
          _isWaiting = false;
        });
      }
    } finally {
      _bootstrapping = false;
    }
  }

  Future<void> _initService() async {
    final seed = _bindings.buildClientDataModelSeed();

    final prompt = PromptBuilder.custom(
      catalog: _catalog,
      allowedOperations: SurfaceOperations.createAndUpdate(dataModel: false),
      systemPromptFragments: _catalog.systemPromptFragments,
      clientDataModel: seed,
      technicalPossibilities: const TechnicalPossibilities(
        codeExecution: false,
        toolCall: false,
        functionCall: false,
      ),
    ).systemPromptJoined();

    _bindings.releaseFromDataModel();
    _conversationEvents.cancel();
    _service?.dispose();
    _bindingsAttached = false;
    _service = OpenAIGenUiService(
      systemPrompt: prompt,
      catalog: _catalog,
      a2uiSurfaceId: GenUiSurfaceIds.longTermPlanning,
    );

    _conversationEvents.listen(
      _service!.conversation,
      _onConversationEvent,
    );
    _attachBindingsIfNeeded();
    if (mounted) setState(() {});
  }

  void _onConversationEvent(ConversationEvent event) {
    if (!mounted) return;
    GenUiFlowScreenHelpers.handleConversationEvent(
      event: event,
      surfaceIds: _surfaceIds,
      setError: (value) => _error = value,
      setWaiting: (value) => _isWaiting = value,
      onStateChanged: () {
        switch (event) {
          case ConversationSurfaceAdded(:final surfaceId):
          case ConversationComponentsUpdated(:final surfaceId):
            _syncPlanningDataForSurface(surfaceId);
          default:
            break;
        }
        setState(() {});
      },
    );
  }

  void _attachBindingsIfNeeded() {
    _syncPlanningDataForSurface(GenUiSurfaceIds.longTermPlanning);
  }

  void _syncPlanningDataForSurface(String surfaceId) {
    if (_service == null || surfaceId != GenUiSurfaceIds.longTermPlanning) {
      return;
    }
    if (_service!.controller.registry.getSurface(surfaceId) == null) {
      return;
    }
    final dataModel = _service!.controller.store.getDataModel(surfaceId);
    if (!_bindingsAttached) {
      _bindings.bindToDataModel(dataModel);
      _bindingsAttached = true;
    }
    dataModel.update(DataPath.root, _bindings.buildClientDataModelSeed());
  }

  Future<void> _sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _service == null || _sendGuard.isInFlight) return;

    await _sendGuard.run(() async {
      _lastMessage = trimmed;
      if (mounted) {
        setState(() {
          _error = null;
          _isWaiting = true;
        });
      }

      _syncFromHome();
      for (final surfaceId in {
        ..._surfaceIds,
        GenUiSurfaceIds.longTermPlanning,
      }) {
        _syncPlanningDataForSurface(surfaceId);
      }

      try {
        await GenUiRequestTracker.sendAndWait(
          conversation: _service!.conversation,
          targetSurfaceId: GenUiSurfaceIds.longTermPlanning,
          send: () =>
              _service!.conversation.sendRequest(ChatMessage.user(trimmed)),
        );
        if (mounted) {
          _textController.clear();
          setState(() => _isWaiting = false);
        }
      } on TimeoutException catch (e) {
        if (mounted) {
          setState(() {
            _error = e.message ?? 'GPT tardó demasiado en responder.';
            _isWaiting = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _error = genUiErrorMessage(e);
            _isWaiting = false;
          });
        }
      }
    });
  }

  void _retryLastMessage() {
    if (_lastMessage.isEmpty) return;
    setState(() => _error = null);
    _sendMessage(_lastMessage);
  }

  void _syncFromHome() {
    final home = ref.read(homeProvider);
    _bindings.updateFromPortfolio(
      summary: home.summary,
      history: home.history,
    );
  }

  Future<void> _handleInteraction(
    String event,
    Map<String, dynamic> payload,
  ) async {
    switch (event) {
      case 'goal_updated':
        _bindings.updateGoal(
          label: payload['label'] as String?,
          amount: (payload['targetAmount'] as num?)?.toDouble(),
          date: payload['targetDate'] as String?,
        );
        _syncPlanningDataForSurface(GenUiSurfaceIds.longTermPlanning);
        await _sendMessage(
          'Actualicé mi meta: ${_bindings.goalLabel.value}, '
          'objetivo ${_bindings.targetAmount.value.round()}, '
          'fecha ${_bindings.targetDate.value}. Recomponé el plan.',
        );
      case 'contribution_updated':
      case 'recalculate_requested':
        final amount = (payload['monthlyAmount'] as num?)?.toDouble() ??
            (payload['newMonthlyContribution'] as num?)?.toDouble();
        if (amount != null) {
          _bindings.setMonthlyContribution(amount);
          await ref.read(preferenceManagerProvider).saveMonthlyContribution(amount);
          _syncPlanningDataForSurface(GenUiSurfaceIds.longTermPlanning);
          await _sendMessage(
            event == 'recalculate_requested'
                ? 'Recalculá el plan con un aporte mensual de \$${amount.round()}'
                : 'Actualicé mi aporte mensual a \$${amount.round()}. '
                    'Recalculá GapAnalysisCard y ProjectionChart.',
          );
        }
      case 'scenario_selected':
        final label = payload['label'] as String? ?? 'Moderado';
        await _sendMessage(
          'El usuario seleccionó el escenario $label. '
          'Actualizá las ActionPriorityCards para este escenario.',
        );
      case 'flow_invest_open':
        final label = _bindings.goalLabel.value.isEmpty
            ? 'mi meta'
            : _bindings.goalLabel.value;
        if (!mounted) return;
        context.pushNamed(
          GenUiRouter.routeNameFor(GenUiFlowType.invest),
          extra: InvestmentFlowArgs(
            initialPrompt:
                'Quiero invertir más para llegar a mi meta de $label',
          ),
        );
    }
  }

  Future<void> _saveGoal() async {
    final payload = _bindings.buildGoalPayload();
    if (payload == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Todavía no hay una meta definida para guardar'),
        ),
      );
      return;
    }

    final goal = SavedGoal(
      label: payload['label'] as String,
      targetAmount: payload['targetAmount'] as double,
      targetDate: payload['targetDate'] as String,
    );

    await ref.read(preferenceManagerProvider).saveGoal(
          label: goal.label,
          targetAmount: goal.targetAmount,
          targetDate: goal.targetDate,
        );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Meta guardada ✓'),
        backgroundColor: AnalysisColors.profit,
      ),
    );
  }

  Future<void> _openContributionSheet() async {
    final confirmed = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AnalysisColors.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _ContributionSheet(
        initialAmount: _bindings.monthlyContribution.value,
      ),
    );

    if (confirmed == null) return;

    await _handleInteraction(
      'contribution_updated',
      {'monthlyAmount': confirmed},
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _conversationEvents.cancel();
    _bindings.releaseFromDataModel();
    _service?.dispose();
    _bindings.dispose();
    super.dispose();
  }

  @override
  Widget buildView(BuildContext context) {
    final service = _service;

    return Scaffold(
      backgroundColor: PortfolioColors.background,
      appBar: AppBar(
        title: const Text('Planificación'),
        backgroundColor: PortfolioColors.background,
        actions: [
          TextButton(
            onPressed: _isWaiting ? null : _saveGoal,
            child: const Text('Guardar meta'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'plan_contribution_fab',
        onPressed: _isWaiting || service == null ? null : _openContributionSheet,
        backgroundColor: PortfolioColors.surfaceElevated,
        foregroundColor: AnalysisColors.textPrimary,
        icon: const Icon(Icons.tune),
        label: const Text('Ajustar aporte'),
      ),
      body: Column(
        children: [
          Expanded(
            child: service == null
                ? const Center(child: CircularProgressIndicator())
                : _buildFlowBody(service),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      style: const TextStyle(color: PortfolioColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Contame tu meta financiera...',
                        filled: true,
                        fillColor: PortfolioColors.surfaceCard,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: _isWaiting ? null : _sendMessage,
                      enabled: !_isWaiting && service != null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _isWaiting || service == null
                        ? null
                        : () => _sendMessage(_textController.text),
                    icon: const Icon(Icons.send),
                    color: const Color(0xFF2979FF),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlowBody(OpenAIGenUiService service) {
    final hasSurfaces = _surfaceIds.isNotEmpty;

    if (_isWaiting && !hasSurfaces) {
      return const GenUiFlowLoadingBody(
        message: 'Armando tu plan financiero...',
      );
    }

    if (_error != null && !hasSurfaces) {
      return GenUiFlowErrorBody(
        message: _error!,
        onRetry: _retryLastMessage,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            'Quiero retirarme en 20 años con \$500k',
            '¿Voy bien para comprar una casa en 5 años?',
          ]
              .map(
                (chip) => ActionChip(
                  label: Text(
                    chip,
                    style: const TextStyle(fontSize: 12),
                  ),
                  onPressed: _isWaiting ? null : () => _sendMessage(chip),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 12),
        if (_error != null && hasSurfaces)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _error!,
              style: const TextStyle(color: AnalysisColors.loss, fontSize: 13),
            ),
          ),
        ..._surfaceIds.map((surfaceId) {
          return Surface(
            surfaceContext: service.controller.contextFor(surfaceId),
            actionDelegate: PlanningActionDelegate(
              onInteraction: _handleInteraction,
            ),
          );
        }),
        if (_isWaiting && hasSurfaces)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(
              child: CircularProgressIndicator(
                color: Color(0xFF2979FF),
              ),
            ),
          ),
      ],
    );
  }
}

class _ContributionSheet extends StatefulWidget {
  const _ContributionSheet({required this.initialAmount});

  final double initialAmount;

  @override
  State<_ContributionSheet> createState() => _ContributionSheetState();
}

class _ContributionSheetState extends State<_ContributionSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialAmount > 0
          ? widget.initialAmount.round().toString()
          : '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    final value = double.tryParse(_controller.text.trim());
    if (value == null || value < 0) return;
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Ajustar aporte mensual',
            style: TextStyle(
              color: AnalysisColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: AnalysisColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Ej: 500',
              filled: true,
              fillColor: PortfolioColors.surfaceElevated,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              prefixText: '\$ ',
            ),
            onSubmitted: (_) => _confirm(),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _confirm,
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }
}
