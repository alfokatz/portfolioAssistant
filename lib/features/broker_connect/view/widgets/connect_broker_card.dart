import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/binance/providers/binance_provider.dart';
import 'package:portfolio_assistant/features/binance/view/widgets/binance_brand.dart';
import 'package:portfolio_assistant/features/broker_connect/nav/connect_broker_router.dart';
import 'package:portfolio_assistant/features/broker_connect/view/broker_status_labels.dart';
import 'package:portfolio_assistant/features/etoro/providers/etoro_connection_provider.dart';
import 'package:portfolio_assistant/features/etoro/view/widgets/etoro_brand.dart';
import 'package:portfolio_assistant/features/snaptrade/providers/snaptrade_provider.dart';
import 'package:portfolio_assistant/features/snaptrade/view/widgets/snaptrade_brand.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';

void _openConnectBroker(BuildContext context) {
  PortyHapticsService.maybeOf(context)?.selectionTap();
  context.pushNamed(ConnectBrokerRouter.routeName);
}

/// La entrada destacada de Ajustes (arriba de todo, después del perfil):
/// sin nada conectado invita a conectar; con algo conectado, dice qué y
/// lleva a la misma pantalla para ver o sumar otro.
class ConnectBrokerCard extends ConsumerWidget {
  const ConnectBrokerCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final names = BrokerStatusLabels.connectedNames(
      etoro: ref.watch(etoroConnectionProvider),
      binance: ref.watch(binanceProvider),
      snaptrade: ref.watch(snaptradeProvider),
    );
    final connected = names.isNotEmpty;

    return Semantics(
      container: true,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surfaceCard,
          borderRadius: BorderRadius.circular(AppDimens.radiusXl),
          border: Border.all(color: colors.border),
        ),
        padding: const EdgeInsets.all(AppDimens.cardPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ExcludeSemantics(child: _BrokerIcons()),
            const SizedBox(height: AppDimens.sp16),
            Text(
              (connected
                      ? 'connect_broker_card_connected_title'
                      : 'connect_broker_card_title')
                  .tr(),
              style: tt.titleMedium?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppDimens.sp4),
            Text(
              connected ? names.join(' · ') : 'connect_broker_card_body'.tr(),
              style: tt.bodyMedium?.copyWith(
                color: colors.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: AppDimens.sp16),
            if (connected)
              SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: () => _openConnectBroker(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.textPrimary,
                    side: BorderSide(color: colors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppDimens.radiusLg),
                    ),
                    textStyle: tt.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text('connect_broker_card_manage'.tr()),
                ),
              )
            else
              PositionPrimaryButton(
                label: 'connect_broker_cta'.tr(),
                onPressed: () => _openConnectBroker(context),
              ),
          ],
        ),
      ),
    );
  }
}

/// eToro, Binance y "tu bróker", en fila: se entiende de un vistazo qué se
/// puede conectar.
class _BrokerIcons extends StatelessWidget {
  const _BrokerIcons();

  @override
  Widget build(BuildContext context) => const Row(
    children: [
      EtoroAppIcon(size: 32),
      SizedBox(width: AppDimens.sp6),
      BinanceAppIcon(size: 32),
      SizedBox(width: AppDimens.sp6),
      SnaptradeAppIcon(size: 32),
    ],
  );
}

/// "Conectar tu bróker" como alternativa a cargar a mano (Home vacía).
/// Secundario: borde, sin relleno; lo principal sigue siendo agregar una
/// posición.
class ConnectBrokerButton extends StatelessWidget {
  const ConnectBrokerButton({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: () => _openConnectBroker(context),
        icon: const Icon(Icons.link_rounded, size: AppDimens.iconMd),
        label: Text('connect_broker_cta'.tr()),
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.textPrimary,
          side: BorderSide(color: colors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          ),
          textStyle: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
