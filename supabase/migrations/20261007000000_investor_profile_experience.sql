-- Perfil de inversor: dos preguntas opcionales más (2026-10-07).
--   experience         cuánto sabe de inversiones (ajusta el nivel de las
--                      explicaciones de Porty)
--   drawdown_reaction  qué haría si la cartera cae 20% en un mes (riesgo por
--                      comportamiento)
-- Nullable: los perfiles existentes siguen válidos y la app las trata como
-- opcionales. Las políticas RLS de investor_profiles ya cubren las columnas.

alter table public.investor_profiles
  add column if not exists experience text
    check (experience in ('beginner', 'intermediate', 'advanced')),
  add column if not exists drawdown_reaction text
    check (drawdown_reaction in ('sell', 'hold', 'buy_more'));
