import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/domain/entities/benchmark_point.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lo último que mostró la Home, para abrirla con datos al instante (y
/// actualizarlos en el lugar cuando llega lo nuevo) en vez de un skeleton.
@immutable
class HomeSnapshot {
  const HomeSnapshot({
    required this.summary,
    this.history = const [],
    this.benchmark = const [],
    this.closedPositionsCount = 0,
  });

  final PortfolioSummary summary;
  final List<PortfolioHistoryPoint> history;
  final List<BenchmarkPoint> benchmark;
  final int closedPositionsCount;
}

/// Guarda un [HomeSnapshot] por usuario en `SharedPreferences`. La clave
/// lleva el id del usuario: otra cuenta en el mismo teléfono nunca ve la
/// cartera de la anterior. Cualquier dato roto se ignora (sin caché = el
/// skeleton de siempre).
class HomePortfolioCache {
  HomePortfolioCache({
    required SharedPreferences prefs,
    required String? Function() userId,
  }) : _prefs = prefs,
       _userId = userId;

  final SharedPreferences _prefs;
  final String? Function() _userId;

  static const _version = 1;
  static const _prefix = 'home_snapshot_v${_version}_';

  String? get _key {
    final id = _userId();
    return id == null || id.isEmpty ? null : '$_prefix$id';
  }

  HomeSnapshot? read() {
    final key = _key;
    if (key == null) return null;
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      return HomeSnapshotCodec.decode(jsonDecode(raw) as Map<String, Object?>);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(HomeSnapshot snapshot) async {
    final key = _key;
    if (key == null) return;
    await _prefs.setString(key, jsonEncode(HomeSnapshotCodec.encode(snapshot)));
  }
}

/// JSON de un [HomeSnapshot] (las entidades del dominio no tienen uno).
abstract final class HomeSnapshotCodec {
  static Map<String, Object?> encode(HomeSnapshot s) => {
    'summary': {
      'totalValue': s.summary.totalValue,
      'totalCostBasis': s.summary.totalCostBasis,
      'totalPnlAbsolute': s.summary.totalPnlAbsolute,
      'totalPnlPercent': s.summary.totalPnlPercent,
      'valuations': [for (final v in s.summary.valuations) _valuation(v)],
      'lots': [for (final v in s.summary.lots) _valuation(v)],
    },
    'history': [
      for (final p in s.history)
        {
          'date': p.date.toIso8601String(),
          'totalValue': p.totalValue,
          'totalCostBasis': p.totalCostBasis,
        },
    ],
    'benchmark': [
      for (final p in s.benchmark)
        {
          'date': p.date.toIso8601String(),
          'portfolio': p.portfolioNormalized,
          'sp500': p.sp500Normalized,
        },
    ],
    'closedPositionsCount': s.closedPositionsCount,
  };

  static HomeSnapshot decode(Map<String, Object?> json) {
    final summary = json['summary']! as Map<String, Object?>;
    List<Map<String, Object?>> list(Object? v) =>
        (v as List? ?? const []).cast<Map<String, Object?>>();
    double n(Object? v) => (v! as num).toDouble();

    return HomeSnapshot(
      summary: PortfolioSummary(
        totalValue: n(summary['totalValue']),
        totalCostBasis: n(summary['totalCostBasis']),
        totalPnlAbsolute: n(summary['totalPnlAbsolute']),
        totalPnlPercent: n(summary['totalPnlPercent']),
        valuations: [
          for (final v in list(summary['valuations'])) _toValuation(v),
        ],
        lots: [for (final v in list(summary['lots'])) _toValuation(v)],
      ),
      history: [
        for (final p in list(json['history']))
          PortfolioHistoryPoint(
            date: DateTime.parse(p['date']! as String),
            totalValue: n(p['totalValue']),
            totalCostBasis: n(p['totalCostBasis']),
          ),
      ],
      benchmark: [
        for (final p in list(json['benchmark']))
          BenchmarkPoint(
            date: DateTime.parse(p['date']! as String),
            portfolioNormalized: n(p['portfolio']),
            sp500Normalized: n(p['sp500']),
          ),
      ],
      closedPositionsCount:
          (json['closedPositionsCount'] as num?)?.toInt() ?? 0,
    );
  }

  static Map<String, Object?> _valuation(PositionValuation v) => {
    'id': v.position.id,
    'ticker': v.position.ticker,
    'quantity': v.position.quantity,
    'purchasePrice': v.position.purchasePrice,
    'purchaseDate': v.position.purchaseDate.toIso8601String(),
    'currentPrice': v.currentPrice,
    'marketValue': v.marketValue,
    'pnlAbsolute': v.pnlAbsolute,
    'pnlPercent': v.pnlPercent,
  };

  static PositionValuation _toValuation(Map<String, Object?> v) {
    double n(String k) => (v[k]! as num).toDouble();
    return PositionValuation(
      position: Position(
        id: v['id']! as String,
        ticker: v['ticker']! as String,
        quantity: n('quantity'),
        purchasePrice: n('purchasePrice'),
        purchaseDate: DateTime.parse(v['purchaseDate']! as String),
      ),
      currentPrice: n('currentPrice'),
      marketValue: n('marketValue'),
      pnlAbsolute: n('pnlAbsolute'),
      pnlPercent: n('pnlPercent'),
    );
  }
}

/// `null` sin `SharedPreferences` o sin sesión (tests, arranque sin
/// override): la Home funciona igual, sin caché.
final homePortfolioCacheProvider = Provider<HomePortfolioCache?>((ref) {
  try {
    final prefs = ref.watch(sharedPreferencesProvider);
    final auth = ref.watch(supabaseAuthServiceProvider);
    return HomePortfolioCache(
      prefs: prefs,
      userId: () {
        try {
          return auth.currentUser?.id;
        } catch (_) {
          return null;
        }
      },
    );
  } catch (_) {
    return null;
  }
});
