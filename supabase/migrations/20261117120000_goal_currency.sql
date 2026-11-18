-- Moneda de cada meta: "juntar $U 1.000.000 para el auto" queda en pesos.
--
-- Todo lo que el usuario carga en la meta (el monto objetivo, el aporte del
-- plan, lo que tiene fuera de la app, los aportes registrados) está en esta
-- moneda. Las inversiones asignadas se valúan en dólares y la app las
-- convierte con el tipo de cambio del día al calcular el avance.
--
-- Las metas que ya existen quedan en dólares (como se guardaban).
-- Códigos ISO 4217 de las monedas que ofrece la app (DisplayCurrency).

alter table public.user_goals
  add column if not exists currency text not null default 'USD';

alter table public.user_goals
  drop constraint if exists user_goals_currency_check;

alter table public.user_goals
  add constraint user_goals_currency_check check (
    currency in (
      'USD', 'UYU', 'ARS', 'BRL', 'MXN', 'CLP', 'COP', 'PEN',
      'EUR', 'GBP', 'CAD', 'AUD', 'CHF', 'JPY', 'INR'
    )
  );

comment on column public.user_goals.currency is
  'Moneda de los montos de la meta (ISO 4217). Las inversiones asignadas se convierten desde dólares con el tipo de cambio del día.';
