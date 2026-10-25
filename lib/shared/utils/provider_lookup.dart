import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Lee [provider] del `ProviderScope` ancestro sin registrar dependencia y
/// sin crashear si no hay uno — pensado para widgets del catálogo GenUI,
/// que son funciones estáticas sin `ref` y a veces se testean en
/// aislamiento. Devuelve `null` si no hay scope.
///
/// También devuelve `null` si construir el provider falla (p. ej. un cliente
/// HTTP que lee `dotenv` antes de que esté cargado): todo lo que se busca
/// por acá es opcional — logos, sparklines, haptics — y una falla de eso no
/// puede tumbar la card entera.
T? readProviderOrNull<T>(BuildContext context, ProviderListenable<T> provider) {
  final element =
      context.getElementForInheritedWidgetOfExactType<
        UncontrolledProviderScope
      >();
  final scope = element?.widget as UncontrolledProviderScope?;
  if (scope == null) return null;
  try {
    return scope.container.read(provider);
  } catch (error) {
    debugPrint('[readProviderOrNull] ${provider.runtimeType}: $error');
    return null;
  }
}
