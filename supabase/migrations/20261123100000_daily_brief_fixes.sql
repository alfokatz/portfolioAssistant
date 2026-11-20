-- Brief diario: correcciones de la revisión (migración nueva; las tres
-- anteriores ya están commiteadas y no se editan). Idempotente.
--
-- 1. La purga no borra briefs de cortesía: `claim_daily_brief` cuenta la
--    cortesía usada con esas filas, y al purgarlas a los 14 días un Free
--    recuperaba el brief `full` para siempre. Son a lo sumo `courtesy_days`
--    (tope 15) filas por usuario; salen con el usuario (on delete cascade).
-- 2. `daily_brief_entitlement` ignora la fila de un día que ya no es válido
--    (`_daily_brief_valid_day`): sin eso, un Free sin cortesía o un Premium
--    que bajó de plan seguía viendo `full` unos días más.
-- 3. `news_compare_allowed`: permiso de "Qué dice cada medio" por plan
--    efectivo, sin las puertas de `gold_data_allowed` (informe semanal en
--    curso, cortesía de un ticker).

-- ---------------------------------------------------------------------------
-- 1. Purga
-- ---------------------------------------------------------------------------

create or replace function public.daily_brief_purge()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_videos int;
  v_briefs int;
begin
  delete from public.news_videos where fetched_at < now() - interval '7 days';
  get diagnostics v_videos = row_count;
  delete from public.daily_briefs
   where created_at < now() - interval '14 days' and not courtesy;
  get diagnostics v_briefs = row_count;
  return jsonb_build_object('videos', v_videos, 'briefs', v_briefs);
end;
$$;

revoke all on function public.daily_brief_purge() from public, anon, authenticated;
grant execute on function public.daily_brief_purge() to service_role;

-- ---------------------------------------------------------------------------
-- 3. Permiso de comparar fuentes
-- ---------------------------------------------------------------------------

create or replace function public.news_compare_allowed(p_user_id uuid, p_ticker text default null)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public._effective_tier(p_user_id), 'free') = 'gold'
    or (
      p_ticker is not null
      and coalesce(public._effective_tier(p_user_id), 'free') = 'premium'
      and public._news_provider() = 'v2'
      and exists (
        select 1 from public.positions
         where user_id = p_user_id
           and upper(ticker) = upper(p_ticker)
           and quantity > 0
      )
    );
$$;

revoke all on function public.news_compare_allowed(uuid, text) from public, anon, authenticated;
grant execute on function public.news_compare_allowed(uuid, text) to service_role;

-- ---------------------------------------------------------------------------
-- 2. Entitlement (copia de 20261121100000 con un solo cambio: la fila del día
--    solo cuenta si el día es válido)
-- ---------------------------------------------------------------------------

create or replace function public.daily_brief_entitlement(p_user_id uuid, p_day date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_on boolean := public._daily_brief_on(p_user_id);
  v_tier text;
  v_row public.daily_briefs%rowtype;
  v_variant text;
  v_courtesy boolean := false;
  v_held jsonb;
  v_watch jsonb := '[]'::jsonb;
  v_markets text[];
  v_classes text[];
  v_topics jsonb;
  v_prefer jsonb;
  v_mute jsonb;
begin
  if not v_on or p_user_id is null then
    return jsonb_build_object(
      'enabled', false,
      'pieces', jsonb_build_object(
        'push', false, 'feed', false, 'topics', false, 'sources', false,
        'market', false, 'compare', false, 'videos', false)
    );
  end if;

  v_tier := coalesce(public._effective_tier(p_user_id), 'free');

  -- Un día fuera de la ventana (ayer a mañana, hábil) no usa su fila: si no,
  -- el `full` de una cortesía o de un plan viejo seguiría vivo unos días.
  if public._daily_brief_valid_day(p_day) then
    select * into v_row from public.daily_briefs
    where user_id = p_user_id and brief_day = p_day;
  end if;
  if v_row.user_id is not null then
    v_variant := v_row.variant;
    v_courtesy := v_row.courtesy;
  elsif v_tier in ('premium', 'gold') then
    v_variant := 'full';
  else
    v_variant := 'numbers';
  end if;

  -- Cartera: una fila por ticker en mayúsculas, con su peso.
  with h as (
    select upper(p.ticker) as symbol
      from public.positions p
     where p.user_id = p_user_id
     group by upper(p.ticker)
    having sum(p.quantity) > 0
  ),
  w as (
    select upper(symbol) as symbol, weight_pct
      from public.push_holding_weights(array[p_user_id])
  )
  select coalesce(jsonb_agg(jsonb_build_object('symbol', h.symbol, 'weight_pct', w.weight_pct)
                            order by w.weight_pct desc nulls last, h.symbol), '[]'::jsonb)
    into v_held
    from h left join w on w.symbol = h.symbol;

  -- Mercados (sufijo de la bolsa; sin sufijo = EE. UU.; .A/.B/.C son clases
  -- de acciones, no una bolsa) y clases de activo (quoteType de Yahoo).
  with h as (
    select upper(p.ticker) as symbol
      from public.positions p
     where p.user_id = p_user_id
     group by upper(p.ticker)
    having sum(p.quantity) > 0
  ),
  c as (
    select h.symbol,
           q.quote_type,
           coalesce(h.symbol ~ '-(USD|USDT|EUR)$' or q.quote_type = 'CRYPTOCURRENCY', false) as is_crypto,
           substring(h.symbol from '\.([A-Z]{1,3})$') as suffix
      from h left join public.market_quotes q on q.symbol = h.symbol
  )
  select
    coalesce(array_agg(distinct
      case when is_crypto then null
           when suffix is null or suffix in ('A', 'B', 'C') then 'US'
           else '.' || suffix end
    ) filter (where not is_crypto), '{}'),
    coalesce(array_agg(distinct
      case when is_crypto then 'crypto'
           when quote_type = 'ETF' then 'etf'
           else 'equity' end
    ), '{}')
    into v_markets, v_classes
    from c;
  v_markets := array_remove(v_markets, null);

  if v_tier = 'gold' then
    select coalesce(jsonb_agg(w.symbol order by w.created_at, w.symbol), '[]'::jsonb)
      into v_watch
      from public.watchlist_items w
     where w.user_id = p_user_id;
  end if;

  select coalesce(jsonb_agg(t.id order by t.sort, t.id), '[]'::jsonb)
    into v_topics
    from public.news_topics t
   where t.enabled
     and (
       exists (select 1 from public.user_news_topics u
                where u.user_id = p_user_id and u.topic_id = t.id and u.followed)
       or (
         not exists (select 1 from public.user_news_topics u
                      where u.user_id = p_user_id and u.topic_id = t.id and not u.followed)
         and (t.default_global
              or t.auto_markets && v_markets
              or t.auto_asset_classes && v_classes)
       )
     );

  select coalesce(jsonb_agg(s.domain order by s.domain) filter (where s.preference = 'prefer'), '[]'::jsonb),
         coalesce(jsonb_agg(s.domain order by s.domain) filter (where s.preference = 'mute'), '[]'::jsonb)
    into v_prefer, v_mute
    from public.user_news_sources s
   where s.user_id = p_user_id;

  return jsonb_build_object(
    'enabled', true,
    'pieces', jsonb_build_object(
      'push', public._daily_brief_piece('push'),
      'feed', public._daily_brief_piece('feed'),
      'topics', public._daily_brief_piece('topics'),
      'sources', public._daily_brief_piece('sources'),
      'market', public._daily_brief_piece('market'),
      'compare', public._daily_brief_piece('compare'),
      'videos', public._daily_brief_piece('videos')
    ),
    'tier', v_tier,
    'variant', v_variant,
    'courtesy', v_courtesy,
    'held', v_held,
    'watchlist', v_watch,
    'topics', v_topics,
    'prefer', v_prefer,
    'mute', v_mute,
    'markets', to_jsonb(v_markets),
    'asset_classes', to_jsonb(v_classes)
  );
end;
$$;

revoke all on function public.daily_brief_entitlement(uuid, date) from public, anon, authenticated;
grant execute on function public.daily_brief_entitlement(uuid, date) to service_role;
