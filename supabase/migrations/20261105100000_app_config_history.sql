-- Historial de `app_config` (docs/superpowers/specs/2026-11-05-diferenciacion-planes-v2.md §3.7).
-- Guarda cuándo cambió cada interruptor y a qué valor, para reconstruir el
-- cohorte de cualquier evento (`_rollout_bucket(user_id) < percent` vigente a
-- esa fecha) sin tener que mandar una prop `flags` en cada evento.
--
-- Sin uuids: `users` (y `allow_users`) se sacan del valor y queda solo la
-- cantidad. Por eso la tabla no necesita sumarse al borrado de cuenta.
-- RLS activado y sin políticas: solo la service role la lee.

create table if not exists public.app_config_history (
  id bigserial primary key,
  key text not null,
  value jsonb,
  users_count int,
  op text not null check (op in ('snapshot', 'insert', 'update', 'delete')),
  changed_at timestamptz not null default now()
);

create index if not exists app_config_history_key_changed_idx
  on public.app_config_history (key, changed_at desc);

alter table public.app_config_history enable row level security;
revoke all on public.app_config_history from public, anon, authenticated;
grant select, insert on public.app_config_history to service_role;
grant usage, select on sequence public.app_config_history_id_seq to service_role;

-- Valor sin listas de usuarios (uuids).
create or replace function public._app_config_public_value(p_value jsonb)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select case
    when jsonb_typeof(p_value) = 'object' then p_value - 'users' - 'allow_users'
    else p_value
  end;
$$;

create or replace function public._app_config_users_count(p_value jsonb)
returns int
language sql
immutable
set search_path = public
as $$
  select case
    when jsonb_typeof(p_value) = 'object' and jsonb_typeof(p_value -> 'users') = 'array'
      then jsonb_array_length(p_value -> 'users')
    else null
  end;
$$;

create or replace function public._app_config_history_log()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    insert into public.app_config_history (key, value, users_count, op)
    values (old.key, public._app_config_public_value(old.value), public._app_config_users_count(old.value), 'delete');
    return old;
  end if;
  if tg_op = 'UPDATE'
     and public._app_config_public_value(new.value) is not distinct from public._app_config_public_value(old.value)
     and public._app_config_users_count(new.value) is not distinct from public._app_config_users_count(old.value) then
    -- Solo cambió el instante o la lista de usuarios sin cambiar la cantidad.
    return new;
  end if;
  insert into public.app_config_history (key, value, users_count, op)
  values (new.key, public._app_config_public_value(new.value), public._app_config_users_count(new.value), lower(tg_op));
  return new;
end;
$$;

revoke all on function public._app_config_public_value(jsonb) from public, anon, authenticated;
revoke all on function public._app_config_users_count(jsonb) from public, anon, authenticated;
revoke all on function public._app_config_history_log() from public, anon, authenticated;

drop trigger if exists app_config_history_log on public.app_config;
create trigger app_config_history_log
  after insert or update or delete on public.app_config
  for each row execute function public._app_config_history_log();

-- Foto inicial de lo que hay hoy (solo si la historia está vacía: idempotente).
insert into public.app_config_history (key, value, users_count, op)
select c.key, public._app_config_public_value(c.value), public._app_config_users_count(c.value), 'snapshot'
from public.app_config c
where not exists (select 1 from public.app_config_history);
