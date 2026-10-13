-- Test de la migración 20261013000000_landing_waitlist.sql (landing de
-- validación, repo porty-web).
--
-- Corre contra una base con la migración aplicada (supabase start, o un
-- Postgres con los roles anon/authenticated/service_role). Cada chequeo que
-- falla corta con una excepción; si termina, imprime LANDING_DB_TEST_OK.
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/landing_db_test.sql
--
-- Todo corre dentro de una transacción que se deshace al final.

begin;

delete from public.landing_events;
delete from public.waitlist;
delete from public.landing_rate_limits;

-- ── El cliente anónimo no ve ni toca nada ─────────────────────────────────
set local role anon;

do $$
begin
  begin
    perform 1 from public.waitlist;
    raise exception 'RLS: anon pudo leer waitlist';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.waitlist (email, variant, ref_code, consent)
    values ('x@y.com', 'a', 'ABCDEF', true);
    raise exception 'RLS: anon pudo escribir waitlist';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.landing_events (anon_id, event) values ('anon-0001', 'page_view');
    raise exception 'RLS: anon pudo escribir landing_events';
  exception when insufficient_privilege then null;
  end;
  begin
    perform 1 from public.landing_stats;
    raise exception 'RLS: anon pudo leer landing_stats';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.landing_signup('x@y.com', 'a');
    raise exception 'RLS: anon pudo llamar landing_signup';
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;
set local role authenticated;

do $$
begin
  begin
    perform 1 from public.waitlist;
    raise exception 'RLS: authenticated pudo leer waitlist';
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;

-- ── Altas (como la edge function) ─────────────────────────────────────────
set local role service_role;

create temp table r (k text primary key, v jsonb) on commit drop;

insert into r values ('ana', public.landing_signup(
  '  Ana@Example.COM ', 'b', null,
  '{"utm_source":"tiktok","utm_medium":"organic","utm_campaign":"lanzamiento","utm_content":"reel1"}',
  null, 'AR', 'anon-ana-0001', '/'));

do $$
declare
  w public.waitlist;
  res jsonb := (select v from r where k = 'ana');
begin
  select * into w from public.waitlist where email = 'ana@example.com';
  if not found then raise exception 'signup: no creó la fila (o no pasó el email a minúsculas)'; end if;
  if w.variant <> 'b' or w.utm_source <> 'tiktok' or w.utm_content <> 'reel1' or w.country <> 'AR' then
    raise exception 'signup: no guardó variante, UTM o país: %', row_to_json(w);
  end if;
  if not w.consent or w.intended_plan is not null then
    raise exception 'signup: consent/intended_plan mal';
  end if;
  if (res ->> 'position')::bigint <> w.position or res ->> 'ref_code' <> w.ref_code
     or (res ->> 'created')::boolean is not true then
    raise exception 'signup: respuesta inesperada %', res;
  end if;
  if w.ref_code !~ '^[A-Z2-9]{6}$' then raise exception 'signup: ref_code inválido %', w.ref_code; end if;
end $$;

-- Mismo email: no duplica, devuelve el mismo puesto.
insert into r values ('ana2', public.landing_signup(
  'ana@example.com', 'c', null, '{}', null, null, 'anon-ana-0002', '/'));

do $$
begin
  if (select count(*) from public.waitlist where email = 'ana@example.com') <> 1 then
    raise exception 'repetido: duplicó la fila';
  end if;
  if (select v ->> 'position' from r where k = 'ana2') <> (select v ->> 'position' from r where k = 'ana')
     or (select v ->> 'ref_code' from r where k = 'ana2') <> (select v ->> 'ref_code' from r where k = 'ana') then
    raise exception 'repetido: cambió el puesto o el código';
  end if;
  if (select (v ->> 'created')::boolean from r where k = 'ana2') then
    raise exception 'repetido: dijo created=true';
  end if;
  if (select variant from public.waitlist where email = 'ana@example.com') <> 'b' then
    raise exception 'repetido: pisó la variante original';
  end if;
end $$;

-- Referido + precio fundador: Beto llega con el código de Ana desde /precios.
insert into r values ('beto', public.landing_signup(
  'beto@example.com', 'a', 'gold', '{"utm_source":"meta"}',
  lower((select v ->> 'ref_code' from r where k = 'ana')), 'UY', 'anon-beto-0001', '/precios'));

-- Un código que no existe no se guarda.
insert into r values ('caro', public.landing_signup(
  'caro@example.com', 'a', null, '{}', 'ZZZZZZ', null, 'anon-caro-0001', '/'));

-- Ana vuelve desde el modal y elige Premium: se actualiza el plan.
insert into r values ('ana3', public.landing_signup(
  'ana@example.com', 'b', 'premium', '{}', null, null, 'anon-ana-0001', '/precios'));

do $$
begin
  if (select referred_by from public.waitlist where email = 'beto@example.com')
     <> (select ref_code from public.waitlist where email = 'ana@example.com') then
    raise exception 'referido: no guardó referred_by';
  end if;
  if (select intended_plan from public.waitlist where email = 'beto@example.com') <> 'gold' then
    raise exception 'fundador: no guardó intended_plan en el alta';
  end if;
  if (select referred_by from public.waitlist where email = 'caro@example.com') is not null then
    raise exception 'referido: guardó un código inexistente';
  end if;
  if (select intended_plan from public.waitlist where email = 'ana@example.com') <> 'premium' then
    raise exception 'fundador: no actualizó intended_plan de un email existente';
  end if;
  if (select (v ->> 'position')::bigint from r where k = 'beto')
     <= (select (v ->> 'position')::bigint from r where k = 'ana') then
    raise exception 'orden: el puesto no respeta el orden de llegada';
  end if;
  -- Un email repetido no consume número: Beto quedó justo después de Ana.
  if (select (v ->> 'position')::bigint from r where k = 'beto')
     <> (select (v ->> 'position')::bigint from r where k = 'ana') + 1 then
    raise exception 'orden: el email repetido dejó un hueco';
  end if;
end $$;

-- ── Rate limit ────────────────────────────────────────────────────────────
do $$
begin
  if not public.landing_rate_hit('hash-1', 'signup', 2) then raise exception 'rate: 1º rechazado'; end if;
  if not public.landing_rate_hit('hash-1', 'signup', 2) then raise exception 'rate: 2º rechazado'; end if;
  if public.landing_rate_hit('hash-1', 'signup', 2) then raise exception 'rate: 3º aceptado'; end if;
  if not public.landing_rate_hit('hash-2', 'signup', 2) then raise exception 'rate: otra IP rechazada'; end if;
end $$;

-- ── Métricas ──────────────────────────────────────────────────────────────
-- Visitas: 4 en A (una repetida), 2 en B, 1 en C.
insert into public.landing_events (anon_id, variant, event, path) values
  ('anon-beto-0001', 'a', 'page_view', '/'),
  ('anon-beto-0001', 'a', 'page_view', '/precios'),
  ('anon-caro-0001', 'a', 'page_view', '/'),
  ('anon-dani-0001', 'a', 'page_view', '/'),
  ('anon-eli0-0001', 'a', 'page_view', '/'),
  ('anon-ana-0001', 'b', 'page_view', '/'),
  ('anon-fer0-0001', 'b', 'page_view', '/'),
  ('anon-gus0-0001', 'c', 'page_view', '/');
insert into public.landing_events (anon_id, variant, event, plan, path) values
  ('anon-beto-0001', 'a', 'plan_click', 'gold', '/precios'),
  ('anon-ana-0001', 'b', 'plan_click', 'premium', '/precios');

do $$
declare
  s record;
begin
  select * into s from public.landing_stats where day is null and variant = 'a';
  if s.unique_visitors <> 4 or s.signups <> 2 or s.conversion_rate <> 0.5 then
    raise exception 'stats A acumulado: %', row_to_json(s);
  end if;
  if s.clicks_gold <> 1 or s.founder_signups <> 1 or s.founder_signups_gold <> 1 then
    raise exception 'stats A planes: %', row_to_json(s);
  end if;

  select * into s from public.landing_stats where day is null and variant = 'b';
  if s.unique_visitors <> 2 or s.signups <> 1 or s.conversion_rate <> 0.5
     or s.clicks_premium <> 1 or s.founder_signups_premium <> 1 then
    raise exception 'stats B acumulado: %', row_to_json(s);
  end if;

  select * into s from public.landing_stats where day is null and variant = 'c';
  if s.unique_visitors <> 1 or s.signups <> 0 or s.conversion_rate <> 0 then
    raise exception 'stats C acumulado: %', row_to_json(s);
  end if;

  select * into s from public.landing_stats
  where day = (now() at time zone 'America/Argentina/Buenos_Aires')::date and variant = 'a';
  if s.unique_visitors <> 4 then raise exception 'stats A por día: %', row_to_json(s); end if;
end $$;

reset role;

select 'LANDING_DB_TEST_OK';

rollback;
