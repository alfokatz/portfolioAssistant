# Revisión de compliance: Brief diario, medios nuevos y videos de YouTube

**Fecha:** 2026-11-20 (archivo rotulado 2026-11-21 por pedido) · **Autor:** porty-compliance (no es asesoramiento legal)
**Alcance:** `supabase/migrations/20261121100100_daily_brief_catalogs.sql` (medios y fuentes oficiales con `enabled=false`), `video_channel_allowlist` (vacía), spec `docs/superpowers/specs/2026-11-20-brief-diario-tech.md` (§3.2, §8, §10 D4), y el código de videos que ya está en el repo (`supabase/functions/news-warm/youtube.ts`, `supabase/functions/daily-brief/handler.ts`, `lib/features/news_feed/view/widgets/youtube_iframe_player.dart`, `news_video_sheet.dart`, `news_videos_section.dart`).

**Veredicto: ok con cambios.**
- **Lista interna con el interruptor: se puede**, porque todo lo nuevo arranca apagado.
- **Lanzamiento general: bloqueado** hasta cerrar H1 (cláusulas de YouTube en Términos y Privacidad), H2 (identificación del reproductor) y H6 (rótulo de IA), y hasta que el usuario apruebe la lista de medios de la sección 1.
- **Ningún medio de la sección 1 en "No habilitar" se enciende** sin un cambio de veredicto firmado por el usuario.

**Requiere abogado: sí.** Ver sección 5 (derecho conexo de la prensa en la UE, demandas abiertas contra proveedores de IA, transparencia de contenido generado por IA).

## Qué pude y qué no pude verificar (leer antes de confiar en los veredictos)

Esta sesión solo tiene búsqueda web. **No pude abrir** `developers.google.com`, `youtube.com` ni `portyassistant.com`, ni las páginas de términos de casi ningún medio. Lo que sigue se apoya en resultados de búsqueda (fragmentos de las páginas oficiales, noticias de demandas) y en el código del repo. Por eso cada veredicto lleva su confianza:
- **Alta:** la política oficial dice algo explícito (organismos públicos, demandas con fuente).
- **Media:** hay una señal pública (litigio, tipo de negocio) pero no leí los términos.
- **Baja:** sin señal propia; es el criterio conservador por defecto.

Ninguna cita de las políticas de YouTube salió de la página oficial. Las confirmé con fragmentos de búsqueda y con `docs/superpowers/specs/2026-11-20-brief-diario-research-notes.md`. Hay que releerlas antes del lanzamiento general (R4).

**Los `channel_id` no están verificados contra YouTube.** Ver sección 2: no hay `YOUTUBE_API_KEY` ni red a YouTube en esta sesión.

Normas y fuentes:
- YouTube API Services, Developer Policies: https://developers.google.com/youtube/terms/developer-policies (no abierta). Guía: https://developers.google.com/youtube/terms/developer-policies-guide. Historial de revisiones: https://developers.google.com/youtube/terms/revision-history. Métricas derivadas y los 30 días: https://developers.google.com/youtube/terms/derived-metrics-policy
- Directiva (UE) 2019/790, art. 15 (derecho de los editores de prensa): https://eur-lex.europa.eu/eli/dir/2019/790/oj. Comentario sobre "extractos muy breves": https://legalblogs.wolterskluwer.com/copyright-blog/taking-freedom-of-information-seriously-the-very-short-extracts-limitation-in-article-15-cdsm-directive-and-how-not-to-implement-it-part-1/
- Reglamento (UE) 2024/1689 (AI Act), art. 50: https://eur-lex.europa.eu/eli/reg/2024/1689/oj
- OpenAI, herramienta de búsqueda web (las citas tienen que ser visibles y clicables): https://developers.openai.com/api/docs/guides/tools-web-search
- Ley 24.240 (Defensa del Consumidor), art. 4: https://servicios.infoleg.gob.ar/infolegInternet/anexos/0-4999/638/texact.htm
- Fuentes de cada medio y organismo: se citan en las tablas.

---

## 0. Una discrepancia que cambia la revisión: el video ya está embebido

La spec (§2 "Fuera de alcance" y D4) dice "en v1 el video se abre en YouTube" y descarta el reproductor embebido. **El código ya lo embebe**: `pubspec.yaml` suma `youtube_player_iframe` y `webview_flutter_wkwebview`, y `news_video_sheet.dart` muestra el IFrame Player con "Ver en YouTube" como respaldo. Revisé contra el código y contra el pedido de hoy (embebido con fallback). La spec está desactualizada en esos dos puntos. Se lo marco a `porty-product-owner` en H7. La consecuencia para compliance: el reproductor carga código y cookies de Google dentro de la app, y eso entra en la política de privacidad, los privacy labels y los requisitos de YouTube para el embebido (sección 3).

---

## 1. Medios y fuentes oficiales: veredicto uno por uno

### Criterios que usé

Un dominio puede pasar a `enabled=true` si cumple todo esto:
1. **Modelo de uso.** Título + medio + fecha + link + paráfrasis propia con cita. Nunca el texto del artículo ni citas textuales largas.
2. **Sin litigio ni oposición pública contra proveedores de IA** de la clase de OpenAI (nuestro proveedor de búsqueda y de redacción) o contra buscadores de respuestas con IA.
3. **Términos sin cláusula** que prohíba rastreo automatizado, minería de textos o enlazar. La leen **personas** (yo no pude abrirlos).
4. **Señal técnica opcional:** si el `robots.txt` del medio bloquea los rastreadores de búsqueda de OpenAI, es una señal de oposición y no se habilita. El nombre del rastreador figura en la documentación de OpenAI. Es una señal, no una garantía.
5. **Aporta cobertura.** Aparece en la medición `scripts/news_coverage.ts` (spec §8) como un medio que suma titulares. Lo que no suma no se habilita, para no ampliar la superficie legal gratis.
6. **Paywall.** Un paywall no veta por sí solo (WSJ, FT y Bloomberg ya están). La paráfrasis tiene que salir de lo visible sin suscripción (título, entradilla, fragmento). Nunca se omite un paywall. Esto no lo puedo verificar técnicamente; hay que probarlo con 5 notas de cada medio.

Condición **C-estándar** (la repito abajo como "C"): cumplir 3, 4 y 6 con revisión de una persona antes de prender el dominio.

### 1.1 Medios globales y en español (20)

| Dominio | Veredicto | Confianza | Por qué |
|---|---|---|---|
| `asia.nikkei.com` | **No habilitar** | Media | Nikkei y Asahi demandaron a Perplexity en Tokio (26/08/2025) por copiar y almacenar su contenido saltando protecciones técnicas: https://www.theregister.com/2025/08/26/perplexity_asahi_nikkei_lawsuits/. Su página de copyright, según un resultado de búsqueda, prohíbe el rastreo y la minería de datos para buscar y enlazar su contenido: https://info.asia.nikkei.com/copyright (no la abrí). Paywall duro. |
| `scmp.com` | **Habilitar con condición** | Baja | No encontré demanda ni cláusula. Metered paywall. Condición C. Aporta cobertura de China y Hong Kong que hoy no hay (tema `china_economy`). |
| `economictimes.indiatimes.com` | **No habilitar** (v1) | Baja | Sin señal a favor y valor marginal para una app es/en. Términos del grupo no leídos. El gremio de medios digitales de India (DNPA) se sumó a la demanda de ANI contra OpenAI en Delhi: https://www.barandbench.com/news/litigation/digital-news-publishers-association-ani-openai-copyright-infringement-suit-delhi-high-court. No pude confirmar si este medio es miembro. Reevaluar si aparecen usuarios en India. |
| `livemint.com` | **No habilitar** (v1) | Baja | Idem: valor marginal y sin verificar su relación con el DNPA. |
| `business-standard.com` | **No habilitar** (v1) | Baja | Idem, y paywall duro. |
| `theglobeandmail.com` | **No habilitar** | Alta | The Globe and Mail es **demandante contra OpenAI** (junto con Torstar, Postmedia, Canadian Press y CBC) en Ontario. El 13/11/2026 el tribunal rechazó la apelación de OpenAI sobre jurisdicción: https://www.ctvnews.ca/toronto/article/news-publishers-copyright-lawsuit-against-openai-to-go-ahead-in-ontario/ y https://www.cp24.com/news/canada/2026/11/13/court-allows-news-publishers-copyright-lawsuit-against-openai-to-go-ahead/. Citarlos con una búsqueda de OpenAI es provocar al litigante contra nuestro proveedor. |
| `financialpost.com` | **No habilitar** | Alta | Es de Postmedia, también demandante. Mismas fuentes. |
| `afr.com` | **No habilitar** (v1) | Baja | Paywall duro (Nine), términos sin leer, valor marginal frente a Reuters, Bloomberg y FT. |
| `straitstimes.com` | **Habilitar con condición** | Baja | Sin señal en contra; cubre el sudeste asiático. Metered paywall. Condición C. |
| `dw.com` | **Habilitar con condición** | Baja | Medio público alemán, sin paywall. Su contenido está protegido por derecho de autor alemán y no tiene licencia abierta (Pressenza lo aclara en una página de terceros). Sirve enlazar y parafrasear, no copiar. Condición C. Prioridad baja. |
| `france24.com` | **Habilitar con condición** | Baja | Sin paywall; no encontré sus términos. Condición C. Prioridad baja. |
| `euronews.com` | **Habilitar con condición** | Media | Sus términos permiten bajar una copia para uso personal no comercial: https://euronews.com/terms-and-conditions. No vi cláusula sobre IA ni rastreo. Nuestro uso es enlazar y parafrasear, pero lo tiene que confirmar una persona. Condición C. Prioridad baja. |
| `aljazeera.com` | **Habilitar con condición** | Baja | Sus términos limitan el servicio a "uso personal no comercial" y regulan los outputs de su propia IA: https://aljazeera.com/terms-and-conditions/. No vi prohibición de enlazar ni de parafrasear. Condición C. **Aparte del riesgo legal, es una decisión de marca del usuario** (medio financiado por un Estado; no lo veto por eso). Prioridad baja. |
| `caixinglobal.com` | **No habilitar** (v1) | Baja | Paywall duro y modelo de licenciar contenido a terceros; no encontré sus términos. La cobertura de China la cubre SCMP (si pasa C), Reuters y Bloomberg. |
| `portafolio.co` | **Habilitar con condición** | Baja | Cubre Colombia, que hoy no tiene medio propio en la lista. Condición C. |
| `larepublica.co` | **Habilitar con condición** | Baja | Idem Colombia. Condición C. |
| `gestion.pe` | **Habilitar con condición** | Baja | Cubre Perú. Condición C (con atención al paywall). |
| `df.cl` | **Habilitar con condición** | Baja | Cubre Chile. Paywall en buena parte: la paráfrasis solo de lo visible. Condición C. |
| `elconfidencial.com` | **No habilitar** (v1) | Media | España ya está cubierta por Expansión, Cinco Días, El Economista y El País. El valor marginal no compensa el derecho conexo de la prensa en la UE (sección 5, R2) ni la reserva de minería de textos que los medios españoles suelen declarar. |
| `europapress.es` | **No habilitar** | Media | Es una **agencia** que vive de licenciar contenido a otros medios. Un resumen de IA de sus despachos compite con su negocio. Sus términos no los pude leer. Además replica en medios que ya están en la lista. |

### 1.2 Fuentes oficiales (10)

| Dominio | Veredicto | Confianza | Por qué y condición |
|---|---|---|---|
| `federalreserve.gov` | **Habilitar** | Alta | "Public domain unless otherwise indicated" y pide citar al Board: https://federalreserve.gov/disclaimer.htm. No usar el nombre ni el símbolo "Federal Reserve" como marca de Porty. |
| `bls.gov` | **Habilitar** | Alta | Dominio público; enlazar no necesita permiso; el emblema es marca registrada: https://www.bls.gov/opub/copyright-information.htm. Sin logo. |
| `bea.gov` | **Habilitar** | Alta | Dominio público, se puede reproducir sin permiso y pide "Source: U.S. Bureau of Economic Analysis": https://bea.gov/help/faq/145 |
| `ecb.europa.eu` | **Habilitar** | Alta | Las estadísticas se reutilizan gratis, también comercialmente, citando la fuente y sin modificarlas: https://www.ecb.europa.eu/stats/ecb_statistics/governance_and_quality_framework/html/usage_policy.en.html. El resto del sitio: reproducir con exactitud y citar al BCE: https://www.ecb.europa.eu/home/disclaimer/html/index.en.html. Se excluyen datos de terceros. Si se muestra una cifra, va tal cual y con "Fuente: BCE". |
| `indec.gob.ar` | **Habilitar con condición** | Media | Según resultados de búsqueda, el material del sitio lleva licencia Creative Commons y se puede reproducir citando la fuente. **No supe cuál variante.** Si es "NoComercial", se aplica la condición de BoJ. Una persona confirma la variante antes de prender. |
| `bankofengland.co.uk` | **Habilitar con condición** | Media | El contenido es del Banco y solo la base de datos va bajo la Open Government Licence: https://www.bankofengland.co.uk/legal. Solo título + link + paráfrasis de hechos (decisión de tasas, cifras publicadas) con "Fuente: Bank of England". Sin tablas, gráficos ni billetes. |
| `boj.or.jp` | **Habilitar con condición** | Media | Permite copiar con crédito, pero la **reproducción comercial, los gráficos y el material marcado quedan fuera**: https://www.boj.or.jp/en/about/copyright.htm. Misma condición que el Banco de Inglaterra: hechos parafraseados y link, nada reproducido. |
| `imf.org` | **No habilitar** | Alta | Su política exige permiso escrito para uso comercial, no permite obras derivadas y **no autoriza usar su contenido para entrenar LLM sin permiso explícito**: https://www.imf.org/en/about/copyright-and-terms. Hay fair use para "news reporting" no comercial, que no es nuestro caso. Si el usuario quiere el FMI, puede pedir permiso a copyright@imf.org. Mientras tanto, Reuters y Bloomberg lo cubren. |
| `bcra.gob.ar` | **No habilitar** hasta tener autorización | Alta | El aviso legal prohíbe usar los contenidos con fines comerciales, publicitarios o de campaña sin autorización previa y expresa: https://www.bcra.gob.ar/aviso-legal/. Porty cobra suscripciones. Los datos del BCRA llegan igual por Ámbito, El Cronista, Infobae y Reuters. Si se quiere, la autorización la pide el usuario. |
| `cnv.gov.ar` | **No habilitar** hasta verificar | Baja | Es un dominio **probablemente desactualizado**: los organismos nacionales hoy publican en `.gob.ar` y la CNV en `argentina.gob.ar/cnv`. Como `filters.allowed_domains` filtra por dominio, habilitar `argentina.gob.ar` abriría **todo el sitio del Estado**, no solo la CNV. Sin términos verificados. Ver H9. |

### 1.3 Resumen y SQL para cuando el usuario apruebe

- **Habilitar ya:** 4 (`federalreserve.gov`, `bls.gov`, `bea.gov`, `ecb.europa.eu`).
- **Habilitar con condición:** 13 (10 medios: `scmp.com`, `straitstimes.com`, `dw.com`, `france24.com`, `euronews.com`, `aljazeera.com`, `portafolio.co`, `larepublica.co`, `gestion.pe`, `df.cl`; 3 oficiales: `indec.gob.ar`, `bankofengland.co.uk`, `boj.or.jp`).
- **No habilitar:** 13 (10 medios: `asia.nikkei.com`, `economictimes.indiatimes.com`, `livemint.com`, `business-standard.com`, `theglobeandmail.com`, `financialpost.com`, `afr.com`, `caixinglobal.com`, `elconfidencial.com`, `europapress.es`; 3 oficiales: `imf.org`, `bcra.gob.ar`, `cnv.gov.ar`).

Propuesta, no ejecutada (la corre el usuario o backend con su OK; no se edita la migración):

```sql
update public.news_source_allowlist set enabled = true
 where domain in ('federalreserve.gov', 'bls.gov', 'bea.gov', 'ecb.europa.eu');
-- Los "con condición" se agregan a esta lista de a uno, cuando una persona
-- cierra la condición C y anota la fecha en docs/legal/.
```

La allowlist queda en unos 50 dominios habilitados; el tope de la búsqueda web es 100, así que no hay problema de espacio.

### 1.4 Medios y fuentes que faltan

**Globales clave: no falta ninguno.** Reuters, AP, Bloomberg, FT, WSJ, CNBC, BBC, The Guardian, The Economist y Bloomberg Línea ya están habilitados. Lo que sí falta son fuentes primarias de datos de bajo riesgo para los temas que ya existen. Candidatos, a verificar uno por uno antes de proponerlos como migración:

| Dominio | Tema al que sirve | Por qué entraría | Estado |
|---|---|---|---|
| `sec.gov` | resultados (`earnings_season`) | Ya lo usamos por la función `sec`; es dominio público de EE. UU. | Alta confianza que se puede; la política de acceso justo (fair access) de la SEC ya figura como pendiente en `docs/runbooks/news-sources-v2.md`. |
| `eia.gov` | `oil_energy` | Estadísticas de energía de EE. UU., dominio público. | A verificar. |
| `home.treasury.gov` | `bonds_rates` | Rendimientos del Tesoro, dominio público de EE. UU. | A verificar el dominio exacto. |
| `ons.gov.uk` | `inflation` (Reino Unido) | Open Government Licence. | A verificar. |
| `worldbank.org`, `bis.org` | `emerging_markets`, `global_indices` | Datos con licencia abierta o con atribución. | A verificar los términos de cada uno. |

**Cripto:** el tema `crypto` no tiene medio especializado y se cubre con Reuters, Bloomberg y CNBC. Si el usuario quiere uno (CoinDesk, The Block), sería con condición C **y** con una advertencia: la prensa cripto mezcla mucho contenido patrocinado y "predicciones de precio", que chocan con "Información, no una recomendación". Mi recomendación es no agregarlo en v1.

**Sobre la lista que ya está habilitada** (fuera de esta migración, pero relevante):
- `nytimes.com` ya está habilitado y su dueño **litiga contra OpenAI** desde 2023 (caso 1:23-cv-11195, en trámite en septiembre de 2026): https://axios.com/2026/09/08/nyt-openai-microsoft-copyright-lawsuit. Es el mismo riesgo que el de Globe and Mail. Ver H10.
- `seekingalpha.com`, `thestreet.com`, `investing.com` y `forbes.com` (colaboradores) publican mucha opinión y "picks" de acciones. Un resumen parafraseado de una nota de "por qué comprar X" es recomendación de un tercero aunque la redacte nuestra IA. El validador ya descarta consejo y consejo de terceros, pero es una fuente de ruido. Ver H10.

---

## 2. Canales de YouTube para `video_channel_allowlist`

### 2.1 Criterios para que un canal entre

1. **Canal oficial del medio.** El mismo medio lo enlaza desde su sitio y tiene la verificación de YouTube. Nada de canales de fans, resubidas ni "clips de".
2. **Permite embeber.** El video tiene `status.embeddable = true`. **Se verifica por video, no por canal**, con `videos.list?part=status` (1 unidad por cada 50 ids). `playlistItems.list` no informa esto. Ver H4.
3. **Sin "señales" ni trading.** Se descarta el canal si su formato principal es recomendar: "stock picks", "señales", predicciones de precio, "Mad Money"-style, influencers de trading o cripto. Los canales mixtos entran con filtro de títulos reforzado (H5).
4. **Sin opinión personal de analistas** como formato central. Los programas de entrevistas con analistas pueden entrar si el filtro de títulos los atrapa.
5. **Solo es/en**, con `region` correcta (`us`, `eu`, `latam`, `asia`, `global`).
6. **Un canal de noticias generales no entra a "mercado".** Ver H3: hoy, un video que no coincide con ningún tema se muestra como "de mercado".
7. **Cuota:** hasta 40 canales por corrida (`youtubeConfig.maxChannels`); recomiendo arrancar con 12.
8. `outlet_domain` se completa solo si ese medio está **habilitado** en `news_source_allowlist`, para que el orden de "preferidos" sea coherente.

### 2.2 Cómo se resuelve el `channel_id` (nadie lo inventa)

Backend toma el enlace del canal que el propio medio publica en su sitio, y resuelve con `channels.list?part=id,snippet,contentDetails` (1 unidad). Compara `snippet.title` con el nombre del medio y guarda `channel_id` y `contentDetails.relatedPlaylists.uploads`. **Un mismo medio puede tener varios canales** (por ejemplo, el de The Wall Street Journal que encontré en una búsqueda tenía un id distinto del que recordaba), así que el id **se lee del sitio del medio, no de memoria ni de listados de terceros.**

### 2.3 Lista propuesta

Estado de cada `channel_id`: **ninguno está verificado contra YouTube.** Los tres que traigo salieron de páginas de terceros (VidIQ y un análisis de datos); hay que confirmarlos con `channels.list`. El resto va "a verificar".

**Prioridad 1: arrancar con estos (12)**

| Canal | `channel_id` | Idioma | Región | Temas | Cuidado |
|---|---|---|---|---|---|
| Reuters | a verificar | en | global | `fed_rates`, `inflation`, `global_indices`, `oil_energy`, `earnings_season` | General (agencia): exigir coincidencia de tema (H3). |
| Bloomberg Television | `UCIALMKvObZNtJ6AmdCLP7Lg` (candidato; fuente de terceros) | en | global | `fed_rates`, `inflation`, `global_indices`, `earnings_season`, `tech_ai` | Entrevistas con gestores: filtro de títulos. |
| CNBC | `UCvJJ_dzjViJCoLf5uKUTwoA` (candidato; fuente de terceros) | en | us | `earnings_season`, `fed_rates`, `global_indices` | Incluye segmentos de "picks": filtro. |
| CNBC Television | a verificar | en | us | idem | Idem; aquí se concentran los clips de "Mad Money". |
| Yahoo Finance | `UCEAZeUIeJs0IjQiqTCdVSIg` (candidato; fuente de terceros) | en | us | `global_indices`, `earnings_season`, `crypto` | Muchos "stocks to buy": filtro fuerte. |
| The Wall Street Journal | a verificar (hay más de un canal) | en | us | `fed_rates`, `inflation`, `earnings_season` | Confirmar cuál es el canal general. |
| Financial Times | a verificar | en | eu | `ecb_rates`, `boe_rates`, `global_indices` | Ninguno especial. |
| The Economist | a verificar | en | global | `inflation`, `emerging_markets`, `china_economy` | Explicativos: buen encaje con "tranquilo". |
| DW News | a verificar | en | eu | `ecb_rates`, `global_indices` | General: exigir coincidencia de tema (H3). Depende de `dw.com`. |
| CNN en Español | a verificar | es | latam | `latam_markets`, `fed_rates`, `inflation` | General: exigir coincidencia de tema. |
| Bloomberg Línea | a verificar | es | latam | `latam_markets`, `ar_bcra_dollar`, `bonds_rates`, `crypto` | Es el canal más específico en español. |
| DW Español | a verificar | es | eu / latam | `ecb_rates`, `latam_markets` | General: exigir coincidencia de tema. |

**Prioridad 2: más adelante, si faltan videos en es o en una región**

| Canal | Idioma | Región | Nota |
|---|---|---|---|
| France 24 Español, France 24 English | es, en | eu | General; exigir coincidencia de tema. Depende de que `france24.com` pase C. |
| Euronews (English / Español) | en, es | eu | Idem. |
| El Cronista, Ámbito, Infobae | es | latam (AR) | Mezclan política y espectáculos: exigir coincidencia de tema. |
| El Financiero (México) | es | latam | Más financiero; confirmar canal. |
| BBC News, Associated Press | en | global | Generales; valor marginal. |
| El País | es | eu | General. |

**No proponer:** canales de analistas individuales, de trading, de cripto con "predicciones", ni canales de medios en la lista "No habilitar" de la sección 1 cuando el motivo sea una demanda contra nuestro proveedor (los canales de Globe and Mail y Financial Post no aportan igual). Para el resto, el embed oficial no copia nada: el veredicto de texto no se arrastra automáticamente a los videos.

---

## 3. YouTube API Services: qué exige y si el diseño lo cumple

Marco: la app usa la YouTube Data API **solo desde el servidor**, con una clave de API, para leer subidas públicas (`playlistItems.list`). **No hay OAuth ni datos de usuarios de Google**, así que no aplican las reglas de "authorized data" (revocación desde la cuenta de Google, etc.). Sí aplican las de los términos del cliente, privacidad, datos no autorizados (títulos, ids), reproductor embebido y distribución.

| # | Requisito (fuente: fragmentos de la política vigente; no abierta) | Nuestro diseño | Estado |
|---|---|---|---|
| 1 | **Términos del cliente:** mostrar un enlace a los Términos de YouTube (https://www.youtube.com/t/terms) y decir que, al usar la app, el usuario acepta quedar obligado por ellos (sección III.A). | No existe en repo. Los Términos de Porty no se pudieron abrir. | **Falta (H1)**: cláusula en sección 4. |
| 2 | **Política de privacidad:** avisar que se usan YouTube API Services y enlazar la Política de Privacidad de Google (sección III.A). Tiene que estar visible y accesible siempre. | No hay mención. | **Falta (H1)**: párrafo en sección 4. |
| 3 | **Refrescar o borrar a los 30 días** los datos no autorizados que se guardan de la API (títulos, canales). | `news_videos` se purga a los 7 días (`daily_brief_purge`, `daily-jobs` a las 04:00 UTC) y `fetched_at` se actualiza en cada lectura. | **Cumple.** Condición: `daily-jobs` tiene que estar corriendo; si falla la purga, hay que enterarse (alerta). |
| 4 | **No vender ni condicionar el acceso** a los API Services ni al contenido audiovisual de YouTube. | Los videos son gratis en los tres planes y no dependen de `tier` (`videosFor` no mira el plan). | **Cumple.** Regla para el futuro: ni el paywall ni el marketing pueden anunciar "videos" como beneficio de Premium o Gold. Aviso a `porty-monetization`. |
| 5 | **Reproductor embebido oficial, sin tocar:** controles y marca visibles, sin superponer ni tapar elementos, sin bloquear anuncios, tamaño mínimo. | IFrame Player oficial (`youtube_player_iframe`), `showControls: true`, 16:9 a todo el ancho de la hoja, sin overlays. | **Cumple** (verificar el tamaño mínimo en pantallas chicas). |
| 6 | **Sin reproducción automática** sin acción del usuario. | `cueVideoById` (no `loadVideoById`); el usuario toca para abrir la hoja y luego para reproducir. | **Cumple.** |
| 7 | **Identificar al cliente que embebe** (desde 2025, el reproductor devuelve el error 153 si no hay Referer; las WebView de Android suelen no mandarlo). Dato de las notas de investigación; no pude abrir la fuente de YouTube. | `origin: 'https://www.youtube.com'`: se usa un host **de YouTube** como embebedor porque la versión 5.x del paquete también lo usa como `host` y uno propio rompe la carga. El propio código dice "falta confirmar en un Android real". | **Corregir (H2).** Declarar que el embebedor es YouTube no identifica a Porty. |
| 8 | **Marca:** atribuir a YouTube y no usar su logo ni su botón de play sin seguir sus lineamientos; no sugerir que YouTube o el medio respaldan a Porty. | Texto "Video de YouTube · {canal}" y un ícono de play genérico de Material. | **Cumple.** Regla: nada de logos de YouTube ni de medios en las tarjetas. |
| 9 | **Privacidad del reproductor:** al cargarlo, Google recibe IP, identificadores y datos de uso, y puede usar cookies. Hay que informarlo y, en el EEE/Reino Unido/Suiza, evaluar el consentimiento previo. | El reproductor solo se carga **al tocar** (bien). Las **miniaturas** (`i.ytimg.com`) se descargan al mostrar la lista, sin tocar nada: Google ve la IP del usuario antes de que haga nada. | **Corregir (H8)**: informarlo; evaluar consentimiento para el EEE (revisión humana). |
| 10 | **No guardar ni modificar el contenido audiovisual,** ni separar audio y video. | Solo metadatos (id, título, fecha, canal, idioma, temas). | **Cumple.** |
| 11 | **Datos de la API fuera de IA.** Hay reglas sobre el uso de los datos de la API; no pude leer la sección actual sobre aprendizaje automático. | Los temas se asignan por palabras clave **sin LLM** (`assignTopics`). Los títulos de video no entran al prompt del brief ni de `get_daily_brief`. | **Cumple por diseño.** Regla: mantenerlo así. Si alguien quiere resumir videos con IA, vuelve a compliance. |
| 12 | **Clave de API:** restringida y protegida. | Solo en el secreto `YOUTUBE_API_KEY` del servidor; nunca se loguea la URL ni el cuerpo de un error (`youtube.ts`). | **Cumple.** Restringir la clave a la YouTube Data API y por IP/origen en Google Cloud (lo hace el usuario, pregunta P1). |
| 13 | **Cuota:** `playlistItems.list` = 1 unidad; sin `search.list`. | 30–40 canales × 48 lecturas = 1.440 de 10.000 por día. | **Cumple.** Si se suma `videos.list` para `embeddable` (H4): +1 unidad por cada 50 videos nuevos, despreciable. |

**Qué falta para cumplir YouTube:** H1 (Términos y Privacidad), H2 (identificación del embebedor y prueba en Android real), H8 (miniaturas y reproductor en privacidad, privacy labels y Data safety). Lo demás cumple por diseño.

---

## 4. Textos legales: borradores

Lo que **no** existe hoy: no hay `docs/legal/disclaimers.md`, `data-inventory.md` ni borrador de Términos o Privacidad en el repo, y las páginas `https://portyassistant.com/app/terminos` y `/privacidad` (`lib/config/legal/legal_links.dart`) no se pudieron abrir. Estos bloques son **cláusulas para agregar**, no los documentos completos. Todos con **Revisión humana: sí**. `{email}` lo define el usuario (en la revisión del 02/11 ya figuraba como bloqueo: no hay casilla de soporte en el repo).

### 4.1 Términos de uso: cláusulas nuevas

**es**

> **Noticias, resúmenes y videos de terceros.** El brief diario, las noticias, "Mercado hoy", los temas y la comparación de medios muestran títulos, nombres de medios, fechas y enlaces a notas que publican terceros, junto con resúmenes redactados por inteligencia artificial a partir de esas fuentes. Porty no reproduce las notas: para leerlas completas tenés que abrir la fuente, y algunos medios piden una suscripción.
>
> Los resúmenes los genera una IA y pueden tener errores, omisiones o estar desactualizados. Cada afirmación indica su fuente: verificala ahí antes de usarla. Cuando comparamos medios, solo resumimos en qué coinciden y en qué difieren; no decidimos cuál tiene razón.
>
> Los nombres, las marcas y los contenidos de los medios, los organismos y los canales pertenecen a sus titulares. Porty no tiene vínculo con ellos y ellos no respaldan a Porty. Si sos titular de un contenido y querés que lo retiremos, escribinos a {email} y respondemos en {plazo}.
>
> **Información, no una recomendación.** Lo que ves en el brief, en las noticias y en los videos es información general y no es asesoramiento financiero, de inversión, legal ni impositivo, ni una recomendación o invitación a comprar, vender o mantener ningún activo. Porty no ejecuta órdenes. Lo que una noticia, un medio o un video digan sobre un activo es opinión o información de su autor, no de Porty. Las decisiones son tuyas. El rendimiento pasado no garantiza resultados futuros.
>
> **Videos de YouTube.** Los videos de canales oficiales de medios se reproducen con el reproductor de YouTube y los aloja YouTube. Al usarlos aceptás quedar obligado por los Términos de Servicio de YouTube (https://www.youtube.com/t/terms). Porty no cobra por el acceso a esos videos: están en todos los planes.

**en**

> **Third-party news, summaries and videos.** The daily brief, news, "Market today," topics and outlet comparison show headlines, outlet names, dates and links to articles published by third parties, along with summaries written by artificial intelligence based on those sources. Porty does not reproduce the articles: to read one in full you open the source, and some outlets require a subscription.
>
> Summaries are generated by AI and may contain errors, omissions or be out of date. Each statement names its source: check it there before you rely on it. When we compare outlets we only summarize where they agree and where they differ; we don't decide who is right.
>
> The names, trademarks and content of outlets, agencies and channels belong to their owners. Porty is not affiliated with them and they don't endorse Porty. If you own content and want us to remove it, write to {email} and we will reply within {period}.
>
> **Information, not a recommendation.** What you see in the brief, the news and the videos is general information. It is not financial, investment, legal or tax advice, and it is not a recommendation or an invitation to buy, sell or hold any asset. Porty does not place orders. What a news item, an outlet or a video says about an asset is the opinion or information of its author, not Porty's. The decisions are yours. Past performance does not guarantee future results.
>
> **YouTube videos.** Videos from official media channels are played with the YouTube player and hosted by YouTube. By using them you agree to be bound by the YouTube Terms of Service (https://www.youtube.com/t/terms). Porty does not charge for access to those videos: they are available on every plan.

### 4.2 Política de privacidad: párrafos nuevos

**es**

> **Brief diario, noticias y resúmenes con IA.** Para armar tu brief usamos tu cartera (tus posiciones y el peso de cada una), tu lista de seguimiento y los temas y medios que elegís. Los resúmenes los redacta un proveedor de IA (OpenAI). Para redactar el brief le enviamos los símbolos de tus posiciones y descripciones cualitativas (por ejemplo, "subió" o "pesa mucho") junto con titulares públicos; no le enviamos montos, tu nombre ni tu mail. Los resúmenes generales (mercado y temas) y la comparación de medios se arman con búsquedas sobre fuentes públicas, sin datos de tu cuenta, salvo el símbolo o el tema que consultás. Guardamos tu brief por 14 días y lo borramos antes si borrás tu cuenta; tus temas y medios preferidos o silenciados se borran con tu cuenta. {Retención y entrenamiento de OpenAI: completar con los términos vigentes del contrato de API.}
>
> **Videos de YouTube.** Porty usa los servicios de API de YouTube (YouTube API Services) para listar los videos más recientes de canales oficiales de medios. Esa consulta la hace nuestro servidor con una clave de Porty: no envía tus datos ni usa tu cuenta de Google. Cuando mirás la lista de videos, tu dispositivo descarga las miniaturas desde servidores de Google, y cuando abrís un video se carga el reproductor de YouTube, que puede recopilar tu dirección IP, identificadores del dispositivo y datos de uso, y usar cookies o tecnologías similares. Esos datos los trata Google bajo su propia política: Política de Privacidad de Google (https://policies.google.com/privacy). Porty no recibe esos datos. De nuestro lado solo guardamos los datos públicos de los videos (título, canal, fecha) por hasta 7 días, y registramos que abriste un video, sin su título ni su canal.

**en**

> **Daily brief, news and AI summaries.** To build your brief we use your portfolio (your positions and the weight of each), your watchlist, and the topics and outlets you choose. Summaries are written by an AI provider (OpenAI). To write the brief we send it the symbols of your positions and qualitative descriptions (for example, "went up" or "weighs a lot") together with public headlines; we do not send amounts, your name or your email. General summaries (market and topics) and outlet comparisons are built from searches over public sources, without your account data, except the symbol or topic you ask about. We keep your brief for 14 days and delete it sooner if you delete your account; your followed topics and your preferred or muted outlets are deleted with your account. {OpenAI retention and training: fill in with the current API terms.}
>
> **YouTube videos.** Porty uses YouTube API Services to list the latest videos from official media channels. That request is made by our server with a Porty key: it sends none of your data and does not use your Google account. When you view the video list, your device downloads thumbnails from Google servers, and when you open a video the YouTube player loads, which may collect your IP address, device identifiers and usage data, and may use cookies or similar technologies. Google handles that data under its own policy: Google Privacy Policy (https://policies.google.com/privacy). Porty does not receive that data. On our side we only store the videos' public data (title, channel, date) for up to 7 days, and we record that you opened a video, without its title or channel.

Verificá con `porty-assistant-dev` y `porty-backend-dev` antes de publicar: (a) que `toPromptJson` siga sin cifras ni montos (hoy es así: dirección, tamaño y peso en palabras); (b) que `news_video_opened` siga sin título ni canal (hoy lleva solo `kind`); (c) el link exacto a la política de Google que pide la política vigente de YouTube (el texto antiguo apuntaba a `http://www.google.com/policies/privacy`, que redirige).

### 4.3 Entradas para `data-inventory.md` (cuando exista)

| Dato | Dónde | Para qué | Cuánto | Se borra con la cuenta |
|---|---|---|---|---|
| Brief del día (texto, números, enlaces) | `daily_briefs.payload` | Mostrarlo en la app | 14 días | Sí (cascade) |
| Temas seguidos o apagados | `user_news_topics` | Personalizar el brief | Mientras exista la cuenta | Sí (cascade) |
| Medios preferidos o silenciados | `user_news_sources` | Orden y filtro del feed | Idem | Sí (cascade) |
| Título, canal y fecha de videos | `news_videos` | Mostrar videos | 7 días | No es dato personal |
| Eventos de uso (`daily_brief_*`, `news_*`) | `product_events` | Medir el producto | Según política vigente de eventos | Según el flujo actual de borrado |
| Símbolos y descriptores cualitativos al LLM | OpenAI (vía `ai-chat`) | Redactar el brief | Según contrato de OpenAI | No controlado por Porty |
| IP e identificadores al cargar miniaturas y reproductor | Google (YouTube) | Servir el video | Política de Google | No controlado por Porty |

Privacy labels de Apple y Data safety de Google: hay que declarar que un tercero (Google, vía el reproductor y las miniaturas) recibe identificadores y datos de uso, y confirmar que el etiquetado de OpenAI ya cubre los símbolos de la cartera. Revisión humana: sí.

### 4.4 Pie del brief y del feed: revisión

**Lo que está bien.** "Información, no una recomendación." / "Information, not a recommendation." (`daily_brief_footer_disclaimer`, `market_today_footer`) aparece en el brief (`daily_brief_screen.dart:639`), en Mercado hoy, en las dos pestañas del feed y en la pantalla de tema (`NewsDisclaimer`). Es coherente con el pie del informe semanal.

[CORREGIR] H6. Falta el rótulo de que el resumen lo generó una IA a partir de fuentes de terceros, y el pie queda al final de la pantalla
Por qué: el brief y los resúmenes de temas y de mercado son texto generado por IA que informa sobre temas de interés público. Los requisitos de transparencia del art. 50 del AI Act apuntan a avisar que el texto es artificial (https://eur-lex.europa.eu/eli/reg/2024/1689/oj; hay que confirmar si aplica a un resumen personalizado y desde qué fecha, porque están discutiendo prórrogas). Aunque no aplicara, es barato y protege: el usuario tiene que saber que es un resumen de IA y no una nota del medio. OpenAI además exige que las citas sean visibles y clicables (https://developers.openai.com/api/docs/guides/tools-web-search): ya lo cumple la línea "{medio} · {hace cuánto}" con link; no hay que sacarla.
Texto propuesto (clave nueva `news_ai_notice`, que reemplaza al pie actual en el brief, en Mercado hoy, en el feed y en la pantalla de tema):
- es: "Resumen hecho con IA a partir de las fuentes citadas; puede tener errores. Información, no una recomendación."
- en: "AI-generated summary based on the cited sources; it may contain errors. Information, not a recommendation."
Para el brief y "Mercado hoy": además mostrar una versión corta bajo el título (por ejemplo "Resumen hecho con IA"), para que se lea antes del contenido y no al final.
Revisión humana: sí (confirmar el alcance del art. 50).

[CORREGIR] H6b. `daily_brief_teaser_premium`: "Con Premium ves por qué se movió lo tuyo" promete una causa que el producto, por diseño, no afirma
Por qué: el brief "vincula con un titular, sin afirmar causa" (el validador descarta "subió por…"). Un texto de venta que promete el "por qué" es un claim que el producto no cumple. Ley 24.240 art. 4 (información cierta y clara) y las guías de suscripción de las tiendas (Apple 3.1.2) piden que lo prometido sea lo entregado. Es el mismo criterio de la revisión del 02/11 (H5, H6).
Texto propuesto:
- es: "Con Premium ves las noticias de tus posiciones junto a lo que se movió en tu cartera, con medio y link."
- en: "With Premium you see the news on your positions next to what moved in your portfolio, with outlet and link."
Revisión humana: no. Se lo paso a `porty-monetization` porque la decisión del 05/11 dice "Premium = por qué se movió lo tuyo" y el texto del paywall y la ficha también.

[SUGERENCIA] El reproductor de videos y la tarjeta de comparar medios no tienen el pie
Por qué: la hoja del video (`NewsVideoSheet`) muestra la atribución a YouTube pero no el pie, y el contenido de un video de un medio puede incluir opiniones de analistas. La tarjeta `QaSourceComparison` vive en el chat, que ya tiene su disclaimer general.
Texto propuesto: sumar `news_ai_notice` debajo del título del video solo si el video muestra algún resumen nuestro; si es solo el reproductor, alcanza con la línea "Video de YouTube · {canal}". Para la tarjeta de comparación, confirmar que el pie del chat sea visible junto a ella.
Revisión humana: no.

**El push** (`Tu brief de hoy está listo`, sin montos, porcentajes ni tickers) está bien: no afirma nada y no es urgencia.

---

## 5. Hallazgos

[BLOQUEA el lanzamiento general] H1. Términos y Privacidad sin las cláusulas de YouTube ni del brief
Por qué: los YouTube API Services Terms exigen (III.A) los Términos de YouTube enlazados y aceptados por el usuario, y la política de privacidad con el aviso de uso de YouTube API Services y el enlace a la Política de Privacidad de Google (https://developers.google.com/youtube/terms/developer-policies, leída solo por fragmentos). Incumplirlo es motivo de suspensión de la clave. Además, el brief envía símbolos de la cartera a OpenAI y eso tiene que estar en la política (Ley 25.326 art. 6: información previa al titular).
Texto propuesto: secciones 4.1 y 4.2.
Revisión humana: sí. Un abogado valida los Términos y la Privacidad completos; esta revisión solo aporta las cláusulas.

[CORREGIR antes del lanzamiento general] H2. `YoutubeIframePlayer.origin = 'https://www.youtube.com'`
Por qué: YouTube pide identificar a la app que embebe; usar un host de YouTube como embebedor no la identifica y es una solución provisional para el error 153. El propio código lo documenta y propone pasar a `https://com.portyassistant.app` al subir a la 6.x del paquete (Flutter 3.47+). Riesgo: que YouTube restrinja o bloquee al cliente, o que cambie el comportamiento sin aviso. La caída es suave (la hoja cae a "Ver en YouTube"), pero no es un buen lugar para estar en producción.
Texto propuesto: no es de texto. Probar en un Android real y en un iPhone real con 10 videos de 5 canales, y decidir: (a) migrar a 6.x antes del lanzamiento general, o (b) dejar el reproductor apagado en Android y abrir en YouTube hasta migrar. Anotar el resultado en la revisión.
Revisión humana: no. Dueño: `porty-flutter-dev`.

[CORREGIR antes de agregar canales generales] H3. Un video sin tema se muestra como "de mercado"
Por qué: `assignTopics` deja `topic_ids = []` cuando ningún tema coincide, y `videosFor` en modo mercado muestra **solo** esos. Con un canal financiero (Bloomberg, CNBC) los sin tema son resúmenes de mercado, y está bien. Con un canal de noticias generales (DW, CNN en Español, BBC, AP), los sin tema son política, guerra, policiales o deportes, y aparecerían como "Mercado hoy", con miniaturas que pueden ser gráficas. Eso rotula mal el contenido y puede ser sensible en una app de inversiones.
Texto propuesto: no es de texto. Una columna `general_news boolean` en `video_channel_allowlist`, o `require_topic`: para esos canales, un video sin tema se descarta. Cambio de backend, en una migración nueva.
Revisión humana: no. Dueño: `porty-backend-dev`.

[CORREGIR] H4. No se verifica que el video permita embeber
Por qué: `NewsVideo.embeddable` solo comprueba el formato del id (`news_bundle.dart:173`), no la configuración real del video. Hoy la hoja falla bien y cae a "Ver en YouTube", pero el usuario ve un reproductor roto antes. Además, un video con `privacyStatus` distinto de público no debería listarse.
Texto propuesto: no es de texto. `videos.list?part=status` (1 unidad por 50 ids) en el cron de `news-warm`; guardar `embeddable` y descartar lo no público; usar ese campo en la app.
Revisión humana: no. Dueño: `porty-backend-dev` y `porty-flutter-dev`.

[CORREGIR] H5. El filtro de recomendaciones de títulos de video es corto y está sesgado al inglés y al rioplatense
Por qué: `isRecommendation` descarta "should you buy", "stocks to buy", "buy now", "comprá", "vendé", "aprovechá", pero no atrapa, por ejemplo, "top stock picks", "price target", "predicción de precio", "qué comprar", "dónde invertir", ni los imperativos neutros "compra", "vende", "invierte". Los canales de la lista (Yahoo Finance, CNBC Television, Bloomberg Línea) producen esos títulos. Un video de un medio que dice "comprá X" dentro de un producto que dice "Información, no una recomendación" es una contradicción visible.
Texto propuesto: ampliar la lista compartida (`_shared/recommendation.ts` y `WidgetItemsSelector.recommendation`, que tienen que cambiar juntas) con casos de prueba en es y en. Para videos, sumar una lista de canales mixtos con filtro reforzado.
Revisión humana: no. Dueños: `porty-backend-dev` y `porty-assistant-dev`.

[CORREGIR] H7. La spec y el código no coinciden: "se abre en YouTube" (D4) frente a reproductor embebido
Por qué: la spec dice que el embebido queda como pregunta P6 y el código ya lo tiene. Quien lea la spec para armar la ficha de las tiendas, el paywall o la política de privacidad va a describir algo distinto de lo que hace la app. Eso afecta los privacy labels y los textos de la sección 4.
Texto propuesto: actualizar §2 y D4 de la spec y cerrar P6 como "embebido con respaldo". Aviso a `porty-product-owner`: el embebido suma WebView como dependencia y las obligaciones de la sección 3 (puede cambiar el alcance de la ficha y de la privacidad).
Revisión humana: no.

[CORREGIR] H8. Privacy labels, Data safety y miniaturas
Por qué: las miniaturas se descargan de `i.ytimg.com` al ver el feed, y el reproductor carga código de Google. Apple pide declarar los datos que recopilan los socios de terceros integrados en la app, y Google Play pide lo mismo en Data safety. El código no lo declara en ninguna parte.
Texto propuesto: sección 4.2 (párrafo YouTube) y 4.3 (tabla). Para el EEE, Reino Unido y Suiza, evaluar si hace falta consentimiento antes de cargar contenido de Google; una opción de bajo costo es mostrar las miniaturas solo después de que el usuario abra el feed (ya es así) y cargar el reproductor solo al tocar (ya es así).
Revisión humana: sí.

[CORREGIR] H9. `cnv.gov.ar` en la migración de catálogos
Por qué: dominio probablemente desactualizado. Habilitarlo no sirve, y reemplazarlo por `argentina.gob.ar` abriría todo el sitio del Estado al filtro de búsqueda.
Texto propuesto: dejarlo apagado. Si el usuario quiere la CNV, que confirme el dominio y los términos, y que backend lo corrija con una migración nueva (no se edita la existente).
Revisión humana: no.

[SUGERENCIA] H10. Revisar la lista ya habilitada con el mismo criterio
Por qué: `nytimes.com` es demandante contra OpenAI (en trámite); `seekingalpha.com`, `thestreet.com`, `investing.com` y `forbes.com` mezclan opinión y "picks"; `finance.yahoo.com` ya figuraba en el runbook como "sacar si no se quiere". La lista de 46 dominios nunca se revisó con el modelo "paráfrasis de IA diaria", que es más intenso que el de antes (una consulta a demanda).
Texto propuesto: sacar `nytimes.com` mientras dure el litigio, o pedirle una decisión explícita al usuario. Revisar los otros cuatro con la condición C.
Revisión humana: sí.

[SUGERENCIA] H11. Detalles del reproductor
Por qué: (a) la URL de embed del servidor (`embedUrl`) incluye `modestbranding=1`, un parámetro que YouTube dejó sin efecto: no aporta nada y puede leerse como intento de ocultar marca; sacarlo. (b) `showFullscreenButton: false` no infringe nada, pero conviene permitir pantalla completa por usabilidad y para no tapar controles. (c) `strictRelatedVideos: true` es buena práctica (los relacionados quedan del mismo canal).
Revisión humana: no.

---

## 6. Riesgos que quedan y qué decide el usuario

### Riesgos

- **R1. Derechos de autor en los resúmenes de IA.** "Paráfrasis + cita + link" baja el riesgo, pero no lo elimina: hay demandas abiertas contra proveedores de IA (NYT contra OpenAI y Microsoft; los medios canadienses contra OpenAI; Nikkei y Asahi contra Perplexity; ANI y el DNPA en India). Ninguna es contra una app como Porty, pero Porty depende de la búsqueda web de OpenAI. **Abogado: sí.**
- **R2. Derecho de los editores de prensa en la UE** (Directiva 2019/790, art. 15; en España, art. 129 bis de la LPI según la transposición de 2021). Quedan fuera el enlace y las "palabras sueltas o extractos muy breves"; una paráfrasis de varias oraciones por IA podría quedar adentro, y España limitó la excepción a extractos "muy breves o de poca relevancia". Si Porty se ofrece en la UE, esto aplica a medios españoles, franceses, alemanes e italianos de la lista actual, no solo a los nuevos. **Abogado: sí.**
- **R3. Transparencia de contenido generado por IA** (AI Act, art. 50): alcance y fecha de aplicación sin confirmar. Abogado: sí.
- **R4. Políticas de YouTube sin leer en la fuente.** Releer Developer Policies, la guía de cumplimiento y el requisito de identificación del cliente antes del lanzamiento general. La clave de la API puede ser auditada.
- **R5. Términos de los medios sin leer.** La condición C (10 a 15 minutos por medio) la hace una persona. Ningún "con condición" se enciende sin esa constancia.
- **R6. Retiro de contenido.** No hay casilla de contacto ni plazo definidos para pedidos de retiro. Necesita `{email}` real y un responsable que la lea.
- **R7. Recomendaciones de terceros dentro del contenido** (títulos de notas, videos). Los validadores y `isRecommendation` reducen, no eliminan. H5 reduce más.
- **R8. Fuentes oficiales con permiso comercial dudoso** (BoE, BoJ, INDEC): quedan "con condición" porque solo se parafrasean hechos y se enlaza, pero no son un permiso expreso.
- **R9. Videos y pricing.** Si en algún momento se quiere cobrar por videos o por "mejor calidad de video", YouTube lo prohíbe: aviso a monetization.
- **R10. Medios que cambian de postura.** Un medio puede bloquear a OpenAI o demandar después de que lo habilitemos: hay que poder apagarlo sin deploy (`enabled=false`, ya existe).

### Qué decide el usuario

1. **Lista de medios y fuentes oficiales (P8).** Aprobar los 4 "Habilitar" ya, delegar en alguien la condición C de los 13 "con condición", y confirmar que los 13 "No habilitar" quedan apagados. Si hay un medio que quiere sí o sí, me lo dice y lo reviso aparte.
2. **Permisos a pedir.** ¿Querés pedir autorización al FMI (copyright@imf.org) y al BCRA? Se piden por escrito y los manda el usuario.
3. **Videos.** Aprobar el arranque con los 12 canales de Prioridad 1, resolver los ids con la clave (P1) y decidir qué hacer con H2: ¿esperar a la versión 6.x del paquete (Flutter 3.47+) o abrir en YouTube en Android hasta tenerla? Confirmar también el cierre de P6: embebido con respaldo.
4. **Abogado.** Contratar una consulta breve para R1, R2 y R3, y para los Términos y la Privacidad completos.
5. **Casilla y plazo de retiro de contenido** (`{email}`, `{plazo}`), y quién la atiende.
6. **`nytimes.com`** (H10): ¿se saca mientras dure el litigio?
7. **Texto del rótulo de IA y del teaser de Premium** (H6 y H6b), para pasarlo a flutter y monetization.
8. **Al Jazeera:** si querés evitarlo por marca, queda en "No habilitar" por decisión tuya, no por compliance.

### Orden sugerido

1. Hoy: lista interna con el interruptor, con los 4 oficiales habilitados y los canales de Prioridad 1 solo si ya tenés los ids resueltos.
2. Antes del lanzamiento general: H1, H2, H3, H4, H5, H6, H8 cerrados, Términos y Privacidad publicados, consulta con abogado, constancias de la condición C de cada "con condición".
3. En paralelo: H7 (spec), H9 y H10.
