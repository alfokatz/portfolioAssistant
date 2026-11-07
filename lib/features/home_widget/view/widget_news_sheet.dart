import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/nav/assistant_nav.dart';
import 'package:portfolio_assistant/features/assistant/states/assistant_state.dart';
import 'package:portfolio_assistant/features/home_widget/data/widget_items_cache.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:portfolio_assistant/features/subscription/config/paywall_source.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_paywall_sheet.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:url_launcher/url_launcher.dart';

/// Abre una URL afuera de la app (inyectable en tests).
final widgetUrlLauncherProvider = Provider<Future<bool> Function(Uri uri)>(
  (ref) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// Qué plan trae lo que el aviso del widget prometía (estado bloqueado).
enum WidgetLockedKind {
  news('news', 'home_widget_locked_premium', PaywallSource.widgetHeldNews),
  earnings('earnings', 'home_widget_locked_gold', PaywallSource.widgetEarnings);

  const WidgetLockedKind(this.type, this.textKey, this.source);

  final String type;
  final String textKey;
  final String source;

  /// Noticias usa `heldNews` y resultados `goldRequired` (no hay motivos
  /// propios del widget).
  PaywallReason get reason =>
      this == news ? PaywallReason.heldNews : PaywallReason.goldRequired;
}

/// "Novedades de tu cartera": los ítems vigentes de la caché privada con el
/// tocado arriba, o el estado bloqueado si venía de un aviso del plan
/// siguiente. Se abre desde `WidgetLaunchListener`, sin ruta de go_router.
class WidgetNewsSheet extends StatelessWidget {
  const WidgetNewsSheet({
    super.key,
    required this.items,
    required this.now,
    this.locked,
    this.onRead,
    this.onAsk,
    this.onSeePlans,
  });

  final List<WidgetCachedItem> items;
  final DateTime now;
  final WidgetLockedKind? locked;
  final void Function(WidgetCachedItem item)? onRead;
  final void Function(WidgetCachedItem item)? onAsk;
  final VoidCallback? onSeePlans;

  /// Abre la hoja. [items] ya viene con el tocado primero.
  static Future<void> show(
    BuildContext context,
    WidgetRef ref, {
    required List<WidgetCachedItem> items,
    WidgetLockedKind? locked,
    DateTime? now,
  }) {
    final events = ref.read(productEventsProvider);
    void log(String action, String type) => events.log(
      ProductEvent.widgetItemAction,
      {'action': action, 'type': type, 'from_widget': true},
    );
    final launcher = ref.read(widgetUrlLauncherProvider);
    final host = context;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder:
          (sheet) => WidgetNewsSheet(
            items: items,
            now: now ?? DateTime.now(),
            locked: locked,
            onRead: (item) {
              log('read_source', item.kind);
              final uri = Uri.tryParse(item.url ?? '');
              // Solo https: un link http se puede reemplazar en una red
              // hostil por una página falsa que llega desde Porty.
              if (uri != null && uri.scheme == 'https') {
                launcher(uri).catchError((_) => false);
              }
            },
            onAsk: (item) {
              log('ask_porty', item.kind);
              final id = item.isNews ? 'news_why' : 'earnings_when';
              final question = 'home_widget_question_$id'.tr(
                namedArgs: {'ticker': item.ticker},
              );
              Navigator.of(sheet).pop();
              if (host.mounted) {
                GotoAssistant(
                  initialQuestion: question,
                  origin: AssistantQuestionOrigin.widget(id),
                ).navigate(context: host);
              }
            },
            onSeePlans: () {
              final kind = locked!;
              log('open_paywall', kind.type);
              Navigator.of(sheet).pop();
              if (host.mounted) {
                SubscriptionPaywallSheet.show(
                  host,
                  ref,
                  reason: kind.reason,
                  source: kind.source,
                  onUpgraded:
                      () => ref.read(subscriptionProvider.notifier).refresh(),
                );
              }
            },
          ),
    );
  }

  /// "hace 25 min" / "hace 3 h" / "ayer", como el widget.
  static String ageLabel(DateTime publishedAt, DateTime now) {
    final age = now.difference(publishedAt);
    if (age.inMinutes < 60) {
      return 'home_widget_age_min'.tr(
        namedArgs: {'n': '${age.inMinutes < 1 ? 1 : age.inMinutes}'},
      );
    }
    if (age.inHours < 24) {
      return 'home_widget_age_h'.tr(namedArgs: {'n': '${age.inHours}'});
    }
    return 'home_widget_age_yesterday'.tr();
  }

  static String _at(List<String> list, int i) => i < list.length ? list[i] : '';

  /// "AAPL · fecha estimada de resultados: hoy / mañana / jue 7 nov".
  static String earningsLine(WidgetCachedItem item, DateTime now) {
    final date = item.date!;
    final today = DateTime(now.year, now.month, now.day);
    final days =
        DateTime(date.year, date.month, date.day).difference(today).inDays;
    final ticker = {'ticker': item.ticker};
    if (days <= 0) {
      return 'home_widget_earnings_today'.tr(namedArgs: ticker);
    }
    if (days == 1) {
      return 'home_widget_earnings_tomorrow'.tr(namedArgs: ticker);
    }
    final weekdays = 'home_widget_weekdays'.tr().split(',');
    final months = 'home_widget_months'.tr().split(',');
    return 'home_widget_earnings_date'.tr(
      namedArgs: {
        ...ticker,
        'date': 'home_widget_date_format'.tr(
          namedArgs: {
            'weekday': _at(weekdays, date.weekday % 7),
            'day': '${date.day}',
            'month': _at(months, date.month - 1),
          },
        ),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final lockedKind = locked;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pageHorizontal,
          0,
          AppDimens.pageHorizontal,
          AppDimens.sp16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                'home_widget_sheet_title'.tr(),
                style: tt.titleLarge?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            const SizedBox(height: AppDimens.sp16),
            if (lockedKind != null)
              _Locked(kind: lockedKind, onSeePlans: onSeePlans)
            else
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) Divider(height: 1, color: colors.border),
                _ItemRow(
                  item: items[i],
                  now: now,
                  primary: i == 0,
                  onRead: onRead,
                  onAsk: onAsk,
                ),
              ],
            const SizedBox(height: AppDimens.sp20),
            Text(
              'home_widget_sheet_legend'.tr(),
              style: tt.bodySmall?.copyWith(
                color: colors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Locked extends StatelessWidget {
  const _Locked({required this.kind, required this.onSeePlans});

  final WidgetLockedKind kind;
  final VoidCallback? onSeePlans;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          kind.textKey.tr(),
          style: tt.bodyLarge?.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: AppDimens.sp16),
        SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: onSeePlans,
            style: FilledButton.styleFrom(
              backgroundColor: colors.textPrimary,
              foregroundColor: colors.surfaceCard,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDimens.radiusLg),
              ),
            ),
            child: Text('assistant_quota_nudge_cta'.tr()),
          ),
        ),
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.now,
    required this.primary,
    required this.onRead,
    required this.onAsk,
  });

  final WidgetCachedItem item;
  final DateTime now;
  final bool primary;
  final void Function(WidgetCachedItem item)? onRead;
  final void Function(WidgetCachedItem item)? onAsk;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final source = item.source ?? '';
    final String small;
    final String main;
    if (item.isNews) {
      small =
          '${item.ticker} · $source · '
          '${WidgetNewsSheet.ageLabel(item.publishedAt!, now)}';
      main = item.headline ?? '';
    } else {
      small = '';
      main = WidgetNewsSheet.earningsLine(item, now);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.sp12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (small.isNotEmpty)
            Text(
              small,
              style: tt.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          Text(
            main,
            style: tt.bodyLarge?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          if (primary) ...[
            const SizedBox(height: AppDimens.sp12),
            Wrap(
              spacing: AppDimens.sp8,
              runSpacing: AppDimens.sp8,
              children: [
                if (item.isNews && (item.url ?? '').isNotEmpty)
                  OutlinedButton(
                    onPressed: () => onRead?.call(item),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, AppDimens.touchTarget),
                      foregroundColor: colors.textPrimary,
                      side: BorderSide(color: colors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
                      ),
                    ),
                    child: Text(
                      'home_widget_read_on'.tr(namedArgs: {'source': source}),
                    ),
                  ),
                TextButton(
                  onPressed: () => onAsk?.call(item),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, AppDimens.touchTarget),
                    foregroundColor: colors.accentBlue,
                  ),
                  child: Text('home_widget_ask_porty'.tr()),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
