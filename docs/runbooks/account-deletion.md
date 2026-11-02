# Borrado de cuenta

Spec: `docs/superpowers/specs/2026-11-02-borrado-de-cuenta.md`. Piezas:

- `supabase/migrations/20261102130000_account_deletion.sql`: trigger `account_purge_before_delete` sobre `auth.users` (Vault, `subscription_sync_log`, flags de `app_config`, `waitlist` con mail verificable), contador `account_deletions_daily` y cascade asegurado en `positions` / `closed_positions`.
- Edge function `delete-account`: SnapTrade → RevenueCat → eToro → Binance → `auth.admin.deleteUser`. Idempotente.
- `revenuecat-webhook`: no llama a `GET /subscribers/{id}` para un uid que ya no existe (lo recrearía en RevenueCat).

## Antes del `db push` (lo corre el usuario, solo lectura)

En el SQL editor de producción. Las tablas `positions` / `closed_positions` son anteriores a la CLI y su FK es desconocida (R1 de la spec).

```sql
-- 1. Toda FK hacia auth.users con su acción al borrar (c = cascade, n = set null,
--    a = no action, r = restrict). Esperado: todas en 'c'.
select conrelid::regclass as tabla, conname, confdeltype, convalidated
from pg_constraint
where contype = 'f' and confrelid = 'auth.users'::regclass
order by 1;

-- 2. Tablas de public con user_id sin FK a auth.users. Esperado: solo
--    subscription_sync_log (la limpia el trigger).
select c.table_name, c.data_type
from information_schema.columns c
join information_schema.tables t
  on t.table_schema = c.table_schema and t.table_name = c.table_name and t.table_type = 'BASE TABLE'
where c.table_schema = 'public' and c.column_name = 'user_id'
  and not exists (
    select 1 from pg_constraint k
    where k.contype = 'f' and k.confrelid = 'auth.users'::regclass
      and k.conrelid = format('public.%I', c.table_name)::regclass
  )
order by 1;

-- 3. Tipo de positions.user_id / closed_positions.user_id. Tiene que ser uuid:
--    si no, la migración corta con un mensaje (no lo arregla sola).
select table_name, data_type from information_schema.columns
where table_schema = 'public' and table_name in ('positions', 'closed_positions') and column_name = 'user_id';
```

Si la consulta 2 muestra otra tabla aparte de `subscription_sync_log`, o la 1 una FK que no está en `c` (salvo `positions` / `closed_positions`, que la migración arregla), no hagas el push: avisale a porty-backend-dev.

## Secretos

No hace falta ninguno nuevo; la función usa los del proyecto (`supabase secrets list`):

| Secreto | Para | Nota |
|---|---|---|
| `REVENUECAT_SECRET_API_KEY` | DELETE del cliente | Clave secreta **v1** `sk_…` con permiso de borrar. Sin ella la función responde 500 `misconfigured` sin tocar nada |
| `SNAPTRADE_CLIENT_ID`, `SNAPTRADE_CONSUMER_KEY` | Borrar el usuario de SnapTrade | Solo se exigen si el usuario tiene SnapTrade |
| `ETORO_CLIENT_ID`, `ETORO_CLIENT_SECRET` | Revocar tokens | Sin ellos no se revoca (best effort), pero se desconecta igual |
| `SNAPTRADE_API_URL`, `ETORO_ENVIRONMENT` | Opcionales | |

## Deploy (con OK del usuario)

1. Consulta de auditoría de arriba.
2. `supabase db push` (aplica `20261102130000_account_deletion.sql`).
3. `supabase functions deploy delete-account` y `supabase functions deploy revenuecat-webhook`, **juntos**: sin el webhook nuevo, un evento de RevenueCat de un usuario borrado recrea su cliente.
4. Humo en staging (qa-engineer, criterios 5 y 6 de la spec).

`delete-account` importa `snaptrade-sync/snaptrade.ts`, `etoro-sync/etoro.ts` y `revenuecat-webhook/handler.ts`: si cambia alguno, redesplegar también `delete-account`.

## Tests

```bash
# SQL: "no queda nada" + guardia de catálogo (una tabla nueva con user_id sin decidir lo rompe).
psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/account_deletion_db_test.sql   # → ACCOUNT_DELETION_DB_TEST_OK

# Edge functions (stack local: supabase start)
cd supabase/functions
deno test --allow-net --allow-env --allow-read tests/delete_account_test.ts tests/revenuecat_webhook_test.ts
# Sin stack, solo los que usan base falsa:
SERVICE_ROLE_KEY=x ANON_KEY=x deno test --allow-net --allow-env --allow-read --filter "[sin base]" tests/delete_account_test.ts
```

Si agregás una tabla con `user_id`, sumala al inventario de `account_deletion_db_test.sql` (`cascade` o `trigger`) y dale `on delete cascade`.

## Operación

- **Logs:** `{fn: "delete-account", op: "delete", step, outcome}`, sin uid ni tokens. `outcome: "deleted"` es el final feliz; `already_deleted`, un reintento después de un borrado que terminó.
- **Contador:** `select * from account_deletions_daily order by day desc;` (por día UTC y plan, sin user_id).
- **Falla a mitad:** la app muestra el error "parcial" (`nothingDeleted: false`). El usuario puede reintentar: cada paso hecho es un no-op. Los brókers quedan desconectados con la cartera como manual.
- **Borrado desde el dashboard (soporte):** el trigger y los cascades corren igual, pero **no** se borran el cliente de RevenueCat ni el usuario de SnapTrade. Hacelo a mano: RevenueCat → Customer → Delete; SnapTrade → `DELETE /snapTrade/deleteUser`. Lo mejor es pedirle al usuario que borre desde la app.
- **Waitlist:** la fila con su mail se borra solo si el mail está confirmado o la cuenta es OAuth (compliance §6.1).
- **Binance:** no hay API para revocar. Borramos nuestra copia; la clave (de solo lectura) sigue en la cuenta de Binance del usuario.
- **Riesgo residual:** si llega un evento de RevenueCat entre el paso 2 (RevenueCat borrado) y el 5 (auth borrado), el webhook todavía ve al usuario y su GET puede recrear el cliente. La ventana dura lo que tardan los pasos locales (eToro/Binance, segundos). Si pasa, el cliente recreado queda vacío y sin datos personales.
