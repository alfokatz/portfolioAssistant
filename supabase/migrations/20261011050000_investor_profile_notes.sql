-- Perfil de inversor: texto libre por pregunta (2026-10-11).
--   notes  {"objective": "...", "horizon": "...", "experience": "..."}
--          lo que el usuario quiso contarle a Porty además de la opción
--          elegida ("quiero comprarme una compu el año que viene").
-- Nullable: los perfiles existentes siguen válidos. Las políticas RLS de
-- investor_profiles ya cubren la columna.

alter table public.investor_profiles
  add column if not exists notes jsonb
    check (notes is null or jsonb_typeof(notes) = 'object');
