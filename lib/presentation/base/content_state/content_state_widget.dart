import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/presentation/base/content_state/content_state_provider.dart';
import 'package:portfolio_assistant/presentation/base/loading/Loading.dart';

class ContentStateWidget extends HookConsumerWidget {
  final Widget child;
  bool showAppBarWithLoadingState = false;
  PreferredSizeWidget? appBar;
  Widget? customLoading;

  ContentStateWidget({
    required this.child,
    this.customLoading,
    this.appBar,
    this.showAppBarWithLoadingState = false,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(contentStateNotifierProvider);
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar:
          _canShowContent(state: state) || showAppBarWithLoadingState
              ? appBar
              : null,
      body: SafeArea(
        child: Container(
          color: Theme.of(context).colorScheme.surface,
          width: size.width,
          height: size.height,
          child: Stack(
            children: [
              if (state == ContentState.loading)
                customLoading ?? const Loading(),
              if (_canShowContent(state: state))
                FadeIn(
                  duration: const Duration(milliseconds: 350),
                  delay: const Duration(milliseconds: 150),
                  child: child,
                ),
              if (state == ContentState.loadingOverlay)
                SizedBox(width: size.width, height: size.height),
            ],
          ),
        ),
      ),
    );
  }

  bool _canShowContent({required ContentState state}) {
    return state == ContentState.showContent ||
        state == ContentState.loadingOverlay;
  }
}
