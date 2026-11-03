# Piezas de presentación — semana 1

Generadas con `tools/marketing/render_social.mjs` (imágenes) y `tools/marketing/video/` (video motion design), con capturas reales de la app (cuenta demo, screenshot tests) y los textos corregidos por compliance (`docs/legal/reviews/2026-11-03-plan-redes.md` §6). Por decisión del usuario, las imágenes no llevan chip de cuenta demo ni disclaimers: van en el caption. Captions, hashtags y CTA: `docs/marketing/social/2026-11-03-plan-lanzamiento-ig-tiktok.md` §3 y §6.1.

| Pieza | Archivos | Dónde | Al publicar |
|---|---|---|---|
| PR1 "Esto es Porty" | `PR1_esto_es_porty_motion.mp4` (22 s, 9:16, 60 fps) | TikTok + Reel | Falta la locución con IA (`tools/marketing/video/vo_script.md`). Música de la biblioteca comercial de cada red. Caption del plan con disclaimer. |
| PR1b "Porty te acompaña" (live action) | `PR1_live_action_porty.mp4` (24 s, 9:16, 30 fps, mudo) | TikTok + Reel | Planos de contexto con IA (Seedance 2.0) + Porty personaje compuesto + UI real. Marcar como contenido con IA. Música de la biblioteca comercial. |
| PR2 "Qué es Porty en 5 placas" | `PR2_placa1.png` … `PR2_placa5.png` (1080x1350) | IG carrusel | Subir en orden. Caption del plan. |
| PR3 "Conocé a Porty" | `PR3_conoce_a_porty_feed.png` (1080x1350), `PR3_conoce_a_porty_story.png` (1080x1920) | IG feed + Stories | Caption del plan. |
| PR5 Stories de presentación | `PR5_story1.png` … `PR5_story5.png` (1080x1920) | IG Stories (día 1) | Stickers en Instagram, en el espacio libre: placa 2 encuesta "¿En cuántos lugares tenés tu plata? 1 / 2 o más"; placa 4 pregunta "¿Qué te gustaría que Porty te explique? No me cuentes montos ni datos de tu cuenta."; placa 5 link con el UTM de Stories. Sin cuenta regresiva. |

Pendiente antes de publicar: el link de descarga / UTM (plan §7). Logos: bajados de Finnhub (`static2.finnhub.io` → `static9`) y servidos con `LOGO_BASE_URL` al test de capturas; la cartera demo usa SPY en vez de VOO (`TICKER_SWAP=VOO:SPY`, solo en las capturas) con el logo de State Street (emisor de los SPDR), porque Finnhub no tiene logo para ETFs. Las respuestas a la caja de preguntas usan la plantilla del review (§4, Stories 6.2), sin handle ni foto de quien preguntó.

Para regenerar (por ejemplo, con otras capturas): ver el encabezado de cada script.
