import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/binance/domain/binance_connection.dart';
import 'package:portfolio_assistant/features/binance/nav/binance_router.dart';
import 'package:portfolio_assistant/features/binance/providers/binance_provider.dart';
import 'package:portfolio_assistant/features/binance/view/widgets/binance_brand.dart';
import 'package:portfolio_assistant/features/broker_connect/view/broker_status_labels.dart';
import 'package:portfolio_assistant/features/etoro/nav/etoro_router.dart';
import 'package:portfolio_assistant/features/etoro/providers/etoro_connection_provider.dart';
import 'package:portfolio_assistant/features/etoro/view/widgets/etoro_brand.dart';
import 'package:portfolio_assistant/features/snaptrade/domain/snaptrade_connection.dart';
import 'package:portfolio_assistant/features/snaptrade/nav/snaptrade_router.dart';
import 'package:portfolio_assistant/features/snaptrade/providers/snaptrade_provider.dart';
import 'package:portfolio_assistant/features/snaptrade/view/widgets/snaptrade_brand.dart';
import 'package:portfolio_assistant/features/statement_import/nav/statement_import_router.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// "Conectá tu bróker": UNA entrada para todas las conexiones. Porty elige
/// el camino según el bróker: eToro y Binance van directo (gratis y con más
/// datos); el resto, por SnapTrade. Así nadie conecta eToro o Binance por
/// SnapTrade sin querer (y no se paga por eso).
class ConnectBrokerScreen extends ConsumerStatefulWidget {
  const ConnectBrokerScreen({super.key});

  @override
  ConsumerState<ConnectBrokerScreen> createState() =>
      _ConnectBrokerScreenState();
}

class _ConnectBrokerScreenState extends ConsumerState<ConnectBrokerScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!ref.read(etoroConnectionProvider).loaded) {
        ref.read(etoroConnectionProvider.notifier).load();
      }
      if (!ref.read(binanceProvider).loaded) {
        ref.read(binanceProvider.notifier).load();
      }
      if (!ref.read(snaptradeProvider).loaded) {
        ref.read(snaptradeProvider.notifier).load();
      }
    });
  }

  void _open(String routeName) {
    PortyHapticsService.maybeOf(context)?.selectionTap();
    context.pushNamed(routeName);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final etoroState = ref.watch(etoroConnectionProvider);
    final binanceState = ref.watch(binanceProvider);
    final othersState = ref.watch(snaptradeProvider);
    final etoro = BrokerStatusLabels.etoro(etoroState);
    final binance = BrokerStatusLabels.binance(binanceState);
    final others = BrokerStatusLabels.snaptrade(othersState);

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.pageHorizontal,
            0,
            AppDimens.pageHorizontal,
            AppDimens.sp48,
          ),
          children: [
            Semantics(
              header: true,
              child: Text(
                'connect_broker_title'.tr(),
                style: tt.displaySmall?.copyWith(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  height: 1.2,
                  color: colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: AppDimens.sp8),
            Text(
              'connect_broker_body'.tr(),
              style: tt.bodyMedium?.copyWith(
                color: colors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppDimens.sectionGap),
            Container(
              decoration: BoxDecoration(
                color: colors.surfaceCard,
                borderRadius: BorderRadius.circular(AppDimens.radiusLg),
                border: Border.all(color: colors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  BrokerChoiceRow(
                    leading: const EtoroAppIcon(),
                    title: 'eToro',
                    subtitle: etoro ?? 'connect_broker_etoro_body'.tr(),
                    status:
                        etoro == null
                            ? null
                            : etoroState.connection.isConnected &&
                                !etoroState.connection.needsReconnect,
                    onTap: () => _open(EtoroRouter.connectionRouteName),
                  ),
                  Divider(
                    height: 1,
                    indent: 64,
                    endIndent: AppDimens.sp16,
                    color: colors.border,
                  ),
                  BrokerChoiceRow(
                    leading: const BinanceAppIcon(),
                    title: 'Binance',
                    subtitle: binance ?? 'connect_broker_binance_body'.tr(),
                    status:
                        binance == null
                            ? null
                            : binanceState.connection.status ==
                                BinanceStatus.connected,
                    onTap: () => _open(BinanceRouter.routeName),
                  ),
                  Divider(
                    height: 1,
                    indent: 64,
                    endIndent: AppDimens.sp16,
                    color: colors.border,
                  ),
                  BrokerChoiceRow(
                    leading: const SnaptradeAppIcon(),
                    title: 'connect_broker_others_title'.tr(),
                    subtitle: others ?? 'connect_broker_others_body'.tr(),
                    status:
                        others == null
                            ? null
                            : !othersState.connection.imported.any(
                                  (b) => b.disabled,
                                ) &&
                                othersState.connection.status ==
                                    SnaptradeStatus.connected,
                    onTap: () => _open(SnaptradeRouter.routeName),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppDimens.sp16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.lock_outline_rounded,
                    size: 14,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(width: AppDimens.sp6),
                Expanded(
                  child: Text(
                    'connect_broker_read_only'.tr(),
                    style: tt.bodySmall?.copyWith(
                      color: colors.textSecondary,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.sp20),
            // Si su bróker no está (o prefiere no conectarlo): un extracto.
            TextButton.icon(
              onPressed: () => _open(StatementImportRouter.routeName),
              icon: const Icon(Icons.upload_file_rounded, size: 18),
              label: Text('connect_broker_file_cta'.tr()),
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                foregroundColor: colors.textPrimary,
                minimumSize: const Size(
                  AppDimens.touchTarget,
                  AppDimens.touchTarget,
                ),
                textStyle: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Un bróker en la lista: su ícono, el nombre y una línea (qué trae, o su
/// estado si ya está conectado), y la flecha.
class BrokerChoiceRow extends StatelessWidget {
  const BrokerChoiceRow({
    super.key,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.onTap,
  });

  final Widget leading;
  final String title;
  final String subtitle;

  /// null: no está conectado (la línea dice qué trae). true: conectado (la
  /// línea es su estado, con el punto verde). false: hay que reconectar
  /// (punto rojo).
  final bool? status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: '$title. $subtitle',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.sp16,
              vertical: AppDimens.sp12,
            ),
            child: Row(
              children: [
                leading,
                const SizedBox(width: AppDimens.sp12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: tt.titleSmall?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (status != null) ...[
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: status! ? colors.profit : colors.loss,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: AppDimens.sp6),
                          ],
                          Expanded(
                            child: Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: tt.bodySmall?.copyWith(
                                color: colors.textSecondary,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppDimens.sp8),
                Icon(Icons.chevron_right_rounded, color: colors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
