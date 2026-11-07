-- GPT-6 Luna: reemplazo de gpt-4.1-mini, que OpenAI apaga el 2027-01-14
-- (https://developers.openai.com/api/docs/deprecations). El proxy `ai-chat`
-- reescribe gpt-4.1-mini a gpt-6-luna, así las versiones viejas de la app
-- siguen andando después del apagado.
--
-- Precios por 1M tokens (developers.openai.com/api/docs/models/gpt-6-luna,
-- 2026-10-14): input 0,10, cached 0,01, output 0,50. La escritura de caché
-- (0,125) no tiene columna: se estima al precio de input.
insert into public.model_prices
  (model, input_per_mtok, cached_input_per_mtok, output_per_mtok, allowed)
values
  ('gpt-6-luna', 0.10, 0.01, 0.50, true)
on conflict (model) do update set
  input_per_mtok = excluded.input_per_mtok,
  cached_input_per_mtok = excluded.cached_input_per_mtok,
  output_per_mtok = excluded.output_per_mtok,
  allowed = excluded.allowed,
  updated_at = now();
