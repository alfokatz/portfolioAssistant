-- 20261011060000_web_search revoca `web_search_hit` de public sin dárselo a
-- la service role: la edge function `web-search` recibía "permission
-- denied" y respondía siempre daily_limit (search_web nunca buscaba).
grant execute on function public.web_search_hit(uuid) to service_role;
grant select, insert, update, delete on public.web_search_cache, public.web_search_usage to service_role;
