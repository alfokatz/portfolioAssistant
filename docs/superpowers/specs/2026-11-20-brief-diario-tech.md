# Spec técnica: Brief diario de tu cartera (alcance completo)

**Fecha:** 2026-11-20 · **Autor:** porty-architect · **Implementa:** `docs/product/briefs/2026-11-20-brief-diario-de-cartera.md` (el bloque "Actualización del usuario (20/11)" pisa §16 y lo marcado "Afuera") y las decisiones del 20/11 y del 05/11 de `docs/product/decisions.md`. **Evidencia:** `docs/superpowers/specs/2026-11-20-brief-diario-research-notes.md` (archivo:línea y URLs).

**Estado:** lista para implementar detrás de `app_config.daily_brief`, apagado en producción.

---

## 1. Objetivo

Cada mañana hábil, a las 8:00 de su hora, el usuario con cartera ve en un minuto qué pasó con **lo suyo**: cómo cerró la cartera, qué pesó, con qué noticias coincidió (con medio y link) y qué pasa en el mercado y en los temas que sigue. Alrededor del brief hay:

- un **feed de noticias** de cartera, watchlist y temas;
- **"Mercado hoy"**: tendencias explicadas con calma;
- **videos** de canales oficiales de medios;
- **"¿Cómo me afecta?"**: abre el chat con la noticia como contexto;
- **"Qué dice cada medio"**: compara fuentes;
- preferencias de **temas** y **medios**.

Es global por defecto, y lo argentino es un tema más.

**"Listo"** quiere decir dos cosas:

1. Con el interruptor prendido para la lista interna, los criterios de §9 pasan en Free, Premium y Gold, en es y en en.
2. Con el interruptor apagado no cambia nada para nadie: ni push, ni Home, ni `morning_brief`, ni chat.

## 2. Fuera de alcance

- Audio/TTS. Queda solo el punto de extensión `payload.audio` (§3.4).
- Fines de semana. Tampoco hay un brief cripto aparte.
- Elegir la hora, mandar por mail, compartir, historial de más de 2 días y calendario económico.
- Temas de texto libre (el catálogo es cerrado) y medios o canales fuera de las allowlists.
- Rankings de "lo que más sube/baja" o "lo más buscado". Tampoco noticias de tickers que el usuario no tiene ni sigue (eso sigue siendo Gold en el chat, como hoy).
- Videos asociados a tickers: solo de mercado y de temas (D4).
- Integración con el widget de inicio (v1.1).
- Recomendaciones de cualquier tipo.

---

## 3. Contrato de datos

### 3.1 Decisiones de arquitectura

| # | Decisión | Por qué (una línea) |
|---|---|---|
| A1 | **El brief se genera en la app al abrirlo**, como el informe semanal: números con `PortfolioDayMove` y aportes por posición, 1 llamada al LLM vía `ai-chat` en modo `daily_brief` (no cobra cuota), validador en Dart y guardado con `complete_daily_brief`. | Los números son idénticos a la línea 1D de la Home (misma cuenta) y la IA la pagan solo los que leen. |
| A2 | **Free no llama al LLM.** Recibe los números (sin IA), 1 hecho de mercado ya redactado y validado en la caché compartida, y un aviso sin ticker. | El costo variable de Free es US$0. |
| A3 | **Todo el contenido de noticias del brief y del feed llega por una edge function nueva, `daily-brief`.** Lee cartera, watchlist, temas y medios desde la base: el cliente no manda tickers. Plan y cortesía se aplican en el servidor. | El cliente no puede pedir más de lo que su plan le da, y no hace falta abrir `gold_data_allowed` como hace el semanal. |
| A4 | **Caché de titulares por ticker y por día.** GDELT se consulta en lotes de hasta 10 nombres, solo para lo que falta. Un cron calienta los tickers más tenidos antes de las 8 de cada región. | La clave por conjunto de tickers de `headlines` hace que cada cartera sea un miss, y el limitador global de GDELT (1 pedido cada 5,5 s, unas 650 por hora) no aguanta el pico de las 8. |
| A5 | **Lo general es compartido y gratis en todos los planes; el cruce con lo tuyo es pago.** "Mercado hoy", resúmenes de temas y videos se generan una vez por región o tema, idioma y franja. | Coherente con el 05/11 (se gatean noticias de tickers, no lo que regala cualquier medio), y el costo no crece con los usuarios. |
| A6 | **Medios preferidos y silenciados se aplican después de la caché** (reordenar y filtrar), nunca en la clave. | No fragmenta la caché compartida. |
| A7 | **Los temas son un catálogo cerrado en la base** (`news_topics`). Los temas por defecto se calculan por mercado y clase de activo de la cartera; solo se guarda lo que el usuario cambia. | Cero configuración, global y sin listas de tickers en el código (regla 10). |
| A8 | **Comparar fuentes es una edge function propia (`news-compare`)** con validador de atribución en el servidor. En el chat se usa con la tool `compare_sources` y la card `QaSourceComparison`; desde el feed se abre el chat con una pregunta de plantilla. | Un solo camino de costo y de validación; el chat es el centro del producto. |
| A9 | **Videos: YouTube Data API v3 sobre una allowlist de canales de medios.** Se lee la lista de subidas de cada canal por cron (`playlistItems.list`, 1 unidad), nunca `search.list`. Se asignan a temas por palabras clave, sin LLM. Son gratis en todos los planes y se abren en YouTube. | Contenido publicado por el propio medio, cuota fija y chica, y las políticas de YouTube prohíben vender el acceso al contenido audiovisual (no puede ir detrás de un plan). |
| A10 | **El push `daily_brief` reemplaza a `morning_brief`** para quien tiene el interruptor prendido: misma preferencia (`notification_preferences.morning_brief`), mismo horario y plantilla sin números. Sin el interruptor, `morning_brief` sigue igual. | Decisión del usuario: un solo push a la mañana. |
| A11 | **"¿Cómo me afecta?" no agrega una tool.** Es `screen_context` con la noticia, más una guía en el contexto fijado de cada turno, que no forma parte del hash. | Cero tokens fijos nuevos y sin deploy por esta pieza. |

### 3.2 Migraciones (todas nuevas e idempotentes; dueño: backend)

Archivos sugeridos:

- `supabase/migrations/20261121100000_daily_brief.sql`: esquema, RPC, interruptor y cron.
- `supabase/migrations/20261121100100_daily_brief_catalogs.sql`: semillas.

Nunca se edita una migración existente. Las funciones que se redefinen copian el cuerpo **vigente**, indicado en cada caso.

**Interruptor.** Fila en `app_config` con formato `PortyRolloutFlag`, insertada con `on conflict do nothing`:

```json
{ "percent": 0, "users": [],
  "courtesy_days": 7, "courtesy_since": "2026-12-01",
  "pieces": { "push": true, "feed": true, "topics": true, "sources": true,
              "market": true, "compare": true, "videos": true } }
```

- `public._daily_brief_on(uid)` = `_rollout_on('daily_brief', uid)`. El servidor decide y la app no lee el flag (lo recibe en `daily_brief_status`).
- `public._daily_brief_piece(p_key text) returns boolean`: si la clave falta, vale `true`.
- `courtesy_days` se acota a 1..15.
- `courtesy_since`: solo las cuentas creadas desde esa fecha son "altas nuevas" con cortesía. La base actual no recibe regalo sin que el usuario lo decida (§11, P4). Las cohortes de noviembre no se tocan: el interruptor es propio y `app_config_history` registra sus cambios.

**Tablas nuevas.** Todas con RLS. Las que tienen datos del usuario llevan FK `on delete cascade` a `auth.users`.

```sql
create table if not exists public.daily_briefs (
  user_id uuid not null references auth.users(id) on delete cascade,
  brief_day date not null,                      -- fecha LOCAL del usuario
  status text not null check (status in ('generating','ready','failed')),
  variant text not null check (variant in ('full','numbers')),
  courtesy boolean not null default false,
  payload jsonb,                                -- §3.4, <= 64 KB
  attempts smallint not null default 1,
  llm_rounds smallint not null default 0,
  claimed_at timestamptz not null default now(),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (user_id, brief_day)
);
create index if not exists daily_briefs_courtesy_idx on public.daily_briefs (user_id) where courtesy;
-- RLS: select propio. Sin policies de escritura (solo RPC).

create table if not exists public.news_topics (               -- catálogo cerrado
  id text primary key check (id ~ '^[a-z0-9_]{2,40}$'),
  kind text not null check (kind in ('macro','asset','sector','region','market')),
  label_es text not null, label_en text not null,
  query_en text not null, query_es text not null,             -- para la búsqueda web
  keywords text[] not null default '{}',                      -- es+en, para videos
  auto_markets text[] not null default '{}',                  -- 'US','.BA','.MC','.L','.T','.HK','.SA','.MX',...
  auto_asset_classes text[] not null default '{}',            -- 'crypto','bond','etf','equity'
  asset_link_es text, asset_link_en text,                     -- frase fija "tenés X que..." (mapeo tema→clase)
  default_global boolean not null default false,
  region text not null default 'global',
  sort smallint not null default 100,
  enabled boolean not null default true
);
-- RLS: select para authenticated; escribe service_role.

create table if not exists public.user_news_topics (
  user_id uuid not null references auth.users(id) on delete cascade,
  topic_id text not null references public.news_topics(id) on delete cascade,
  followed boolean not null,           -- false = apagó un "por defecto"
  updated_at timestamptz not null default now(),
  primary key (user_id, topic_id)
);
-- RLS: CRUD propio. Trigger: hasta 12 con followed = true ('topic_limit_reached').

create table if not exists public.user_news_sources (
  user_id uuid not null references auth.users(id) on delete cascade,
  domain text not null references public.news_source_allowlist(domain) on delete cascade,
  preference text not null check (preference in ('prefer','mute')),
  updated_at timestamptz not null default now(),
  primary key (user_id, domain)
);
-- RLS: CRUD propio. Trigger: hasta 10 'prefer' y 10 'mute' ('source_limit_reached').

create table if not exists public.video_channel_allowlist (
  channel_id text primary key check (channel_id ~ '^UC[A-Za-z0-9_-]{22}$'),
  uploads_playlist_id text not null,
  name text not null,
  outlet_domain text references public.news_source_allowlist(domain),
  lang text not null check (lang in ('es','en')),
  region text not null default 'global',
  enabled boolean not null default true
);
-- RLS habilitado, sin policies (solo service_role).

create table if not exists public.news_videos (               -- caché, se purga a los 7 días
  video_id text primary key,
  channel_id text not null references public.video_channel_allowlist(channel_id) on delete cascade,
  title text not null,
  published_at timestamptz not null,
  lang text not null,
  topic_ids text[] not null default '{}',
  region text not null,
  fetched_at timestamptz not null default now()
);
-- RLS habilitado, sin policies (se sirve por `daily-brief`).

create table if not exists public.market_reference_instruments (
  symbol text primary key,
  kind text not null check (kind in ('index','sector','commodity','rate','fx','crypto')),
  region text not null,
  label_es text not null, label_en text not null,
  markets text[] not null default '{}',     -- mercados de cartera que lo suman a "Mercado hoy"
  core boolean not null default false,      -- se muestra siempre
  sort smallint not null default 100,
  enabled boolean not null default true
);
-- RLS: select para authenticated; escribe service_role.
```

**Columnas nuevas en `news_source_allowlist`** (`add column if not exists`):

| Columna | Definición | Para qué |
|---|---|---|
| `region` | `text not null default 'global'` | Elegir medios según los mercados de la cartera. |
| `kind` | `text not null default 'media' check (kind in ('media','official'))` | Distinguir medios de fuentes oficiales. |
| `gdelt_priority` | `smallint`, null = no va en la cláusula `domain:` | Reemplaza la lista fija `queryDomains` de `_shared/gdelt.ts`. |

Se mantiene `lang in ('es','en')`. Además: `grant select (domain, name, lang, region, kind)` a `authenticated` y una policy de lectura, para la pantalla de medios.

**Semillas.** Las carga backend con `on conflict do nothing`; compliance revisa la lista de medios y de canales antes del lanzamiento.

- **Medios globales nuevos.** Candidatos: Nikkei Asia, South China Morning Post, The Economic Times, Mint, Business Standard, The Globe and Mail, Financial Post, Australian Financial Review, The Straits Times, DW, France 24, Euronews, Al Jazeera y Caixin Global. En español: Portafolio y La República (CO), Gestión (PE), Diario Financiero (CL), El Confidencial y Europa Press (ES). La lista final sale de la medición de §8.
- **Fuentes oficiales** (`kind = 'official'`): federalreserve.gov, ecb.europa.eu, bankofengland.co.uk, boj.or.jp, bls.gov, bea.gov, imf.org, bcra.gob.ar, indec.gob.ar y cnv.gov.ar. Son primarias y no tienen problema de licencia.
- **`news_topics`** (unos 16):
  - globales por defecto: `fed_rates`, `inflation`, `earnings_season`, `oil_energy`, `global_indices`;
  - por cartera: `ecb_rates` (EU), `boe_rates` (`.L`), `boj_rates` (`.T`), `china_economy` (`.HK .SS .SZ`), `crypto` (clase `crypto`), `bonds_rates` (clase `bond`), `tech_ai` (sector), `latam_markets`, `emerging_markets`, `ar_bcra_dollar` y `ar_country_risk_cer` (`.BA`).
  - `asset_link_*` es el mapeo **fijo y chico** tema → clase de activo del brief §4.5 (por ejemplo `bonds_rates` → "tenés bonos o ETF de renta fija").
- **`market_reference_instruments`**:
  - core: `^GSPC ^IXIC ^DJI ^STOXX50E ^N225 CL=F GC=F ^TNX BTC-USD`;
  - por mercado de la cartera: `^MERV` (.BA), `^IBEX` (.MC), `^FTSE` (.L), `^HSI` (.HK), `^BVSP` (.SA), `^MXX` (.MX);
  - sectores de EE. UU. con `kind = 'sector'`.
  - Es un catálogo de referencias de mercado en la base, no una lista de tickers del usuario en el código.
- **`video_channel_allowlist`**: canales oficiales de medios que ya están en la allowlist (por ejemplo Reuters, Bloomberg Television, CNBC Television, Yahoo Finance, WSJ, Financial Times, DW News, France 24 en es/en, Bloomberg Línea y CNN en Español). Backend resuelve `channel_id` y `uploads_playlist_id` con `channels.list` (1 unidad cada uno) al cargar la semilla.

**Notificaciones:**

- `notification_outbox_kind_check` se redefine con `'daily_brief'`. Copiar la lista vigente: la última definición está en `20261024000300_contribution_reminder.sql`; backend lo confirma con un grep antes.
- `push_dispatch_context` se redefine sumando `'daily_brief'` al conteo de automáticos de 24 h (copiar el cuerpo vigente del mismo archivo).
- No hay preferencia nueva: se usa `morning_brief`.

**Uso de IA:** el check de `ai_turn_usage.purpose` pasa a `('chat','weekly_report','daily_brief')` (drop + add constraint).

**Cron.** Mismo patrón que `20261113000000_sync_prod_drift.sql:153-160`: `do $$ if exists pg_cron` y `cron.schedule('news-warm', '*/15 * * * *', $c$select public._call_function('news-warm')$c$)`.

**Borrado de cuenta.** `daily_briefs`, `user_news_topics` y `user_news_sources` tienen cascade y se suman al catálogo de `supabase/tests/account_deletion_db_test.sql`. No guardan nada fuera de una FK.

### 3.3 RPC

**De la app** (rol `authenticated`, con `auth.uid()`):

| RPC | Devuelve |
|---|---|
| `daily_brief_status()` | `{enabled, pieces:{push,feed,topics,sources,market,compare,videos}}`. Con `enabled = false`, la app no muestra nada nuevo. |
| `claim_daily_brief(p_day date)` | `{state}`. Los estados están abajo. |
| `complete_daily_brief(p_day date, p_payload jsonb)` | `{ok}` o `{ok:false, reason}` con reason `invalid_payload`, `payload_too_large` o `not_claimed`. |
| `fail_daily_brief(p_day date)` | `{ok}` |

Estados de `claim_daily_brief`:

| `state` | Significa | Datos extra |
|---|---|---|
| `disabled` | El interruptor no cubre al usuario. | — |
| `no_portfolio` | No tiene posiciones. | — |
| `not_business_day` | El día no es hábil o no es plausible. | — |
| `ready` | El brief del día ya está guardado. | `payload`, `variant`, `courtesy` |
| `claimed` | Le toca a este dispositivo generar el brief completo. | `variant:'full'`, `courtesy`, `courtesy_number?`, `courtesy_total?`, `attempt` |
| `numbers_only` | Free sin cortesía: la app arma el brief sin LLM y lo guarda con `complete_daily_brief`. | — |
| `in_progress` | Otro dispositivo lo está generando. | — |
| `failed` | Se agotaron los intentos. | — |

Reglas de `claim_daily_brief`. El patrón es el de `claim_weekly_report` en `20261103120000`:

- `p_day` es plausible si está entre `utc_date - 1` y `utc_date + 1` y es día hábil (isodow 1–5). Si no, `not_business_day`.
- Sin posiciones con `quantity > 0`: `no_portfolio`.
- Variante `full` en dos casos:
  - tier Premium o Gold;
  - cortesía: cuenta creada en o después de `courtesy_since` y menos de `courtesy_days` briefs `courtesy` usados, con `pg_advisory_xact_lock` igual que `_weekly_courtesy_limit`.
- En cualquier otro caso, `numbers_only`. `complete_daily_brief` acepta `variant = 'numbers'` sin un claim previo e inserta la fila en `ready`.
- Claim con TTL de 2 minutos y hasta 3 intentos (`_report_claim_ttl()`, `_report_max_attempts()`).

**Del servidor** (service role):

- **`ai_brief_begin(p_user_id, p_turn_id, p_day, p_model, p_max_rounds, p_rate_per_minute)`.** Es la copia de `ai_report_begin` vigente (`20261106100000`) contra `daily_briefs`: exige `generating` con el claim vigente, `llm_rounds < p_max_rounds` y `_daily_brief_on`, y registra `purpose = 'daily_brief'`.
- **`daily_brief_entitlement(p_user_id, p_day)`.** Devuelve:

  ```
  {tier, variant, courtesy, held:[{symbol, weight_pct}], watchlist:[symbol],
   topics:[id], prefer:[domain], mute:[domain], markets:[...], asset_classes:[...]}
  ```

  Resuelve todo en una sola consulta a la base:
  - `variant` sale de la fila del día; si no existe, de la regla del claim, sin escribir.
  - `topics` = (temas por defecto según mercados y clases de la cartera) ∪ seguidos − apagados.
  - `weight_pct` sale de `push_holding_weights`.
- **`daily_brief_push_inputs(p_user_ids uuid[])`.** Devuelve tenencias, tier, `big_move_sensitivity`, si el interruptor y la pieza `push` están prendidos y `show_amounts`.
- **`daily_brief_warm_symbols(p_timezones text[], p_limit int)`.** Devuelve los símbolos más tenidos por usuarios de esos husos, con su conteo y sin `user_id`.

Permisos: `revoke all from public, anon`; las de la app con `grant execute` a `authenticated`, y las demás solo a `service_role`.

### 3.4 Payload del brief (`daily_briefs.payload`) y contrato con el LLM

```json
{
  "v": 1, "day": "2026-12-02", "lang": "es", "variant": "full",
  "as_of": "2026-12-02T08:03:11Z",
  "numbers": { "period": "last_close", "as_of_day": "2026-12-01",
               "abs": 312.4, "pct": 0.82,
               "movers": [ {"ticker":"NVDA","pct":4.1,"contribution_abs":220.0,"weight_pct":18.2} ] },
  "why":       [ {"ticker":"NVDA","text":"Subió 4,1 % el día que presentó resultados.","news_id":"h1"} ],
  "held_news": [ {"ticker":"AAPL","text":"...","news_id":"h3"} ],
  "watch_news":[ {"ticker":"MELI","text":"...","news_id":"h5"} ],
  "market":    [ {"topic_id":"fed_rates","text":"...","source_ids":["p1"],"connection":"..."} ],
  "earnings":  [ {"ticker":"CRM","kind":"reported|estimated","date":"2026-12-01","url":"https://www.sec.gov/..."} ],
  "signals":   [ {"kind":"concentration","ticker":"NVDA","weight_pct":31.0} ],
  "teaser":    null,
  "sources":   { "h1": {"title":"...","source":"Reuters","domain":"reuters.com","url":"...","published_at":"..."} },
  "audio":     null
}
```

Quién escribe cada campo:

- **La app, sin IA:** `numbers`, `movers` (2–3 por aporte absoluto), `signals` (de `PortyInsightsBuilder`, los mismos umbrales que `morning_brief`), `earnings`, `market[].text` y `source_ids` (vienen tal cual del pulso validado) y `sources`.
- **El LLM:** devuelve solo `why[].text`, `held_news[].text`, `watch_news[].text` y `market[].connection`, con los ids de la entrada y en `json_schema` estricto, como el semanal.
  - `connection` solo puede parafrasear el `asset_link_*` del tema, y solo si el usuario tiene esa clase de activo. Si no, va `null`.
- **Free (`numbers`):** `why`, `held_news` y `watch_news` vacíos; `market` con 1 ítem sin `connection`; `teaser = {"kind":"held_news","required_plan":"premium"}`, sin ticker.
- **Gold:** `watch_news` y `earnings`. `reported` es un 8-K 2.02 presentado desde el último cierre (confirmado, con link a la SEC); `estimated` es una próxima fecha estimada en los 3 días hábiles siguientes, siempre rotulada como "estimada", porque la SEC no publica calendario.
- **`audio`:** punto de extensión del TTS. En v1 siempre es `null`, la pantalla lo ignora y el validador de `complete_daily_brief` lo acepta solo como `null` o como objeto `{url, duration_s}`.
- **Idioma:** se genera en el idioma de la app. Si el usuario lo cambia en el día, la prosa queda en el idioma original y los rótulos se traducen. No hay traducción en v1: el brief vive un día.
- **Día sin cierre nuevo:** si `PortfolioDayMove.asOfDay` no es más nuevo que el `numbers.as_of_day` del brief anterior (feriado de todos los mercados de la cartera), no hay brief del día. La fila de la Home se oculta y el push no sale.

### 3.5 Edge function nueva `daily-brief` (dueño: backend)

Llamada: `GET /functions/v1/daily-brief?scope=<scope>&lang=es|en&day=YYYY-MM-DD[&topic=<id>]` con JWT.

- Rate limit: 20 por minuto (`rate_limit_hit`, bucket `daily_brief`).
- Siempre arranca con `daily_brief_entitlement`. El cliente nunca manda tickers.

| scope | Uso | Contenido |
|---|---|---|
| `brief` | Entrada para generar el brief | `numbers`: `market` (pulso de la región principal de la cartera, 1 ítem). `full`: `mine` de las 8 posiciones de más peso (48 h, hasta 3 titulares por ticker), `watch` (solo Gold), `earnings` (solo Gold) y `market` (hasta 3, con prioridad a los temas seguidos). |
| `feed` | Pantalla de noticias | `mine` (Premium y cortesía: cartera; Gold: más la watchlist). En Free, en lugar de `mine` va `locked: {mine_tickers_48h}`, un número sin tickers (mismo cálculo que `headlines?count_only`). Además `topics` (digests de los temas, todos los planes) y `videos` (todos). |
| `market` | Mercado hoy | `instruments` (core más los de los mercados de la cartera, con variación del último cierre, caché de 10 min), `pulse` de las regiones de la cartera y `videos` de mercado. Todos los planes. |
| `topic` | Detalle de un tema | Digest del tema, titulares de la allowlist que lo nombran (caché GDELT por tema) y videos. Todos los planes. |

Forma de la respuesta:

```json
{
  "status": "ok",
  "as_of": "2026-12-02T08:01:00Z",
  "plan": { "tier": "premium", "variant": "full", "courtesy": false },
  "mine": [ { "id":"h1","ticker":"NVDA","kind":"held|watch","title":"...","source":"Reuters",
              "domain":"reuters.com","url":"...","published_at":"...","lang":"en","preferred":true } ],
  "locked": null,
  "earnings": [ {"ticker":"CRM","kind":"reported","date":"2026-12-01","url":"https://www.sec.gov/..."} ],
  "topics": [ { "topic_id":"fed_rates","label":"Fed y tasas","status":"ok|empty|failed",
                "summary":[ {"text":"...","source_ids":["c1"]} ], "as_of":"..." } ],
  "market": { "instruments":[ {"symbol":"^GSPC","label":"S&P 500","kind":"index","pct":-0.4,"as_of":"..."} ],
              "pulse":[ {"text":"...","source_ids":["p1"],"topic_id":"fed_rates"} ] },
  "videos": [ { "video_id":"abc","title":"...","channel":"Reuters","published_at":"...",
                "topic_id":"fed_rates","url":"https://www.youtube.com/watch?v=abc",
                "thumbnail":"https://i.ytimg.com/vi/abc/mqdefault.jpg" } ],
  "sources": { "c1": {"title":"...","source":"AP","domain":"apnews.com","url":"..."} },
  "attribution": { "videos": "YouTube" }
}
```

Errores:

| Código | Tipo |
|---|---|
| 401 | `unauthorized` |
| 400 | `invalid_scope`, `invalid_day`, `invalid_topic` |
| 403 | `disabled` (interruptor o pieza apagada) |
| 429 | `rate_limited` |

Si falla una pieza, la respuesta igual es 200: ese bloque viene con `status: "failed"` o vacío.

Reglas internas:

- **Titulares.** Función nueva `headlinesByTicker(deps, symbols, day)` en `_shared/gdelt.ts`.
  - Lee `gdelt:t:<SYM>:<day>`. TTL: 30 minutos hasta las 12 UTC y 2 horas después.
  - Lo que falta va en lotes de hasta 10 nombres, se reparte con `assignByName` y se guarda por ticker.
  - Si el limitador global no da turno en 7 segundos, devuelve lo que haya y nunca lanza.
  - Filtra `isRecommendation` y `looksLikeInstructions` (portar la regex de `weekly_report_input_builder.dart:145-155` a Deno).
  - Nombre de búsqueda: el de la SEC (`resolveCik`) o, si no hay CIK (tickers no listados en EE. UU.), el `longName`/`shortName` de Yahoo limpiado con `pressName`. Hay que parsear esos campos en `market-watch/quotes.ts` o en un helper de `_shared`.
  - Cláusula `domain:`: hasta 8 dominios por `gdelt_priority`, elegidos según la `region` de los tickers del lote.
- **Medios.** `mute` filtra. `prefer` pone `preferred: true` y ordena primero dentro de cada ticker y en los digests (las `source_ids` preferidas van primero). Nunca entran en una clave de caché.
- **Pulso y temas.** Módulo nuevo `_shared/news_digest.ts`: Responses API con `web_search`, `filters.allowed_domains` = la allowlist habilitada (medios y oficiales, hasta 100), `search_context_size: medium` y `reasoning.effort: low`.
  - Salida: 2–4 viñetas de una oración. Cada viñeta tiene al menos 1 cita cuya anotación cae dentro de esa oración (validador de atribución, compartido con §3.6). Lo que no tiene cita se descarta.
  - Claves de caché: `digest:pulse:<region>:<lang>:<utc_day>:<slot6h>` y `digest:topic:<id>:<lang>:<utc_day>:<slot12h>`.
  - Generación perezosa con `pg_try_advisory_lock(hashtext(key))`: un solo generador; el resto sirve la entrada anterior o `status: "empty"`.
  - **No gasta cupo del usuario.** Es costo de Porty, acotado por catálogo × idiomas × franjas (§7). Se registra en `ai_turn_usage` con `user_id = null` (o con una fila de sistema; backend elige) y `purpose = 'daily_brief'` para poder medirlo.
  - Prompt: "inform, never recommend; no causes stated as fact; paraphrase; every sentence cites". Mismas reglas que `news-context`.
- **Videos.** Lee `news_videos` de las últimas 48 h, de los temas del usuario y de la región. Hasta 3 por bloque, con preferidos primero según `outlet_domain`. Si no hay ninguno, el bloque viene vacío y la app no muestra la sección.

### 3.6 Edge function nueva `news-compare` (dueño: backend)

Llamada: `POST /functions/v1/news-compare` con JWT y `x-porty-turn-id`.

```json
{ "ticker": "NVDA", "topic_id": null, "story_url": "https://www.reuters.com/...", "lang": "es" }
```

Va exactamente uno de `ticker` o `topic_id`. `story_url` es opcional: si su dominio no está en la allowlist, se ignora.

```json
{
  "status": "ok | insufficient_sources | empty",
  "subject": "NVIDIA (NVDA)",
  "points": [
    { "kind": "agree",  "text": "Reuters y CNBC informan que ...", "source_ids": ["s1","s2"] },
    { "kind": "differ", "text": "Bloomberg Línea pone el foco en ...", "source_ids": ["s3"] },
    { "kind": "only",   "text": "Según Expansión, ...", "source_ids": ["s4"] }
  ],
  "outlets": ["Reuters","CNBC","Bloomberg Línea","Expansión"],
  "sources": { "s1": {"title":"...","source":"Reuters","domain":"reuters.com","url":"..."} },
  "as_of": "..."
}
```

Errores:

| Código | Tipo |
|---|---|
| 403 | `plan_required {required_plan}`, `disabled` |
| 429 | `turn_limit`, `daily_limit`, `monthly_limit`, `rate_limited` |
| 502 | `upstream_failed` |

**Gating:**

- Ticker: `news_data_allowed(uid, ticker)`. Gold puede comparar cualquiera; Premium solo tickers en cartera.
- Tema: `gold_data_allowed(uid, null)`, solo Gold.
- Free: 403 con `required_plan` (`premium` para un ticker en cartera, `gold` para el resto).

**Costo y topes**, dentro de los de `news-context`, sin cupos nuevos:

- Caché compartida de 6 horas con clave `compare:<subject>|<story_url normalizada>|<lang>`. Un hit no gasta nada.
- Un miss gasta **3 unidades** de `news_context_quota_hit(uid, 3)`: 1 pedido del tope diario y 3 unidades del mensual. Así, Premium (80 unidades) hace hasta unas 26 comparaciones por mes y Gold (160) unas 53.
- Cuenta como la búsqueda del turno (`turn_web_search_calls` y `record_web_search_usage`), igual que `news-context`.

**Búsqueda:** 1 llamada a la Responses API con `web_search`, con la instrucción de cubrir al menos 3 medios distintos de la allowlist. Devuelve viñetas en texto, y backend arma los `points` a partir de las anotaciones.

**Validador de atribución** (determinístico, en `_shared/news_attribution.ts`, con tests Deno):

1. Cada punto tiene al menos 1 anotación dentro de su rango de texto, de un dominio de la allowlist, que pase `isArticleUrl`.
2. `agree` exige al menos 2 dominios distintos. Si tiene uno solo, pasa a `only`.
3. El texto nombra al medio de cada cita. Si no lo nombra, se antepone "Según <medio>," o "According to <outlet>,".
4. Se descartan los puntos con consejo (`isRecommendation` más una regex de comprar/vender/mantener en es/en), con comillas o con cifras que no estén en el título citado.
5. Si quedan menos de 2 medios distintos en total, el resultado es `insufficient_sources`. Se cachea 1 hora y se cobra, porque la búsqueda se hizo.

Refactor que hace falta: `citationsOf`, `allowedDomain`, `isArticleUrl`, `titleFromUrl` y `costUsd` pasan de `news-context/handler.ts` a `_shared/news_citations.ts`. `handler.ts` los re-exporta para que sus tests no cambien.

### 3.7 Cambios en edge functions existentes (dueño: backend; el allowlist es de assistant)

| Función | Cambio |
|---|---|
| `ai-chat/handler.ts` | Nuevo `x-porty-purpose: daily_brief` con el header `x-porty-brief-day`. Es copia de `handleReport`: allowlist `allowed_brief_prompts.json`, sin tools ni stream ni mensajes de sistema extra, `ai_brief_begin`, `maxBriefRounds = 2` y `maxBriefOutputTokens = 900`. No cobra cuota. **Requiere deploy de `ai-chat` (OK del usuario).** |
| `ai-chat/allowed_brief_prompts.json` | Archivo nuevo con los hashes del prompt del brief en es y en. **Dueño: assistant.** Backend crea el import con `{"hashes": []}` en su PR y assistant agrega los hashes. |
| `daily-jobs` | A las 8 locales: `dailyBriefRows` para los usuarios con el interruptor y la pieza `push`; `morningBriefRows` para el resto. A las 04 UTC: purga de `news_videos` de más de 7 días y de `daily_briefs` de más de 14. |
| `notify-dispatch` | Kind `daily_brief` en `kinds.ts`: `pref: morning_brief`, `automatic`, `minTier: free`, `quiet: defer`, `maxAgeMinutes: 360`, canal `reports`. Plantilla nueva en `templates.ts` con `route: daily_brief` y `routeArgs: {day}`. |
| `news-context` | Solo el refactor de §3.6, sin cambios de comportamiento. |
| `headlines` | Sin cambios de contrato. Lo siguen usando el chat y el widget. |
| `market-watch/quotes.ts` | Parsear `longName`, `shortName` y `regularMarketTime`, como campos opcionales. |

**Push de las 8.** Es la función pura `dailyBriefRows(users, inputs, quotes, headlineCounts, signals)` en `daily-jobs/jobs.ts`.

- Solo sale con `local_dow` de 1 a 5, cartera cargada y un cierre nuevo de algún mercado de la cartera (`regularMarketTime` posterior al brief anterior).
- Sale si hay **algo que contar**, al menos una de estas:
  - la variación de la cartera en el último cierre (sobre `prevClose` y `changePct`, con cobertura de al menos 80 %) supera el umbral `portfolio` de `thresholds[sensibilidad]` en `market-watch/moves.ts`;
  - algún ticker en cartera tiene un titular en las últimas 24 h, **mirando solo la caché ya calentada** (nunca se consulta GDELT por usuario);
  - hay una señal de concentración o desvío nueva en el mes (la regla de `morningBriefRows`);
  - en Gold, hay un resultado `reported` desde el último cierre.
- `data` del push: `{day, moved, news_tickers, signals, earnings}`, solo booleanos y conteos.
- Plantilla es/en, sin IA y sin montos, porcentajes ni tickers. Título "Tu brief de hoy está listo"; cuerpo con una línea armada de los conteos ("Tu cartera se movió más que de costumbre. Hay 2 noticias de lo tuyo.").
- `dedupe_key = daily_brief:<local_date>`.
- **Prioridad dentro del tope de 3 automáticos:** el brief es el primero del día, porque sale a las 8. Si el usuario ya tiene 3 automáticos en las últimas 24 h, no sale (el brief sigue en la Home). `big_move`, `portfolio_move` y `watchlist_move` del día compiten por los otros 2, como hoy.

### 3.8 Jobs y horarios

Todo lo que es "por usuario" usa la zona horaria del dispositivo (`push_devices.timezone`, la misma que `push_users_at_local_hour`).

| Job | Dónde | Cuándo | Qué hace |
|---|---|---|---|
| Push del brief | `daily-jobs` | 8:00 local, de lunes a viernes | Lo de §3.7. |
| Calentamiento de titulares | `news-warm` (función nueva, cron cada 15 min) | En los husos donde son entre las 6:00 y las 7:45 | Toma los 200 símbolos más tenidos de esos husos (`daily_brief_warm_symbols`) y llama a `headlinesByTicker`. Hasta 6 lotes por corrida (unos 35 s, por debajo del timeout de 55 s de `_call_function`). |
| Pulso y temas | `news-warm` | A las 6:30 de cada región: `us` (America/New_York), `eu` (Europe/Madrid), `latam` (America/Argentina/Buenos_Aires), `asia` (Asia/Tokyo) | Pulso de la región en es y en, y digest de los temas con al menos un seguidor en esa región, solo en los idiomas que tienen usuarios (`push_devices.locale`). Después de eso, generación perezosa. |
| Videos | `news-warm` | Cada 30 min | `playlistItems.list` (maxResults 10) por canal habilitado. Upsert en `news_videos` con `topic_ids` asignados por `keywords` y con `region`. Filtra `isRecommendation` en el título. |
| Purga | `daily-jobs` | 04:00 UTC | `news_videos` de más de 7 días (las políticas de YouTube piden refrescar o borrar los datos guardados a los 30 días) y `daily_briefs` de más de 14. |

### 3.9 Contrato app ↔ backend

- **`DailyBriefRepository`** (`lib/features/daily_brief/data/daily_brief_repository.dart`, de flutter):
  - `status()`, `claim(day)`, `complete(day, payload)` y `fail(day)` por RPC;
  - `bundle(scope, {topic})` por `PortyEdgeClient` (Dio), nunca con `functions.invoke`;
  - fallas tipadas con la clase sellada `DailyBriefFailure` (`disabled`, `network`, `server`, `notClaimed`).
- **`NewsPreferencesRepository`** (`lib/features/news_preferences/data/news_preferences_repository.dart`, de flutter): CRUD de `user_news_topics` y `user_news_sources` por PostgREST; lectura de `news_topics` y `news_source_allowlist`; errores `topic_limit_reached` y `source_limit_reached` tipados.
- **`DailyBriefGenerator`** (de assistant): `generate({required String day, required DailyBriefInput input, String? language}) → Future<DailyBriefGeneration>`. Nunca lanza y tiene la misma forma que `WeeklyReportGenerator` (`draft`, `rounds`, `remainingIssues`, `error`).
- **`DailyBriefInput`** (dominio, de assistant; flutter lo construye): `{numbers, movers, mine: List<BriefNewsItem>, watch, market: List<BriefMarketItem>, assetClasses: Set<String>, signals}` y `toPromptJson()`.
- **Fakes para arrancar en paralelo:**
  - fixtures en `test/fixtures/daily_brief/{bundle_brief_full,bundle_brief_numbers,bundle_feed_premium,bundle_feed_free,bundle_market,bundle_topic,compare_ok,compare_insufficient}.json`, que escribe backend como parte del contrato y que flutter y assistant usan como fake;
  - flutter: `FakeDailyBriefRepository` en `test/features/daily_brief/fakes/`;
  - assistant: `FakeDailyBriefGenerator` para que flutter no dependa del LLM.

### 3.10 Chat (dueño: assistant)

- **"¿Cómo me afecta?"**
  - `PortyScreen` suma `dailyBrief('daily_brief')` y `newsItem('news_item')`.
  - `PortyScreenContext` suma el campo opcional `news` `{title, source, url, published_at, ticker?, topic_id?}`, que se serializa en `toBrief`.
  - La pregunta es de plantilla (claves `daily_brief_ask_affects` y `news_ask_affects`).
  - `AssistantOpenAiService.pinnedContextFor` agrega `newsContextGuidance` cuando existe `screen_context.news`:
    - "You only know the headline; explain the user's exposure from the brief (weight, asset class), never state causes, never advise".
    - "For more context call get_news (the plan applies)".
    - "If the headline is about something they don't hold, say how little or how indirectly it touches them".
  - Free puede preguntar y gasta consulta. `get_news` sigue bloqueado como hoy. No cambia el hash.
- **Tool `get_daily_brief`** (en `tools/report_tools.dart`): devuelve el payload de hoy con `status: ok | not_ready`. Es para "Preguntale a Porty" desde el pie del brief (screen `dailyBrief`). La respuesta usa `QaAnswerText` y no tiene card propia. La carga viene de `ctx.loadDailyBrief`, que inyecta el proveedor del chat leyendo `daily_briefs` por medio de un callback que expone flutter (§4).
- **Tool `compare_sources`** (en `tools/web_tools.dart`):
  - parámetros `{ticker?: string, topic?: string}`; `topic` es un id del catálogo que el modelo toma de `screen_context.news.topic_id`;
  - gating antes de llamar con `PlanMatrix.allowsNewsFor(tier, held:)` para tickers y `ctx.allows(PlanFeature.news)` para temas; si no pasa, devuelve `locked` + `required_plan`;
  - comparte con `get_news` el tope de 1 búsqueda por turno (`ctx.newsContextCalls`);
  - status posibles: `ok`, `empty`, `insufficient_sources`, `locked`, `limit` o `failed`, siempre con `as_of`;
  - en `monthly_limit` usa el mismo `AnswerGuide` de tope que `get_news`.
- **Card `QaSourceComparison`:**
  - sin props: la dibuja la app desde la evidencia del turno (`QaEvidenceScope`, como `QaWeeklyReport`);
  - filas "Coinciden / Difieren / Solo un medio", cada una con medio y link tocable;
  - el modelo escribe 1–2 oraciones en `QaAnswerText`;
  - se declara como `DeferredSpec` del área `research`.
  - **Cambia el hash del catálogo:** hay que regenerar `allowed_system_prompts.json` y desplegar `ai-chat`, en el mismo deploy que §3.7.
  - Si el presupuesto de 1060 tokens del área no alcanza, assistant propone el número nuevo con la medición en el PR.
- **Grounding:** en `assistant_grounding_check.dart`, todo medio nombrado en la prosa ("según X", "X dice", "according to X") tiene que estar en `outlets` de una evidencia de `compare_sources` o `get_news`. Lleva un caso en `bilingual_checks_test.dart`.
- **Prompt del brief:** `dailyBriefSystemPromptFor(lang)`, en inglés y con una variante por idioma. Parte de `weekly_report_prompt.dart`, con límites propios:
  - `why`: 120 caracteres;
  - `held_news` y `watch_news`: 100;
  - `connection`: 120;
  - prosa total: hasta unas 120 palabras.
- **Validador del brief:** `DailyBriefValidator.review(draft, input, language:)` reutiliza las reglas del semanal (causas, consejo, consejo de terceros, jerga, vacío, ausencias, comillas, cifras respaldadas, "tu cartera" en ítems que no la tocan, inglés en un brief en español).
  - Esas reglas se extraen de `WeeklyReportValidator` a `lib/features/weekly_report/domain/report_prose_rules.dart`, sin cambiar el comportamiento del semanal (sus tests siguen verdes).
  - Suma una regla propia: `connection` solo si el usuario tiene la clase del tema.

### 3.11 Eventos (`product_events` con `ProductEvents.log` y el enum `ProductEvent`; lo implementa flutter)

| Evento | Props |
|---|---|
| `daily_brief_opened` | `source` (`push`, `home`, `feed`), `variant` (`full`, `numbers`), `courtesy`, `tier` |
| `daily_brief_generated` | `variant`, `rounds`, `removed_items`, `held_with_news_pct` (0–100), `ms`, `error?` |
| `daily_brief_item_tapped` | `kind` (`why`, `headline`, `watch`, `macro`, `earnings`, `source`, `video`, `teaser`, `see_all`) |
| `daily_brief_ask_porty` | `from` (`footer`, `item`) |
| `daily_brief_feedback` | `useful` (bool), `reason?` (`wrong`, `irrelevant`, `too_long`) |
| `news_feed_opened` | `tab` (`mine`, `topics`, `market`), `source` (`brief`, `home`, `push`) |
| `news_item_opened` | `kind` (`held`, `watch`, `topic`, `market`), `preferred` |
| `news_how_affects_tapped` | `from` (`brief`, `feed`, `topic`, `market`) |
| `news_compare_tapped` | `from` (`feed`, `topic`), `subject_kind` (`ticker`, `topic`), `locked` |
| `news_compare_result` | `result` (`ok`, `insufficient`, `locked`, `limit`, `failed`), `cache` (`hit`, `miss`). Lo registra la tool del chat por medio de un callback de `AssistantToolContext`, como los demás eventos del chat. |
| `market_today_opened` | `source` |
| `news_video_opened` | `kind` (`topic`, `market`) |
| `news_topic_changed` | `topic_id`, `followed`, `was_default` |
| `news_source_changed` | `domain`, `preference` (`prefer`, `mute`, `none`) |
| `paywall_viewed` | `source`: constantes nuevas `daily_brief`, `news_feed` y `news_compare` en `PaywallSource` |

Ningún evento lleva tickers ni titulares. `app_opened` ya existe y suma `source: push_daily_brief`. Antes de cerrar la lista, `porty-data-analyst` valida nombres y umbrales: es una tarea de §4, no de esta spec.

### 3.12 Traducciones (las agrega flutter primero; assistant solo usa las claves)

En `assets/translations/es-ES.json` y `en-US.json`:

| Prefijo | Qué cubre |
|---|---|
| `daily_brief_*` | Título, fila de la Home, secciones, aviso de plan sin ticker, pie "Información, no una recomendación", "Preguntale a Porty", "¿Te sirvió?", "día {n} de {total}" de la cortesía, "estimada", estado vacío y de error. |
| `daily_brief_ask_affects`, `news_ask_affects`, `news_ask_compare` | Plantillas de pregunta, con `{title}` o `{subject}`. |
| `news_feed_*`, `market_today_*`, `news_topic_screen_*` | Las pantallas de noticias, mercado y tema. |
| `news_prefs_*` | Temas, medios, preferido o silenciado, límites. |
| `news_video_*` | Atribución "Video de YouTube · {channel}". |
| `qa_src_compare_*` | Card de comparación: coinciden, difieren, solo un medio, no alcanzan las fuentes. |

Los rótulos de temas e instrumentos vienen de la base (`label_es`, `label_en`). Las plantillas del push viven en `templates.ts`, el patrón actual del servidor. El nombre visible queda como placeholder ("Tu brief de hoy" / "Your daily brief") hasta que el usuario decida (§11).

### 3.13 Pantallas y rutas (flutter)

Todas se registran en `app_router.dart` y se navega siempre por nombre.

| Pantalla | Router | Reusa |
|---|---|---|
| `DailyBriefScreen` (hoy y ayer) | `DailyBriefRouter` (`/daily-brief`, extra `{day, source}`) | Formato de números de `weekly_report_format.dart`, `PortySays`, `SubscriptionPaywallSheet`, `NewsHeadlineRow` |
| Fila "Tu brief de hoy" en la Home | `daily_brief_home_row.dart`, insertado en `home_screen.dart` cerca de `WeeklyReportCard` | El patrón de `weekly_report_card.dart` |
| `NewsFeedScreen` (pestañas Lo tuyo / Temas / Mercado) | `NewsFeedRouter` (`/news`, extra `{tab, source}`) | `NewsHeadlineRow` |
| `MarketTodayScreen` (pestaña y ruta propia) | `MarketTodayRouter` (`/market-today`) | — |
| `NewsTopicScreen` | `NewsTopicRouter` (`/news/topic`, extra `topicId`) | `NewsHeadlineRow` |
| `NewsPreferencesScreen` (temas y medios) | `NewsPreferencesRouter` (`/settings/news`) | Filas de `notification_settings_screen.dart` |
| Push `daily_brief` → `DailyBriefScreen` | `PushRouteDailyBrief` en `push_route.dart` y en `PushOpenListener` | — |

`NewsHeadlineRow` es un widget compartido nuevo en `lib/presentation/shared/widgets/news_headline_row.dart`. Se extrae la fila de `widget_news_sheet.dart`, que pasa a usarlo sin cambio visual.

Acciones de cada noticia:

- abrir la fuente afuera (`launchUrl`);
- **¿Cómo me afecta?**: `GotoAssistant` con `PortyScreenContext(newsItem, news: ...)`;
- **Qué dice cada medio**: si el plan lo permite (`allowsNewsFor`), `GotoAssistant` con `news_ask_compare`; si no, aviso de plan sin ticker y paywall con `source: news_compare`.

Videos:

- miniatura, título, canal y "YouTube";
- al tocarlo, `launchUrl` externo;
- sin reproducción automática ni contadores de vistas.

"Mercado hoy" tiene un orden **fijo por catálogo**, nunca por tamaño del movimiento. No usa colores de alarma (se aplican los tokens de `DESIGN.md`). Primero muestra el "por qué" en prosa y después los instrumentos.

Entradas al feed: "Ver todas" desde el brief y una fila secundaria en la Home, las dos solo con el interruptor prendido. Preferencias: desde Ajustes → Noticias y desde un ícono en el feed.

---

## 4. Tareas por dueño

Ningún archivo tiene dos dueños. Las tallas son en días-persona, con implementación y tests propios.

### Fase 0: contrato (backend, 1 día; los demás arrancan contra fixtures el mismo día)

- **Backend:** fixtures JSON de §3.9 y los tipos TS del contrato en `supabase/functions/daily-brief/contract.ts`. Avisa a flutter y a assistant cuando están en la rama.

### Fase 1: en paralelo

**`porty-backend-dev`** (9 días):

| Archivos | Tarea | Días |
|---|---|---|
| `supabase/migrations/20261121100000_daily_brief.sql`, `..._daily_brief_catalogs.sql` | Esquema, RLS, RPC, interruptor, cron y semillas (§3.2–3.3) | 2,5 |
| `supabase/tests/daily_brief_db_test.sql`, `supabase/tests/account_deletion_db_test.sql` (solo agregar las tablas) | Tests SQL: claim, cortesía, carrera de dos dispositivos, RLS, límites de temas y medios, `entitlement` sin tickers ajenos | incluido |
| `supabase/functions/_shared/gdelt.ts`, `_shared/news_digest.ts`, `_shared/news_citations.ts`, `_shared/news_attribution.ts`, `news-context/handler.ts` (refactor) | Titulares por ticker, digests, atribución | 2 |
| `supabase/functions/daily-brief/*` | Función con 4 scopes y gating | 2 |
| `supabase/functions/ai-chat/handler.ts` | Purpose `daily_brief` y el import del allowlist nuevo (vacío) | 0,5 |
| `supabase/functions/market-watch/quotes.ts` | Nombre y `regularMarketTime` | 0,25 |
| `supabase/functions/tests/*daily_brief*`, `*news_digest*`, `*attribution*` | Tests Deno | 0,75 |
| `supabase/functions/scripts/news_coverage.ts` | Script de cobertura (§8) | 1 |

**`porty-flutter-dev`** (6 días; arranca con `FakeDailyBriefRepository` y `FakeDailyBriefGenerator`):

| Archivos | Tarea | Días |
|---|---|---|
| `assets/translations/es-ES.json`, `en-US.json` | **Todas** las claves de §3.12, el primer día (assistant las usa) | 0,5 |
| `lib/features/daily_brief/{data/daily_brief_repository.dart, domain/daily_brief.dart, domain/daily_brief_numbers.dart, providers/daily_brief_provider.dart, view/**, nav/daily_brief_router.dart}` | Repositorio, números del día (`PortfolioDayMove` y aportes por posición), `DailyBriefInput` construido desde el bundle, controlador (claim → generar → complete, reintentos), pantalla y fila de la Home | 3,5 |
| `lib/presentation/shared/widgets/news_headline_row.dart`, `lib/features/home_widget/view/widget_news_sheet.dart` (solo para usar la fila) | Fila compartida | 0,5 |
| `lib/presentation/flows/home/ui/home_screen.dart` | Insertar la fila del brief y la entrada al feed | 0,25 |
| `lib/features/product_events/data/product_events.dart`, `lib/features/subscription/config/paywall_source.dart` | Eventos y fuentes de paywall | 0,25 |
| `test/features/daily_brief/**` (salvo `prompts/` y `validator/`) | Tests de controlador, gating visual y números iguales a la Home | 1 |

**`porty-assistant-dev`** (4 días; arranca con los fixtures `bundle_brief_*`):

| Archivos | Tarea | Días |
|---|---|---|
| `lib/features/daily_brief/prompts/daily_brief_prompt.dart`, `lib/features/daily_brief/domain/daily_brief_input.dart`, `domain/daily_brief_draft.dart`, `domain/daily_brief_validator.dart`, `data/daily_brief_generator.dart` | Prompt es/en, esquema, validador y generador | 2 |
| `lib/features/weekly_report/domain/report_prose_rules.dart`, `lib/features/weekly_report/domain/weekly_report_validator.dart` | Extraer las reglas compartidas sin cambiar el comportamiento | 0,5 |
| `supabase/functions/ai-chat/allowed_brief_prompts.json` | Hashes del prompt del brief | incluido |
| `test/features/daily_brief/prompts/**`, `test/features/daily_brief/validator/**` (incluye `daily_brief_prompt_allowlist_test.dart`) | Golden de prompt, casos de validador es/en y hash en el allowlist. El test vive fuera de `test/security/` para no tocar controles (§10, D8). | 1 |
| `test/evals/daily_brief_evals_test.dart` | Evals del brief (no se corren sin OK, §11) | 0,5 |

### Fase 2: en paralelo (cuando backend avisa que `daily-brief` y las RPC están en la base local)

**`porty-backend-dev`** (5 días):

| Archivos | Tarea | Días |
|---|---|---|
| `supabase/functions/news-compare/*` y sus tests | Comparar fuentes (§3.6) | 1,5 |
| `supabase/functions/news-warm/*` y sus tests | Calentamiento, pulso, temas y videos (YouTube) | 2 |
| `supabase/functions/daily-jobs/{jobs.ts,handler.ts,store.ts}`, `notify-dispatch/{kinds.ts,templates.ts}` y sus tests | Push `daily_brief`, reemplazo de `morning_brief` y purgas | 1,5 |

**`porty-flutter-dev`** (5 días):

| Archivos | Tarea | Días |
|---|---|---|
| `lib/features/news_feed/**` (repositorio del bundle `feed`/`topic`/`market`, feed, tema, Mercado hoy, videos) y su `nav/` | Pantallas | 3 |
| `lib/features/news_preferences/**` | Temas y medios | 1 |
| `lib/features/notifications/domain/push_route.dart`, `view/push_open_listener.dart`, `lib/config/navigation/app_router.dart` | Ruta del push y registro de routers | 0,5 |
| `lib/features/daily_brief/data/daily_brief_chat_loader.dart` | Callback `loadDailyBrief` que el chat inyecta | 0,25 |
| `test/features/news_feed/**`, `test/features/news_preferences/**` | Tests | 0,25 |

**`porty-assistant-dev`** (3 días):

| Archivos | Tarea | Días |
|---|---|---|
| `lib/features/assistant/models/porty_screen_context.dart`, `services/assistant_openai_service.dart` | Contexto de noticia y guía en el contexto fijado | 0,5 |
| `lib/features/assistant/tools/report_tools.dart`, `tools/web_tools.dart`, `tools/assistant_tool_context.dart`, `tools/assistant_toolset.dart` | `get_daily_brief` y `compare_sources` | 1 |
| `lib/features/assistant/data/web/source_compare_fetcher.dart`, `catalog/widgets/source_widgets.dart`, `catalog/portfolio_qa_catalog.dart`, `catalog/assistant_catalog.dart`, `areas/porty_areas.dart`, `prompts/assistant_prompt_rules.dart`, `utils/assistant_grounding_check.dart` | Card, área, regla diferida y grounding | 1 |
| `supabase/functions/ai-chat/allowed_system_prompts.json` y `test/features/assistant/**` | Regenerar el hash del chat y tests (`flutter test test/features/assistant test/features/genui_core test/security`) | 0,5 |

**Dependencias:**

- Flutter integra contra la base local cuando backend avisa (fin de la Fase 1).
- El controlador del brief (flutter) llama a `DailyBriefGenerator` (assistant) solo por su firma (§3.9). Hasta que assistant lo entregue, usa el fake.
- El deploy de `ai-chat` junta §3.7 y §3.10, y sale una sola vez, con OK.

### Fase 3: integración y calidad (1 día-persona por dueño más revisión)

- Cada dueño corre `tools/verify/verify.sh`; backend además Supabase local, Deno y SQL; flutter, el E2E web del flujo del brief.
- Revisión: `porty-code-reviewer` (contra `REVIEW.md`), `porty-security-reviewer` (gating de `daily-brief` y `news-compare`, RLS, inyección en titulares y digests), `porty-ui-reviewer` (pantallas nuevas).
- `porty-qa-engineer`: humo por plan (Free, Free con cortesía, Premium, Gold), en es y en, con el interruptor apagado y prendido.
- `porty-data-analyst`: valida eventos y umbrales (§3.11 y §8).
- `porty-compliance`: allowlist de medios y canales, textos de YouTube en Términos y Privacidad, pie "Información, no una recomendación".

**Talla total:** backend 15 (1 + 9 + 5), flutter 12 (6 + 5 + 1), assistant 8 (4 + 3 + 1). Total **unos 35 días-persona**, sin contar revisión ni QA. Con los tres en paralelo, unas 3 semanas de calendario.

---

## 5. Gating por plan (el servidor manda)

| Pieza | Free | Free con cortesía (7 días hábiles) | Premium | Gold | Dónde se valida |
|---|---|---|---|---|---|
| Números del día y lo que más pesó | Sí | Sí | Sí | Sí | App (son sus datos) |
| "Por qué" por posición | Aviso sin ticker | Sí | Sí | Sí | `claim_daily_brief` + `daily-brief` |
| Titulares de lo tuyo (brief y feed) | Conteo sin ticker | Sí | Sí (cartera) | Sí (+ watchlist) | `daily-brief` |
| Mercado y macro en el brief | 1 hecho, sin cruce | Hasta 3 con cruce | Hasta 3 con cruce | Hasta 3 con cruce | `daily-brief` + payload |
| Resultados | No | No | No | Sí (presentado o estimado) | `daily-brief` |
| Mercado hoy, temas, videos | Sí | Sí | Sí | Sí | — (es general; los videos no pueden ir detrás de un plan) |
| Seguir temas y elegir medios | Sí | Sí | Sí | Sí | RLS |
| ¿Cómo me afecta? | Sí (gasta consulta) | Sí | Sí | Sí | Cuota del chat |
| Comparar fuentes | No (aviso) | No | Solo tickers en cartera | Tickers y temas | `news-compare` |
| Push | Sí | Sí | Sí | Sí | `notify-dispatch` |

No hace falta un `PlanFeature` nuevo: el brief lo decide el servidor (como el semanal) y comparar fuentes usa `allowsNewsFor`. Si monetization quiere mencionar el brief en el paywall, se suma una `leadingMarketingKeys` (`plan_feature_daily_brief`) en un cambio aparte.

## 6. Interruptores

- `daily_brief` (`percent`, `users`) cubre todo. Apagado: `daily_brief_status.enabled = false`, `claim` devuelve `disabled`, `daily-brief` y `news-compare` responden 403 `disabled`, `ai_brief_begin` corta, `daily-jobs` manda `morning_brief` como hoy y el chat no ofrece nada nuevo. `compare_sources` devuelve `failed` con `reason: disabled`, y la guía le indica al modelo responder con `get_news`.
- Hay sub-interruptores en `pieces`: `push`, `feed`, `topics`, `sources`, `market`, `compare` y `videos`. Cada uno apaga su pieza y su costo sin tocar el resto.
- La lista interna se maneja con `users`. Las cohortes de noviembre no cambian porque el interruptor es otro y `app_config_history` registra cada cambio.

## 7. Costo por usuario y por día (supuestos marcados)

Precios con los que se calcula:

- gpt-6-luna en tarifa `fast`: US$0,20 de entrada y 1,00 de salida por M de tokens (`20261014130000_gpt6_luna_fast_prices.sql`).
- Búsqueda web: US$0,01 por llamada, más los tokens de contenido al precio del modelo ([pricing de OpenAI](https://developers.openai.com/api/docs/pricing)).
- gpt-5-mini: US$0,25 / 2,00 por M (`news-context/handler.ts`).
- **Supuesto:** una búsqueda con contenido y salida cuesta unos US$0,015; un digest con 2 búsquedas, unos US$0,03.

**Variable por usuario y por día:**

| Plan | Qué cuesta | Por día | Por mes (21 días hábiles) |
|---|---|---|---|
| Free | Nada: sin LLM; GDELT, Yahoo, YouTube y FCM son gratis | US$0 | US$0 |
| Free con cortesía | 1 brief: unos 3k tokens de entrada + 0,5k de salida ≈ US$0,0011, más 30 % de reescritura | ≈ US$0,0015 | ≈ US$0,01 por alta (7 días) |
| Premium | Brief ≈ US$0,0015. Comparar fuentes y "¿cómo me afecta?" entran en topes que ya existen (news-context 80 unidades; consultas del chat) | ≈ US$0,0015 | ≈ US$0,03 (brief) |
| Gold | Brief con watchlist (unos 4k tokens de entrada) ≈ US$0,002 | ≈ US$0,002 | ≈ US$0,04 (brief) |

El guardarraíl del brief (≤ US$0,10 por mes por lector diario) queda cubierto con margen.

**Comparar fuentes:** un miss cuesta unos US$0,05 (supuesto: 3 búsquedas más tokens). El peor caso por usuario y mes ya está acotado por el tope mensual de news-context: Premium unas 26 comparaciones, alrededor de US$1,3; Gold unas 53, alrededor de US$2,6. Es el mismo orden que el tope de unidades de hoy, y los hits de caché no cuestan.

**Costo fijo de Porty** (no crece con los usuarios):

| Pieza | Peor caso por día | Típico (supuesto) |
|---|---|---|
| Pulso de mercado: 4 regiones × 2 idiomas × 4 franjas de 6 h × US$0,03 | US$0,96 | US$0,25 (1–2 franjas, 1 idioma en la mayoría de las regiones) |
| Temas: 16 × 2 idiomas × 2 franjas de 12 h × US$0,03 | US$1,92 | US$0,45 (unos 10 temas seguidos, 1,5 idiomas) |
| YouTube: 30 canales × 48 lecturas = 1.440 unidades de 10.000 diarias | US$0 | US$0 |
| **Total** | **≈ US$2,9 por día (≈ US$87 por mes)** | **≈ US$0,7 por día (≈ US$21 por mes)** |

Topes que acotan el costo:

- franjas de caché por clave (6 y 12 h) con un solo generador por clave;
- catálogo cerrado de temas y regiones;
- solo los idiomas que tienen usuarios;
- `pieces.topics` y `pieces.market` para apagar;
- `maxBriefRounds = 2` y `maxBriefOutputTokens = 900`;
- comparar fuentes dentro de `news_context_quota_hit`;
- 1 búsqueda por turno.

Todo se mide en `ai_turn_usage` (`purpose = 'daily_brief'`) y en los logs de `news-warm` y `news-compare` (`cost_usd`). Se revisa en la primera semana con la lista interna.

## 8. Cobertura global de noticias: riesgos y plan para medirla

**Qué sabemos:**

- GDELT busca por nombre, con el idioma limitado a inglés y español y una cláusula de hasta 8 dominios, que hoy son casi todos de EE. UU. (`_shared/gdelt.ts:10-40`).
- Los tickers sin CIK de la SEC (.BA, .MC, .T, .L, .HK…) hoy se buscan por el ticker solo, y la cobertura debería ser pobre.
- Los bonos (AL30, GD30) y los CEDEAR no tienen nombre de prensa útil.
- **No se pudo medir desde esta sesión:** GDELT no es alcanzable desde acá.

**Mitigaciones en esta spec:**

1. Nombre de Yahoo para los tickers sin CIK.
2. Dominios por región en la consulta (`gdelt_priority` + `region`).
3. Medios globales y oficiales nuevos en la allowlist.
4. Para los activos sin cobertura por ticker, el brief se apoya en los **temas** de su mercado o clase (por ejemplo `ar_country_risk_cer` para bonos argentinos). Nunca se inventa: si no hay titular, la línea no aparece.
5. Un CEDEAR usa el nombre del subyacente que devuelve Yahoo, sin mapeo fijo.

**Plan de medición** (lo hace backend; es criterio de lanzamiento, no de desarrollo):

- `supabase/functions/scripts/news_coverage.ts` lee los símbolos distintos con `quantity > 0` agrupados por mercado (sufijo y `quoteType`), sin `user_id`, y corre `headlinesByTicker` respetando el limitador.
- Reporta, por mercado: porcentaje de símbolos con al menos 1 titular en 48 h y en 7 días, mezcla de idiomas, medios más frecuentes y tickers sin nombre de prensa.
- Se corre en desarrollo con carteras de prueba y, **con OK del usuario**, en modo lectura contra producción.
- **Umbral para prometer el "por qué" en un mercado:** que al menos el 60 % de las posiciones con más peso tengan titular en 48 h (supuesto, lo valida data). Por debajo de eso, ese mercado se cubre con temas y se ajusta la allowlist.
- En el producto: `daily_brief_generated.held_with_news_pct`, que permite cortar por mercado en `product_events` combinándolo con la cartera.

---

## 9. Criterios de aceptación (los reviewers revisan contra esto)

**Interruptor y convivencia**

1. Con `daily_brief` apagado, no cambia nada. Lo prueban un test SQL (`claim` → `disabled`, `daily-brief` → 403) y un test Deno de que `daily-jobs` sigue generando `morning_brief` y no genera `daily_brief`; en la app, no se ven la fila de la Home ni la entrada al feed.
2. Con el interruptor prendido para un usuario, ese usuario recibe `daily_brief` y no `morning_brief` el mismo día (test de `dailyBriefRows` y `morningBriefRows`).

**Brief**

3. Los números del brief son iguales a los de la línea 1D de la Home para la misma cartera e historial (test de `daily_brief_numbers.dart` contra `PortfolioDayMove`).
4. Free: payload `numbers` sin llamada al LLM (el test verifica que no se llama al generador), 1 hecho de mercado con fuente y aviso sin ticker que abre el paywall con `source: daily_brief`.
5. Free con cortesía: brief `full` durante `courtesy_days` briefs, solo si la cuenta es de `courtesy_since` en adelante. Dos dispositivos a la vez no regalan uno de más (test SQL con dos claims).
6. Premium: el "por qué" sale solo de titulares de tickers en cartera, y nunca aparecen titulares de la watchlist. Gold: watchlist y resultados con "estimada" cuando corresponde.
7. El validador del brief descarta causas afirmadas, consejo, consejo de terceros, comillas y cifras sin respaldo, en es y en (casos en `test/features/daily_brief/validator/`). Los tests del validador semanal siguen verdes después de la extracción.
8. Cada titular y cada hecho de mercado tienen medio y link (test de la pantalla y del payload).
9. El hash del prompt del brief está en `allowed_brief_prompts.json` y no está en `allowed_system_prompts.json` (`daily_brief_prompt_allowlist_test.dart`). `ai-chat` rechaza el purpose `daily_brief` sin claim vigente, con tools o con stream (tests Deno).
10. La prosa de un brief completo tiene como máximo 120 palabras en los fixtures de evals (lectura de un minuto o menos).

**Push**

11. Sale a las 8 locales solo de lunes a viernes, solo si hay algo que contar, sin montos, porcentajes ni tickers, y respeta el silencio y el tope de 3 (tests de `dailyBriefRows`, `templates.ts` y `kinds.ts`). Al tocarlo se abre `DailyBriefScreen` (test de `push_route.dart`).
12. Se apaga con la preferencia `morning_brief`, y el brief sigue en la Home.

**Feed, temas, medios, mercado y videos**

13. `daily-brief?scope=feed` nunca devuelve titulares de tickers a Free (solo `locked.mine_tickers_48h`), ni de la watchlist a Premium. Un usuario no puede ver la cartera de otro (tests Deno y SQL de RLS y `entitlement`).
14. Silenciar un medio lo saca del feed y del brief; preferirlo lo sube. La clave de caché no cambia (test del armado de claves).
15. Los temas por defecto salen de la cartera (una cartera con `.BA` incluye `ar_bcra_dollar`; una sin `.BA`, no). Seguir o dejar de seguir persiste, y el tope de 12 se aplica en la base.
16. "Mercado hoy" muestra los instrumentos en el orden del catálogo, sin rankings, cada línea explicativa con cita, y aparece en los tres planes.
17. Los videos salen solo de canales de la allowlist, se abren en YouTube, están en los tres planes y llevan atribución. `news_videos` no guarda nada de más de 7 días (test de la purga).

**Chat**

18. "¿Cómo me afecta?" abre el chat con la pregunta de plantilla y `screen_context.news`; la respuesta no afirma causas. Un eval con fixtures cubre es y en, y no se corre sin OK.
19. `compare_sources`: Free → `locked`; Premium con un ticker que no tiene → `locked gold`; Gold con un tema → `ok`. Cada fila de la card tiene medio y link, y `agree` siempre tiene 2 o más medios (tests de la tool y del validador de atribución en Deno). Un hit de caché no gasta unidades (test Deno).
20. `flutter test test/features/assistant test/features/genui_core test/security` en verde, con el hash nuevo del catálogo agregado y los anteriores conservados.

**Calidad general**

21. `tools/verify/verify.sh` en verde, `flutter analyze` sin warnings nuevos, tests Deno y SQL en verde, y el E2E web del flujo del brief (`tools/verify/e2e/run.sh`) en verde.
22. Todos los textos nuevos están en `es-ES.json` y en `en-US.json`.
23. Costo: en la semana de la lista interna, `ai_turn_usage` con `purpose = 'daily_brief'` da un promedio de US$0,003 o menos por brief completo, y el costo fijo diario queda en US$3 o menos.

---

## 10. Riesgos y decisiones

| # | Decisión | Alternativa descartada y por qué |
|---|---|---|
| D1 | Generar el brief al abrir, en la app | Generarlo en el servidor a las 8 para todos: los números no coincidirían con la Home (la valuación vive en la app) y se pagaría IA por briefs que nadie lee. |
| D2 | Bundle `daily-brief` que lee la cartera desde la base | Reusar `headlines` con los tickers del cliente: obliga a abrir `gold_data_allowed` durante la generación (hoy el semanal habilita **todo** Gold por 30 minutos) y la caché por conjunto de tickers no escala. |
| D3 | "Mercado hoy" tranquilo: índices de referencia en orden fijo, más el "por qué" en prosa con citas | Lo que más sube o baja y lo más buscado: es estilo casino y va contra `PRODUCT.md` ("No trader UX"). |
| D4 | Videos por YouTube Data API desde canales de medios, asignados a **temas y mercado**, gratis en todos los planes, reproducidos **embebidos** (IFrame Player oficial, `youtube_player_iframe` 5.x) con respaldo a abrir en YouTube (P6 cerrada por el usuario el 20/11) | (a) `search.list` por ticker: 100 unidades por llamada y un tope de unas 100 llamadas por día. (b) Videos por ticker: con las políticas de YouTube no se pueden poner detrás de un plan, y si se dan gratis le regalan a Free las "noticias de lo tuyo" que el 05/11 reserva para Premium. (c) Reproductor embebido: suma WebView como dependencia nativa y desde 2025 YouTube exige identificar al embebedor (error 153 en las WebView de Android). Se aceptan esos costos (P6). Obligaciones de YouTube en `docs/legal/reviews/2026-11-21-brief-diario-medios-y-youtube.md` §3. |
| D5 | Comparar fuentes con 3 unidades del tope de `news-context` y caché de 6 h | Un cupo nuevo, `compare_per_month`: es otra columna, otro espejo en `PlanSpec` y otro paywall, sin ganancia real. |
| D6 | Preferencias de medios aplicadas después de la caché | Filtrar la búsqueda por los medios del usuario: rompe la caché compartida y multiplica el costo. |
| D7 | "¿Cómo me afecta?" sin tool nueva | Una tool `explain_news_impact`: suma tokens fijos y deploy, y no agrega datos que el contexto no tenga. |
| D8 | El test del hash del brief va en `test/features/daily_brief/` | Ponerlo en `test/security/`: ese archivo está en CODEOWNERS y no se toca en el mismo cambio. Se propone moverlo en un PR aparte, con OK del usuario. |
| D9 | `payload.audio = null` como punto de extensión del TTS | Diseñar ya el almacenamiento del audio: el audio está fuera de la v1. |
| D10 | Push con plantilla sin cifras | Push con el porcentaje de la cartera: el número del servidor (Yahoo, `changePct`) puede no coincidir con el de la Home, y el brief exige que nunca se contradigan. |

**Riesgos:**

- **Licencias.** Se mantiene título + medio + link + paráfrasis. Para un producto diario, compliance revisa la allowlist nueva. YouTube exige que la política de privacidad mencione el uso de YouTube API Services con un link a la Política de Privacidad de Google, y que los Términos remitan a los de YouTube. Los textos exactos se verifican en la página oficial, que no se pudo abrir desde esta sesión.
- **Pico de GDELT a las 8.** Mitigado con caché por ticker y calentamiento. Si el limitador global no da abasto, el brief sale sin el "por qué" de los tickers fríos: no falla.
- **Inyección por titulares y digests.** Filtro `looksLikeInstructions` en el servidor, datos delimitados en el prompt y salida estructurada estricta.
- **Costo de las búsquedas web.** Hay reportes de búsquedas internas de más. Por eso el costo real por llamada se lee de `ai_turn_usage` y se corta con `pieces` si se pasa.

**Necesita OK del usuario:**

1. `db push` de las dos migraciones.
2. Deploy de `ai-chat` (purpose nuevo y hash del catálogo). Va antes de publicar la app.
3. Deploy de las funciones nuevas `daily-brief`, `news-compare` y `news-warm`, y de los cambios en `daily-jobs` y `notify-dispatch`.
4. Crear la clave de YouTube Data API (P1).
5. Evals pagas del brief y de `compare_sources`: unos US$0,10–0,25 por corrida (supuesto, unos 20 casos).
6. Correr el script de cobertura en modo lectura contra producción.
7. Prender el interruptor para la lista interna y, después, para todos.
8. Mover el test del hash a `test/security/` en un PR aparte.

## 11. Preguntas que decide el usuario

- **P1. Clave de YouTube Data API.** Hay que crear un proyecto en Google Cloud, habilitar la API, generar una clave restringida a la API y guardarla en `YOUTUBE_API_KEY` en los secretos de Supabase. No tiene costo con la cuota por defecto de 10.000 unidades por día. ¿La creás vos?
- **P2. Nombre visible.** "Brief diario", "Tu mañana", "Resumen de la mañana" u otro (con `porty-marketing-lead`).
- **P3. Lanzamiento frente a la prueba de Gold de enero.** Es la pregunta 3 del brief y sigue abierta.
- **P4. `courtesy_since`.** ¿La cortesía de 7 días es solo para las altas desde el lanzamiento (mi recomendación) o también para la base actual?
- **P5. Costo fijo compartido.** ¿Aprobás hasta unos US$90 por mes en el peor caso (unos US$21 típico) para "Mercado hoy" y los temas en es y en? Si no, arrancamos con una franja por día.
- **P6. Videos.** ~~¿Abrir en YouTube o reproductor embebido?~~ **Cerrada (20/11): embebido, con respaldo a abrir en YouTube.**
- **P7. Videos por ticker.** ¿Los descartamos (mi recomendación, por lo de D4) o los damos gratis a todos los planes, aceptando que Free vea videos de sus tickers?
- **P8. Allowlist global.** ¿Aprobás sumar los medios y las fuentes oficiales de §3.2? La lista final sale de la medición de §8 y la revisa compliance. ¿Hay algún medio que quieras sí o sí, o ninguno?
- **P9. Medición en producción.** ¿Autorizás correr `news_coverage.ts` en modo lectura contra producción (lee símbolos agregados, sin `user_id`)?
