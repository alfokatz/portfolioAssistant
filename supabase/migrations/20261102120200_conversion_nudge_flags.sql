-- Interruptores de la spec "sin callejones"
-- (docs/superpowers/specs/2026-11-02-sin-callejones.md §3.1).
-- Arrancan apagados: la app falla cerrado y todo se ve como hoy.
--   broker_screenshot_exit: salida "traela con una captura" en Binance/SnapTrade bloqueados.
--   diagnosis_bridge: filas "que se actualice sola" y "¿te aviso el sábado?" del diagnóstico.
--   quota_nudge: línea de cuota baja en el chat.
--
-- Para prender (lo hace el usuario):
--   update public.app_config
--      set value = '{"percent": 100, "users": []}'::jsonb, updated_at = now()
--    where key in ('broker_screenshot_exit', 'diagnosis_bridge', 'quota_nudge');
--
-- app_config ya tiene RLS y lectura pública (20260930130000_app_config.sql).
-- Idempotente: no pisa un valor que ya se haya prendido.

insert into public.app_config (key, value) values
  ('broker_screenshot_exit', '{"percent": 0, "users": []}'::jsonb),
  ('diagnosis_bridge',       '{"percent": 0, "users": []}'::jsonb),
  ('quota_nudge',            '{"percent": 0, "users": []}'::jsonb)
on conflict (key) do nothing;
