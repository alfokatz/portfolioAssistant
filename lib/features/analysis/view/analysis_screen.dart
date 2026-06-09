import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/navigation/navigator.dart';
import 'package:portfolio_assistant/features/analysis/catalog/analysis_colors.dart';
import 'package:portfolio_assistant/features/analysis/catalog/analysis_catalog.dart';
import 'package:portfolio_assistant/features/analysis/models/portfolio_data_bindings.dart';
import 'package:portfolio_assistant/features/analysis/services/analysis_openai_service.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_error_message.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_flow_screen_helpers.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_request_tracker.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_send_guard.dart';
import 'package:portfolio_assistant/features/genui_core/widgets/gen_ui_flow_body.dart';
import 'package:portfolio_assistant/features/investment/models/investment_flow_args.dart';
import 'package:portfolio_assistant/features/analysis/view/analysis_action_delegate.dart';
import 'package:portfolio_assistant/features/genui_core/models/gen_ui_flow_type.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/features/genui_core/nav/genui_nav.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';
import 'package:portfolio_assistant/presentation/flows/position/nav/position_nav.dart';

class AnalysisScreen extends StatefulHookConsumerWidget {
  const AnalysisScreen({super.key, this.initialPrompt});

  final String? initialPrompt;

  @override
  ConsumerState<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends BaseStatefulWidget<AnalysisScreen> {
  static const _defaultPrompt = 'Haceme un resumen de mi portfolio actual';

  late final Catalog _catalog;
  late final PortfolioDataBindings _bindings;
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
    _catalog = AnalysisCatalog.build();
    _bindings = PortfolioDataBindings();
    super.initState();
    runAfterPostFrameCallback(_bootstrap);
  }

  Future<void> _bootstrap() async {
    if (_bootstrapping) return;
    _bootstrapping = true;
    try {
      if (ref.read(homeProvider).summary == null) {
        await ref.read(homeProvider.notifier).refresh();
      }
      _syncPortfolioFromHome();
      await _initService();
      final prompt = widget.initialPrompt ?? _defaultPrompt;
      await _sendMessage(prompt);
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
    final summary = ref.read(homeProvider).summary;
    _bindings.updateFromSummary(summary);
    final seed = _bindings.buildClientDataModelSeed(summary);

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
    _service = AnalysisOpenAiService(
      systemPrompt: prompt,
      catalog: _catalog,
      portfolioTickers: () => List<String>.from(_bindings.tickers.value),
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
            _syncPortfolioDataForSurface(surfaceId);
          default:
            break;
        }
        setState(() {});
      },
    );
  }

  void _attachBindingsIfNeeded() {
    _syncPortfolioDataForSurface(GenUiSurfaceIds.portfolioAnalysis);
  }

  void _syncPortfolioDataForSurface(String surfaceId) {
    if (_service == null) return;
    final dataModel = _service!.controller.store.getDataModel(surfaceId);
    if (surfaceId == GenUiSurfaceIds.portfolioAnalysis && !_bindingsAttached) {
      _bindings.bindToDataModel(dataModel);
      _bindingsAttached = true;
    }
    dataModel.update(
      DataPath.root,
      _bindings.buildClientDataModelSeed(ref.read(homeProvider).summary),
    );
  }

  void _syncPortfolioFromHome() {
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

      _syncPortfolioFromHome();
      for (final surfaceId in {
        ..._surfaceIds,
        GenUiSurfaceIds.portfolioAnalysis,
      }) {
        _syncPortfolioDataForSurface(surfaceId);
      }

      try {
        await GenUiRequestTracker.sendAndWait(
          conversation: _service!.conversation,
          targetSurfaceId: GenUiSurfaceIds.portfolioAnalysis,
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

  void _handleInteraction(String event, Map<String, dynamic> payload) {
    switch (event) {
      case 'portfolio_refresh':
        _refreshPortfolio();
      case 'asset_detail_open':
        final ticker = payload['ticker'] as String?;
        if (ticker != null) {
          ref.read(navigationProvider.notifier).navigate(
                GotoAddPosition(ticker: ticker),
              );
        }
      case 'flow_invest_open':
        ref.read(navigationProvider.notifier).navigate(
              GotoGenUiFlow(
                flowType: GenUiFlowType.invest,
                investmentArgs: InvestmentFlowArgs(
                  suggestedTicker: payload['ticker'] as String?,
                ),
              ),
            );
      case 'flow_planning_open':
        ref.read(navigationProvider.notifier).navigate(
              GotoGenUiFlow(flowType: GenUiFlowType.plan),
            );
    }
  }

  Future<void> _refreshPortfolio() async {
    setState(() => _isWaiting = true);
    await ref.read(homeProvider.notifier).refresh();
    _syncPortfolioFromHome();
    if (mounted) {
      setState(() => _isWaiting = false);
    }
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
    final hasPositions =
        (ref.watch(homeProvider).summary?.valuations.length ?? 0) > 0;

    return Scaffold(
      backgroundColor: PortfolioColors.background,
      appBar: AppBar(
        title: Text('genui_analysis_title'.tr()),
        backgroundColor: PortfolioColors.background,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _isWaiting ? null : _refreshPortfolio,
          ),
        ],
      ),
      body: Column(
        children: [
          if (!hasPositions)
            MaterialBanner(
              content: Text('genui_empty_portfolio'.tr()),
              actions: [
                TextButton(
                  onPressed: () => ref
                      .read(navigationProvider.notifier)
                      .navigate(GotoAddPosition()),
                  child: Text('add_position'.tr()),
                ),
              ],
            ),
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
        message: 'Analizando tu portfolio...',
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
            'genui_chip_how_today'.tr(),
            'genui_chip_week_change'.tr(),
            'genui_chip_portfolio_news'.tr(),
            'genui_chip_market_today'.tr(),
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
            actionDelegate: AnalysisActionDelegate(
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
