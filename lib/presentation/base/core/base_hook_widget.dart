import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

abstract class BaseHookWidget extends HookConsumerWidget {
  BaseHookWidget({
    super.key,
  });

  Widget buildView(BuildContext context, WidgetRef ref);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return buildView(context, ref);
  }
}
