-- Interruptor del plan anual en el paywall
-- (docs/superpowers/specs/2026-11-02-paywall-medible-y-anual.md §3.6).
--
-- Formato PortyRolloutFlag. Arranca en 100: el anual igual solo aparece si la
-- tienda devuelve los productos, y el revisor de Apple tiene que poder verlo.
-- Sirve para apagarlo sin publicar:
--
--   update public.app_config
--      set value = '{"percent": 0, "users": []}'::jsonb, updated_at = now()
--    where key = 'paywall_annual';
--
-- `do nothing`: si alguien ya lo tocó a mano, un db push no lo pisa.
-- app_config ya tiene RLS y lectura pública (20260930130000_app_config.sql).

insert into public.app_config (key, value)
values ('paywall_annual', '{"percent": 100, "users": []}'::jsonb)
on conflict (key) do nothing;
