import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/binance/view/widgets/binance_auto_sync.dart';
import 'package:portfolio_assistant/features/snaptrade/view/widgets/snaptrade_auto_sync.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/subscription/subscription_policy.dart';
import 'package:portfolio_assistant/features/etoro/view/widgets/etoro_auto_sync.dart';
import 'package:portfolio_assistant/features/notifications/view/push_open_listener.dart';
import 'package:portfolio_assistant/features/portfolio_diagnosis/view/first_portfolio_watcher.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_paywall_sheet.dart';
import 'package:portfolio_assistant/presentation/base/core/base_screen.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/app_bottom_nav_bar.dart';

/// Shell around the three tabbed sections (Home, Assistant, Settings).
///
/// Each branch keeps its own [Navigator] alive inside the swipeable
/// [ShellBranchPager] that app_router.dart gives the `StatefulShellRoute` —
/// switching tabs moves pages, it doesn't rebuild them, so a screen's scroll position,
/// local state and cached provider data all survive a tab switch instead
/// of being torn down and rebuilt (which is what made "Inicio" feel like a
/// reload every time you tapped back to it).
///
/// Because all three tabs stay mounted at once, this is also the single
/// place that subscribes to [alertProvider]/[navigationProvider] for the
/// three of them: Home, Assistant and Settings each opt out of their own
/// `BaseStatefulWidget` subscription (`subscribesToGlobalEvents = false`).
/// If each one *also* subscribed, one event (e.g. opening a position's
/// detail) would fire once per mounted tab and push the same screen
/// 2-3 times.
class AppShell extends ConsumerWidget with BaseScreen {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _onAddPosition(BuildContext context, WidgetRef ref) {
    final tier = ref.read(subscriptionProvider).tier;
    final limit = SubscriptionPolicy.positionLimit(tier);
    final count = ref.read(homeProvider).summary?.valuations.length ?? 0;
    if (limit != null && count >= limit) {
      SubscriptionPaywallSheet.show(
        context,
        ref,
        reason: PaywallReason.modeLocked,
      );
      return;
    }
    ref.read(homeProvider.notifier).openAddPosition();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    subscribeAlert(ref: ref, context: context);
    subscribeNavigation(ref: ref, context: context);
    final colors = context.customColors;
    final current = AppNavDestination.values[navigationShell.currentIndex];
    final isHome = current == AppNavDestination.home;

    return Scaffold(
      extendBody: true,
      floatingActionButton:
          isHome
              ? Material(
                color: colors.accentWarm,
                borderRadius: BorderRadius.circular(28),
                elevation: 0,
                child: InkWell(
                  onTap: () => _onAddPosition(context, ref),
                  borderRadius: BorderRadius.circular(28),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: Icon(Icons.add, color: colors.onAccent, size: 26),
                  ),
                ),
              )
              : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: AppBottomNavBar(
        current: current,
        onSelect: (destination) {
          final index = AppNavDestination.values.indexOf(destination);
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
      ),
      // Las pestañas se pasan deslizando (ShellBranchPager, armado en
      // app_router.dart). Al abrir la app y al volver a ella, eToro, Binance
      // y los brókers de SnapTrade se ponen al día solos. Tocar una
      // notificación abre su pantalla
      // (también desde cerrada).
      // La primera vez que la cartera tiene posiciones, Porty muestra lo
      // que vio en ella (el diagnóstico).
      body: PushOpenListener(
        child: FirstPortfolioWatcher(
          isHome: isHome,
          child: EtoroAutoSync(
            child: BinanceAutoSync(
              child: SnaptradeAutoSync(child: navigationShell),
            ),
          ),
        ),
      ),
    );
  }
}

