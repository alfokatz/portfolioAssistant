-- Interruptor de la respuesta en streaming de Porty: el texto aparece
-- mientras se escribe; las cards con datos, con la respuesta completa y
-- validada (ver docs/superpowers/research/2026-10-15-porty-latencia.md).
-- Lo lee la app (`PortyStreamingConfig`), cada 10 minutos.
--
--   users:   ids de usuario que lo tienen siempre (para probarlo antes);
--   percent: 0-100, qué parte del resto lo tiene (estable por usuario).
--
-- Probarlo con un usuario:
--   update public.app_config
--      set value = jsonb_set(value, '{users}', (value->'users') || '"<uuid>"'),
--          updated_at = now()
--    where key = 'porty_streaming';
-- Abrirlo a un 10 % (y volver con 0):
--   update public.app_config
--      set value = jsonb_set(value, '{percent}', '10'), updated_at = now()
--    where key = 'porty_streaming';
insert into public.app_config (key, value)
values ('porty_streaming', '{"percent": 0, "users": []}'::jsonb)
on conflict (key) do nothing;
