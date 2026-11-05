import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/features/broker_links/domain/broker_link.dart';
import 'package:portfolio_assistant/features/snaptrade/providers/snaptrade_provider.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:url_launcher/url_launcher.dart';

/// "Abrir en eToro ↗": filas planas (sin card) debajo de "Se actualiza
/// desde…", una por bróker de donde vino la posición. Abren afuera de
/// Porty: el usuario opera allá y la próxima sincronización lo trae.
class OpenInBrokerLinks extends ConsumerWidget {
  const OpenInBrokerLinks({
    super.key,
    required this.ticker,
    required this.sources,
    this.launch,
  });

  final String ticker;

  /// De dónde vienen las compras importadas.
  final Set<PositionSource> sources;

  /// Para tests; por defecto, el navegador o la app del bróker.
  final Future<bool> Function(Uri url)? launch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final links = BrokerLinks.forPosition(
      ticker: ticker,
      sources: sources,
      snaptradeImported:
          sources.contains(PositionSource.snaptrade)
              ? ref.watch(snaptradeProvider).connection.imported
              : const [],
    );
    if (links.isEmpty) return const SizedBox.shrink();
    final colors = context.customColors;

    Future<void> open(BrokerLink link) async {
      var ok = false;
      try {
        ok = await (launch ??
            (u) => launchUrl(u, mode: LaunchMode.externalApplication))(
          link.url,
        );
      } catch (_) {}
      if (!ok) {
        ref
            .read(alertProvider.notifier)
            .showError(message: 'broker_open_failed'.tr());
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final link in links)
          Semantics(
            link: true,
            hint: 'broker_open_hint'.tr(),
            child: TextButton.icon(
              onPressed: () => open(link),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              iconAlignment: IconAlignment.end,
              label: Text(
                (link.instrumentPage ? 'broker_open_in' : 'broker_open_site')
                    .tr(namedArgs: {'broker': link.broker}),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: TextButton.styleFrom(
                foregroundColor: colors.textPrimary,
                minimumSize: const Size(
                  AppDimens.touchTarget,
                  AppDimens.touchTarget,
                ),
                padding: const EdgeInsets.symmetric(horizontal: AppDimens.sp4),
                textStyle: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
      ],
    );
  }
}
