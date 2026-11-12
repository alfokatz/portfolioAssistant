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
  firstChatAnswer('first_chat_answer', once: true),

  /// Se abrió el paywall. Props: `reason`, `source`, `tier`,
  /// `visible_tiers`, `queries_used`, `queries_limit`.
  paywallViewed('paywall_viewed'),

  /// Tocó el botón de un plan, antes de comprar. Props: `tier`, `period`,
  /// `source`.
  paywallPlanTapped('paywall_plan_tapped'),

  /// Volvió de comprar o de restaurar. Props: `action` (`purchase` |
  /// `restore`), `tier` y `period` (solo en compras), `source`, `result`
  /// (`success` | `cancelled` | `failed` | `not_configured`) y
  /// `error_code` (solo en `failed`).
  purchaseResult('purchase_result'),

  /// La hoja se cerró sin compra ni restauración exitosa. Props: `source`,
  /// `seconds_open`, `tapped_plan`.
  paywallDismissed('paywall_dismissed'),

  /// Tocó la salida alternativa de una pantalla bloqueada. Props: `surface`
  /// (`broker_locked_binance` | `broker_locked_snaptrade`), `action`.
  nudgeTapped('nudge_tapped'),

  /// Terminó un intento de conectar un bróker. Props: `broker` (`etoro` |
  /// `binance` | `snaptrade`), `result` (`ok` | `plan_required` | `limit` |
  /// `cancelled` | `error`).
  brokerConnectResult('broker_connect_result'),

  /// Se cerró el pedido de permiso de notificaciones (si se mostró). Props:
  /// `source` (`PushPromptReason.name`), `result` (`granted` | `denied` |
  /// `dismissed`).
  pushOptIn('push_opt_in'),

  /// Un turno del chat se respondió con una consulta de mercado gratis.
  /// Props: `remaining`.
  marketTasteUsed('market_taste_used'),

  /// Se mostró el aviso de Premium tras agotar las consultas de mercado.
  marketTeaserShown('market_teaser_shown'),

  /// Se abrió la app. Props: `source` (`icon` | `widget` | `widget_question`
  /// | `push` | `other`).
  appOpened('app_opened'),

  /// Tocó el widget de la pantalla de inicio. Props: `platform`, `size`,
  /// `target` (`chat` | `question` | `home` | `news` | `earnings` | ...),
  /// `question_id` (el `wire` de la plantilla), `question_source`
  /// (`novelty` | `goal` | `plan` | `biggest` | `profile`), `item_kind`,
  /// `item_prio`, `data_age_min`, `positions_hidden`. Nunca ticker, texto
  /// de la pregunta ni id de ítem.
  widgetOpened('widget_opened'),

  /// Cambió qué widgets hay instalados. Props: `platform`, `sizes` (lista;
  /// vacía = lo sacó).
  widgetPresence('widget_presence'),

  /// Ya no se usa (el ajuste ahora es "Ocultar posiciones"): queda en el
  /// enum por compatibilidad.
  widgetAmountsToggled('widget_amounts_toggled'),

  /// Activó o desactivó "Ocultar posiciones en el widget". Props: `hidden`.
  widgetPositionsToggled('widget_positions_toggled'),

  /// El usuario avanzó la novedad del widget mediano (sin abrir la app; se
  /// registra al abrir). Props: `platform`, `size` (`medium`), `taps` (la
  /// diferencia desde lo último registrado).
  widgetFeedAdvanced('widget_feed_advanced'),

  /// Terminó el turno de una pregunta que vino del widget. Props:
  /// `question_id`, `result` (`answered` | `quota` | `paywall` | `failed`).
  widgetQuestionResult('widget_question_result'),

  /// Aproximación de impresiones de las novedades del widget (lo que dibujó
  /// el nativo, leído al abrir). Props: `size`, `news_count`,
  /// `earnings_count`, `teaser` (`none` | `news` | `earnings`), `tier`,
  /// `positions_hidden`, `platform`, y de la v2: `line_kind` (chico),
  /// `shown_kind`, `shown_prio` (mediano), `insight_count`, `mover_count`,
  /// `biggest_count`, `live_count`. Nunca ticker, titular ni id de ítem.
  widgetItemsRendered('widget_items_rendered'),

  /// Acción en la hoja de novedades del widget. Props: `action`
  /// (`read_source` | `ask_porty` | `open_paywall`), `type` (`news` |
  /// `earnings`), `from_widget`. Nunca ticker ni titular.
  widgetItemAction('widget_item_action'),

  /// Se mostró la hoja "Tené a Porty en tu pantalla de inicio". Props:
  /// `source` (`auto` | `settings`).
  widgetPromptShown('widget_prompt_shown'),

  /// Tocó "Agregar" en esa hoja. Props: `platform`, `method` (`pin`: pide
  /// al sistema que lo agregue | `steps`: se le mostraron los pasos).
  widgetPromptAddTapped('widget_prompt_add_tapped'),

  /// Cerró la hoja con "Ahora no" o deslizándola, sin tocar "Agregar".
  /// Props: `source`.
  widgetPromptDismissed('widget_prompt_dismissed'),

  /// Cuánto tardó cada tramo de un turno del chat (ver `TurnTiming` y
  /// docs/superpowers/research/2026-10-15-porty-latencia.md, §4). Props:
  /// `result`, `stream`, `total_ms`, `pre_ms`, `throttle_ms`,
  /// `first_text_ms`, `ready_ms`, `rounds` (`kind`, `start_ms`, `ms`,
  /// `server`: tramos del proxy), `tools` (`name`, `ms`, `status`),
  /// `extra_round`, `retries`, `final_chars`, `region`. Nunca texto,
  /// tickers ni argumentos.
  chatTurnTiming('chat_turn_timing');

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
  static const snaptrade = 'snaptrade';
  static const chat = 'chat';

  /// Escribió lo que tiene y Porty lo leyó.
  static const note = 'note';
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
