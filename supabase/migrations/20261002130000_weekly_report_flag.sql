-- Interruptor del informe semanal (F6 del plan
-- docs/superpowers/plans/2026-10-01-informe-semanal-porty.md).
--
-- Va en una migración aparte porque 20261002120000_weekly_reports ya está
-- aplicada en dev: redefine claim_weekly_report y ai_report_begin con el
-- chequeo del interruptor (mismo cuerpo, más el `if` del principio).

-- Interruptor del informe (`app_config.weekly_report.enabled`, arranca
-- apagado). Lo chequea el servidor, no la app: apagarlo frena la tarjeta y
-- el gasto de LLM incluso en versiones viejas, sin publicar nada:
--
--   update public.app_config set value = '{"enabled": true}', updated_at = now()
--    where key = 'weekly_report';
insert into public.app_config (key, value)
values ('weekly_report', '{"enabled": false}'::jsonb)
on conflict (key) do nothing;

create or replace function public._weekly_report_enabled()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select (value ->> 'enabled')::boolean from public.app_config
     where key = 'weekly_report'),
    false
  );
$$;

-- claim_weekly_report: igual que en 20261002120000, más el estado
-- `disabled` (el informe está apagado: sin tarjeta).
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
    return jsonb_build_object(
      'state', 'claimed', 'courtesy', v_row.courtesy,
      'attempt', v_row.attempts + 1
    );
  end if;

  if v_tier = 'gold' then
    v_courtesy := false;
  elsif exists (
    select 1 from public.weekly_reports
    where user_id = v_user_id and courtesy
  ) then
    return jsonb_build_object('state', 'numbers_only');
  else
    v_courtesy := true;
  end if;

  insert into public.weekly_reports (user_id, week_start, status, courtesy)
  values (v_user_id, p_week_start, 'generating', v_courtesy)
  on conflict (user_id, week_start) do nothing;
  if not found then
    -- Otro dispositivo ganó la carrera en este mismo instante.
    return jsonb_build_object('state', 'in_progress');
  end if;

  return jsonb_build_object('state', 'claimed', 'courtesy', v_courtesy, 'attempt', 1);
end;
$$;

-- ai_report_begin: igual que en 20261002120000, más `disabled` (apagado a
-- mitad de una generación: no se gasta ni una llamada más).
create or replace function public.ai_report_begin(
  p_user_id uuid,
  p_turn_id text,
  p_week_start date,
  p_model text,
  p_max_rounds int,
  p_rate_per_minute int
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.weekly_reports%rowtype;
  v_owner uuid;
begin
  -- Apagado a mitad de una generación: no se gasta ni una llamada más.
  if not public._weekly_report_enabled() then
    return jsonb_build_object('ok', false, 'reason', 'disabled');
  end if;
  if not exists (
    select 1 from public.model_prices where model = p_model and allowed
  ) then
    return jsonb_build_object('ok', false, 'reason', 'model_not_allowed');
  end if;

  if not public.rate_limit_hit(p_user_id, 'ai', p_rate_per_minute) then
    return jsonb_build_object('ok', false, 'reason', 'rate_limited');
  end if;

  select * into v_row from public.weekly_reports
  where user_id = p_user_id and week_start = p_week_start
  for update;
  if not found
     or v_row.status <> 'generating'
     or v_row.claimed_at <= now() - public._report_claim_ttl() then
    return jsonb_build_object('ok', false, 'reason', 'not_claimed');
  end if;
  if v_row.llm_rounds >= p_max_rounds then
    return jsonb_build_object('ok', false, 'reason', 'too_many_rounds');
  end if;

  insert into public.ai_turn_usage (turn_id, user_id, tier, model, purpose)
  values (
    p_turn_id, p_user_id,
    coalesce(public._effective_tier(p_user_id), 'free'), p_model,
    'weekly_report'
  )
  on conflict (turn_id) do nothing;
  select user_id into v_owner from public.ai_turn_usage where turn_id = p_turn_id;
  if v_owner <> p_user_id then
    return jsonb_build_object('ok', false, 'reason', 'turn_mismatch');
  end if;

  update public.weekly_reports
  set llm_rounds = llm_rounds + 1
  where user_id = p_user_id and week_start = p_week_start;
  update public.ai_turn_usage
  set round_count = round_count + 1
  where turn_id = p_turn_id;

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public._weekly_report_enabled() from public, anon, authenticated;
