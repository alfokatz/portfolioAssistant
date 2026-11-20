// Contrato de la función `daily-brief` y de `news-compare`, y forma del
// payload del brief (`daily_briefs.payload`). Solo tipos y constantes: lo
// leen la app (flutter y assistant) como referencia y los fixtures de
// `test/fixtures/daily_brief/*.json`, que tienen que cumplirlo (lo verifica
// `tests/daily_brief_contract_test.ts`).
//
// Spec: docs/superpowers/specs/2026-11-20-brief-diario-tech.md §3.4–§3.6 y §3.9.
//
//   GET /functions/v1/daily-brief?scope=<scope>&lang=es|en&day=YYYY-MM-DD[&topic=<id>]
//   con el JWT del usuario. El cliente NUNCA manda tickers.

export const scopes = ["brief", "feed", "market", "topic"] as const;
export type Scope = (typeof scopes)[number];

export type Lang = "es" | "en";
export type Tier = "free" | "premium" | "gold";
export type Variant = "full" | "numbers";

/// Errores con forma estable `{error: {type, message}}`; la app los mapea a
/// `DailyBriefFailure`. Una pieza que falla NO es un error: la respuesta es
/// 200 con ese bloque en `status: "failed"` o vacío.
export const errorTypes = {
  unauthorized: 401,
  method_not_allowed: 405,
  invalid_scope: 400,
  invalid_day: 400,
  invalid_topic: 400,
  disabled: 403,
  rate_limited: 429,
} as const;
export type ErrorType = keyof typeof errorTypes;

/// Piezas con interruptor propio (`app_config.daily_brief.pieces`).
export const pieces = ["push", "feed", "topics", "sources", "market", "compare", "videos"] as const;
export type Piece = (typeof pieces)[number];

// ---------------------------------------------------------------------------
// Respuesta de `daily-brief`
// ---------------------------------------------------------------------------

export type PlanInfo = { tier: Tier; variant: Variant; courtesy: boolean };

/// Un titular de lo tuyo. `kind` = `held` (cartera), `watch` (watchlist, solo
/// Gold). Un ticker ajeno nunca aparece.
export type NewsItem = {
  id: string;
  ticker: string;
  kind: "held" | "watch";
  title: string;
  source: string;
  domain: string;
  url: string;
  published_at: string;
  lang: Lang | null;
  /// El usuario prefirió este medio (va primero dentro de cada ticker).
  preferred: boolean;
};

/// Free: en lugar de `mine`, solo cuántos tickers de su cartera tienen
/// titular en 48 h (sin tickers ni titulares).
export type Locked = { mine_tickers_48h: number };

export type EarningsItem = {
  ticker: string;
  /// `reported` = 8-K 2.02 presentado (link a la SEC); `estimated` = próxima
  /// fecha estimada, siempre rotulada "estimada".
  kind: "reported" | "estimated";
  date: string;
  url: string | null;
};

export type DigestLine = { text: string; source_ids: string[] };

export type TopicDigest = {
  topic_id: string;
  label: string;
  status: "ok" | "empty" | "failed";
  summary: DigestLine[];
  as_of: string | null;
};

export type Instrument = {
  symbol: string;
  label: string;
  kind: "index" | "sector" | "commodity" | "rate" | "fx" | "crypto";
  /// Variación del último cierre; null si Yahoo no la trajo.
  pct: number | null;
  as_of: string | null;
};

/// Una línea del pulso de mercado. `asset_link` y `asset_class` (solo en
/// `scope=brief`, `variant=full`) son la frase fija "tenés X que..." del tema
/// y la clase que menciona: el LLM de la app solo puede parafrasearla, y solo
/// si el usuario tiene esa clase (`asset_classes` de la respuesta).
export type PulseLine = {
  text: string;
  source_ids: string[];
  topic_id: string | null;
  asset_link?: string | null;
  asset_class?: string | null;
};

export type MarketBlock = { instruments: Instrument[]; pulse: PulseLine[] };

export type Video = {
  video_id: string;
  title: string;
  channel: string;
  published_at: string;
  topic_id: string | null;
  url: string;
  thumbnail: string;
};

export type SourceRef = {
  title: string;
  source: string;
  domain: string;
  url: string;
  published_at?: string;
};

export type BundleResponse = {
  status: "ok";
  as_of: string;
  plan: PlanInfo;
  mine: NewsItem[];
  locked: Locked | null;
  earnings: EarningsItem[];
  topics: TopicDigest[];
  market: MarketBlock;
  videos: Video[];
  sources: Record<string, SourceRef>;
  attribution: { videos: "YouTube" };
  /// Solo `scope=brief`: clases de activo de la cartera (`crypto`, `bond`,
  /// `etf`, `equity`) para validar `connection`.
  asset_classes?: string[];
  /// Solo `scope=topic`: titulares de la allowlist que nombran al tema.
  topic_news?: TopicNewsItem[];
};

export type TopicNewsItem = {
  id: string;
  title: string;
  source: string;
  domain: string;
  url: string;
  published_at: string;
  lang: Lang | null;
  preferred: boolean;
};

export type ErrorBody = { error: { type: ErrorType | string; message: string } };

// ---------------------------------------------------------------------------
// `news-compare` (Fase 2; el contrato se publica ahora para el chat)
// ---------------------------------------------------------------------------

export type CompareRequest = {
  /// Exactamente uno de `ticker` o `topic_id`.
  ticker: string | null;
  topic_id: string | null;
  story_url?: string | null;
  lang: Lang;
};

export type ComparePoint = {
  kind: "agree" | "differ" | "only";
  text: string;
  source_ids: string[];
};

export type CompareResponse = {
  status: "ok" | "insufficient_sources" | "empty";
  subject: string;
  points: ComparePoint[];
  outlets: string[];
  sources: Record<string, { title: string; source: string; domain: string; url: string }>;
  as_of: string;
};

// ---------------------------------------------------------------------------
// Payload del brief (`daily_briefs.payload`, <= 64 KB)
// ---------------------------------------------------------------------------

export type BriefMover = {
  ticker: string;
  pct: number;
  contribution_abs: number;
  weight_pct: number;
};

export type BriefPayload = {
  v: 1;
  day: string;
  lang: Lang;
  variant: Variant;
  as_of: string;
  numbers: {
    period: "last_close";
    as_of_day: string;
    abs: number;
    pct: number;
    movers: BriefMover[];
  };
  why: { ticker: string; text: string; news_id: string }[];
  held_news: { ticker: string; text: string; news_id: string }[];
  watch_news: { ticker: string; text: string; news_id: string }[];
  market: { topic_id: string | null; text: string; source_ids: string[]; connection: string | null }[];
  earnings: EarningsItem[];
  signals: { kind: string; ticker?: string; weight_pct?: number }[];
  /// Free: `{kind:"held_news", required_plan:"premium"}`, sin ticker.
  teaser: { kind: "held_news"; required_plan: "premium" } | null;
  sources: Record<string, SourceRef>;
  /// Punto de extensión del TTS: en v1 siempre null.
  audio: { url: string; duration_s: number } | null;
};

// ---------------------------------------------------------------------------
// RPC del servidor `daily_brief_entitlement(p_user_id, p_day)`
// ---------------------------------------------------------------------------

export type Entitlement = {
  tier: Tier;
  variant: Variant;
  courtesy: boolean;
  held: { symbol: string; weight_pct: number | null }[];
  watchlist: string[];
  topics: string[];
  prefer: string[];
  mute: string[];
  markets: string[];
  asset_classes: string[];
  /// Interruptor y piezas (el servidor decide; la app no lee el flag).
  enabled: boolean;
  pieces: Record<Piece, boolean>;
};
