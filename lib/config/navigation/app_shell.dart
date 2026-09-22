import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/subscription/subscription_policy.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_paywall_sheet.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/app_bottom_nav_bar.dart';

/// Shell around the three tabbed sections (Home, Assistant, Settings).
///
/// Each branch keeps its own [Navigator] alive inside the
/// `StatefulShellRoute.indexedStack` in app_router.dart — switching tabs
/// swaps *visibility*, not the widget tree, so a screen's scroll position,
/// local state and cached provider data all survive a tab switch instead
/// of being torn down and rebuilt (which is what made "Inicio" feel like a
/// reload every time you tapped back to it).
class AppShell extends ConsumerWidget {
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
                  child: const SizedBox(
                    width: 56,
                    height: 56,
                    child: Icon(Icons.add, color: Colors.white, size: 26),
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
      body: navigationShell,
    );
  }
}
