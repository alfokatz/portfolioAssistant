-- Brief diario de tu cartera, fase 2 de backend: calentamiento (news-warm),
-- costo fijo configurable y purga.
--
-- Todo es idempotente y aditivo: no cambia nada de lo que ya existe.
--
-- 1. `app_config.daily_brief_costs`: cuántas franjas por día se generan del
--    pulso de mercado y de los temas (costo fijo de Porty, spec §7). Por
--    defecto la opción más barata: 1 por día. Lo lee `news-warm` y `daily-brief`.
-- 2. `_daily_brief_tz_region(tz)`: a qué región de noticias (us, eu, latam,
--    asia) pertenece una zona horaria.
-- 3. `daily_brief_warm_zones(from_min, to_min)`: zonas (de dispositivos
--    reales) donde ahora es entre esos minutos del día, con su fecha local.
-- 4. `daily_brief_warm_plan(region)`: qué idiomas y qué temas tienen
--    usuarios en esa región (sin user_id): así solo se generan idiomas y
--    temas que alguien va a leer.
-- 5. `daily_brief_purge()`: videos de más de 7 días y briefs de más de 14.

-- ---------------------------------------------------------------------------
-- 1. Costo fijo configurable
-- ---------------------------------------------------------------------------

-- Franjas por día: divisores de 24 (1, 2, 3, 4, 6, 8, 12, 24). Con un valor
-- inválido el código usa 1. `max_digests_per_run` acota lo que genera una
-- corrida de news-warm.
insert into public.app_config (key, value)
values (
  'daily_brief_costs',
  '{"pulse_slots_per_day": 1, "topic_slots_per_day": 1, "max_digests_per_run": 24}'::jsonb
)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- 2. Región de una zona horaria
-- ---------------------------------------------------------------------------

create or replace function public._daily_brief_tz_region(p_tz text)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when p_tz is null then 'us'
    when p_tz ~ '^America/(Argentina|Sao_Paulo|Bahia|Fortaleza|Recife|Manaus|Belem|Mexico_City|Monterrey|Merida|Cancun|Bogota|Lima|Santiago|Montevideo|Asuncion|La_Paz|Caracas|Guayaquil|Panama|Costa_Rica|Guatemala|El_Salvador|Tegucigalpa|Managua|Havana|Santo_Domingo|Puerto_Rico)' then 'latam'
    when p_tz like 'America/%' or p_tz like 'US/%' or p_tz like 'Canada/%' or p_tz like 'Pacific/Honolulu' then 'us'
    when p_tz like 'Europe/%' or p_tz like 'Africa/%' or p_tz like 'Atlantic/%' then 'eu'
    when p_tz like 'Asia/%' or p_tz like 'Australia/%' or p_tz like 'Pacific/%' or p_tz like 'Indian/%' then 'asia'
    else 'us'
  end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Zonas con un horario local dado (solo las que tienen dispositivos)
-- ---------------------------------------------------------------------------

create or replace function public.daily_brief_warm_zones(p_from_min int, p_to_min int)
returns table (timezone text, local_date date)
language sql
stable
security definer
set search_path = public
as $$
  with zones as (
    select distinct d.timezone
      from public.push_devices d
      join pg_catalog.pg_timezone_names n on n.name = d.timezone
  )
  select z.timezone,
         (now() at time zone z.timezone)::date
    from zones z
   where extract(hour from now() at time zone z.timezone)::int * 60
         + extract(minute from now() at time zone z.timezone)::int
         between p_from_min and p_to_min - 1
   order by z.timezone;
$$;

-- ---------------------------------------------------------------------------
-- 4. Qué se necesita generar en una región (sin user_id)
-- ---------------------------------------------------------------------------

-- Una fila por idioma con la cuenta de usuarios (`topic_id` null = pulso) y
-- una por (idioma, tema) con la cuenta de usuarios a los que les toca el
-- tema: por defecto (según su cartera) o seguido, menos los apagados.
-- Idioma: es si el `locale` del dispositivo empieza con "es"; si no, en.
create or replace function public.daily_brief_warm_plan(p_region text)
returns table (lang text, topic_id text, users int)
language sql
stable
security definer
set search_path = public
as $$
  with latest as (
    select distinct on (d.user_id) d.user_id, d.timezone, d.locale
      from public.push_devices d
     order by d.user_id, d.last_seen_at desc
  ),
  u as (
    select l.user_id,
           case when lower(coalesce(l.locale, '')) like 'es%' then 'es' else 'en' end as lang
      from latest l
     where public._daily_brief_tz_region(l.timezone) = p_region
       and public._daily_brief_on(l.user_id)
       and exists (select 1 from public.positions p where p.user_id = l.user_id and p.quantity > 0)
  ),
  held as (
    select u.user_id, upper(p.ticker) as symbol
      from u
      join public.positions p on p.user_id = u.user_id
     group by u.user_id, upper(p.ticker)
    having sum(p.quantity) > 0
  ),
  traits as (
    select h.user_id,
           coalesce(h.symbol ~ '-(USD|USDT|EUR)$' or q.quote_type = 'CRYPTOCURRENCY', false) as is_crypto,
           q.quote_type,
           substring(h.symbol from '\.([A-Z]{1,3})$') as suffix
      from held h
      left join public.market_quotes q on q.symbol = h.symbol
  ),
  markets as (
    select t.user_id,
           coalesce(array_agg(distinct
             case when t.suffix is null or t.suffix in ('A', 'B', 'C') then 'US' else '.' || t.suffix end
           ) filter (where not t.is_crypto), '{}') as markets,
           coalesce(array_agg(distinct
             case when t.is_crypto then 'crypto' when t.quote_type = 'ETF' then 'etf' else 'equity' end
           ), '{}') as classes
      from traits t
     group by t.user_id
  ),
  wanted as (
    select u.lang, t.id as topic_id, u.user_id
      from u
      join markets m on m.user_id = u.user_id
      cross join public.news_topics t
     where t.enabled
       and (
         exists (select 1 from public.user_news_topics x
                  where x.user_id = u.user_id and x.topic_id = t.id and x.followed)
         or (
           not exists (select 1 from public.user_news_topics x
                        where x.user_id = u.user_id and x.topic_id = t.id and not x.followed)
           and (t.default_global
                or t.auto_markets && m.markets
                or t.auto_asset_classes && m.classes)
         )
       )
  )
  select u.lang, null::text, count(*)::int from u group by u.lang
  union all
  select w.lang, w.topic_id, count(*)::int from wanted w group by w.lang, w.topic_id;
$$;

-- ---------------------------------------------------------------------------
-- 5. Purga
-- ---------------------------------------------------------------------------

-- Las políticas de YouTube piden refrescar o borrar lo guardado a los 30
-- días: acá se borra a los 7. Los briefs sirven hoy y ayer; se guardan 14.
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
  delete from public.daily_briefs where created_at < now() - interval '14 days';
  get diagnostics v_briefs = row_count;
  return jsonb_build_object('videos', v_videos, 'briefs', v_briefs);
end;
$$;

revoke all on function public._daily_brief_tz_region(text) from public, anon, authenticated;
revoke all on function public.daily_brief_warm_zones(int, int) from public, anon, authenticated;
revoke all on function public.daily_brief_warm_plan(text) from public, anon, authenticated;
revoke all on function public.daily_brief_purge() from public, anon, authenticated;
grant execute on function
  public._daily_brief_tz_region(text),
  public.daily_brief_warm_zones(int, int),
  public.daily_brief_warm_plan(text),
  public.daily_brief_purge()
to service_role;
