-- eToro: la vinculación se completa desde la app (auditoría de seguridad
-- 2026-11-05).
--
-- Antes, el callback OAuth (GET desde el navegador, sin JWT) cambiaba el
-- código por tokens e importaba la cartera al usuario dueño del `state`.
-- Quien completara la URL de autorización —no necesariamente quien la
-- generó— le vinculaba su cuenta de eToro a ese usuario. Ahora el callback
-- solo guarda el código y el hash de un handle de un solo uso que viaja en
-- el deep link; la app termina con POST /connect/complete y su JWT, y la
-- función exige que sea el mismo usuario que inició el flujo.

alter table public.etoro_oauth_states
  add column if not exists auth_code text,
  add column if not exists completion_hash text,
  add column if not exists returned_at timestamptz;

create unique index if not exists etoro_oauth_states_completion_hash_idx
  on public.etoro_oauth_states (completion_hash)
  where completion_hash is not null;

-- La tabla ya es solo de la service role (RLS sin policies y sin permisos
-- para anon/authenticated, migración 20261009000000): las columnas nuevas
-- heredan eso. Se repite el revoke por si un entorno quedó distinto.
revoke all on public.etoro_oauth_states from anon, authenticated;
