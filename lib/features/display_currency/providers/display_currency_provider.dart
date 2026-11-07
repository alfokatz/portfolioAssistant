import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/features/display_currency/domain/display_currency.dart';
import 'package:portfolio_assistant/features/display_currency/domain/fx_breakdown.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:portfolio_assistant/infraestructure/repositories/quote_repository_impl.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const settingsDisplayCurrencyKey = 'settings_display_currency';

/// La moneda que eligió el usuario en Ajustes (dólar si nunca eligió).
/// Vive en el teléfono, como el tema: es solo cómo se muestra. Sin
/// preferencias disponibles (tests), queda en memoria.
class DisplayCurrencyNotifier extends StateNotifier<DisplayCurrency> {
  DisplayCurrencyNotifier(this._prefs) : super(read(_prefs));

  final SharedPreferences? _prefs;

  static DisplayCurrency read(SharedPreferences? prefs) {
    try {
      return DisplayCurrency.fromCode(
        prefs?.getString(settingsDisplayCurrencyKey),
      );
    } catch (_) {
      return DisplayCurrency.usd;
    }
  }

  Future<void> set(DisplayCurrency currency) async {
    state = currency;
    try {
      await _prefs?.setString(settingsDisplayCurrencyKey, currency.code);
    } catch (_) {}
  }
}

final displayCurrencyProvider =
    StateNotifierProvider<DisplayCurrencyNotifier, DisplayCurrency>((ref) {
      SharedPreferences? prefs;
      try {
        prefs = ref.watch(sharedPreferencesProvider);
      } catch (_) {
        // Sin override (tests de otras pantallas): dólar, en memoria.
      }
      return DisplayCurrencyNotifier(prefs);
    });

/// Tipo de cambio de hoy (unidades de [currency] por dólar). `null` si no
/// se pudo traer o es el dólar.
final fxRateProvider = FutureProvider.autoDispose
    .family<double?, DisplayCurrency>((ref, currency) async {
      if (currency.isUsd) return null;
      final quotes = ref.watch(quoteRepositoryProvider);
      final result = await quotes.getCurrentPrice(currency.yahooSymbol);
      return result.fold<double?>((_) => null, (r) => r > 0 ? r : null);
    });

/// Arma el desglose de las compras de [lots] en [currency]. `null` si no
/// hay tipo de cambio de hoy.
Future<FxBreakdown?> loadFxBreakdown({
  required QuoteRepository quotes,
  required DisplayCurrency currency,
  required List<PositionValuation> lots,
}) async {
  if (currency.isUsd || lots.isEmpty) return null;
  final now = await quotes.getCurrentPrice(currency.yahooSymbol);
  final rateNow = now.fold<double?>((_) => null, (r) => r > 0 ? r : null);
  if (rateNow == null) return null;
  final history = await quotes.getHistoricalDaily(currency.yahooSymbol);
  return FxBreakdown.compute(
    lots: [
      for (final l in lots)
        FxLot(
          costUsd: l.position.costBasis,
          valueUsd: l.marketValue,
          purchaseDate: l.position.purchaseDate,
        ),
    ],
    rateNow: rateNow,
    history: history.fold((_) => const [], (h) => h),
  );
}

/// El desglose de la cartera de la Home en la moneda elegida.
final fxBreakdownProvider = FutureProvider.autoDispose<FxBreakdown?>((ref) {
  final currency = ref.watch(displayCurrencyProvider);
  final lots = ref.watch(
    homeProvider.select((s) => s.summary?.lots ?? const <PositionValuation>[]),
  );
  return loadFxBreakdown(
    quotes: ref.watch(quoteRepositoryProvider),
    currency: currency,
    lots: lots,
  );
});
