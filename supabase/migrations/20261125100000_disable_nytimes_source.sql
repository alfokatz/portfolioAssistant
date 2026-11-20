-- Saca nytimes.com de las fuentes de noticias (decisión del usuario del
-- 21/11/2026, revisión de compliance docs/legal/reviews/
-- 2026-11-21-brief-diario-medios-y-youtube.md H10): el medio litiga contra
-- OpenAI por el uso de sus notas en IA, y el brief diario, los temas, la
-- comparación de medios y el chat parafrasean titulares con OpenAI.
--
-- Se apaga, no se borra: deja de usarse en titulares (GDELT), en la búsqueda
-- con citas (news-context, news-compare, digests) y en la lista de medios
-- preferidos. Volver a habilitarlo es un update con OK del usuario. Las
-- preferencias de usuarios que lo tenían elegido quedan, pero sin efecto.
update public.news_source_allowlist
   set enabled = false
 where domain = 'nytimes.com';
