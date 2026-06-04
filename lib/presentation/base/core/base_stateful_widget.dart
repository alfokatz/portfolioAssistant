import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/presentation/base/core/base_screen.dart';

abstract class BaseStatefulWidget<T extends ConsumerStatefulWidget>
    extends ConsumerState<T> with BaseScreen {
  Widget buildView(BuildContext context);

  @override
  Widget build(BuildContext context) {
    subscribeAlert(ref: ref);
    subscribeNavigation(
      ref: ref,
      context: context,
    );
    return buildView(context);
  }
}
