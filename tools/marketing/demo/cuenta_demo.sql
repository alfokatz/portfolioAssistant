-- =====================================================================
-- Cuenta demo de Porty para grabar videos (y para la revisión de Apple, F8).
--
-- Cómo usarlo:
--   1. Supabase → Authentication → Users → "Add user" → "Create new user":
--      email (ej. demo@portyassistant.com), contraseña, y "Auto Confirm User".
--   2. Cambiá el email de abajo si usaste otro (tiene que contener "demo").
--   3. Pegá todo esto en Supabase → SQL Editor y ejecutalo.
--
-- Qué hace:
--   - Borra las posiciones manuales que tuviera ESA cuenta demo y carga una
--     cartera de ejemplo comprada en distintas fechas (2023–2025), con varias
--     compras por acción, como una cartera real.
--   - El precio de compra se calcula desde el último precio guardado en
--     market_quotes (si no hay, usa un precio de referencia) con un margen
--     chico, para que la ganancia o pérdida de cada posición quede entre
--     −8 % y +14 %, con verdes y rojos (regla de compliance para videos).
--   - Le da plan Gold manual (para ver todas las funciones en los videos y
--     para que el revisor de Apple vea todo).
--
-- La cartera está armada para los videos:
--   - Tecnología queda en ~50–55 % contando lo que hay adentro de SPY y QQQ
--     → hallazgo "Tecnología es el X% de tu cartera" en el diagnóstico.
--   - AAPL directa y también adentro de SPY y QQQ → hallazgo de solapamiento.
--   - Salud (JNJ), finanzas (JPM), consumo (KO) y bonos (BND) para que la
--     concentración por sector tenga varias partes.
--
-- Seguridad: solo toca la cuenta del email indicado y se niega a correr si
-- el email no contiene "demo" (para no borrar nunca una cuenta real).
-- =====================================================================

do $$
declare
  demo_email text := 'demo@portyassistant.com';   -- ← cambialo si hace falta
  demo_id uuid;
begin
  if position('demo' in lower(demo_email)) = 0 then
    raise exception 'El email % no parece de una cuenta demo: no hago nada.', demo_email;
  end if;

  select id into demo_id from auth.users where lower(email) = lower(demo_email);
  if demo_id is null then
    raise exception 'No existe el usuario %. Crealo primero en Authentication → Users.', demo_email;
  end if;

  -- Cartera limpia (solo las posiciones manuales de la cuenta demo).
  delete from public.positions where user_id = demo_id and source = 'manual';

  -- ticker, cantidad, fecha de compra, precio de referencia (si no hay cotización), factor
  -- factor < 1 → compró más barato (ganancia); factor > 1 → compró más caro (pérdida).
  insert into public.positions (id, user_id, ticker, quantity, purchase_price, purchase_date, source, purchase_date_known)
  select gen_random_uuid(), demo_id, l.ticker, l.qty,
         round((coalesce(q.price, l.ref_price) * l.factor)::numeric, 2),
         l.bought::timestamptz, 'manual', true
  from (values
    ('SPY',   5::numeric, '2023-03-14 15:30:00+00', 670.0, 0.88),
    ('SPY',   3::numeric, '2024-08-05 15:30:00+00', 670.0, 0.95),
    ('QQQ',   4::numeric, '2023-10-23 15:30:00+00', 600.0, 0.90),
    ('QQQ',   2::numeric, '2025-04-09 15:30:00+00', 600.0, 1.04),
    ('AAPL', 10::numeric, '2023-06-12 15:30:00+00', 260.0, 0.92),
    ('AAPL',  5::numeric, '2024-11-18 15:30:00+00', 260.0, 1.06),
    ('MSFT',  6::numeric, '2024-02-20 15:30:00+00', 510.0, 1.08),
    ('NVDA', 15::numeric, '2024-09-09 15:30:00+00', 185.0, 0.89),
    ('JNJ',   8::numeric, '2024-05-15 15:30:00+00', 190.0, 1.05),
    ('JPM',   6::numeric, '2025-01-27 15:30:00+00', 300.0, 0.93),
    ('KO',   20::numeric, '2023-09-05 15:30:00+00',  70.0, 1.03),
    ('BND',  10::numeric, '2025-06-02 15:30:00+00',  74.0, 1.01)
  ) as l(ticker, qty, bought, ref_price, factor)
  left join public.market_quotes q on q.symbol = l.ticker;

  -- Plan Gold manual para la cuenta demo.
  insert into public.user_subscriptions (user_id, tier, provider, status, current_period_end, updated_at)
  values (demo_id, 'gold', 'manual', 'active', '2027-12-31 23:59:59+00', now())
  on conflict (user_id) do update
    set tier = 'gold', provider = 'manual', status = 'active',
        current_period_end = '2027-12-31 23:59:59+00', updated_at = now();

  raise notice 'Cuenta demo % lista: % posiciones, plan Gold.', demo_email,
    (select count(*) from public.positions where user_id = demo_id);
end $$;

-- Para revisar la cartera cargada (opcional):
-- select ticker, quantity, purchase_price, purchase_date::date
-- from public.positions p join auth.users u on u.id = p.user_id
-- where lower(u.email) = 'demo@portyassistant.com' order by ticker, purchase_date;
