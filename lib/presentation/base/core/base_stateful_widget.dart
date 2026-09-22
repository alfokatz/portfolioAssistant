import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/presentation/base/core/base_screen.dart';

abstract class BaseStatefulWidget<T extends ConsumerStatefulWidget>
    extends ConsumerState<T>
    with BaseScreen {
  Widget buildView(BuildContext context);

  /// Screens that live as tabs inside a `StatefulShellRoute.indexedStack`
  /// (Home, Assistant, Settings) are *all* mounted at once, so if each one
  /// also subscribed here, a single [alertProvider]/[navigationProvider]
  /// event would fire once per mounted tab — e.g. tapping a position would
  /// push its detail screen 2-3 times, one per listening tab, which is
  /// exactly the bug this guards against. Those screens override this to
  /// `false` and rely on the single subscription in `AppShell` instead.
  bool get subscribesToGlobalEvents => true;

  @override
  Widget build(BuildContext context) {
    if (subscribesToGlobalEvents) {
      subscribeAlert(ref: ref, context: context);
      subscribeNavigation(ref: ref, context: context);
    }
    return buildView(context);
  }
}
