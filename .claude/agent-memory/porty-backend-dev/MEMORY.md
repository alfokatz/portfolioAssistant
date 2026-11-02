# Memoria de porty-backend-dev

- Entorno sin Deno ni Supabase CLI ni daemon de Docker: Deno sale rápido con `npm install --prefix <scratchpad>/deno deno`; los tests de funciones que usan `helpers.ts` necesitan `supabase start` (sin stack, correr solo los puros con `--filter`, poniendo `SERVICE_ROLE_KEY=dummy ANON_KEY=dummy` porque `helpers.ts` crea el cliente al importar).
- `initdb`/`pg_ctl` no corren como root y los padres del scratchpad son 700: para validar SQL usar PGlite (`npm install @electric-sql/pglite` en el scratchpad, import por ruta absoluta a `dist/index.js`) con un stub de `auth.users`, `auth.uid()` y roles anon/authenticated/service_role.
- `create or replace view` solo deja agregar columnas al final: copiar la definición vigente entera (buscar la última migración que la toca) y sumar abajo.
- Los default privileges de Supabase le dan todo a `service_role` en tablas nuevas de `public`: `grant select, insert` suma, no restringe.
- Tablas con FK a `auth.users` que escribe un webhook: un usuario borrado hace fallar el insert (23503) y el proveedor reintenta para siempre; reintentar con `user_id: null`.
- `deno lint` marca `no-import-prefix` en todos los tests (`jsr:`/`npm:` inline): es el estilo del repo, no corregir.
