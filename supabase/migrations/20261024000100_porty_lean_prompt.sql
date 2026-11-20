-- Interruptor del prompt lean de Porty (`PromptVariant.lean`): lo que cada
-- área solo necesita después de traer sus datos (reglas de respuesta y
-- esquemas de sus widgets) viaja con el resultado de la tool (`area_spec`)
-- en vez de en el prefijo fijo de cada pedido (ver
-- docs/superpowers/research/2026-10-24-porty-escalable.md). Lo lee la app
-- (`PortyRolloutFlag.leanPrompt`) cada 10 minutos y se decide al abrir el
-- chat. Arranca apagado: prenderlo después de medirlo con evals.
--
-- Antes de prenderlo, `ai-chat` tiene que estar desplegado con el hash del
-- prompt lean en allowed_system_prompts.json.
--
--   users:   ids de usuario que lo tienen siempre (para probarlo antes);
--   percent: 0-100, qué parte del resto lo tiene (estable por usuario).
--
-- Probarlo con un usuario:
--   update public.app_config
--      set value = jsonb_set(value, '{users}', (value->'users') || '"<uuid>"'),
--          updated_at = now()
--    where key = 'porty_lean_prompt';
insert into public.app_config (key, value)
values ('porty_lean_prompt', '{"percent": 0, "users": []}'::jsonb)
on conflict (key) do nothing;
