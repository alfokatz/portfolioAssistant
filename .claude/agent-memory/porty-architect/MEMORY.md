# Memoria de porty-architect

- Interruptores de producto: fila en `app_config` con formato `PortyRolloutFlag` (`{"percent","users"}`); en la app se leen desde `lib/features/subscription/config/conversion_flags.dart` (flutter-dev) importando `PortyRolloutFlag` de assistant/data sin editarlo.
- Eventos de producto: siempre `product_events` vía `ProductEvents.log` (enum `ProductEvent`); nunca tablas de eventos nuevas. Tests con fake que extiende `ProductEvents` (ver `first_portfolio_watcher_test.dart`).
- Todo paywall pasa `source` obligatorio (`PaywallSource` en `lib/features/subscription/config/paywall_source.dart`); cada paywall nuevo suma su constante.
- Cambiar la firma de algo que usa el chat: fases A (agregar opcional) → assistant-dev migra → C (volver obligatorio), para no romper la compilación entre dueños.
- El tier lo calcula el webhook de RevenueCat por entitlements: productos nuevos (anuales, promos) no requieren tocar `planFrom`.
- Datos de RevenueCat: `subscription_events` (solo service role, sin evento crudo por PII en `subscriber_attributes`).
- Traducciones son solo de flutter-dev: si assistant-dev necesita textos, la spec lista las claves y flutter-dev las agrega primero.
- Avisos de la app en el chat (cuota, límites) van fuera del catálogo, estilo `AssistantQuietNotice`: no tocan prompt ni allowlist.
- Límites por plan nuevos van como campo de `PlanSpec` (capacidad), nunca `if (tier == ...)`.
