import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/presentation/shared/loading/button_spinner.dart';
import 'package:portfolio_assistant/domain/entities/symbol_search_result.dart';
import 'package:portfolio_assistant/domain/repositories/symbol_search_repository.dart';
import 'package:portfolio_assistant/domain/use_cases/get_current_price_use_case.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_identity.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/infraestructure/repositories/finnhub_symbol_search_repository_impl.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/porty_says.dart';

/// Búsqueda de símbolos (Finnhub `/search` por el proxy).
final symbolSearchRepositoryProvider = Provider<SymbolSearchRepository>(
  (ref) => FinnhubSymbolSearchRepositoryImpl(),
);

/// Elegir un ticker buscándolo por nombre o por símbolo, con Porty guiando.
/// - Mientras escribe, los resultados de la búsqueda (logo, símbolo, nombre
///   y tipo); tocar uno lo elige.
/// - Si lo escrito parece un ticker y no está entre los resultados (p. ej.
///   `GGAL.BA`, que Finnhub no lista), "Usar GGAL.BA": Porty lo verifica
///   con la cotización de hoy antes de aceptarlo y, si no la encuentra, dice
///   qué revisar.
/// - Lo que ya está en [existing] se muestra marcado y no se puede elegir.
///
/// Devuelve el ticker elegido (en mayúsculas) o `null`.
class TickerSearchSheet extends ConsumerStatefulWidget {
  const TickerSearchSheet({
    super.key,
    required this.title,
    required this.existing,
    this.existingLabel,
    this.takenReasons = const {},
  });

  final String title;
  final Set<String> existing;

  /// Cómo se marca lo que ya está ("Ya está en tu plan").
  final String? existingLabel;

  /// Otros tickers que no se pueden elegir, cada uno con su motivo
  /// ({"AAPL": "Ya la tenés"}).
  final Map<String, String> takenReasons;

  bool isTaken(String symbol) =>
      existing.contains(symbol) || takenReasons.containsKey(symbol);

  String takenLabelFor(String symbol, String fallback) =>
      takenReasons[symbol] ?? existingLabel ?? fallback;

  static Future<String?> show(
    BuildContext context, {
    required String title,
    Set<String> existing = const {},
    String? existingLabel,
    Map<String, String> takenReasons = const {},
  }) => showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder:
        (_) => TickerSearchSheet(
          title: title,
          existing: existing,
          existingLabel: existingLabel,
          takenReasons: takenReasons,
        ),
  );

  /// Lo mismo que acepta la base para un ticker.
  static final tickerPattern = RegExp(r'^[A-Z0-9.\-^=]{1,15}$');

  @override
  ConsumerState<TickerSearchSheet> createState() => _TickerSearchSheetState();
}

enum _Status { idle, searching, results, empty, failed }

class _TickerSearchSheetState extends ConsumerState<TickerSearchSheet> {
  final _query = TextEditingController();
  Timer? _debounce;
  int _requestId = 0;

  _Status _status = _Status.idle;
  List<SymbolSearchResult> _results = const [];

  /// El ticker que se está verificando con la cotización (o el último que
  /// no se encontró).
  String? _checking;
  String? _notFound;

  static const _maxResults = 8;

  /// Lo escrito parece un ticker con sufijo o clase (punto, guion, números).
  static final _exotic = RegExp(r'[.\-^=0-9]');

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  String get _typed => _query.text.trim().toUpperCase();

  void _onChanged(String _) {
    _debounce?.cancel();
    setState(() => _notFound = null);
    final q = _query.text.trim();
    if (q.isEmpty) {
      setState(() {
        _status = _Status.idle;
        _results = const [];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
  }

  Future<void> _search(String q) async {
    final id = ++_requestId;
    setState(() => _status = _Status.searching);
    final result = await ref.read(symbolSearchRepositoryProvider).search(q);
    if (!mounted || id != _requestId) return;
    result.fold(
      (_) => setState(() {
        _status = _Status.failed;
        _results = const [];
      }),
      (list) {
        final seen = <String>{};
        final valid = [
          for (final r in list)
            if (TickerSearchSheet.tickerPattern.hasMatch(
                  r.symbol.toUpperCase(),
                ) &&
                seen.add(r.symbol.toUpperCase()))
              r,
        ];
        setState(() {
          _results = valid.take(_maxResults).toList();
          _status = _results.isEmpty ? _Status.empty : _Status.results;
        });
      },
    );
  }

  /// Un ticker escrito a mano: se acepta si tiene cotización hoy.
  Future<void> _useTyped() async {
    final ticker = _typed;
    if (!TickerSearchSheet.tickerPattern.hasMatch(ticker)) return;
    setState(() {
      _checking = ticker;
      _notFound = null;
    });
    final price = await ref
        .read(getCurrentPriceUseCaseProvider)
        .call(params: ticker);
    if (!mounted || _checking != ticker) return;
    price.fold(
      (_) => setState(() {
        _checking = null;
        _notFound = ticker;
      }),
      (_) => Navigator.of(context).pop(ticker),
    );
  }

  void _pick(String symbol) => Navigator.of(context).pop(symbol.toUpperCase());

  ({String text, PortyAvatarState mood}) _porty() {
    final notFound = _notFound;
    if (_checking != null) {
      return (
        text: 'ticker_search_checking'.tr(namedArgs: {'ticker': _checking!}),
        mood: PortyAvatarState.thinking,
      );
    }
    if (notFound != null) {
      return (
        text: 'ticker_search_not_found'.tr(namedArgs: {'ticker': notFound}),
        mood: PortyAvatarState.concerned,
      );
    }
    return switch (_status) {
      _Status.idle => (
        text: 'ticker_search_porty'.tr(),
        mood: PortyAvatarState.idle,
      ),
      _Status.searching => (
        text: 'ticker_search_searching'.tr(),
        mood: PortyAvatarState.thinking,
      ),
      _Status.results => (
        text: 'ticker_search_results'.tr(),
        mood: PortyAvatarState.answered,
      ),
      _Status.empty => (
        text: 'ticker_search_empty'.tr(
          namedArgs: {'query': _query.text.trim()},
        ),
        mood: PortyAvatarState.serious,
      ),
      _Status.failed => (
        text: 'ticker_search_failed'.tr(),
        mood: PortyAvatarState.concerned,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final typed = _typed;
    final porty = _porty();
    final inResults = _results.any((r) => r.symbol.toUpperCase() == typed);
    final canUseTyped =
        typed.isNotEmpty &&
        TickerSearchSheet.tickerPattern.hasMatch(typed) &&
        !inResults &&
        !widget.isTaken(typed) &&
        (_status == _Status.empty ||
            _status == _Status.failed ||
            // Un ticker de otro mercado ("GGAL.BA", "BRK-B") aunque haya
            // resultados: la búsqueda no siempre los lista.
            (_status == _Status.results && _exotic.hasMatch(typed)));

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.pageHorizontal,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: tt.titleLarge?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppDimens.sp16),
                  PortySays(
                    messageKey: porty.text,
                    mood: porty.mood,
                    message: Text(
                      porty.text,
                      style: PortySays.style(
                        context,
                      )?.copyWith(fontSize: 16, height: 1.4),
                    ),
                  ),
                  const SizedBox(height: AppDimens.sp16),
                  TextField(
                    controller: _query,
                    autofocus: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.search,
                    onChanged: _onChanged,
                    onSubmitted: (_) {
                      if (_results.length == 1 &&
                          !widget.isTaken(
                            _results.first.symbol.toUpperCase(),
                          )) {
                        _pick(_results.first.symbol);
                      } else if (canUseTyped) {
                        _useTyped();
                      }
                    },
                    decoration: InputDecoration(
                      hintText: 'ticker_search_hint'.tr(),
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon:
                          _query.text.isEmpty
                              ? null
                              : IconButton(
                                tooltip: 'ticker_search_clear'.tr(),
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () {
                                  _query.clear();
                                  _onChanged('');
                                },
                              ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppDimens.sp8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(
                  AppDimens.pageHorizontal,
                  0,
                  AppDimens.pageHorizontal,
                  AppDimens.sp24,
                ),
                children: [
                  if (_status == _Status.idle)
                    Padding(
                      padding: const EdgeInsets.only(top: AppDimens.sp4),
                      child: Text(
                        'ticker_search_tip'.tr(),
                        style: tt.bodySmall?.copyWith(
                          color: colors.textSecondary,
                          height: 1.45,
                        ),
                      ),
                    ),
                  for (final r in _results)
                    _ResultTile(
                      result: r,
                      taken: widget.isTaken(r.symbol.toUpperCase()),
                      takenLabel: widget.takenLabelFor(
                        r.symbol.toUpperCase(),
                        'ticker_search_taken'.tr(),
                      ),
                      onTap: () => _pick(r.symbol),
                    ),
                  if (canUseTyped)
                    _UseTypedTile(
                      ticker: typed,
                      checking: _checking == typed,
                      onTap: _checking == null ? _useTyped : null,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.result,
    required this.taken,
    required this.takenLabel,
    required this.onTap,
  });

  final SymbolSearchResult result;
  final bool taken;
  final String takenLabel;
  final VoidCallback onTap;

  /// "Common Stock" → "Acción", "ETP" → "ETF"… (lo que no conocemos, nada).
  static String? _kind(String type) => switch (type.toUpperCase()) {
    'COMMON STOCK' => 'ticker_search_kind_stock'.tr(),
    'ETP' || 'ETF' => 'ticker_search_kind_etf'.tr(),
    'ADR' => 'ticker_search_kind_adr'.tr(),
    'REIT' => 'ticker_search_kind_reit'.tr(),
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final symbol = result.symbol.toUpperCase();
    final kind = _kind(result.type);
    final name = result.description.trim();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: taken ? null : onTap,
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: AppDimens.sp8,
            horizontal: AppDimens.sp4,
          ),
          child: Opacity(
            opacity: taken ? 0.5 : 1,
            child: Row(
              children: [
                QaTickerAvatar(ticker: symbol, size: 36),
                const SizedBox(width: AppDimens.sp12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        symbol,
                        style: tt.bodyMedium?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (name.isNotEmpty || kind != null)
                        Text(
                          [
                            if (name.isNotEmpty) _titleCase(name),
                            if (kind != null) kind,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppDimens.sp8),
                if (taken)
                  Text(
                    takenLabel,
                    style: tt.labelSmall?.copyWith(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else
                  Icon(
                    Icons.add_circle_outline_rounded,
                    color: colors.accentBlue,
                    size: AppDimens.iconLg,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Finnhub manda los nombres en mayúsculas ("APPLE INC").
  static String _titleCase(String s) {
    if (s != s.toUpperCase()) return s;
    return s
        .toLowerCase()
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}

/// "Usar GGAL.BA": lo escrito tal cual, verificado con la cotización.
class _UseTypedTile extends StatelessWidget {
  const _UseTypedTile({
    required this.ticker,
    required this.checking,
    required this.onTap,
  });

  final String ticker;
  final bool checking;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppDimens.sp8),
      child: Material(
        color: colors.inset,
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppDimens.radiusMd),
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.sp12),
            child: Row(
              children: [
                Icon(
                  Icons.keyboard_rounded,
                  size: AppDimens.iconMd,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: AppDimens.sp12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ticker_search_use_typed'.tr(
                          namedArgs: {'ticker': ticker},
                        ),
                        style: tt.bodyMedium?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'ticker_search_use_typed_body'.tr(),
                        style: tt.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (checking)
                  ButtonSpinner.small(color: colors.textSecondary)
                else
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: AppDimens.iconMd,
                    color: colors.accentBlue,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
