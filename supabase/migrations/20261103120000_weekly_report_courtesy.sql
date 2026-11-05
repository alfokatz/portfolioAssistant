-- Hábito del sábado: los primeros N informes completos de regalo
-- (docs/superpowers/specs/2026-11-03-habito-del-sabado.md §3.2 y §3.3).
-- Requiere 20261103110000_rollout_flag_sql.sql.
--
-- Prender (lo hace el usuario):
--   update public.app_config
--      set value = '{"percent": 100, "users": [], "reports": 3}'::jsonb, updated_at = now()
--    where key = 'weekly_report_courtesy';

insert into public.app_config (key, value)
values ('weekly_report_courtesy', '{"percent": 0, "users": [], "reports": 3}'::jsonb)
on conflict (key) do nothing;

-- Informes completos de regalo para [p_user_id]: 1 con el interruptor
-- apagado (lo de hoy); con el interruptor, `reports` acotado a 1..8 (3 si
-- falta o no es número).
create or replace function public._weekly_courtesy_limit(p_user_id uuid)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select case
    when not public._rollout_on('weekly_report_courtesy', p_user_id) then 1
    else coalesce(
      (select least(greatest(floor((value ->> 'reports')::numeric), 1), 8)::int
       from public.app_config
       where key = 'weekly_report_courtesy'
         and jsonb_typeof(value -> 'reports') = 'number'),
      3
    )
  end;
$$;

revoke all on function public._weekly_courtesy_limit(uuid) from public, anon, authenticated;

-- claim_weekly_report: cuerpo de 20261002130000 (con `disabled`), más el
-- conteo de regalos contra _weekly_courtesy_limit y los campos
-- courtesy_number / courtesy_total en los `claimed` de regalo.
create or replace function public.claim_weekly_report(p_week_start date)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_tier text;
  v_row public.weekly_reports%rowtype;
  v_courtesy boolean;
  v_limit int;
  v_used int;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if not public._valid_report_week(p_week_start) then
    raise exception 'invalid_week_start';
  end if;
  if not public._weekly_report_enabled() then
    return jsonb_build_object('state', 'disabled');
  end if;

  v_tier := coalesce(public._effective_tier(v_user_id), 'free');

  select * into v_row from public.weekly_reports
  where user_id = v_user_id and week_start = p_week_start
  for update;

  if found then
    if v_row.status = 'ready' then
      return jsonb_build_object(
        'state', 'ready', 'payload', v_row.payload, 'courtesy', v_row.courtesy
      );
    end if;
    if v_row.status = 'generating'
       and v_row.claimed_at > now() - public._report_claim_ttl() then
      return jsonb_build_object('state', 'in_progress');
    end if;
    if v_row.attempts >= public._report_max_attempts() then
      if v_row.status <> 'failed' then
        update public.weekly_reports set status = 'failed'
        where user_id = v_user_id and week_start = p_week_start;
      end if;
      return jsonb_build_object('state', 'failed');
    end if;
    update public.weekly_reports
    set status = 'generating',
        attempts = attempts + 1,
        claimed_at = now()
    where user_id = v_user_id and week_start = p_week_start;
    if v_row.courtesy then
      -- Número de este regalo: los regalos hasta esta semana inclusive.
      select count(*) into v_used from public.weekly_reports
      where user_id = v_user_id and courtesy and week_start <= p_week_start;
      return jsonb_build_object(
        'state', 'claimed', 'courtesy', true,
        'attempt', v_row.attempts + 1,
        'courtesy_number', v_used,
        'courtesy_total', public._weekly_courtesy_limit(v_user_id)
      );
    end if;
    return jsonb_build_object(
      'state', 'claimed', 'courtesy', v_row.courtesy,
      'attempt', v_row.attempts + 1
    );
  end if;

  if v_tier = 'gold' then
    v_courtesy := false;
  else
    v_limit := public._weekly_courtesy_limit(v_user_id);
    -- Serializa los claims del mismo usuario: dos claims en paralelo para
    -- semanas distintas verían el mismo v_used y regalarían uno de más.
    perform pg_advisory_xact_lock(hashtext('weekly_courtesy:' || v_user_id::text));
    select count(*) into v_used from public.weekly_reports
    where user_id = v_user_id and courtesy;
    if v_used >= v_limit then
      return jsonb_build_object('state', 'numbers_only');
    end if;
    v_courtesy := true;
  end if;

  insert into public.weekly_reports (user_id, week_start, status, courtesy)
  values (v_user_id, p_week_start, 'generating', v_courtesy)
  on conflict (user_id, week_start) do nothing;
  if not found then
    -- Otro dispositivo ganó la carrera en este mismo instante.
    return jsonb_build_object('state', 'in_progress');
  end if;

  if v_courtesy then
    return jsonb_build_object(
      'state', 'claimed', 'courtesy', true, 'attempt', 1,
      'courtesy_number', v_used + 1, 'courtesy_total', v_limit
    );
  end if;
  return jsonb_build_object('state', 'claimed', 'courtesy', false, 'attempt', 1);
end;
$$;
