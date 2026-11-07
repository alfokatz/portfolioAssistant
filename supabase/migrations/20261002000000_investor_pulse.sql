-- Informe semanal de Porty: "qué dicen los super investors" (F2 del plan
-- docs/superpowers/plans/2026-10-01-informe-semanal-porty.md).
--
-- La lista de inversores es de negocio, no de código: se edita en esta
-- tabla (activar, desactivar, sumar) sin publicar otra versión de la app.
-- El resumen de cada semana es el mismo para todos los usuarios, así que se
-- calcula una vez y se cachea por semana.

create table if not exists public.super_investors (
  id text primary key,
  -- Lo que muestra la app ("Warren Buffett", "Presidente de la Fed").
  display_name text not null,
  organization text,
  -- 'investor' = super investor; 'market_voice' = voces del mercado
  -- (banqueros, la Fed…), que la app etiqueta aparte.
  kind text not null check (kind in ('investor', 'market_voice')),
  -- Cómo se busca en las noticias: cada término va entre comillas y unido
  -- con OR, y el titular tiene que contener alguno (nombre completo, nunca
  -- un apellido suelto: "Marks", "Wood" o "Smith" traen cualquier cosa).
  search_terms text[] not null check (cardinality(search_terms) > 0),
  -- CIKs de EDGAR (sin ceros a la izquierda) de las entidades que presentan
  -- por él: 13F, Form 4, Schedule 13D/G. Vacío = solo noticias.
  ciks text[] not null default '{}',
  active boolean not null default true,
  sort smallint not null default 100,
  updated_at timestamptz not null default now()
);

alter table public.super_investors enable row level security;
-- Sin policies: la lee solo la edge function investor-pulse.

create table if not exists public.investor_pulse_cache (
  -- Lunes de la semana bursátil cubierta.
  week_start date primary key
    check (extract(isodow from week_start) = 1),
  items jsonb not null,
  fetched_at timestamptz not null default now()
);

alter table public.investor_pulse_cache enable row level security;
-- Sin policies: solo la service role.

grant select on public.super_investors to service_role;
grant select, insert, update, delete on public.investor_pulse_cache
  to service_role;

-- CIKs verificados contra data.sec.gov/submissions el 2026-10-02 (nombre de
-- la entidad y último 13F). Scion (Burry) dejó de presentar 13F en
-- nov-2025: queda solo con noticias. Para Icahn va el CIK personal (Icahn
-- Enterprises también es emisora y sus Form 4 son de sus propios insiders).
insert into public.super_investors
  (id, display_name, organization, kind, search_terms, ciks, sort)
values
  ('warren-buffett', 'Warren Buffett', 'Berkshire Hathaway', 'investor',
    array['Warren Buffett', 'Greg Abel', 'Berkshire Hathaway'], array['1067983'], 10),
  ('bill-ackman', 'Bill Ackman', 'Pershing Square', 'investor',
    array['Bill Ackman', 'Pershing Square'], array['1336528'], 20),
  ('michael-burry', 'Michael Burry', 'Scion', 'investor',
    array['Michael Burry'], array[]::text[], 30),
  ('ray-dalio', 'Ray Dalio', 'Bridgewater', 'investor',
    array['Ray Dalio', 'Bridgewater Associates'], array['1350694'], 40),
  ('stanley-druckenmiller', 'Stanley Druckenmiller', 'Duquesne Family Office', 'investor',
    array['Stanley Druckenmiller', 'Druckenmiller'], array['1536411'], 50),
  ('howard-marks', 'Howard Marks', 'Oaktree', 'investor',
    array['Howard Marks', 'Oaktree Capital'], array['949509'], 60),
  ('cathie-wood', 'Cathie Wood', 'ARK Invest', 'investor',
    array['Cathie Wood', 'ARK Invest'], array['1697748'], 70),
  ('david-tepper', 'David Tepper', 'Appaloosa', 'investor',
    array['David Tepper', 'Appaloosa Management'], array['1656456'], 80),
  ('carl-icahn', 'Carl Icahn', 'Icahn Enterprises', 'investor',
    array['Carl Icahn', 'Icahn Enterprises'], array['921669'], 90),
  ('seth-klarman', 'Seth Klarman', 'Baupost', 'investor',
    array['Seth Klarman', 'Baupost'], array['1061768'], 100),
  ('jeremy-grantham', 'Jeremy Grantham', 'GMO', 'investor',
    array['Jeremy Grantham'], array['1352662'], 110),
  ('terry-smith', 'Terry Smith', 'Fundsmith', 'investor',
    array['Terry Smith', 'Fundsmith'], array['1569205'], 120),
  ('li-lu', 'Li Lu', 'Himalaya Capital', 'investor',
    array['Li Lu', 'Himalaya Capital'], array['1709323'], 130),
  ('mohnish-pabrai', 'Mohnish Pabrai', 'Pabrai Investment Funds', 'investor',
    array['Mohnish Pabrai', 'Pabrai'], array['1549575'], 140),
  ('bill-gross', 'Bill Gross', null, 'investor',
    array['Bill Gross'], array[]::text[], 150),
  -- Voces del mercado: por rol cuando la persona cambia (la presidencia de
  -- la Fed), por nombre cuando no.
  ('fed-chair', 'Presidente de la Fed', 'Reserva Federal', 'market_voice',
    array['Fed Chair', 'Fed chairman', 'Federal Reserve Chair'], array[]::text[], 200),
  ('jamie-dimon', 'Jamie Dimon', 'JPMorgan Chase', 'market_voice',
    array['Jamie Dimon'], array[]::text[], 210),
  ('larry-fink', 'Larry Fink', 'BlackRock', 'market_voice',
    array['Larry Fink'], array[]::text[], 220),
  ('mohamed-el-erian', 'Mohamed El-Erian', null, 'market_voice',
    array['Mohamed El-Erian', 'El-Erian'], array[]::text[], 230)
on conflict (id) do nothing;
