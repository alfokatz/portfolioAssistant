-- ---------------------------------------------------------------------------
-- Configuración pública de la app, leída al arrancar (sin sesión).
--
-- `min_supported_build`: build mínimo (el `+N` de pubspec) por plataforma.
-- Una versión por debajo muestra "Actualizá la app" y no deja seguir. Se
-- sube desde el SQL editor / CLI, sin publicar nada:
--
--   update public.app_config
--      set value = jsonb_set(value, '{ios}', '5'), updated_at = now()
--    where key = 'min_supported_build';
--
-- 0 = sin mínimo. Las URLs de tienda van en el mismo valor para que el
-- botón abra la ficha correcta.
-- ---------------------------------------------------------------------------

create table if not exists public.app_config (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);

alter table public.app_config enable row level security;

drop policy if exists "app_config public read" on public.app_config;
create policy "app_config public read"
  on public.app_config for select
  to anon, authenticated
  using (true);

insert into public.app_config (key, value)
values (
  'min_supported_build',
  '{"android": 0, "ios": 0, "android_store_url": null, "ios_store_url": null}'::jsonb
)
on conflict (key) do nothing;

revoke all on public.app_config from public, anon, authenticated;
grant select on public.app_config to anon, authenticated;
grant select, insert, update, delete on public.app_config to service_role;
