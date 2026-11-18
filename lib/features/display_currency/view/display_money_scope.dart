import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/display_currency/domain/display_money.dart';
import 'package:portfolio_assistant/features/display_currency/providers/display_currency_provider.dart';

/// En qué moneda se muestran los montos de *tu plata* (valor de la cartera,
/// de cada posición, ganancia), para cualquier widget de la app sin pasarla
/// a mano: `DisplayMoneyScope.of(context).money(usd)`. Los precios del
/// mercado (a cuánto está una acción, precio de compra, alertas) siguen en
/// dólares, que es como se cotizan.
///
/// Sin scope arriba (tests de un widget suelto), dólares.
class DisplayMoneyScope extends InheritedWidget {
  const DisplayMoneyScope({
    super.key,
    required this.money,
    required super.child,
  });

  final DisplayMoney money;

  static DisplayMoney of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DisplayMoneyScope>()?.money ??
      DisplayMoney.usd;

  @override
  bool updateShouldNotify(DisplayMoneyScope old) => old.money != money;
}

/// Pone el [DisplayMoneyScope] con la moneda elegida y el tipo de cambio de
/// hoy (ver `displayMoneyProvider`). Va una vez, en el `builder` de la app.
class DisplayMoneyHost extends ConsumerWidget {
  const DisplayMoneyHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      DisplayMoneyScope(money: ref.watch(displayMoneyProvider), child: child);
}
