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
- Limpieza al borrar un usuario: trigger `before delete on auth.users` (`_account_purge_before_delete`); toda tabla nueva con datos del usuario lleva FK `on delete cascade` y, si guarda algo fuera de FK (Vault, text user_id, arrays en app_config), se suma al trigger; la guardia de catálogo de `account_deletion_db_test.sql` falla si no.
- `positions`/`closed_positions` son pre-CLI: su esquema en prod no es el de las migraciones; cualquier supuesto sobre FKs o constraints ahí necesita auditoría de solo lectura en prod.
- RevenueCat `GET /v1/subscribers/{id}` crea el cliente si no existe: nunca llamarlo para un uid que puede estar borrado.
- Vault: borrar la fila puntero no borra el secreto; siempre `*_delete` o el trigger de borrado de cuenta.
- Features que necesitan datos de RevenueCat sin tocar `lib/features/subscription/` leen `Purchases` desde su propia carpeta con costura inyectable y usan `revenueCatServiceProvider` solo para leer.
- Inventarios de tablas: buscar también `drop table` en migraciones posteriores; el test de catálogo manda sobre la lista de la spec.
