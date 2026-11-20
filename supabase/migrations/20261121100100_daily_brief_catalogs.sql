-- Brief diario de tu cartera: semillas de los catálogos
-- (docs/superpowers/specs/2026-11-20-brief-diario-tech.md §3.2).
-- Requiere 20261121100000_daily_brief.sql.
--
-- Todo con `on conflict do nothing`: correr dos veces no cambia nada.
--
-- Medios y fuentes oficiales NUEVOS entran con `enabled = false`: la lista
-- final sale de la medición de cobertura (`scripts/news_coverage.ts`) y la
-- aprueba compliance (spec §11, P8). Hasta entonces `news-context` y
-- `headlines` siguen citando exactamente los mismos medios que hoy. Para
-- habilitar los que se aprueben:
--   update public.news_source_allowlist set enabled = true
--    where domain in ('...');
--
-- `video_channel_allowlist` queda vacía: el `channel_id` y la lista de
-- subidas de cada canal se resuelven con `channels.list` (YouTube Data API,
-- requiere YOUTUBE_API_KEY, spec §11 P1). No se inventan IDs.

-- ---------------------------------------------------------------------------
-- Medios que ya están: región y prioridad en la consulta de GDELT
-- ---------------------------------------------------------------------------

-- Los que GDELT indexa bien (los de `gdeltConfig.queryDomains`), en el mismo
-- orden de preferencia. Solo se completa lo que está sin definir.
update public.news_source_allowlist set gdelt_priority = v.p
  from (values
    ('reuters.com', 1), ('apnews.com', 2), ('cnbc.com', 3), ('marketwatch.com', 4),
    ('forbes.com', 5), ('businessinsider.com', 6), ('infobae.com', 7)
  ) as v(d, p)
 where news_source_allowlist.domain = v.d and news_source_allowlist.gdelt_priority is null;

update public.news_source_allowlist set region = 'us'
 where region = 'global'
   and domain in ('cnbc.com', 'marketwatch.com', 'barrons.com', 'finance.yahoo.com',
                  'investing.com', 'nytimes.com', 'forbes.com', 'fortune.com',
                  'businessinsider.com', 'axios.com', 'wsj.com', 'cnn.com',
                  'washingtonpost.com', 'latimes.com', 'seekingalpha.com',
                  'investors.com', 'thestreet.com', 'morningstar.com');

update public.news_source_allowlist set region = 'eu'
 where region = 'global'
   and domain in ('ft.com', 'bbc.com', 'economist.com', 'theguardian.com',
                  'expansion.com', 'eleconomista.es', 'cincodias.elpais.com', 'elpais.com');

update public.news_source_allowlist set region = 'latam'
 where region = 'global'
   and domain in ('ambito.com', 'infobae.com', 'lanacion.com.ar', 'cronista.com',
                  'iproup.com', 'clarin.com', 'eleconomista.com.mx', 'bloomberglinea.com',
                  'elfinanciero.com.mx', 'expansion.mx', 'eleconomista.com.ar');

-- ---------------------------------------------------------------------------
-- Medios globales nuevos y fuentes oficiales (deshabilitados hasta compliance)
-- ---------------------------------------------------------------------------

insert into public.news_source_allowlist (domain, name, lang, region, kind, gdelt_priority, enabled) values
  ('asia.nikkei.com', 'Nikkei Asia', 'en', 'asia', 'media', null, false),
  ('scmp.com', 'South China Morning Post', 'en', 'asia', 'media', null, false),
  ('economictimes.indiatimes.com', 'The Economic Times', 'en', 'asia', 'media', null, false),
  ('livemint.com', 'Mint', 'en', 'asia', 'media', null, false),
  ('business-standard.com', 'Business Standard', 'en', 'asia', 'media', null, false),
  ('theglobeandmail.com', 'The Globe and Mail', 'en', 'us', 'media', null, false),
  ('financialpost.com', 'Financial Post', 'en', 'us', 'media', null, false),
  ('afr.com', 'Australian Financial Review', 'en', 'asia', 'media', null, false),
  ('straitstimes.com', 'The Straits Times', 'en', 'asia', 'media', null, false),
  ('dw.com', 'DW', 'en', 'eu', 'media', null, false),
  ('france24.com', 'France 24', 'en', 'eu', 'media', null, false),
  ('euronews.com', 'Euronews', 'en', 'eu', 'media', null, false),
  ('aljazeera.com', 'Al Jazeera', 'en', 'global', 'media', null, false),
  ('caixinglobal.com', 'Caixin Global', 'en', 'asia', 'media', null, false),
  ('portafolio.co', 'Portafolio', 'es', 'latam', 'media', null, false),
  ('larepublica.co', 'La República', 'es', 'latam', 'media', null, false),
  ('gestion.pe', 'Gestión', 'es', 'latam', 'media', null, false),
  ('df.cl', 'Diario Financiero', 'es', 'latam', 'media', null, false),
  ('elconfidencial.com', 'El Confidencial', 'es', 'eu', 'media', null, false),
  ('europapress.es', 'Europa Press', 'es', 'eu', 'media', null, false),
  ('federalreserve.gov', 'Federal Reserve', 'en', 'us', 'official', null, false),
  ('ecb.europa.eu', 'European Central Bank', 'en', 'eu', 'official', null, false),
  ('bankofengland.co.uk', 'Bank of England', 'en', 'eu', 'official', null, false),
  ('boj.or.jp', 'Bank of Japan', 'en', 'asia', 'official', null, false),
  ('bls.gov', 'U.S. Bureau of Labor Statistics', 'en', 'us', 'official', null, false),
  ('bea.gov', 'U.S. Bureau of Economic Analysis', 'en', 'us', 'official', null, false),
  ('imf.org', 'International Monetary Fund', 'en', 'global', 'official', null, false),
  ('bcra.gob.ar', 'BCRA', 'es', 'latam', 'official', null, false),
  ('indec.gob.ar', 'INDEC', 'es', 'latam', 'official', null, false),
  ('cnv.gov.ar', 'CNV', 'es', 'latam', 'official', null, false)
on conflict (domain) do nothing;

-- ---------------------------------------------------------------------------
-- Temas (catálogo cerrado)
-- ---------------------------------------------------------------------------

insert into public.news_topics
  (id, kind, label_es, label_en, query_en, query_es, keywords,
   auto_markets, auto_asset_classes, asset_link_es, asset_link_en,
   default_global, region, sort)
values
  -- Globales por defecto
  ('fed_rates', 'macro', 'Fed y tasas', 'Fed and rates',
   'Federal Reserve interest rate decision and outlook',
   'Reserva Federal decisión y perspectiva de tasas de interés',
   '{fed,federal reserve,fomc,powell,tasas,interest rate}',
   '{}', '{}', null, null, true, 'us', 10),
  ('inflation', 'macro', 'Inflación', 'Inflation',
   'inflation data CPI consumer prices',
   'datos de inflación precios al consumidor IPC',
   '{inflation,inflación,cpi,ipc,precios}',
   '{}', '{}', null, null, true, 'global', 20),
  ('earnings_season', 'macro', 'Temporada de resultados', 'Earnings season',
   'quarterly earnings season results companies',
   'temporada de balances resultados trimestrales de empresas',
   '{earnings,resultados,balances,guidance,quarterly}',
   '{}', '{}', null, null, true, 'global', 30),
  ('oil_energy', 'macro', 'Petróleo y energía', 'Oil and energy',
   'oil prices and energy markets',
   'precio del petróleo y mercados de energía',
   '{oil,crude,opec,petróleo,petroleo,energía,energy,brent}',
   '{}', '{}', null, null, true, 'global', 40),
  ('global_indices', 'market', 'Mercados del mundo', 'World markets',
   'global stock markets major indices',
   'mercados bursátiles del mundo principales índices',
   '{stocks,stock market,wall street,bolsa,índices,indices,s&p 500,nasdaq}',
   '{}', '{}', null, null, true, 'global', 50),
  -- Según la cartera
  ('ecb_rates', 'macro', 'BCE y tasas en Europa', 'ECB and euro-area rates',
   'European Central Bank rate decision euro area economy',
   'Banco Central Europeo decisión de tasas y economía de la eurozona',
   '{ecb,bce,lagarde,eurozone,eurozona,euro}',
   '{.MC,.PA,.DE,.MI,.AS,.BR,.LS,.VI,.HE,.AT,.IR}', '{}', null, null, false, 'eu', 60),
  ('boe_rates', 'macro', 'Banco de Inglaterra', 'Bank of England',
   'Bank of England interest rate decision UK economy',
   'Banco de Inglaterra decisión de tasas y economía del Reino Unido',
   '{bank of england,boe,uk,reino unido,sterling,libra}',
   '{.L}', '{}', null, null, false, 'eu', 70),
  ('boj_rates', 'macro', 'Banco de Japón', 'Bank of Japan',
   'Bank of Japan monetary policy yen',
   'Banco de Japón política monetaria y yen',
   '{bank of japan,boj,yen,japan,japón,japon,nikkei}',
   '{.T}', '{}', null, null, false, 'asia', 80),
  ('china_economy', 'region', 'Economía de China', 'China economy',
   'China economy markets and policy',
   'economía de China mercados y política económica',
   '{china,beijing,pekín,pekin,yuan,hang seng}',
   '{.HK,.SS,.SZ}', '{}', null, null, false, 'asia', 90),
  ('crypto', 'asset', 'Criptomonedas', 'Crypto',
   'bitcoin and cryptocurrency markets',
   'bitcoin y mercado de criptomonedas',
   '{bitcoin,crypto,cripto,ethereum,btc}',
   '{}', '{crypto}',
   'tenés criptomonedas, que se mueven con este tipo de noticias',
   'you hold crypto, which moves with this kind of news',
   false, 'global', 100),
  ('bonds_rates', 'asset', 'Bonos y tasas', 'Bonds and yields',
   'government bond yields and fixed income markets',
   'rendimientos de bonos soberanos y renta fija',
   '{bonds,bonos,yield,rendimiento,treasury,tesoro,renta fija}',
   '{}', '{bond}',
   'tenés bonos o ETF de renta fija, que se mueven con las tasas',
   'you hold bonds or fixed-income ETFs, which move with rates',
   false, 'global', 110),
  ('tech_ai', 'sector', 'Tecnología e IA', 'Tech and AI',
   'technology sector and artificial intelligence companies',
   'sector tecnológico e inteligencia artificial empresas',
   '{ai,artificial intelligence,inteligencia artificial,chips,semiconductors,semiconductores,tech}',
   '{}', '{}', null, null, false, 'global', 120),
  ('latam_markets', 'region', 'Mercados de Latinoamérica', 'Latin American markets',
   'Latin America markets economy and currencies',
   'mercados de Latinoamérica economía y monedas',
   '{latam,latinoamérica,latinoamerica,latin america,brasil,méxico,mexico}',
   '{.BA,.SA,.MX}', '{}', null, null, false, 'latam', 130),
  ('emerging_markets', 'region', 'Mercados emergentes', 'Emerging markets',
   'emerging markets economy and flows',
   'mercados emergentes economía y flujos de capital',
   '{emerging markets,mercados emergentes,emergentes,emerging}',
   '{.SA,.MX,.HK}', '{}', null, null, false, 'global', 140),
  ('ar_bcra_dollar', 'macro', 'Dólar y BCRA', 'Dollar and BCRA (Argentina)',
   'Argentina central bank BCRA dollar exchange rate',
   'BCRA dólar tipo de cambio y reservas en Argentina',
   '{bcra,dólar,dolar,reservas,cepo,brecha}',
   '{.BA}', '{}', null, null, false, 'latam', 150),
  ('ar_country_risk_cer', 'macro', 'Riesgo país y bonos en pesos', 'Argentina country risk and peso bonds',
   'Argentina country risk sovereign bonds and CER inflation-linked bonds',
   'riesgo país bonos soberanos argentinos y bonos CER',
   '{riesgo país,riesgo pais,country risk,bonares,globales,cer}',
   '{.BA}', '{}', null, null, false, 'latam', 160)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Instrumentos de referencia de "Mercado hoy" (orden fijo por `sort`)
-- ---------------------------------------------------------------------------

insert into public.market_reference_instruments
  (symbol, kind, region, label_es, label_en, markets, core, sort)
values
  -- Core: se muestran siempre
  ('^GSPC', 'index', 'us', 'S&P 500', 'S&P 500', '{}', true, 10),
  ('^IXIC', 'index', 'us', 'Nasdaq', 'Nasdaq', '{}', true, 20),
  ('^DJI', 'index', 'us', 'Dow Jones', 'Dow Jones', '{}', true, 30),
  ('^STOXX50E', 'index', 'eu', 'Euro Stoxx 50', 'Euro Stoxx 50', '{}', true, 40),
  ('^N225', 'index', 'asia', 'Nikkei 225', 'Nikkei 225', '{}', true, 50),
  ('CL=F', 'commodity', 'global', 'Petróleo WTI', 'WTI crude oil', '{}', true, 60),
  ('GC=F', 'commodity', 'global', 'Oro', 'Gold', '{}', true, 70),
  ('^TNX', 'rate', 'us', 'Bono a 10 años de EE. UU.', 'US 10-year Treasury yield', '{}', true, 80),
  ('BTC-USD', 'crypto', 'global', 'Bitcoin', 'Bitcoin', '{}', true, 90),
  -- Según los mercados de la cartera
  ('^MERV', 'index', 'latam', 'S&P Merval', 'S&P Merval', '{.BA}', false, 110),
  ('^IBEX', 'index', 'eu', 'IBEX 35', 'IBEX 35', '{.MC}', false, 120),
  ('^FTSE', 'index', 'eu', 'FTSE 100', 'FTSE 100', '{.L}', false, 130),
  ('^HSI', 'index', 'asia', 'Hang Seng', 'Hang Seng', '{.HK}', false, 140),
  ('^BVSP', 'index', 'latam', 'Ibovespa', 'Ibovespa', '{.SA}', false, 150),
  ('^MXX', 'index', 'latam', 'S&P/BMV IPC', 'S&P/BMV IPC', '{.MX}', false, 160),
  -- Sectores de EE. UU. (ETF sectoriales SPDR)
  ('XLK', 'sector', 'us', 'Tecnología (EE. UU.)', 'Technology (US)', '{US}', false, 210),
  ('XLF', 'sector', 'us', 'Finanzas (EE. UU.)', 'Financials (US)', '{US}', false, 220),
  ('XLE', 'sector', 'us', 'Energía (EE. UU.)', 'Energy (US)', '{US}', false, 230),
  ('XLV', 'sector', 'us', 'Salud (EE. UU.)', 'Health care (US)', '{US}', false, 240),
  ('XLY', 'sector', 'us', 'Consumo discrecional (EE. UU.)', 'Consumer discretionary (US)', '{US}', false, 250),
  ('XLP', 'sector', 'us', 'Consumo básico (EE. UU.)', 'Consumer staples (US)', '{US}', false, 260),
  ('XLI', 'sector', 'us', 'Industriales (EE. UU.)', 'Industrials (US)', '{US}', false, 270),
  ('XLU', 'sector', 'us', 'Servicios públicos (EE. UU.)', 'Utilities (US)', '{US}', false, 280),
  ('XLB', 'sector', 'us', 'Materiales (EE. UU.)', 'Materials (US)', '{US}', false, 290),
  ('XLRE', 'sector', 'us', 'Inmobiliario (EE. UU.)', 'Real estate (US)', '{US}', false, 300),
  ('XLC', 'sector', 'us', 'Comunicaciones (EE. UU.)', 'Communication services (US)', '{US}', false, 310)
on conflict (symbol) do nothing;
