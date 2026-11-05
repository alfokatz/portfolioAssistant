import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/portfolio_diagnosis/domain/portfolio_diagnosis.dart';
import 'package:portfolio_assistant/presentation/shared/formatting/app_number_format.dart';

/// Los textos de cada hallazgo, con los números en el formato de la app.
/// Porty los dice en primera persona; nunca los escribe el modelo.
abstract final class DiagnosisCopy {
  static String _pct(double? v, {int decimals = 0}) =>
      AppNumberFormat.percent(v ?? 0, decimals: decimals, signed: false);

  /// Redondo: en una frase, los centavos sobran (las comisiones chicas, con
  /// centavos, para que no digan "$0").
  static String _money(double? v) =>
      (v ?? 0).abs() < 100
          ? AppNumberFormat.money(v ?? 0)
          : AppNumberFormat.wholeMoney(v ?? 0);

  /// "VOO", "VOO y QQQ", "VOO, QQQ y VT".
  static String list(List<String> items) {
    if (items.isEmpty) return '';
    if (items.length == 1) return items.single;
    final and = 'diagnosis_list_and'.tr();
    return '${items.sublist(0, items.length - 1).join(', ')} $and ${items.last}';
  }

  static IconData icon(DiagnosisFinding f) => switch (f.kind) {
    DiagnosisKind.overlap => Icons.join_inner_rounded,
    DiagnosisKind.sector => Icons.pie_chart_outline_rounded,
    DiagnosisKind.topHolding => Icons.donut_large_rounded,
    DiagnosisKind.topThree => Icons.stacked_bar_chart_rounded,
    DiagnosisKind.fees => Icons.receipt_long_outlined,
    DiagnosisKind.vsMarket => Icons.compare_arrows_rounded,
    DiagnosisKind.bestWorst =>
      f.numbers.containsKey('worst_pct')
          ? Icons.trending_down_rounded
          : Icons.trending_up_rounded,
    DiagnosisKind.spread => Icons.grid_view_rounded,
  };

  static String title(DiagnosisFinding f) {
    final n = f.numbers;
    return switch (f.kind) {
      DiagnosisKind.overlap => 'diagnosis_overlap_title'.tr(
        namedArgs: {'ticker': f.ticker!, 'total': _pct(n['total'])},
      ),
      DiagnosisKind.sector => 'diagnosis_sector_title'.tr(
        namedArgs: {'sector': f.sector!, 'total': _pct(n['total'])},
      ),
      DiagnosisKind.topHolding =>
        (n['pct'] ?? 0) >= 99.5
            ? 'diagnosis_top_all_title'.tr(namedArgs: {'ticker': f.ticker!})
            : 'diagnosis_top_title'.tr(
              namedArgs: {'ticker': f.ticker!, 'pct': _pct(n['pct'])},
            ),
      DiagnosisKind.topThree => 'diagnosis_three_title'.tr(
        namedArgs: {'pct': _pct(n['pct'])},
      ),
      DiagnosisKind.fees =>
        f.tone == DiagnosisTone.good
            ? 'diagnosis_fees_good_title'.tr()
            : 'diagnosis_fees_title'.tr(
              namedArgs: {'annual': _money(n['annual'])},
            ),
      DiagnosisKind.vsMarket =>
        (n['diff_pct'] ?? 0) >= 0
            ? 'diagnosis_market_ahead_title'.tr(
              namedArgs: {'diff': _money(n['diff']?.abs())},
            )
            : 'diagnosis_market_behind_title'.tr(
              namedArgs: {'diff': _money(n['diff']?.abs())},
            ),
      DiagnosisKind.bestWorst =>
        n.containsKey('worst_pct')
            ? 'diagnosis_worst_title'.tr(
              namedArgs: {
                'ticker': f.ticker!,
                'pct': AppNumberFormat.percent(n['worst_pct']!, decimals: 0),
              },
            )
            : 'diagnosis_best_title'.tr(
              namedArgs: {
                'ticker': f.ticker!,
                'pct': AppNumberFormat.percent(n['best_pct']!, decimals: 0),
              },
            ),
      DiagnosisKind.spread => 'diagnosis_spread_title'.tr(),
    };
  }

  static String detail(DiagnosisFinding f) {
    final n = f.numbers;
    return switch (f.kind) {
      DiagnosisKind.overlap =>
        (n['direct'] ?? 0) > 0
            ? 'diagnosis_overlap_detail'.tr(
              namedArgs: {'direct': _pct(n['direct']), 'via': list(f.via)},
            )
            : 'diagnosis_overlap_detail_funds'.tr(
              namedArgs: {'via': list(f.via)},
            ),
      DiagnosisKind.sector =>
        f.via.isNotEmpty && (n['total'] ?? 0) - (n['direct'] ?? 0) >= 10
            ? 'diagnosis_sector_detail_hidden'.tr(
              namedArgs: {'via': list(f.via), 'direct': _pct(n['direct'])},
            )
            : f.via.isNotEmpty
            ? 'diagnosis_sector_detail'.tr(namedArgs: {'via': list(f.via)})
            : 'diagnosis_sector_detail_stocks'.tr(),
      DiagnosisKind.topHolding => 'diagnosis_top_detail'.tr(
        namedArgs: {
          'ticker': f.ticker!,
          // Si esa posición cae 20 %, cuánto cae la cartera.
          'impact': _pct((n['pct'] ?? 0) * 0.2),
        },
      ),
      DiagnosisKind.topThree => 'diagnosis_three_detail'.tr(
        namedArgs: {
          'tickers': list(f.via),
          'rest': '${((n['count'] ?? 3) - 3).round()}',
        },
      ),
      DiagnosisKind.fees =>
        f.tone == DiagnosisTone.good
            ? 'diagnosis_fees_good_detail'.tr(
              namedArgs: {
                'avg': _pct(n['avg_pct'], decimals: 2),
                'annual': _money(n['annual']),
              },
            )
            : 'diagnosis_fees_detail'.tr(
              namedArgs: {
                'ticker': f.ticker!,
                'ticker_pct': _pct(n['ticker_pct'], decimals: 2),
              },
            ),
      DiagnosisKind.vsMarket => 'diagnosis_market_detail'.tr(
        namedArgs: {
          'year': '${(n['since_year'] ?? 0).round()}',
          'market': _money(n['market']),
          'actual': _money(n['actual']),
        },
      ),
      DiagnosisKind.bestWorst =>
        n.containsKey('worst_pct') && n.containsKey('best_pct')
            ? 'diagnosis_worst_detail_best'.tr(
              namedArgs: {
                'best': f.via.first,
                'best_pct': AppNumberFormat.percent(
                  n['best_pct']!,
                  decimals: 0,
                ),
              },
            )
            : n.containsKey('worst_pct')
            ? 'diagnosis_worst_detail'.tr()
            : 'diagnosis_best_detail'.tr(),
      DiagnosisKind.spread => 'diagnosis_spread_detail'.tr(
        namedArgs: {
          'count': '${(n['count'] ?? 0).round()}',
          'top': _pct(n['top_pct']),
        },
      ),
    };
  }

  /// La pregunta que abre el chat, con los números adentro (así Porty la
  /// entiende sin ir a buscarlos).
  static String question(DiagnosisFinding f) {
    final n = f.numbers;
    return switch (f.kind) {
      DiagnosisKind.overlap => 'diagnosis_overlap_question'.tr(
        namedArgs: {'ticker': f.ticker!, 'total': _pct(n['total'])},
      ),
      DiagnosisKind.sector => 'diagnosis_sector_question'.tr(
        namedArgs: {'sector': f.sector!, 'total': _pct(n['total'])},
      ),
      DiagnosisKind.topHolding => 'diagnosis_top_question'.tr(
        namedArgs: {'ticker': f.ticker!, 'pct': _pct(n['pct'])},
      ),
      DiagnosisKind.topThree => 'diagnosis_three_question'.tr(),
      DiagnosisKind.fees =>
        f.tone == DiagnosisTone.good
            ? 'diagnosis_fees_good_question'.tr()
            : 'diagnosis_fees_question'.tr(),
      DiagnosisKind.vsMarket =>
        (n['diff_pct'] ?? 0) >= 0
            ? 'diagnosis_market_ahead_question'.tr()
            : 'diagnosis_market_behind_question'.tr(),
      DiagnosisKind.bestWorst =>
        n.containsKey('worst_pct')
            ? 'diagnosis_worst_question'.tr(namedArgs: {'ticker': f.ticker!})
            : 'diagnosis_best_question'.tr(namedArgs: {'ticker': f.ticker!}),
      DiagnosisKind.spread => 'diagnosis_spread_question'.tr(),
    };
  }

  /// Lo que dice Porty arriba de todo.
  static String headline(PortfolioDiagnosis d) {
    final attention =
        d.findings.where((f) => f.tone == DiagnosisTone.attention).length;
    if (attention == 0) return 'diagnosis_porty_good'.tr();
    if (attention == 1) return 'diagnosis_porty_one'.tr();
    return 'diagnosis_porty_many'.tr(namedArgs: {'count': '$attention'});
  }
}
