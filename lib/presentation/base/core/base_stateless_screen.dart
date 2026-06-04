import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/presentation/base/core/base_screen.dart';

abstract class BaseStatelessScreen extends HookConsumerWidget with BaseScreen {
  BaseStatelessScreen({
    super.key,
  });

  Widget buildView(BuildContext context, WidgetRef ref);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    subscribeAlert(ref: ref);
    subscribeNavigation(
      ref: ref,
      context: context,
    );
    return buildView(context, ref);
  }
}
