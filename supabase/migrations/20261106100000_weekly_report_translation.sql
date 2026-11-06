-- Informe semanal en el otro idioma, solo cuando hace falta.
--
-- El informe se genera una vez por semana en el idioma de la app (payload
-- `lang`). Si el usuario cambia el idioma a mitad de semana, la app pide
-- traducirlo: claim_weekly_report_translation abre un claim corto sobre la
-- fila ya `ready`, ai-chat lo acepta como claim de informe (ai_report_begin)
-- y complete_weekly_report_translation guarda la versión nueva en
-- `payload.alt`. Con las dos versiones guardadas, volver al idioma anterior
-- no llama al LLM: como mucho una traducción por semana.

alter table public.weekly_reports
  add column if not exists translation_lang text
    check (translation_lang in ('es', 'en')),
  add column if not exists translation_claimed_at timestamptz;

-- ---------------------------------------------------------------------------
-- claim_weekly_report_translation: {state} =
-- - ready        → ya está en ese idioma: {payload}
-- - claimed      → le toca a este dispositivo escribirlo
-- - in_progress  → otro dispositivo lo está escribiendo
-- - disabled     → el informe está apagado
-- - unavailable  → no hay informe completo que traducir (o es de antes del
--                  informe bilingüe, sin `lang`)
-- ---------------------------------------------------------------------------
create or replace function public.claim_weekly_report_translation(
  p_week_start date,
  p_language text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_row public.weekly_reports%rowtype;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if p_language is null or p_language not in ('es', 'en') then
    return jsonb_build_object('state', 'unavailable');
  end if;
  if not public._weekly_report_enabled() then
    return jsonb_build_object('state', 'disabled');
  end if;
  if not public._valid_report_week(p_week_start) then
    return jsonb_build_object('state', 'unavailable');
  end if;

  select * into v_row from public.weekly_reports
  where user_id = v_user_id and week_start = p_week_start
  for update;
  if not found
     or v_row.status <> 'ready'
     or v_row.payload is null
     or v_row.payload ->> 'variant' is distinct from 'full'
     or v_row.payload ->> 'lang' is null then
    return jsonb_build_object('state', 'unavailable');
  end if;
  if v_row.payload ->> 'lang' = p_language
     or v_row.payload -> 'alt' ->> 'lang' = p_language then
    return jsonb_build_object('state', 'ready', 'payload', v_row.payload);
  end if;
  if v_row.translation_claimed_at is not null
     and v_row.translation_claimed_at > now() - public._report_claim_ttl() then
    return jsonb_build_object('state', 'in_progress');
  end if;

  update public.weekly_reports
  set translation_lang = p_language, translation_claimed_at = now()
  where user_id = v_user_id and week_start = p_week_start;
  return jsonb_build_object('state', 'claimed');
end;
$$;

-- Guarda la versión traducida en payload.alt. Solo con el claim de
-- traducción vigente y en el idioma reclamado.
create or replace function public.complete_weekly_report_translation(
  p_week_start date,
  p_alt jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_row public.weekly_reports%rowtype;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if p_alt is null or jsonb_typeof(p_alt) <> 'object' then
    return jsonb_build_object('ok', false, 'reason', 'invalid_payload');
  end if;
  if octet_length(p_alt::text) > 65536 then
    return jsonb_build_object('ok', false, 'reason', 'payload_too_large');
  end if;

  select * into v_row from public.weekly_reports
  where user_id = v_user_id and week_start = p_week_start
  for update;
  if not found
     or v_row.status <> 'ready'
     or v_row.translation_claimed_at is null
     or v_row.translation_claimed_at <= now() - public._report_claim_ttl()
     or p_alt ->> 'lang' is distinct from v_row.translation_lang
     or p_alt ->> 'week' is distinct from v_row.payload ->> 'week' then
    return jsonb_build_object('ok', false, 'reason', 'not_claimed');
  end if;

  update public.weekly_reports
  set payload = (payload - 'alt') || jsonb_build_object('alt', p_alt - 'alt'),
      translation_claimed_at = null
  where user_id = v_user_id and week_start = p_week_start;
  return jsonb_build_object('ok', true);
end;
$$;

-- ai_report_begin: igual que en 20261002130000_weekly_report_flag.sql, pero
-- también acepta el claim de traducción vigente sobre una fila `ready`.
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
  if not found or not (
    (v_row.status = 'generating'
      and v_row.claimed_at > now() - public._report_claim_ttl())
    or (v_row.status = 'ready'
      and v_row.translation_claimed_at is not null
      and v_row.translation_claimed_at > now() - public._report_claim_ttl())
  ) then
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

revoke all on function public.claim_weekly_report_translation(date, text)
  from public, anon;
revoke all on function public.complete_weekly_report_translation(date, jsonb)
  from public, anon;
grant execute on function
  public.claim_weekly_report_translation(date, text),
  public.complete_weekly_report_translation(date, jsonb)
to authenticated;
