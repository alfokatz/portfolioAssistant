-- Más medios en `news_source_allowlist`. La búsqueda web de `news-context`
-- solo mira estos dominios (`filters.allowed_domains`) y GDELT se filtra
-- contra la misma lista: con los 28 originales, "¿qué pasó con NFLX esta
-- semana?" volvía vacío (2026-10-13) porque lo que se publica sobre
-- Netflix sale sobre todo en la prensa de entretenimiento, y las citas de
-- AAPL/NVDA/AMZN eran todas de Bloomberg. Se suman medios con redacción
-- propia: prensa sectorial (entretenimiento, tecnología), diarios
-- generalistas grandes y prensa financiera latinoamericana.
insert into public.news_source_allowlist (domain, name, lang) values
  ('variety.com', 'Variety', 'en'),
  ('deadline.com', 'Deadline', 'en'),
  ('hollywoodreporter.com', 'The Hollywood Reporter', 'en'),
  ('theverge.com', 'The Verge', 'en'),
  ('techcrunch.com', 'TechCrunch', 'en'),
  ('theinformation.com', 'The Information', 'en'),
  ('investors.com', 'Investor''s Business Daily', 'en'),
  ('thestreet.com', 'TheStreet', 'en'),
  ('morningstar.com', 'Morningstar', 'en'),
  ('seekingalpha.com', 'Seeking Alpha', 'en'),
  ('cnn.com', 'CNN', 'en'),
  ('theguardian.com', 'The Guardian', 'en'),
  ('washingtonpost.com', 'The Washington Post', 'en'),
  ('latimes.com', 'Los Angeles Times', 'en'),
  ('bloomberglinea.com', 'Bloomberg Línea', 'es'),
  ('elfinanciero.com.mx', 'El Financiero', 'es'),
  ('expansion.mx', 'Expansión (MX)', 'es'),
  ('eleconomista.com.ar', 'El Economista (AR)', 'es')
on conflict (domain) do nothing;
