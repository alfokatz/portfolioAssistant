import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';
import 'package:portfolio_assistant/features/watchlist/data/watchlist_repository.dart';
import 'package:portfolio_assistant/features/watchlist/domain/watchlist_item.dart';
import 'package:portfolio_assistant/infraestructure/repositories/quote_repository_impl.dart';

class WatchlistState {
  const WatchlistState({
    this.items = const [],
    this.quotes = const {},
    this.loaded = false,
    this.loadFailed = false,
  });

  final List<WatchlistItem> items;

  /// Cotización por símbolo (las que llegaron).
  final Map<String, WatchQuote> quotes;
  final bool loaded;
  final bool loadFailed;

  bool contains(String symbol) =>
      items.any((i) => i.symbol == symbol.trim().toUpperCase());

  WatchlistState copyWith({
    List<WatchlistItem>? items,
    Map<String, WatchQuote>? quotes,
    bool? loaded,
    bool? loadFailed,
  }) => WatchlistState(
    items: items ?? this.items,
    quotes: quotes ?? this.quotes,
    loaded: loaded ?? this.loaded,
    loadFailed: loadFailed ?? this.loadFailed,
  );
}

/// La lista de seguimiento y sus cotizaciones.
class WatchlistNotifier extends StateNotifier<WatchlistState> {
  /// [quotes] se pide recién al cotizar: la tarjeta de la Home crea este
  /// notifier aunque el plan no tenga lista (y en los tests de la Home no
  /// hay cotizaciones configuradas).
  WatchlistNotifier(
    this._repo,
    QuoteRepository Function() quotes, {
    DateTime Function()? now,
  }) : _quotesOf = quotes,
       _now = now ?? DateTime.now,
       super(const WatchlistState());

  final WatchlistRepository _repo;
  final QuoteRepository Function() _quotesOf;
  final DateTime Function() _now;

  Future<void> load() async {
    try {
      final items = await _repo.list();
      if (!mounted) return;
      state = state.copyWith(items: items, loaded: true, loadFailed: false);
      unawaited(refreshQuotes());
    } on WatchlistFailure {
      if (mounted) state = state.copyWith(loaded: true, loadFailed: true);
    }
  }

  Future<void> refreshQuotes() async {
    final symbols = [for (final i in state.items) i.symbol];
    const batch = 6;
    for (var i = 0; i < symbols.length; i += batch) {
      final slice = symbols.skip(i).take(batch).toList();
      final quotes = await Future.wait(slice.map(quoteOf));
      if (!mounted) return;
      state = state.copyWith(
        quotes: {
          ...state.quotes,
          for (var j = 0; j < slice.length; j++)
            if (quotes[j] != null) slice[j]: quotes[j]!,
        },
      );
    }
  }

  /// Precio de hoy y cierre anterior. `null` si no hay cotización.
  Future<WatchQuote?> quoteOf(String symbol) async {
    final yahoo = PortfolioCalculator.toYahooFinanceSymbol(symbol);
    try {
      final quotes = _quotesOf();
      final price = (await quotes.getCurrentPrice(
        yahoo,
      )).fold<double?>((_) => null, (p) => p > 0 ? p : null);
      if (price == null) return null;
      final history = await quotes.getHistoricalDaily(yahoo);
      final prev = history.fold<double?>(
        (_) => null,
        (c) => WatchQuote.previousCloseFrom(c, _now()),
      );
      return WatchQuote(price: price, previousClose: prev);
    } catch (_) {
      return null;
    }
  }

  /// Agrega [symbol] con el precio de hoy. Tira [WatchlistFailure] (tope,
  /// repetido, sin red) o [WatchlistUnknownSymbol] si no hay cotización.
  Future<WatchlistItem> add(String symbol) async {
    final clean = PortfolioCalculator.normalizeTicker(symbol);
    final quote = await quoteOf(clean);
    if (quote == null) throw const WatchlistUnknownSymbol();
    final item = await _repo.add(clean, price: quote.price);
    if (mounted) {
      state = state.copyWith(
        items: [item, ...state.items],
        quotes: {...state.quotes, item.symbol: quote},
      );
    }
    return item;
  }

  Future<void> setNotify(WatchlistItem item, bool notify) async {
    _replace(item.copyWith(notify: notify));
    try {
      await _repo.setNotify(item.id, notify: notify);
    } on WatchlistFailure {
      _replace(item);
      rethrow;
    }
  }

  Future<void> remove(WatchlistItem item) async {
    final before = state.items;
    state = state.copyWith(
      items: [
        for (final i in state.items)
          if (i.id != item.id) i,
      ],
    );
    try {
      await _repo.remove(item.id);
    } on WatchlistFailure {
      if (mounted) state = state.copyWith(items: before);
      rethrow;
    }
  }

  void _replace(WatchlistItem item) {
    if (!mounted) return;
    state = state.copyWith(
      items: [for (final i in state.items) i.id == item.id ? item : i],
    );
  }
}

/// No hay cotización para el ticker (mal escrito o no existe).
class WatchlistUnknownSymbol implements Exception {
  const WatchlistUnknownSymbol();
}

final watchlistProvider =
    StateNotifierProvider<WatchlistNotifier, WatchlistState>(
      (ref) => WatchlistNotifier(
        ref.watch(watchlistRepositoryProvider),
        () => ref.read(quoteRepositoryProvider),
      ),
    );
