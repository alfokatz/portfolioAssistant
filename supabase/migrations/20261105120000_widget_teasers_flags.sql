-- Interruptores de los avisos del plan siguiente en el widget de Home
-- (docs/specs/home-widget-tech.md Am.4.5). Misma forma que el resto de los
-- PortyRolloutFlag: {"percent": 0-100, "users": ["<uuid>", ...]}. Salen
-- apagados; se prenden sin publicar la app:
--
--   update public.app_config
--      set value = '{"percent": 0, "users": ["<uuid>"]}', updated_at = now()
--    where key = 'widget_teasers_android';
insert into public.app_config (key, value)
values
  ('widget_teasers_android', '{"percent": 0, "users": []}'::jsonb),
  ('widget_teasers_ios', '{"percent": 0, "users": []}'::jsonb)
on conflict (key) do nothing;
