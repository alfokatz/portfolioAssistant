import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_client_provider.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Los pasos del camino al "aha" (ver
/// docs/superpowers/plans/2026-10-26-aha-moment.md y la vista
/// `product_funnel`).
enum ProductEvent {
  onboardingStarted('onboarding_started', once: true),
  onboardingFinished('onboarding_finished', once: true),

  /// Primera vez que la cartera tiene posiciones. Props: `method`, `count`.
  portfolioLoaded('portfolio_loaded', once: true),

  /// Vio el primer diagnóstico. Props: `findings` (los tipos mostrados).
  diagnosisSeen('diagnosis_seen', once: true),

  /// Tocó la pregunta del diagnóstico. Props: `kind`.
  diagnosisQuestion('diagnosis_question'),
  firstChatAnswer('first_chat_answer', once: true);

  const ProductEvent(this.wire, {this.once = false});

  final String wire;

  /// Se registra una sola vez por teléfono (lo que mide es "la primera").
  final bool once;
}

/// Cómo llegó la cartera (prop `method` de [ProductEvent.portfolioLoaded]).
abstract final class PortfolioLoadMethod {
  static const manual = 'manual';
  static const file = 'file';
  static const screenshot = 'screenshot';
  static const etoro = 'etoro';
  static const binance = 'binance';
  static const chat = 'chat';
}

/// Registra eventos de producto en `product_events`. Nunca rompe ni demora
/// un flujo: sin sesión, sin red o con cualquier error, no pasa nada.
class ProductEvents {
  ProductEvents({
    required SupabaseClient? Function() client,
    required SharedPreferences? Function() prefs,
  }) : _client = client,
       _prefs = prefs;

  final SupabaseClient? Function() _client;
  final SharedPreferences? Function() _prefs;

  static const _onceKey = 'product_events_once';
  final _sentThisRun = <String>{};

  void log(ProductEvent event, [Map<String, Object?> props = const {}]) {
    unawaited(_log(event, props));
  }

  Future<void> _log(ProductEvent event, Map<String, Object?> props) async {
    try {
      final client = _client();
      final user = client?.auth.currentUser;
      if (client == null || user == null) return;
      // Por usuario: otro login en el mismo teléfono es otro embudo.
      final onceId = '${user.id}:${event.wire}';
      final prefs = _prefs();
      if (event.once) {
        final sent = prefs?.getStringList(_onceKey) ?? const [];
        if (_sentThisRun.contains(onceId) || sent.contains(onceId)) return;
        _sentThisRun.add(onceId);
      }
      await client.from('product_events').insert({
        'name': event.wire,
        'props': props,
      });
      if (event.once && prefs != null) {
        final sent = prefs.getStringList(_onceKey) ?? const [];
        await prefs.setStringList(_onceKey, [...sent, onceId]);
      }
    } catch (_) {
      // Medir nunca le cuesta nada al usuario.
    }
  }
}

final productEventsProvider = Provider<ProductEvents>(
  (ref) => ProductEvents(
    // Sin Supabase o sin preferencias (tests de otras pantallas): no mide.
    client: () {
      try {
        return ref.read(supabaseClientProvider);
      } catch (_) {
        return null;
      }
    },
    prefs: () {
      try {
        return ref.read(sharedPreferencesProvider);
      } catch (_) {
        return null;
      }
    },
  ),
);

/// Por dónde llegó la cartera en este momento (lo anota cada flujo de carga
/// al terminar). Lo lee la Home cuando la cartera pasa de vacía a tener
/// posiciones: es el `method` de [ProductEvent.portfolioLoaded].
final portfolioLoadMethodProvider = StateProvider<String?>((ref) => null);
