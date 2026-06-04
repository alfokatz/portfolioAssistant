import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:genui/genui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/use_cases/add_position_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_current_price_use_case.dart';
import 'package:portfolio_assistant/features/analysis/catalog/analysis_colors.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_error_message.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_flow_screen_helpers.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_request_tracker.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_send_guard.dart';
import 'package:portfolio_assistant/features/genui_core/widgets/gen_ui_flow_body.dart';
import 'package:portfolio_assistant/features/investment/catalog/investment_catalog.dart';
import 'package:portfolio_assistant/features/investment/models/investment_data_bindings.dart';
import 'package:portfolio_assistant/features/investment/models/investment_flow_args.dart';
import 'package:portfolio_assistant/features/investment/view/investment_action_delegate.dart';
import 'package:portfolio_assistant/features/investment/view/widgets/asset_detail_bottom_sheet.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/presentation/flows/home/nav/home_router.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';

class InvestmentScreen extends StatefulHookConsumerWidget {
  const InvestmentScreen({super.key, this.args});

  final InvestmentFlowArgs? args;

  @override
  ConsumerState<InvestmentScreen> createState() => _InvestmentScreenState();
}

class _InvestmentScreenState extends BaseStatefulWidget<InvestmentScreen> {
  late final Catalog _catalog;
  late final InvestmentDataBindings _bindings;
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
    _catalog = InvestmentCatalog.build();
    _bindings = InvestmentDataBindings();
    super.initState();
    runAfterPostFrameCallback(_bootstrap);
  }

  Future<void> _bootstrap() async {
    if (_bootstrapping) return;
    _bootstrapping = true;
    try {
      final prefs = ref.read(preferenceManagerProvider);
      final savedRisk = await prefs.getRiskProfile();
      _bindings.setRiskProfile(savedRisk);

      if (ref.read(homeProvider).summary == null) {
        await ref.read(homeProvider.notifier).refresh();
      }
      _syncFromHome();
      await _initService();
      await _sendMessage(
        widget.args?.resolveInitialPrompt() ??
            const InvestmentFlowArgs().resolveInitialPrompt(),
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
      a2uiSurfaceId: GenUiSurfaceIds.investmentDecision,
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
            _syncInvestmentDataForSurface(surfaceId);
          default:
            break;
        }
        setState(() {});
      },
    );
  }

  void _attachBindingsIfNeeded() {
    _syncInvestmentDataForSurface(GenUiSurfaceIds.investmentDecision);
  }

  void _syncInvestmentDataForSurface(String surfaceId) {
    if (_service == null || surfaceId != GenUiSurfaceIds.investmentDecision) {
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

  void _syncFromHome() {
    _bindings.updateFromSummary(ref.read(homeProvider).summary);
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

      _bindings.parseBudgetFromMessage(trimmed);
      _syncFromHome();
      for (final surfaceId in {
        ..._surfaceIds,
        GenUiSurfaceIds.investmentDecision,
      }) {
        _syncInvestmentDataForSurface(surfaceId);
      }

      try {
        await GenUiRequestTracker.sendAndWait(
          conversation: _service!.conversation,
          targetSurfaceId: GenUiSurfaceIds.investmentDecision,
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

  Future<void> _handleInteraction(
    String event,
    Map<String, dynamic> payload,
  ) async {
    switch (event) {
      case 'risk_profile_updated':
        final value = (payload['value'] as num?)?.toDouble();
        if (value != null) {
          await ref.read(preferenceManagerProvider).saveRiskProfile(value);
          _bindings.setRiskProfile(value);
          _service!.controller.store
              .getDataModel(GenUiSurfaceIds.investmentDecision)
              .update(DataPath('/user/risk_profile'), value);
          await _sendMessage(
            'Actualicé mi perfil de riesgo a ${value.round()}/100. '
            'Recomponé las opciones.',
          );
        }
      case 'investment_confirmed':
        await _confirmInvestment(payload);
      case 'investment_cancelled':
        _cancelLastSurface();
      case 'more_options_requested':
        await _sendMessage('Mostrame otras opciones diferentes');
      case 'asset_detail_open':
        final ticker = payload['ticker'] as String?;
        if (ticker != null) await _openAssetDetail(ticker);
    }
  }

  Future<void> _confirmInvestment(Map<String, dynamic> payload) async {
    final ticker = payload['ticker'] as String?;
    final shares = (payload['shares'] as num?)?.toDouble();
    final price = (payload['pricePerShare'] as num?)?.toDouble();

    if (ticker == null || shares == null || price == null) return;

    setState(() => _isWaiting = true);

    final result = await ref.read(addPositionUseCaseProvider).call(
          params: AddPositionParams(
            ticker: ticker.toUpperCase(),
            quantity: shares,
            purchasePrice: price,
            purchaseDate: DateTime.now(),
          ),
        );

    if (!mounted) return;

    setState(() => _isWaiting = false);

    result.fold(
      (error) {
        setState(() => _error = error.message);
      },
      (_) async {
        await ref.read(homeProvider.notifier).refresh();
        if (!mounted) return;
        context.goNamed(HomeRouter.homeRouteName);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Posición en ${ticker.toUpperCase()} registrada ✓'),
            backgroundColor: AnalysisColors.profit,
          ),
        );
      },
    );
  }

  void _cancelLastSurface() {
    if (_surfaceIds.isEmpty) return;
    final lastId = _surfaceIds.removeLast();
    _service?.controller.handleMessage(DeleteSurface(surfaceId: lastId));
    if (mounted) setState(() {});
  }

  Future<void> _openAssetDetail(String ticker) async {
    double? price;
    final priceResult = await ref.read(getCurrentPriceUseCaseProvider).call(
          params: ticker.toUpperCase(),
        );
    priceResult.fold((_) {}, (p) => price = p);

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => AssetDetailBottomSheet(
        ticker: ticker.toUpperCase(),
        currentPrice: price,
        summary: ref.read(homeProvider).summary,
      ),
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
        title: Text('genui_invest_title'.tr()),
        backgroundColor: PortfolioColors.background,
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
                        hintText: 'genui_input_hint'.tr(),
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
                    color: PortfolioColors.accentBlue,
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
        message: 'Buscando opciones de inversión...',
      );
    }

    if (_error != null && !hasSurfaces) {
      return GenUiFlowErrorBody(
        message: _error!,
        onRetry: _retryLastMessage,
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            'genui_chip_invest_2k'.tr(),
          ]
              .map(
                (chip) => ActionChip(
                  label: Text(chip),
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
            actionDelegate: InvestmentActionDelegate(
              onInteraction: _handleInteraction,
            ),
          );
        }),
        if (_isWaiting && hasSurfaces)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(
              child: CircularProgressIndicator(
                color: PortfolioColors.accentBlue,
              ),
            ),
          ),
      ],
    );
  }
}
