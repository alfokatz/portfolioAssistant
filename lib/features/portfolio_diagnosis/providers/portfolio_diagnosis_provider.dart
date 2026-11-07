import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_client_provider.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';
import 'package:portfolio_assistant/features/portfolio_diagnosis/data/diagnosis_data_source.dart';
import 'package:portfolio_assistant/features/portfolio_diagnosis/domain/portfolio_diagnosis.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// El diagnóstico de la cartera que tiene la Home ahora. Se arma cada vez
/// que se abre la pantalla (autoDispose): fondos, sectores y S&P 500 en
/// paralelo; lo que falla, no sale.
final portfolioDiagnosisProvider =
    FutureProvider.autoDispose<PortfolioDiagnosis>((ref) async {
      final summary = ref.read(homeProvider).summary;
      final valuations = summary?.valuations ?? const [];
      if (valuations.isEmpty) {
        return const PortfolioDiagnosis(findings: [], positions: 0, funds: 0);
      }
      final source = ref.read(diagnosisDataSourceProvider);
      final tickers =
          {
            for (final v in valuations)
              PortfolioCalculator.normalizeTicker(v.position.ticker),
          }.toList();

      final fundsF = source.funds(tickers);
      final spF = source.sp500();
      final funds = await fundsF;
      final stocks = [
        for (final t in tickers)
          if (!funds.containsKey(t.toUpperCase())) t,
      ];
      final sectors = await source.sectors(stocks);
      final sp500 = await spF;

      return PortfolioDiagnosisBuilder.build(
        DiagnosisInputs(
          valuations: valuations,
          lots: summary?.lots ?? const [],
          sectorByTicker: sectors,
          funds: funds,
          sp500: sp500,
          now: DateTime.now(),
        ),
      );
    });

/// Si ya vio su primer diagnóstico (por usuario, en el teléfono). Mientras
/// no lo vio y tiene cartera, la Home lo ofrece.
class DiagnosisSeenNotifier extends StateNotifier<bool> {
  DiagnosisSeenNotifier(this._prefs, this._userId)
    : super(_prefs?.getBool(_key(_userId)) ?? false);

  final SharedPreferences? _prefs;
  final String? _userId;

  static String _key(String? userId) =>
      'portfolio_diagnosis_seen${userId == null ? '' : ':$userId'}';

  Future<void> markSeen() async {
    if (state) return;
    state = true;
    try {
      await _prefs?.setBool(_key(_userId), true);
    } catch (_) {}
  }
}

final diagnosisSeenProvider =
    StateNotifierProvider<DiagnosisSeenNotifier, bool>((ref) {
      SharedPreferences? prefs;
      String? userId;
      try {
        prefs = ref.watch(sharedPreferencesProvider);
      } catch (_) {
        // Sin preferencias (tests de otras pantallas): en memoria.
      }
      try {
        userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
      } catch (_) {}
      return DiagnosisSeenNotifier(prefs, userId);
    });
