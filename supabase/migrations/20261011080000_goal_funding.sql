-- Metas: el progreso sale solo (2026-10-11, segunda vuelta del feedback).
--
-- En vez de un registro de aportes que el usuario tenía que cargar a mano
-- (y que podía decir "atrasada" aunque ya tuviera la plata), cada meta
-- cuenta:
--   linked_tickers    las inversiones de la cartera que son para esta meta
--                     (por defecto, las de su compra mensual); su valor de
--                     mercado actual se suma solo. Cada ticker cuenta para
--                     una sola meta (la app lo mueve si se asigna a otra).
--   external_savings  lo que tiene para la meta fuera de la app (banco,
--                     efectivo): un solo monto que actualiza cuando quiere.
--
-- goal_contributions era de la versión anterior (sin publicar): se borra.

alter table public.user_goals
  add column if not exists linked_tickers text[] not null default '{}',
  add column if not exists external_savings numeric not null default 0
    check (external_savings >= 0 and external_savings < 100000000);

drop table if exists public.goal_contributions;
