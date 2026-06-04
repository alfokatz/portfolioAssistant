import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:genui/genui.dart';
import 'package:intl/intl.dart';
import 'package:portfolio_assistant/features/analysis/catalog/analysis_colors.dart';
import 'package:portfolio_assistant/presentation/shared/charts/sparkline_chart.dart';
import 'package:portfolio_assistant/shared/utils/genui_helpers.dart';
import 'package:url_launcher/url_launcher.dart';

abstract final class AnalysisCatalogWidgets {
  static Widget portfolioSummaryCard(CatalogItemContext ctx) {
    final data = _PortfolioSummaryData.fromMap(ctx.data as JsonMap);
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final isUp = data.totalGainLoss >= 0;
    final pnlColor = isUp ? AnalysisColors.profit : AnalysisColors.loss;

    return Card(
      color: AnalysisColors.cardBackground,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AnalysisColors.textSecondary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    data.periodLabel,
                    style: const TextStyle(
                      color: AnalysisColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
                const Spacer(),
                Icon(
                  _trendIcon(data.trend),
                  color: pnlColor,
                  size: 22,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              currency.format(data.totalValue),
              style: const TextStyle(
                color: AnalysisColors.textPrimary,
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${isUp ? '+' : ''}${currency.format(data.totalGainLoss)} '
              '(${data.totalGainLossPercent.toStringAsFixed(2)}%)',
              style: TextStyle(
                color: pnlColor,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget assetPerformanceCard(CatalogItemContext ctx) {
    final data = _AssetPerformanceData.fromMap(ctx.data as JsonMap);
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final isWinner = data.status == 'winner' || data.gainLoss >= 0;
    final pnlColor = isWinner ? AnalysisColors.profit : AnalysisColors.loss;

    return Card(
      color: AnalysisColors.cardBackground,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.ticker,
                    style: const TextStyle(
                      color: AnalysisColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    data.companyName,
                    style: const TextStyle(
                      color: AnalysisColors.textSecondary,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${data.shares.toStringAsFixed(data.shares == data.shares.roundToDouble() ? 0 : 2)} acciones',
                    style: const TextStyle(
                      color: AnalysisColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  currency.format(data.currentPrice * data.shares),
                  style: const TextStyle(
                    color: AnalysisColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${data.gainLoss >= 0 ? '+' : ''}'
                  '${currency.format(data.gainLoss)} '
                  '(${data.gainLossPercent.toStringAsFixed(1)}%)',
                  style: TextStyle(color: pnlColor, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(width: 10),
            SparklineChart(
              values: data.sparklineData,
              isPositive: data.gainLoss >= 0,
              height: 32,
              width: 64,
            ),
          ],
        ),
      ),
    );
  }

  static Widget alertBanner(CatalogItemContext ctx) {
    final data = _AlertBannerData.fromMap(ctx.data as JsonMap);
    final colors = _severityColors(data.severity);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(colors.icon, color: colors.foreground, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              data.message,
              style: TextStyle(color: colors.foreground, fontSize: 14),
            ),
          ),
          if (data.actionLabel != null && data.actionEvent != null)
            TextButton(
              onPressed: () => ctx.dispatchEvent(
                UserActionEvent(
                  name: data.actionEvent!,
                  sourceComponentId: ctx.id,
                  context: const {},
                ),
              ),
              child: Text(
                data.actionLabel!,
                style: TextStyle(color: colors.foreground),
              ),
            ),
        ],
      ),
    );
  }

  static Widget portfolioInsightCard(CatalogItemContext ctx) {
    final data = _PortfolioInsightData.fromMap(ctx.data as JsonMap);

    return Card(
      color: AnalysisColors.cardBackground,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              _insightIcon(data.icon),
              color: _pillarColor(data.pillar),
              size: 26,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.title,
                    style: const TextStyle(
                      color: AnalysisColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    data.body,
                    style: const TextStyle(
                      color: AnalysisColors.textSecondary,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget newsHighlightCard(CatalogItemContext ctx) {
    final data = _NewsHighlightData.fromMap(ctx.data as JsonMap);
    final borderColor = _sentimentColor(data.sentiment);

    return Card(
      color: AnalysisColors.cardBackground,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor.withValues(alpha: 0.3)),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border(
            left: BorderSide(color: borderColor, width: 4),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              data.headline,
              style: const TextStyle(
                color: AnalysisColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              data.summary,
              style: const TextStyle(
                color: AnalysisColors.textSecondary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              data.relevance,
              style: TextStyle(
                color: borderColor,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${data.source} · ${data.publishedAt}',
                    style: const TextStyle(
                      color: AnalysisColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (data.ticker != null) _tickerBadge(data.ticker!),
              ],
            ),
            if (data.url != null && data.url!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => _openUrl(data.url!),
                  style: TextButton.styleFrom(
                    foregroundColor: AnalysisColors.info,
                    padding: EdgeInsets.zero,
                  ),
                  child: const Text('Leer más →'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static Widget newsFeedCard(CatalogItemContext ctx) {
    final data = _NewsFeedData.fromMap(ctx.data as JsonMap);
    final items = data.items.take(5).toList();

    return Card(
      color: AnalysisColors.cardBackground,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              data.title,
              style: const TextStyle(
                color: AnalysisColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  color: AnalysisColors.textSecondary.withValues(alpha: 0.2),
                ),
              _NewsFeedRow(item: items[i]),
            ],
          ],
        ),
      ),
    );
  }

  static Widget quickActionRow(CatalogItemContext ctx) {
    final data = _QuickActionRowData.fromMap(ctx.data as JsonMap);
    final actions = data.actions.take(3).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () => ctx.dispatchEvent(
                  UserActionEvent(
                    name: actions[i].event,
                    sourceComponentId: ctx.id,
                    context: const {},
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AnalysisColors.textPrimary,
                  side: const BorderSide(color: AnalysisColors.textSecondary),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(actions[i].label),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static IconData _trendIcon(String trend) => switch (trend) {
        'up' => Icons.trending_up,
        'down' => Icons.trending_down,
        _ => Icons.trending_flat,
      };

  static IconData _insightIcon(String icon) => switch (icon) {
        'alert' => Icons.warning_amber_rounded,
        'tip' => Icons.lightbulb_outline,
        _ => Icons.show_chart,
      };

  static Color _pillarColor(String pillar) => switch (pillar) {
        'risk' => AnalysisColors.warning,
        'opportunity' => AnalysisColors.info,
        _ => AnalysisColors.profit,
      };

  static Color _sentimentColor(String sentiment) => switch (sentiment) {
        'positive' => AnalysisColors.profit,
        'negative' => AnalysisColors.loss,
        _ => AnalysisColors.textSecondary,
      };

  static Widget _tickerBadge(String ticker) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AnalysisColors.textSecondary.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        ticker,
        style: const TextStyle(
          color: AnalysisColors.textPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  static Future<bool> _openUrl(String url) async {
    final uri = _parseExternalUrl(url);
    if (uri == null) return false;

    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on PlatformException {
      try {
        return await launchUrl(uri, mode: LaunchMode.platformDefault);
      } on PlatformException {
        return false;
      }
    }
  }

  static Uri? _parseExternalUrl(String url) {
    var value = url.trim();
    if (value.isEmpty) return null;
    if (!value.contains('://')) {
      value = 'https://$value';
    }
    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return uri;
  }

  static _SeverityStyle _severityColors(String severity) => switch (severity) {
        'warning' => _SeverityStyle(
          background: AnalysisColors.warning.withValues(alpha: 0.15),
          border: AnalysisColors.warning.withValues(alpha: 0.5),
          foreground: AnalysisColors.warning,
          icon: Icons.warning_amber_rounded,
        ),
        'critical' => const _SeverityStyle(
          background: Color(0x33FF3D00),
          border: AnalysisColors.critical,
          foreground: AnalysisColors.critical,
          icon: Icons.error_outline,
        ),
        _ => _SeverityStyle(
          background: AnalysisColors.info.withValues(alpha: 0.15),
          border: AnalysisColors.info.withValues(alpha: 0.5),
          foreground: AnalysisColors.info,
          icon: Icons.info_outline,
        ),
      };
}

class _SeverityStyle {
  final Color background;
  final Color border;
  final Color foreground;
  final IconData icon;

  const _SeverityStyle({
    required this.background,
    required this.border,
    required this.foreground,
    required this.icon,
  });
}

extension type _PortfolioSummaryData.fromMap(JsonMap _json) {
  factory _PortfolioSummaryData({
    required double totalValue,
    required double totalGainLoss,
    required double totalGainLossPercent,
    required String trend,
    required String periodLabel,
  }) =>
      _PortfolioSummaryData.fromMap({
        'totalValue': totalValue,
        'totalGainLoss': totalGainLoss,
        'totalGainLossPercent': totalGainLossPercent,
        'trend': trend,
        'periodLabel': periodLabel,
      });

  double get totalValue =>
      GenUiHelpers.safeDouble(_json['totalValue'], defaultValue: 0);
  double get totalGainLoss =>
      GenUiHelpers.safeDouble(_json['totalGainLoss'], defaultValue: 0);
  double get totalGainLossPercent =>
      GenUiHelpers.safeDouble(_json['totalGainLossPercent'], defaultValue: 0);
  String get trend => GenUiHelpers.safeEnum(
        _json['trend'],
        ['up', 'down', 'neutral'],
        defaultValue: 'neutral',
      );
  String get periodLabel =>
      GenUiHelpers.safeString(_json['periodLabel'], defaultValue: 'hoy');
}

extension type _AssetPerformanceData.fromMap(JsonMap _json) {
  factory _AssetPerformanceData({
    required String ticker,
    required String companyName,
    required double currentPrice,
    required double gainLoss,
    required double gainLossPercent,
    required double shares,
    required String status,
    required List<double> sparklineData,
  }) =>
      _AssetPerformanceData.fromMap({
        'ticker': ticker,
        'companyName': companyName,
        'currentPrice': currentPrice,
        'gainLoss': gainLoss,
        'gainLossPercent': gainLossPercent,
        'shares': shares,
        'status': status,
        'sparklineData': sparklineData,
      });

  String get ticker =>
      GenUiHelpers.safeString(_json['ticker'], defaultValue: '—');
  String get companyName =>
      GenUiHelpers.safeString(_json['companyName'], defaultValue: '');
  double get currentPrice =>
      GenUiHelpers.safeDouble(_json['currentPrice'], defaultValue: 0);
  double get gainLoss =>
      GenUiHelpers.safeDouble(_json['gainLoss'], defaultValue: 0);
  double get gainLossPercent =>
      GenUiHelpers.safeDouble(_json['gainLossPercent'], defaultValue: 0);
  double get shares =>
      GenUiHelpers.safeDouble(_json['shares'], defaultValue: 0);
  String get status => GenUiHelpers.safeEnum(
        _json['status'],
        ['winner', 'loser', 'neutral'],
        defaultValue: 'neutral',
      );
  List<double> get sparklineData =>
      GenUiHelpers.safeDoubleList(_json['sparklineData']);
}

extension type _AlertBannerData.fromMap(JsonMap _json) {
  String get message =>
      GenUiHelpers.safeString(_json['message'], defaultValue: '');
  String get severity => GenUiHelpers.safeEnum(
        _json['severity'],
        ['info', 'warning', 'critical'],
        defaultValue: 'info',
      );
  String? get actionLabel => _json['actionLabel'] as String?;
  String? get actionEvent => _json['actionEvent'] as String?;
}

extension type _PortfolioInsightData.fromMap(JsonMap _json) {
  String get title =>
      GenUiHelpers.safeString(_json['title'], defaultValue: '');
  String get body => GenUiHelpers.safeString(_json['body'], defaultValue: '');
  String get pillar => GenUiHelpers.safeEnum(
        _json['pillar'],
        ['performance', 'risk', 'opportunity'],
        defaultValue: 'performance',
      );
  String get icon => GenUiHelpers.safeEnum(
        _json['icon'],
        ['trend', 'alert', 'tip'],
        defaultValue: 'trend',
      );
}

extension type _QuickActionRowData.fromMap(JsonMap _json) {
  List<_QuickAction> get actions {
    final list = _json['actions'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => _QuickAction.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }
}

extension type _QuickAction.fromMap(JsonMap _json) {
  String get label =>
      GenUiHelpers.safeString(_json['label'], defaultValue: 'Acción');
  String get event =>
      GenUiHelpers.safeString(_json['event'], defaultValue: '');
}

extension type _NewsHighlightData.fromMap(JsonMap _json) {
  String get headline =>
      GenUiHelpers.safeString(_json['headline'], defaultValue: '');
  String get summary =>
      GenUiHelpers.safeString(_json['summary'], defaultValue: '');
  String get source =>
      GenUiHelpers.safeString(_json['source'], defaultValue: '');
  String get publishedAt =>
      GenUiHelpers.safeString(_json['publishedAt'], defaultValue: '');
  String get sentiment => GenUiHelpers.safeEnum(
        _json['sentiment'],
        ['positive', 'negative', 'neutral'],
        defaultValue: 'neutral',
      );
  String get relevance =>
      GenUiHelpers.safeString(_json['relevance'], defaultValue: '');
  String? get ticker => _json['ticker'] as String?;
  String? get url => _json['url'] as String?;
}

extension type _NewsFeedData.fromMap(JsonMap _json) {
  String get title => GenUiHelpers.safeString(
        _json['title'],
        defaultValue: 'Más noticias de tu portfolio',
      );
  List<_NewsFeedItem> get items {
    final list = _json['items'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => _NewsFeedItem.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }
}

extension type _NewsFeedItem.fromMap(JsonMap _json) {
  String get headline =>
      GenUiHelpers.safeString(_json['headline'], defaultValue: '');
  String get source =>
      GenUiHelpers.safeString(_json['source'], defaultValue: '');
  String get publishedAt =>
      GenUiHelpers.safeString(_json['publishedAt'], defaultValue: '');
  String get sentiment => GenUiHelpers.safeEnum(
        _json['sentiment'],
        ['positive', 'negative', 'neutral'],
        defaultValue: 'neutral',
      );
  String? get ticker => _json['ticker'] as String?;
  String? get url => _json['url'] as String?;
}

class _NewsFeedRow extends StatelessWidget {
  const _NewsFeedRow({required this.item});

  final _NewsFeedItem item;

  @override
  Widget build(BuildContext context) {
    final dotColor = AnalysisCatalogWidgets._sentimentColor(item.sentiment);
    final hasUrl = item.url != null && item.url!.isNotEmpty;

    return InkWell(
      onTap: hasUrl ? () => AnalysisCatalogWidgets._openUrl(item.url!) : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.headline,
                    style: const TextStyle(
                      color: AnalysisColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${item.source} · ${item.publishedAt}',
                    style: const TextStyle(
                      color: AnalysisColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (item.ticker != null) ...[
              const SizedBox(width: 8),
              AnalysisCatalogWidgets._tickerBadge(item.ticker!),
            ],
          ],
        ),
      ),
    );
  }
}
