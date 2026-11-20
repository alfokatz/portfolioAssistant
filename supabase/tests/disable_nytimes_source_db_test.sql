-- Test de 20261125100000_disable_nytimes_source.sql: nytimes.com queda
-- apagado y el resto de los medios habilitados no cambia.
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/disable_nytimes_source_db_test.sql
--
-- Imprime DISABLE_NYTIMES_SOURCE_DB_TEST_OK. Solo lee (rollback al final).

begin;

do $$
declare n int;
begin
  select count(*) into n from public.news_source_allowlist
   where domain = 'nytimes.com' and not enabled;
  if n <> 1 then raise exception 'nytimes.com no está apagado'; end if;

  -- Los medios globales de siempre siguen habilitados.
  select count(*) into n from public.news_source_allowlist
   where enabled and domain in ('reuters.com', 'apnews.com', 'cnbc.com', 'bloomberg.com');
  if n <> 4 then raise exception 'se apagaron medios de más (% de 4)', n; end if;
end $$;

select 'DISABLE_NYTIMES_SOURCE_DB_TEST_OK';

rollback;
