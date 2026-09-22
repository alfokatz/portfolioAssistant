import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/subscription/subscription_policy.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_paywall_sheet.dart';
import 'package:portfolio_assistant/presentation/base/core/base_screen.dart';
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
      body: _DropInTabContent(
        tabIndex: navigationShell.currentIndex,
        child: navigationShell,
      ),
    );
  }
}

/// Plays a short "drop in, settle with a little bounce" entrance whenever
/// [tabIndex] changes — the IndexedStack under the shell swaps which
/// branch is visible instantly (that's the point: no rebuild, no reload),
/// so this purely cosmetic wrapper is what gives the switch some life.
/// It never re-keys or rebuilds [child]: only its transform/opacity move,
/// so every branch's own navigator, scroll position and provider state
/// stay exactly as they were.
class _DropInTabContent extends StatefulWidget {
  const _DropInTabContent({required this.tabIndex, required this.child});

  final int tabIndex;
  final Widget child;

  @override
  State<_DropInTabContent> createState() => _DropInTabContentState();
}

class _DropInTabContentState extends State<_DropInTabContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _drop;
  late final Animation<double> _fade;
  bool _started = false;

  static const _dropDistance = 32.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _drop = Tween<double>(
      begin: -_dropDistance,
      end: 0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `MediaQuery.disableAnimationsOf` needs an inherited widget, which
    // isn't safely readable from `initState` — this is the earliest safe
    // spot, gated so the first play only fires once.
    if (_started) return;
    _started = true;
    _play();
  }

  @override
  void didUpdateWidget(covariant _DropInTabContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabIndex != widget.tabIndex) _play();
  }

  void _play() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder:
          (context, child) => Opacity(
            opacity: _fade.value.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, _drop.value),
              child: child,
            ),
          ),
    );
  }
}
