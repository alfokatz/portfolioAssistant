-- Memoria de conversaciones de Porty (fase 4 de
-- docs/superpowers/plans/2026-10-24-porty-en-toda-la-app.md): de qué tickers
-- le habló el usuario, cuándo y a qué precio estaban. La arma la app con las
-- tools de cada turno (sin modelo): Porty retoma el tema ("la última vez que
-- me preguntaste por AMZN estaba a $182") y la bandeja avisa si algo se
-- movió fuerte desde entonces.
--
-- Una fila por usuario y ticker (la última vez que se habló de él); hasta 50
-- por usuario, se van las más viejas. El usuario las ve y las borra en
-- "Lo que Porty sabe de vos".

create table if not exists public.porty_topics (
  user_id uuid not null references auth.users (id) on delete cascade,
  ticker text not null check (ticker ~ '^[A-Z0-9.^=-]{1,15}$'),
  -- La pregunta tal como la escribió, recortada.
  question text not null check (char_length(question) between 1 and 200),
  -- Precio del ticker ese día (de get_quote); null si no se trajo.
  price_at numeric check (price_at is null or price_at > 0),
  held boolean not null default false,
  first_asked_at timestamptz not null default clock_timestamp(),
  last_asked_at timestamptz not null default clock_timestamp(),
  times int not null default 1 check (times >= 1),
  primary key (user_id, ticker)
);

create index if not exists porty_topics_recent_idx
  on public.porty_topics (user_id, last_asked_at desc);

alter table public.porty_topics enable row level security;

drop policy if exists "porty_topics own read" on public.porty_topics;
create policy "porty_topics own read" on public.porty_topics
  for select to authenticated using (user_id = auth.uid());

drop policy if exists "porty_topics own delete" on public.porty_topics;
create policy "porty_topics own delete" on public.porty_topics
  for delete to authenticated using (user_id = auth.uid());

grant select, delete on public.porty_topics to authenticated;

-- Registra los tickers de un turno: [{ticker, question, price_at, held}].
-- Si ya estaba, actualiza la pregunta, el precio y la fecha y suma una vez.
-- Devuelve cuántos registró. Solo para el usuario de la sesión.
create or replace function public.porty_topics_touch(p_topics jsonb)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_count int := 0;
  t jsonb;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if jsonb_typeof(p_topics) <> 'array' then
    return 0;
  end if;
  for t in select * from jsonb_array_elements(p_topics) limit 5 loop
    begin
      insert into public.porty_topics as pt
        (user_id, ticker, question, price_at, held)
      values (
        v_user,
        upper(t ->> 'ticker'),
        left(coalesce(nullif(trim(t ->> 'question'), ''), upper(t ->> 'ticker')), 200),
        nullif(t ->> 'price_at', '')::numeric,
        coalesce((t ->> 'held')::boolean, false)
      )
      on conflict (user_id, ticker) do update
        set question = excluded.question,
            price_at = coalesce(excluded.price_at, pt.price_at),
            held = excluded.held,
            -- clock_timestamp y no now(): dentro de una transacción now() es
            -- el mismo para todos y no se sabría cuál es el más reciente.
            last_asked_at = clock_timestamp(),
            times = pt.times + 1;
      v_count := v_count + 1;
    exception when check_violation or invalid_text_representation then
      -- Un ticker raro no corta los demás.
      null;
    end;
  end loop;

  delete from public.porty_topics
   where user_id = v_user
     and ticker in (
       select ticker from public.porty_topics
        where user_id = v_user
        order by last_asked_at desc
        offset 50
     );
  return v_count;
end;
$$;

revoke all on function public.porty_topics_touch(jsonb) from public, anon;
grant execute on function public.porty_topics_touch(jsonb) to authenticated;
