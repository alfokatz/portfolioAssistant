import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Lee [provider] del `ProviderScope` ancestro sin registrar dependencia y
/// sin crashear si no hay uno — pensado para widgets del catálogo GenUI,
/// que son funciones estáticas sin `ref` y a veces se testean en
/// aislamiento. Devuelve `null` si no hay scope.
T? readProviderOrNull<T>(BuildContext context, ProviderListenable<T> provider) {
  final element =
      context.getElementForInheritedWidgetOfExactType<
        UncontrolledProviderScope
      >();
  final scope = element?.widget as UncontrolledProviderScope?;
  return scope?.container.read(provider);
}
