-- Free: la primera importación (archivo, captura o texto) que pase el tope de
-- posiciones entra entera (spec 2026-11-05-diferenciacion-planes-v2 §3.2).
--
-- El tope de posiciones vive solo en la app. Este cupo de una vez se reclama
-- ANTES de escribir; si la app no puede reclamarlo (sin red) no importa:
-- falla cerrado. La importación gratis de eToro (`etoro_connections.free_import_at`)
-- es otro cupo y no se toca.
--
-- Nada de esto depende de que `positions` tenga o no un trigger de tope en
-- producción: no escribe en `positions`, solo registra el cupo.

create table if not exists public.first_full_imports (
  user_id uuid primary key references auth.users (id) on delete cascade,
  import_id text not null check (import_id ~ '^[A-Za-z0-9_-]{8,64}$'),
  origin text not null check (origin in ('file', 'screenshot', 'note')),
  positions int not null check (positions > 0),
  used_at timestamptz not null default now()
);

alter table public.first_full_imports enable row level security;

drop policy if exists "Users read own first import" on public.first_full_imports;
create policy "Users read own first import" on public.first_full_imports
  for select to authenticated using (auth.uid() = user_id);

-- Escritura solo vía claim_first_import.
revoke all on public.first_full_imports from public, anon, authenticated;
grant select on public.first_full_imports to authenticated;
grant select, insert, update, delete on public.first_full_imports to service_role;

create or replace function public.first_import_status()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_used timestamptz;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  select used_at into v_used from public.first_full_imports where user_id = v_uid;
  if v_used is null then
    return jsonb_build_object('available', true);
  end if;
  return jsonb_build_object('available', false, 'used_at', v_used);
end;
$$;

create or replace function public.claim_first_import(p_import_id text, p_origin text, p_positions int)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_existing text;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  if p_import_id is null or p_import_id !~ '^[A-Za-z0-9_-]{8,64}$'
     or p_origin is null or p_origin not in ('file', 'screenshot', 'note')
     or p_positions is null or p_positions <= 0 then
    return jsonb_build_object('ok', false, 'reason', 'invalid_args');
  end if;

  perform pg_advisory_xact_lock(hashtext('first_import:' || v_uid::text));

  select import_id into v_existing from public.first_full_imports where user_id = v_uid;
  if v_existing is not null then
    -- Mismo import_id = reintento de la misma importación (se cortó la red
    -- después de reclamar): sigue valiendo.
    if v_existing = p_import_id then
      return jsonb_build_object('ok', true, 'reused', true);
    end if;
    return jsonb_build_object('ok', false, 'reason', 'already_used');
  end if;

  insert into public.first_full_imports (user_id, import_id, origin, positions)
  values (v_uid, p_import_id, p_origin, p_positions);
  return jsonb_build_object('ok', true, 'reused', false);
end;
$$;

revoke all on function public.first_import_status() from public, anon;
revoke all on function public.claim_first_import(text, text, int) from public, anon;
grant execute on function public.first_import_status() to authenticated;
grant execute on function public.claim_first_import(text, text, int) to authenticated;
