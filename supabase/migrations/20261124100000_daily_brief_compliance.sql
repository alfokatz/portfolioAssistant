-- Brief diario: correcciones de la revisión de compliance
-- (docs/legal/reviews/2026-11-21-brief-diario-medios-y-youtube.md).
-- Idempotente. No toca las migraciones anteriores.
--
-- H3: `require_topic` en canales de noticias generales: un video sin tema se
--     descarta en vez de mostrarse como "de mercado".
-- H4: `embeddable` por video (lo informa `videos.list?part=status`). Default
--     false: una fila vieja sin verificar no se presenta como embebible hasta
--     que `news-warm` la refresque (el upsert la pisa).
-- Medios: se habilitan solo las 4 fuentes oficiales que compliance marcó
--     "habilitar ya". El FMI y el BCRA siguen apagados; nytimes.com no se toca.

alter table public.video_channel_allowlist
  add column if not exists require_topic boolean not null default false;

alter table public.news_videos
  add column if not exists embeddable boolean not null default false;

update public.news_source_allowlist
   set enabled = true
 where domain in ('federalreserve.gov', 'bls.gov', 'bea.gov', 'ecb.europa.eu');
