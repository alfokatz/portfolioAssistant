import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:portfolio_assistant/presentation/base/navigation/navigation_event.dart';

class NavigationNotifier extends StateNotifier<NavigationEvent?> {
  NavigationNotifier() : super(null);

  void navigate(NavigationEvent event) {
    state = event;
    _clear();
  }

  void _clear() {
    Future.delayed(
      Duration(microseconds: 250),
      () {
        state = null;
      },
    );
  }
}

final navigationProvider =
    StateNotifierProvider.autoDispose<NavigationNotifier, NavigationEvent?>(
  (ref) => NavigationNotifier(),
);
