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
# TERMINAL 1 (queda ocupada: `functions serve` no termina)
supabase start
supabase migration up      # si el stack ya estaba levantado: aplica las migraciones nuevas
supabase functions serve --env-file supabase/functions/.env.local   # key de OpenAI de DEV

# TERMINAL 2: todo lo que sigue
# 2) Variables (chequeá que las tres queden cargadas antes de seguir)
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

## Canales de YouTube

`video_channel_allowlist` arranca vacía: ningún `channel_id` se carga de memoria. La lista de candidatos sale de la revisión de compliance (`docs/legal/reviews/2026-11-21-brief-diario-medios-y-youtube.md` §2.3) y vive en `supabase/functions/scripts/youtube_channels.ts`.

1. Con la clave de YouTube (la misma del secreto `YOUTUBE_API_KEY`), desde `supabase/functions`:
   ```bash
   YOUTUBE_API_KEY=<clave> deno run -A scripts/youtube_channels.ts > /tmp/channels.sql
   ```
   Cuesta 1 unidad de cuota por intento (de 10.000 diarias). `--all` suma los de prioridad 2.
2. El reporte sale por la terminal: ✓ para cada canal verificado (título, handle, suscriptores y link) y ✗ para los que no resolvieron. **Abrí cada link** y confirmá que es el canal oficial del medio. Si uno no es, borrá su fila de `/tmp/channels.sql`.
3. Para un ✗: buscá el link del canal en el sitio del medio, agregá el handle o el id `UC…` en `lookups` y volvé a correr.
4. Corré `/tmp/channels.sql` en el SQL editor de Supabase. Es idempotente. `outlet_domain` queda en null si el medio no está habilitado en `news_source_allowlist`.
5. Los videos aparecen después de la próxima corrida de `news-warm` (cada 15 min, solo con `daily_brief` prendido).

Para sacar un canal: `update public.video_channel_allowlist set enabled = false where channel_id = '<id>';`
