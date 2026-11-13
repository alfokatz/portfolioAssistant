-- Alinea las migraciones con lo que producción ya tiene y nunca estuvo en el
-- repo (detectado con `supabase db diff --remote` el 2026-11-13):
--
--   1. positions / closed_positions: se crearon a mano antes de linkear la
--      CLI, con tipos, checks, índices, trigger y policies distintas a las de
--      20261009000000_etoro_sync.sql (que las saltea con `if not exists`).
--   2. public._call_function y los cron jobs de push/daily-jobs: se crearon
--      a mano siguiendo docs/runbooks/push-notifications.md.
--
-- En producción esta migración NO cambia nada (todo es idempotente y con la
-- misma definición). Sirve para que una base nueva (rama develop de
-- Supabase, `supabase start`, tests) quede igual a producción.

-- ---------------------------------------------------------------------------
-- 1. positions / closed_positions
-- ---------------------------------------------------------------------------

alter table public.positions
  add column if not exists updated_at timestamptz not null default now();

alter table public.closed_positions
  add column if not exists source_position_id uuid
    references public.positions (id) on delete set null;

-- Mismo tipo que producción. Si ya es numeric(20,8), Postgres no reescribe.
alter table public.positions
  alter column quantity drop default,
  alter column quantity type numeric(20,8) using quantity::numeric(20,8),
  alter column purchase_price drop default,
  alter column purchase_price type numeric(20,8) using purchase_price::numeric(20,8);

alter table public.closed_positions
  alter column quantity drop default,
  alter column quantity type numeric(20,8) using quantity::numeric(20,8),
  alter column avg_purchase_price drop default,
  alter column avg_purchase_price type numeric(20,8) using avg_purchase_price::numeric(20,8),
  alter column close_price drop default,
  alter column close_price type numeric(20,8) using close_price::numeric(20,8);

do $$
declare
  c record;
begin
  for c in
    select * from (values
      ('positions', 'positions_quantity_positive', 'check (quantity > 0)'),
      ('positions', 'positions_purchase_price_positive', 'check (purchase_price > 0)'),
      ('positions', 'positions_ticker_not_blank', 'check (char_length(trim(both from ticker)) > 0)'),
      ('closed_positions', 'closed_positions_quantity_positive', 'check (quantity > 0)'),
      ('closed_positions', 'closed_positions_avg_purchase_price_positive', 'check (avg_purchase_price > 0)'),
      ('closed_positions', 'closed_positions_close_price_positive', 'check (close_price > 0)'),
      ('closed_positions', 'closed_positions_ticker_not_blank', 'check (char_length(trim(both from ticker)) > 0)')
    ) as t(tbl, name, def)
  loop
    if not exists (
      select 1 from pg_constraint
      where conname = c.name and conrelid = format('public.%I', c.tbl)::regclass
    ) then
      execute format('alter table public.%I add constraint %I %s', c.tbl, c.name, c.def);
    end if;
  end loop;
end $$;

create index if not exists idx_positions_user_id
  on public.positions using btree (user_id);
create index if not exists idx_positions_user_ticker
  on public.positions using btree (user_id, ticker);
create index if not exists idx_closed_positions_user_id
  on public.closed_positions using btree (user_id);
create index if not exists idx_closed_positions_user_closed_at
  on public.closed_positions using btree (user_id, closed_at desc);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
begin
  new.updated_at = now();
  return new;
end;
$function$;

create or replace trigger positions_set_updated_at
  before update on public.positions
  for each row execute function public.set_updated_at();

-- Policies: producción usa una por operación. Las genéricas de etoro_sync
-- solo existen en bases nuevas; se reemplazan.
drop policy if exists "Users manage own positions" on public.positions;
drop policy if exists "Users manage own closed positions" on public.closed_positions;

do $$
declare
  t text;
begin
  foreach t in array array['positions', 'closed_positions'] loop
    if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = t and policyname = t || '_select_own') then
      execute format('create policy %I on public.%I for select to authenticated using (auth.uid() = user_id)', t || '_select_own', t);
    end if;
    if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = t and policyname = t || '_insert_own') then
      execute format('create policy %I on public.%I for insert to authenticated with check (auth.uid() = user_id)', t || '_insert_own', t);
    end if;
    if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = t and policyname = t || '_update_own') then
      execute format('create policy %I on public.%I for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id)', t || '_update_own', t);
    end if;
    if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = t and policyname = t || '_delete_own') then
      execute format('create policy %I on public.%I for delete to authenticated using (auth.uid() = user_id)', t || '_delete_own', t);
    end if;
  end loop;
end $$;

comment on table public.positions is 'Posiciones abiertas del portfolio por usuario.';
comment on table public.closed_positions is 'Historial de cierres parciales o totales por usuario.';
comment on column public.closed_positions.source_position_id is
  'Posición origen al cerrar; nullable si la posición fue eliminada.';

-- ---------------------------------------------------------------------------
-- 2. Cron de edge functions (antes manual, ver runbook push-notifications)
-- ---------------------------------------------------------------------------

-- Igual que en producción, con una diferencia: si el Vault no tiene
-- `project_url` (rama recién creada, base local) no llama a nada, en vez de
-- tirar error cada minuto. La URL y el cron_secret siguen en el Vault de cada
-- entorno, nunca en la migración.
create or replace function public._call_function(
  p_name text,
  p_body jsonb default '{}'::jsonb
)
returns void
language sql
security definer
set search_path to 'public'
as $function$
  select net.http_post(
    url := s.url || '/functions/v1/' || p_name,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')),
    body := p_body,
    timeout_milliseconds := 55000)
  from (
    select decrypted_secret as url
    from vault.decrypted_secrets
    where name = 'project_url'
  ) s
  where s.url is not null;
$function$;

revoke all on function public._call_function(text, jsonb) from public, anon, authenticated;
grant execute on function public._call_function(text, jsonb) to service_role;

-- cron.schedule con un nombre existente actualiza el job (no lo duplica).
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('push-daily-jobs', '0 * * * *', $c$select public._call_function('daily-jobs')$c$);
    perform cron.schedule('push-dispatch', '* * * * *', $c$select public._call_function('notify-dispatch')$c$);
    perform cron.schedule('push-market-watch', '*/5 13-21 * * 1-5', $c$select public._call_function('market-watch')$c$);
  end if;
end $$;
