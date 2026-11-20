# Brief diario

## Evals

Evals del brief diario contra el modelo REAL (`test/evals/daily_brief_evals_test.dart`, 19 casos).
**Cuestan plata** (~US$0,005 por caso, unos US$0,10-0,25 la corrida): correrlas solo con OK del
usuario. Solo contra Supabase local (o el proyecto de DESARROLLO con `ALLOW_REMOTE=1`).

Cada caso necesita su propio usuario: una posición, el interruptor `daily_brief` prendido para él y
el brief del día reservado (`claim_daily_brief` → `claimed`), porque el proxy `ai-chat` en modo
`daily_brief` topea en 2 rondas por claim. El script `eval_brief_users.ts` lo arma (plan `premium`
por defecto, para que el brief sea `full`; elige hoy si es día hábil UTC, si no ayer o mañana).

```bash
# 1) Stack local y proxy (key de OpenAI de DEV en .env.local)
supabase start
supabase functions serve --env-file supabase/functions/.env.local   # en otra terminal

# 2) Variables
eval "$(cd supabase && supabase status -o env | grep -E '^(API_URL|SERVICE_ROLE_KEY|ANON_KEY)=' | sed 's/^/export /')"

# 3) Usuarios: N (por defecto 20; el test tiene 19 casos) y plan opcional (premium | gold | free)
(cd supabase/functions && deno run -A scripts/eval_brief_users.ts 20 premium) > /tmp/brief_users.json

# 4) Evals (llaman al modelo: cuestan plata)
RUN_BRIEF_EVALS=1 EVAL_BRIEF_USERS=/tmp/brief_users.json EVAL_ANON_KEY=$ANON_KEY \
  flutter test test/evals/daily_brief_evals_test.dart
```

El script agrega los usuarios a `app_config.daily_brief.users` sin pisar los que ya estaban. El
claim vale por usuario y día: para repetir la corrida hay que generar usuarios nuevos (paso 3). Si
`deno` no está en el PATH: `~/.deno/bin/deno`.

Salidas: `build/daily_brief_evals.json` (borradores y `rewrite_reasons`) y
`build/daily_brief_evals.md` (los briefs en texto, como se leen en la app). Variables opcionales:
`EVAL_PROXY_URL`, `EVAL_MODEL`, `EVAL_BRIEF_OUT`, `EVAL_BRIEF_TEXT`.

### Limpieza (base local)

Los usuarios son `eval-brief-<uuid>@example.test`. Primero sacarlos de `users`, después borrarlos
(el borrado en `auth.users` arrastra por cascade posiciones, briefs y suscripciones):

```bash
docker exec -i supabase_db_portfolio_assistant psql -U postgres <<'SQL'
update public.app_config
   set value = jsonb_set(value, '{users}', coalesce(
         (select jsonb_agg(u) from jsonb_array_elements(value -> 'users') u
           where (u #>> '{}') not in (
             select id::text from auth.users where email like 'eval-brief-%@example.test')),
         '[]'::jsonb)),
       updated_at = now()
 where key = 'daily_brief';
delete from auth.users where email like 'eval-brief-%@example.test';
SQL
```

Si `users` quedó vacío y `percent` es 0, el interruptor vuelve a estar apagado para todos. En un
proyecto remoto de desarrollo, la misma limpieza con `psql "$DB_URL"` en lugar de `docker exec`.
