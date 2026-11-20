-- Retención de los eventos de la landing: la política de privacidad de
-- portyassistant.com dice que los registros de visitas y clics se borran a
-- los 12 meses. Este job lo cumple, una vez por día.

create or replace function public.landing_events_purge()
returns integer
language sql
security definer
set search_path = public
as $$
  with gone as (
    delete from public.landing_events
    where created_at < now() - interval '12 months'
    returning 1
  )
  select count(*)::int from gone;
$$;

revoke all on function public.landing_events_purge() from public, anon, authenticated;
grant execute on function public.landing_events_purge() to service_role;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('landing-events-retention', '17 6 * * *', $c$select public.landing_events_purge()$c$);
  end if;
end $$;
