-- Memoria de Porty (docs/superpowers/plans/2026-10-11-personalizacion-porty.md).
--
-- Lo que Porty va aprendiendo del usuario en el chat ("quiere comprarse una
-- MacBook Neo rosa", "ahorra 200 USD por mes", "prefiere ETFs"): una fila
-- por dato. Las escribe Porty (tool `remember_about_user`) o el usuario
-- desde Ajustes → "Lo que Porty sabe de vos", donde también las borra.
-- Viajan en el contexto de cada turno para personalizar las respuestas.

create table if not exists public.user_memories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  category text not null default 'other'
    check (category in ('goal', 'finances', 'life', 'preference', 'other')),
  content text not null check (char_length(btrim(content)) between 1 and 280),
  source text not null default 'porty' check (source in ('porty', 'user')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists user_memories_user_idx
  on public.user_memories (user_id, updated_at desc);

-- updated_at lo fija el servidor (igual que investor_profiles).
create or replace function public.touch_user_memory_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists user_memories_touch_updated_at on public.user_memories;
create trigger user_memories_touch_updated_at
  before update on public.user_memories
  for each row
  execute function public.touch_user_memory_updated_at();

-- Tope por usuario: el contexto de cada turno no puede crecer sin límite.
-- La app recibe `user_memory_limit_reached` y Porty sugiere borrar algo.
create or replace function public.enforce_user_memory_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (select count(*) from public.user_memories where user_id = new.user_id) >= 60 then
    raise exception 'user_memory_limit_reached' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists user_memories_limit on public.user_memories;
create trigger user_memories_limit
  before insert on public.user_memories
  for each row
  execute function public.enforce_user_memory_limit();

alter table public.user_memories enable row level security;

drop policy if exists "user_memories own" on public.user_memories;
create policy "user_memories own" on public.user_memories
  for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
