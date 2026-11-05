-- Interruptores de conversión al 100 % (spec 2026-11-05-diferenciacion-planes-v2 §3.1).
-- Idempotente y conserva `users` (y cualquier otra clave del valor, como
-- `reports`). Corre después de 20261105100000_app_config_history para que el
-- cambio quede en el historial.

insert into public.app_config (key, value) values
  ('market_taste',           '{"percent":100,"users":[]}'::jsonb),
  ('quota_nudge',            '{"percent":100,"users":[]}'::jsonb),
  ('diagnosis_bridge',       '{"percent":100,"users":[]}'::jsonb),
  ('broker_screenshot_exit', '{"percent":100,"users":[]}'::jsonb),
  ('weekly_report_courtesy', '{"percent":100,"users":[],"reports":3}'::jsonb)
on conflict (key) do update
  set value = case
        when jsonb_typeof(public.app_config.value) = 'object'
          then public.app_config.value || (excluded.value - 'users')
        else excluded.value
      end,
      updated_at = now();
