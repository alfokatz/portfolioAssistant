-- Metas del usuario (pestaña "Metas"): lo que quiere lograr ("MacBook M5
-- Pro", "Jubilación") con el plan de inversión que armó Porty y los aportes
-- que va registrando, para mostrar si va en camino.
--
-- - `plan` guarda los datos del plan tal como los usa la app para
--   recalcularlo (SavingsPlanInputs), la cartera sugerida y, si la armó, la
--   compra mensual (instrumentos y montos). Es un snapshot: si el usuario
--   rehace el plan en el chat, guarda una meta nueva o la reemplaza.
-- - `goal_contributions`: cada aporte que registra (desde la pantalla de la
--   meta o contándoselo a Porty).

create table if not exists public.user_goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  label text not null check (char_length(btrim(label)) between 1 and 80),
  goal_type text not null default 'other'
    check (goal_type in ('purchase', 'retirement', 'other')),
  target_amount numeric not null check (target_amount > 0),
  target_date date not null,
  plan jsonb not null check (jsonb_typeof(plan) = 'object'),
  status text not null default 'active'
    check (status in ('active', 'achieved', 'archived')),
  -- Para no guardar dos veces el mismo plan (el id estable que arma la app).
  plan_key text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists user_goals_user_idx
  on public.user_goals (user_id, created_at desc);
create unique index if not exists user_goals_plan_key_idx
  on public.user_goals (user_id, plan_key) where plan_key is not null;

create table if not exists public.goal_contributions (
  id uuid primary key default gen_random_uuid(),
  goal_id uuid not null references public.user_goals (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  amount numeric not null check (amount <> 0 and abs(amount) < 100000000),
  contributed_on date not null default current_date,
  note text check (note is null or char_length(note) <= 140),
  source text not null default 'app' check (source in ('app', 'porty')),
  created_at timestamptz not null default now()
);

create index if not exists goal_contributions_goal_idx
  on public.goal_contributions (goal_id, contributed_on);

create or replace function public.touch_user_goal_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists user_goals_touch_updated_at on public.user_goals;
create trigger user_goals_touch_updated_at
  before update on public.user_goals
  for each row
  execute function public.touch_user_goal_updated_at();

-- Tope de metas activas por usuario (las logradas/archivadas no cuentan).
create or replace function public.enforce_user_goal_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (select count(*) from public.user_goals
      where user_id = new.user_id and status = 'active') >= 20 then
    raise exception 'user_goal_limit_reached' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists user_goals_limit on public.user_goals;
create trigger user_goals_limit
  before insert on public.user_goals
  for each row
  execute function public.enforce_user_goal_limit();

alter table public.user_goals enable row level security;
alter table public.goal_contributions enable row level security;

drop policy if exists "user_goals own" on public.user_goals;
create policy "user_goals own" on public.user_goals
  for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Un aporte solo a una meta propia.
drop policy if exists "goal_contributions own" on public.goal_contributions;
create policy "goal_contributions own" on public.goal_contributions
  for all to authenticated
  using (auth.uid() = user_id)
  with check (
    auth.uid() = user_id
    and exists (
      select 1 from public.user_goals g
      where g.id = goal_id and g.user_id = auth.uid()
    )
  );
