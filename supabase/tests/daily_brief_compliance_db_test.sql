-- Test de 20261124100000_daily_brief_compliance.sql: columnas nuevas con su
-- default y solo las 4 fuentes oficiales aprobadas quedan habilitadas.
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/daily_brief_compliance_db_test.sql
--
-- Imprime DAILY_BRIEF_COMPLIANCE_DB_TEST_OK. Solo lee (rollback al final).

begin;

do $$
declare n int;
begin
  -- require_topic y embeddable existen, no nulos, default false.
  select count(*) into n from information_schema.columns
   where table_schema = 'public' and is_nullable = 'NO' and column_default = 'false'
     and ((table_name = 'video_channel_allowlist' and column_name = 'require_topic')
       or (table_name = 'news_videos' and column_name = 'embeddable'));
  if n <> 2 then raise exception 'faltan require_topic/embeddable (% de 2)', n; end if;

  -- Las 4 oficiales aprobadas están habilitadas.
  select count(*) into n from public.news_source_allowlist
   where enabled and domain in ('federalreserve.gov', 'bls.gov', 'bea.gov', 'ecb.europa.eu');
  if n <> 4 then raise exception 'oficiales habilitadas: % de 4', n; end if;

  -- El resto de las oficiales sigue apagado (FMI, BCRA y las "con condición").
  select count(*) into n from public.news_source_allowlist
   where kind = 'official' and enabled
     and domain not in ('federalreserve.gov', 'bls.gov', 'bea.gov', 'ecb.europa.eu');
  if n <> 0 then raise exception 'hay % oficiales habilitadas de más', n; end if;
  select count(*) into n from public.news_source_allowlist
   where domain in ('imf.org', 'bcra.gob.ar') and enabled;
  if n <> 0 then raise exception 'imf.org / bcra.gob.ar tienen que seguir apagados'; end if;
end $$;

rollback;
select 'DAILY_BRIEF_COMPLIANCE_DB_TEST_OK' as result;
