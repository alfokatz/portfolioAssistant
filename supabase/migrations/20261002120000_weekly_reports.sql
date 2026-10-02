-- Informe semanal de Porty (F3 del plan
-- docs/superpowers/plans/2026-10-01-informe-semanal-porty.md).
--
-- Una fila por usuario y semana cubierta (lunes de la semana bursátil
-- cerrada). La fila existe solo cuando el informe lleva texto de Porty
-- (variante 'full'): Gold siempre, y Free/Premium una única vez como
-- degustación. El resto de las semanas Free/Premium ven solo los números,
-- que la app calcula sin LLM y sin fila.
--
-- La generación la hace la app (datos + 1 llamada al LLM vía ai-chat en modo
-- informe, que NO cobra cuota): claim → generar → complete | fail. La PK
-- hace que dos dispositivos no generen dos veces la misma semana.

create table if not exists public.weekly_reports (
  user_id uuid not null references auth.users (id) on delete cascade,
  week_start date not null check (extract(isodow from week_start) = 1),
  status text not null check (status in ('generating', 'ready', 'failed')),
  -- Degustación: el único informe completo de alguien sin Gold.
  courtesy boolean not null default false,
  payload jsonb,
  -- Intentos de generación (cada claim nuevo o re-claim suma uno).
  attempts smallint not null default 1,
  -- Llamadas al LLM de la semana (todas las rondas de todos los intentos).
  llm_rounds smallint not null default 0,
  claimed_at timestamptz not null default now(),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (user_id, week_start)
);

create index if not exists weekly_reports_courtesy_idx
  on public.weekly_reports (user_id) where courtesy;

alter table public.weekly_reports enable row level security;

drop policy if exists "Users read own weekly reports" on public.weekly_reports;
create policy "Users read own weekly reports" on public.weekly_reports
  for select using (auth.uid() = user_id);
-- Sin policies de escritura: solo por las RPCs de abajo.

-- El uso de OpenAI del informe se registra aparte del chat (no cobra cuota).
alter table public.ai_turn_usage
  add column if not exists purpose text not null default 'chat'
  check (purpose in ('chat', 'weekly_report'));

-- ---------------------------------------------------------------------------
-- Reglas
-- ---------------------------------------------------------------------------

-- Semana cubierta plausible: ya cerrada (se habilita el sábado local) y
-- todavía visible (hasta el viernes siguiente), con ±1 día de margen por
-- zona horaria. Adelantar el reloj del teléfono no habilita semanas futuras.
create or replace function public._valid_report_week(p_week_start date)
returns boolean
language sql
stable
as $$
  select p_week_start is not null
    and extract(isodow from p_week_start) = 1
    and p_week_start between (now() at time zone 'utc')::date - 13
                         and (now() at time zone 'utc')::date - 4;
$$;

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

-- Una generación cortada (app cerrada a mitad) se puede retomar después de
-- este tiempo.
create or replace function public._report_claim_ttl()
returns interval
language sql
immutable
as $$ select interval '2 minutes' $$;

create or replace function public._report_max_attempts()
returns int
language sql
immutable
as $$ select 3 $$;

-- ---------------------------------------------------------------------------
-- RPCs de la app (rol authenticated, auth.uid())
-- ---------------------------------------------------------------------------

-- Qué hacer con el informe de una semana. Devuelve {state, ...}:
-- - ready        → ya está: {payload, courtesy}
-- - claimed      → generalo vos ahora (variante full): {courtesy, attempt}
-- - in_progress  → otro dispositivo lo está generando: reintentar en un rato
-- - numbers_only → sin Gold y degustación ya usada: solo números, sin LLM
-- - failed       → se agotaron los intentos: solo números
-- - disabled     → el informe está apagado (app_config): sin tarjeta
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

-- Guarda el informe generado. Solo sobre una fila propia en 'generating'.
create or replace function public.complete_weekly_report(
  p_week_start date,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    return jsonb_build_object('ok', false, 'reason', 'invalid_payload');
  end if;
  if octet_length(p_payload::text) > 65536 then
    return jsonb_build_object('ok', false, 'reason', 'payload_too_large');
  end if;

  update public.weekly_reports
  set status = 'ready', payload = p_payload, completed_at = now()
  where user_id = v_user_id
    and week_start = p_week_start
    and status = 'generating';
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'not_claimed');
  end if;
  return jsonb_build_object('ok', true);
end;
$$;

-- La generación falló en este intento: libera el claim para reintentar
-- (hasta _report_max_attempts) sin esperar el TTL.
create or replace function public.fail_weekly_report(p_week_start date)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  update public.weekly_reports
  set status = 'failed'
  where user_id = v_user_id
    and week_start = p_week_start
    and status = 'generating';
  return jsonb_build_object('ok', found);
end;
$$;

-- ---------------------------------------------------------------------------
-- RPC del proxy ai-chat (service role): antes de cada llamada al LLM del
-- informe. Devuelve {ok} o {ok:false, reason}: disabled | model_not_allowed |
-- rate_limited | not_claimed | too_many_rounds | turn_mismatch.
-- ---------------------------------------------------------------------------

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

-- ---------------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------------

revoke all on function public.ai_report_begin(uuid, text, date, text, int, int)
  from public, anon, authenticated;
revoke all on function public._weekly_report_enabled() from public, anon, authenticated;
revoke all on function public.claim_weekly_report(date) from public, anon;
revoke all on function public.complete_weekly_report(date, jsonb) from public, anon;
revoke all on function public.fail_weekly_report(date) from public, anon;

grant select on public.weekly_reports to authenticated;
grant select, insert, update, delete on public.weekly_reports to service_role;
grant execute on function
  public.claim_weekly_report(date),
  public.complete_weekly_report(date, jsonb),
  public.fail_weekly_report(date)
to authenticated;
grant execute on function
  public.ai_report_begin(uuid, text, date, text, int, int),
  public._valid_report_week(date)
to service_role;
