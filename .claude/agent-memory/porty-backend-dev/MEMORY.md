# Memoria de porty-backend-dev

- Entorno sin Deno ni Supabase CLI ni daemon de Docker: Deno sale rápido con `npm install --prefix <scratchpad>/deno deno`; los tests de funciones que usan `helpers.ts` necesitan `supabase start` (sin stack, correr solo los puros con `--filter`, poniendo `SERVICE_ROLE_KEY=dummy ANON_KEY=dummy` porque `helpers.ts` crea el cliente al importar).
- `initdb`/`pg_ctl` no corren como root y los padres del scratchpad son 700: para validar SQL usar PGlite (`npm install @electric-sql/pglite` en el scratchpad, import por ruta absoluta a `dist/index.js`) con un stub de `auth.users`, `auth.uid()` y roles anon/authenticated/service_role.
- `create or replace view` solo deja agregar columnas al final: copiar la definición vigente entera (buscar la última migración que la toca) y sumar abajo.
- Los default privileges de Supabase le dan todo a `service_role` en tablas nuevas de `public`: `grant select, insert` suma, no restringe.
- Tablas con FK a `auth.users` que escribe un webhook: un usuario borrado hace fallar el insert (23503) y el proveedor reintenta para siempre; reintentar con `user_id: null`.
- `deno lint` marca `no-import-prefix` en todos los tests (`jsr:`/`npm:` inline): es el estilo del repo, no corregir.
- Webhooks con usuario borrado: además del insert propio, `upsert_subscription_from_provider` también falla con 23503 (FK de `user_subscriptions`); registrar `user_deleted` y responder 2xx.
- Antes de crear una migración no pedida, buscar en `docs/superpowers/specs/` si el timestamp ya está reservado para otra spec, y confirmar con el coordinador si la original ya se subió: si no se subió, se edita esa y no se agrega una de corrección.
