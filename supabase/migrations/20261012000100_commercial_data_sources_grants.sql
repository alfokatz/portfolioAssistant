-- Las funciones de 20261012000000_commercial_data_sources quedaron sin
-- permiso para la service role (el `revoke ... from public` también se lo
-- saca): las edge functions sec / news-context / headlines / web-search las
-- llaman con la service role. Va aparte porque esa migración ya puede estar
-- aplicada.
grant execute on function
  public._news_provider(),
  public.upstream_rate_take(text, int),
  public.gold_data_allowed(uuid, text),
  public.news_context_hit(uuid),
  public._turn_for_web_search(uuid, text),
  public.turn_web_search_calls(uuid, text),
  public.record_web_search_usage(uuid, text, int, numeric)
to service_role;

grant select, insert, update, delete on
  public.sec_ticker_cik,
  public.data_source_cache,
  public.upstream_rate_gate,
  public.news_source_allowlist,
  public.news_context_usage
to service_role;
