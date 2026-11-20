-- Tope diario de rondas que no se cobran (auditoría de seguridad 2026-11-05).
--
-- La cuota se cobra cuando llega la respuesta final (una ronda sin tool
-- calls). El cliente decide tools y tool_choice, así que podía forzar una
-- tool call en cada ronda, leer la respuesta de los argumentos de la tool y
-- abrir un turn_id nuevo cada vez: nunca se cobraba nada, y la cuota mensual
-- y el tope diario (que cuentan solo turnos cobrados) nunca saltaban. Lo
-- único que frenaba era el rate limit de 30 pedidos/min.
--
-- No se puede prohibir tool_choice forzado: la app lo usa (reintento de una
-- tool con needs_retry, ronda extra 'required'). Lo que se acota es el gasto
-- sin cobrar: rondas de turnos que NO se cobraron, por usuario y día UTC.
-- Un turno normal se cobra al terminar y deja de contar; acá solo suman los
-- cortados (paywall, error, cancelación) y el abuso. Pasado el tope, un
-- turno nuevo o sin cobrar recibe `daily_limit` (las versiones publicadas de
-- la app ya lo muestran como "volvés a tener consultas mañana"). Un turno ya
-- cobrado sigue pudiendo terminar (repair de la surface).
--
-- También cubre statement-import, que usa ai_begin_request con sus propios
-- turnos (`import:...`).

create or replace function public._daily_uncharged_rounds()
returns int
language sql
immutable
as $$
  -- Un turno cortado usa 1-3 rondas: 40 deja de sobra para el uso real.
  select 40;
$$;

create index if not exists ai_turn_usage_user_uncharged_idx
  on public.ai_turn_usage (user_id, created_at)
  where charged_at is null;

create or replace function public.ai_begin_request(
  p_user_id uuid,
  p_turn_id text,
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
  v_tier text;
  v_turn public.ai_turn_usage%rowtype;
  v_used int;
  v_daily_used int;
  v_monthly int;
  v_daily int;
  v_uncharged int;
begin
  if not exists (
    select 1 from public.model_prices where model = p_model and allowed
  ) then
    return jsonb_build_object('ok', false, 'reason', 'model_not_allowed');
  end if;

  if not public.rate_limit_hit(p_user_id, 'ai', p_rate_per_minute) then
    return jsonb_build_object('ok', false, 'reason', 'rate_limited');
  end if;

  v_tier := coalesce(public._effective_tier(p_user_id), 'free');

  insert into public.ai_turn_usage (turn_id, user_id, tier, model)
  values (p_turn_id, p_user_id, v_tier, p_model)
  on conflict (turn_id) do nothing;

  select * into v_turn from public.ai_turn_usage
  where turn_id = p_turn_id
  for update;

  if v_turn.user_id <> p_user_id then
    return jsonb_build_object('ok', false, 'reason', 'turn_mismatch');
  end if;

  if v_turn.round_count >= p_max_rounds then
    return jsonb_build_object('ok', false, 'reason', 'too_many_rounds');
  end if;

  -- Un turno ya cobrado puede seguir (p. ej. el repair de la surface).
  if v_turn.charged_at is null then
    v_monthly := public._monthly_quota(v_tier);
    select coalesce(queries_used, 0) into v_used
    from public.ai_usage_monthly
    where user_id = p_user_id and month = public._current_usage_month();
    if coalesce(v_used, 0) >= v_monthly then
      return jsonb_build_object(
        'ok', false, 'reason', 'quota_exceeded',
        'queries_used', coalesce(v_used, 0), 'queries_limit', v_monthly
      );
    end if;

    v_daily := public._daily_quota(v_tier);
    if v_daily is not null then
      select count(*) into v_daily_used from public.ai_turn_usage
      where user_id = p_user_id
        and charged_at >= date_trunc('day', now() at time zone 'utc');
      if v_daily_used >= v_daily then
        return jsonb_build_object(
          'ok', false, 'reason', 'daily_limit', 'daily_limit', v_daily
        );
      end if;
    end if;

    -- Rondas sin cobrar de hoy (incluida la de este turno, si ya tuvo).
    select coalesce(sum(round_count), 0) into v_uncharged
    from public.ai_turn_usage
    where user_id = p_user_id
      and charged_at is null
      and created_at >= date_trunc('day', now() at time zone 'utc');
    if v_uncharged >= public._daily_uncharged_rounds() then
      return jsonb_build_object(
        'ok', false, 'reason', 'daily_limit',
        'daily_limit', coalesce(v_daily, v_monthly), 'cause', 'uncharged_rounds'
      );
    end if;
  end if;

  update public.ai_turn_usage
  set round_count = round_count + 1
  where turn_id = p_turn_id;

  return jsonb_build_object('ok', true, 'tier', v_tier);
end;
$$;

revoke all on function public.ai_begin_request(uuid, text, text, int, int)
  from public, anon, authenticated;
revoke all on function public._daily_uncharged_rounds() from public, anon, authenticated;
grant execute on function
  public.ai_begin_request(uuid, text, text, int, int),
  public._daily_uncharged_rounds()
to service_role;
