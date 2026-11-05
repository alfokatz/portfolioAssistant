-- Interruptores por usuario evaluados en el servidor
-- (docs/superpowers/specs/2026-11-03-habito-del-sabado.md §3.1; lo usan
-- también weekly_report_courtesy y market_taste).
--
-- Misma lógica que `PortyRolloutFlag` (app) y `rolloutBucket` (ai-chat): una
-- fila de `app_config` con `{"percent": 0, "users": ["<uuid>", ...]}`.
-- Falla cerrado: sin fila, valor raro o usuario null → apagado.

-- 0..99, estable por usuario: FNV-1a de 32 bits sobre el uuid en texto.
create or replace function public._rollout_bucket(p_user_id uuid)
returns int
language plpgsql
immutable
as $$
declare
  h bigint := 2166136261;
  s text := p_user_id::text;
  i int;
begin
  if p_user_id is null then
    return null;
  end if;
  for i in 1..length(s) loop
    h := h # ascii(substr(s, i, 1));
    h := (h * 16777619) % 4294967296;
  end loop;
  return (h % 100)::int;
end;
$$;

-- true si [p_user_id] está en `users` o su bucket < percent.
create or replace function public._rollout_on(p_key text, p_user_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_value jsonb;
  v_percent numeric;
begin
  if p_user_id is null then
    return false;
  end if;
  select value into v_value from public.app_config where key = p_key;
  if v_value is null or jsonb_typeof(v_value) <> 'object' then
    return false;
  end if;
  if jsonb_typeof(v_value -> 'users') = 'array'
     and (v_value -> 'users') @> to_jsonb(p_user_id::text) then
    return true;
  end if;
  if jsonb_typeof(v_value -> 'percent') <> 'number' then
    return false;
  end if;
  v_percent := (v_value ->> 'percent')::numeric;
  return public._rollout_bucket(p_user_id) < least(greatest(v_percent, 0), 100);
end;
$$;

revoke all on function public._rollout_bucket(uuid) from public, anon, authenticated;
revoke all on function public._rollout_on(text, uuid) from public, anon, authenticated;
