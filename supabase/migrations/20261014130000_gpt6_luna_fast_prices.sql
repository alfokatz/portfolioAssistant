-- El proxy `ai-chat` pide gpt-6-luna con `service_tier: fast` (el doble de
-- velocidad de salida). Precios de esa tarifa por 1M tokens
-- (developers.openai.com/api/docs/pricing, 2026-10-14): input 0,20, cached
-- 0,02, output 1,00. La escritura de caché (0,25) se sigue estimando al
-- precio de input.
update public.model_prices
set input_per_mtok = 0.20,
    cached_input_per_mtok = 0.02,
    output_per_mtok = 1.00,
    updated_at = now()
where model = 'gpt-6-luna';
