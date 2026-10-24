// Textos de cada notificación, en español (rioplatense, como la app) e
// inglés. Reglas (plan §1):
// - Dato + contexto, sin tono de casino ni consejos.
// - Montos del usuario en $ solo con `show_amounts`. El precio de una acción
//   no es un monto del usuario: va siempre.
// - Mismo formato de números que la app (AppNumberFormat): "$751.20",
//   "+7.2%", igual en los dos idiomas.

import type { Kind } from "./kinds.ts";

export type Locale = "es" | "en";

export type Rendered = {
  title: string;
  body: string;
  /// A dónde lleva al tocarla (lo interpreta la app, ver
  /// `PushRoute` en lib/features/notifications/).
  route: string;
  /// Datos extra para la ruta (ticker, pregunta para Porty).
  routeArgs: Record<string, string>;
};

export type RenderOptions = { locale: Locale; showAmounts: boolean };

type Data = Record<string, unknown>;

const num = (v: unknown): number => (typeof v === "number" ? v : Number(v));
/// Como [num], pero lo que falta (null, undefined, "") es NaN y no 0.
const optNum = (v: unknown): number => (v === null || v === undefined || v === "" ? NaN : num(v));
const str = (v: unknown): string => (typeof v === "string" ? v : String(v ?? ""));

export function money(value: number): string {
  return "$" + Math.abs(value).toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

export function signedMoney(value: number): string {
  return (value < 0 ? "-" : "+") + money(value);
}

/// "7.2%"; con signo, "+7.2%" / "-7.2%".
export function percent(value: number, signed = false, decimals = 1): string {
  const abs = Math.abs(value).toLocaleString("en-US", {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  });
  if (!signed) return `${abs}%`;
  return `${value < 0 ? "-" : "+"}${abs}%`;
}

/// "A, B y C" / "A, B and C".
function joinList(items: string[], locale: Locale): string {
  if (items.length <= 1) return items.join("");
  const last = items[items.length - 1];
  return `${items.slice(0, -1).join(", ")} ${locale === "es" ? "y" : "and"} ${last}`;
}

type Move = { symbol: string; change_pct: number };

function moves(data: Data): Move[] {
  const raw = Array.isArray(data.moves) ? data.moves : [];
  return raw
    .map((m) => ({ symbol: str((m as Data).symbol), change_pct: num((m as Data).change_pct) }))
    .filter((m) => m.symbol && Number.isFinite(m.change_pct));
}

function movesLine(list: Move[]): string {
  return list.map((m) => `${m.symbol} ${percent(m.change_pct, true)}`).join(" · ");
}

const askPorty = (question: string): Pick<Rendered, "route" | "routeArgs"> => ({
  route: "assistant",
  routeArgs: { question },
});

type EarningsItem = { symbol: string; weight: number; eps: number; hour: string };

/// Una acción: "Pesa 18% en tu cartera; se espera una ganancia por acción de
/// $0.85, después del cierre." Varias: "Pesan: NVDA 18% · AAPL 6%." Sin
/// datos (versión vieja del productor): la invitación de siempre.
function earningsTomorrowBody(items: EarningsItem[], es: boolean): string {
  const invite = es ? "Tocá para ver el resumen de Porty." : "Tap for Porty's briefing.";
  if (items.length === 0) return es ? "Tocá para ver qué se espera." : "Tap to see what's expected.";
  if (items.length === 1) {
    const i = items[0];
    const parts: string[] = [];
    if (Number.isFinite(i.weight)) {
      parts.push(es ? `Pesa ${percent(i.weight, false, 0)} en tu cartera` : `It's ${percent(i.weight, false, 0)} of your portfolio`);
    }
    if (Number.isFinite(i.eps)) {
      parts.push(
        es
          ? `se espera una ganancia por acción de ${money(i.eps)}`
          : `expected earnings per share: ${money(i.eps)}`,
      );
    }
    const when = i.hour === "bmo"
      ? es ? "antes de la apertura" : "before the open"
      : i.hour === "amc"
      ? es ? "después del cierre" : "after the close"
      : "";
    if (parts.length === 0) return (when ? `${capitalize(when)}. ` : "") + invite;
    const sentence = capitalize(parts.join("; ")) + (when ? `, ${when}` : "") + ".";
    return `${sentence} ${invite}`;
  }
  const weighted = items.filter((i) => Number.isFinite(i.weight)).sort((a, b) => b.weight - a.weight);
  if (weighted.length === 0) return invite;
  const line = weighted.map((i) => `${i.symbol} ${percent(i.weight, false, 0)}`).join(" · ");
  return `${es ? "Pesan" : "Weights"}: ${line}. ${invite}`;
}

function capitalize(s: string): string {
  return s ? s[0].toUpperCase() + s.slice(1) : s;
}

export function render(kind: Kind, data: Data, opts: RenderOptions): Rendered {
  const es = opts.locale === "es";
  switch (kind) {
    case "test":
      return {
        title: "Porty",
        body: es
          ? "Las notificaciones funcionan. Así te vamos a avisar."
          : "Notifications are working. This is how we'll let you know.",
        route: "notification_settings",
        routeArgs: {},
      };

    case "price_alert": {
      const symbol = str(data.symbol);
      const price = num(data.price);
      const target = num(data.target);
      const ref = num(data.reference_price);
      const daily = data.repeat === "daily";
      const again = daily
        ? es ? " Te volvemos a avisar si cruza otra vez." : " We'll let you know if it crosses again."
        : "";
      const routeArgs = { ticker: symbol, alert_id: str(data.alert_id) };
      switch (data.condition) {
        case "above":
          return {
            title: es ? `${symbol} pasó ${money(target)}` : `${symbol} rose above ${money(target)}`,
            body: (es ? `Ahora está en ${money(price)}.` : `It's now at ${money(price)}.`) + again,
            route: "ticker",
            routeArgs,
          };
        case "below":
          return {
            title: es ? `${symbol} bajó de ${money(target)}` : `${symbol} fell below ${money(target)}`,
            body: (es ? `Ahora está en ${money(price)}.` : `It's now at ${money(price)}.`) + again,
            route: "ticker",
            routeArgs,
          };
        case "pct_up":
          return {
            title: es
              ? `${symbol} subió ${percent(target, false, 0)} desde tu alerta`
              : `${symbol} is up ${percent(target, false, 0)} since your alert`,
            body: (es
              ? `Ahora está en ${money(price)} (estaba en ${money(ref)}).`
              : `It's now at ${money(price)} (it was ${money(ref)}).`) + again,
            route: "ticker",
            routeArgs,
          };
        default:
          return {
            title: es
              ? `${symbol} bajó ${percent(target, false, 0)} desde tu alerta`
              : `${symbol} is down ${percent(target, false, 0)} since your alert`,
            body: (es
              ? `Ahora está en ${money(price)} (estaba en ${money(ref)}).`
              : `It's now at ${money(price)} (it was ${money(ref)}).`) + again,
            route: "ticker",
            routeArgs,
          };
      }
    }

    case "big_move": {
      const symbol = str(data.symbol);
      const change = num(data.change_pct);
      const weight = num(data.weight_pct);
      const up = change >= 0;
      return {
        title: es
          ? `${symbol} ${up ? "sube" : "baja"} ${percent(change)} hoy`
          : `${symbol} is ${up ? "up" : "down"} ${percent(change)} today`,
        body: (es
          ? `Pesa ${percent(weight, false, 0)} en tu cartera.`
          : `It's ${percent(weight, false, 0)} of your portfolio.`) +
          (es ? " Tocá para preguntarle a Porty qué está pasando." : " Tap to ask Porty what's going on."),
        ...askPorty(es ? `¿Por qué se mueve ${symbol} hoy?` : `Why is ${symbol} moving today?`),
      };
    }

    case "big_move_digest": {
      const list = moves(data);
      return {
        title: es
          ? `${list.length} de tus acciones se mueven fuerte hoy`
          : `${list.length} of your holdings are moving sharply today`,
        body: movesLine(list),
        route: "home",
        routeArgs: {},
      };
    }

    case "portfolio_move": {
      const change = num(data.change_pct);
      const up = change >= 0;
      const value = num(data.change_value);
      const amount = opts.showAmounts && Number.isFinite(value) ? ` (${signedMoney(value)})` : "";
      const bench = num(data.benchmark_change_pct);
      const parts: string[] = [];
      if (Number.isFinite(bench)) {
        parts.push(
          es
            ? `El S&P 500 ${bench >= 0 ? "sube" : "baja"} ${percent(bench)}.`
            : `The S&P 500 is ${bench >= 0 ? "up" : "down"} ${percent(bench)}.`,
        );
      }
      const top = moves(data).slice(0, 3);
      if (top.length > 0) parts.push((es ? "Lo que más pesa: " : "Biggest drivers: ") + movesLine(top) + ".");
      return {
        title: es
          ? `Tu cartera ${up ? "sube" : "baja"} ${percent(change)} hoy${amount}`
          : `Your portfolio is ${up ? "up" : "down"} ${percent(change)} today${amount}`,
        body: parts.join(" "),
        route: "home",
        routeArgs: {},
      };
    }

    case "weekly_report":
      return {
        title: es ? "Tu semana en Porty está lista" : "Your week in Porty is ready",
        body: es
          ? "Cómo le fue a tu cartera, por qué, y qué viene."
          : "How your portfolio did, why, and what's next.",
        route: "weekly_report",
        routeArgs: {},
      };

    case "etoro_reconnect":
      return {
        title: es ? "Se cortó la conexión con eToro" : "Your eToro connection stopped",
        body: es
          ? "Reconectala para que tu cartera siga al día."
          : "Reconnect it to keep your portfolio up to date.",
        route: "etoro",
        routeArgs: {},
      };

    case "earnings_tomorrow": {
      const symbols = (Array.isArray(data.symbols) ? data.symbols : []).map(str).filter(Boolean);
      const list = joinList(symbols, opts.locale);
      const one = symbols.length === 1;
      const items = (Array.isArray(data.items) ? data.items : []).map((i) => ({
        symbol: str((i as Data).symbol),
        weight: optNum((i as Data).weight_pct),
        eps: optNum((i as Data).eps_estimate),
        hour: str((i as Data).hour),
      }));
      return {
        title: es
          ? `${list} ${one ? "presenta" : "presentan"} resultados mañana`
          : `${list} ${one ? "reports" : "report"} earnings tomorrow`,
        body: earningsTomorrowBody(items, es),
        ...askPorty(
          es
            ? `Armame un resumen antes de los resultados de ${list}: qué se espera, qué conviene mirar y cuánto pesa en mi cartera.`
            : `Give me a briefing before ${list}'s earnings: what's expected, what to watch and how much it weighs in my portfolio.`,
        ),
      };
    }

    case "allocation_drift": {
      const items = (Array.isArray(data.items) ? data.items : [])
        .map((i) => ({
          symbol: str((i as Data).symbol),
          current: num((i as Data).current_pct),
          target: num((i as Data).target_pct),
        }))
        .filter((i) => i.symbol && Number.isFinite(i.current) && Number.isFinite(i.target))
        .slice(0, 2);
      const line = items
        .map((i) =>
          es
            ? `${i.symbol} pesa ${percent(i.current, false, 0)} (tu objetivo: ${percent(i.target, false, 0)})`
            : `${i.symbol} is ${percent(i.current, false, 0)} (your target: ${percent(i.target, false, 0)})`
        )
        .join("; ");
      return {
        title: es ? "Tu cartera se alejó de tu plan" : "Your portfolio drifted from your plan",
        body: (line ? `${line}. ` : "") +
          (es ? "Tocá para ver cómo volver a tu plan." : "Tap to see how to get back to your plan."),
        route: "allocation",
        routeArgs: {},
      };
    }

    case "watchlist_move": {
      const symbol = str(data.symbol);
      const change = num(data.change_pct);
      const since = num(data.since_added_pct);
      const up = change >= 0;
      const sinceText = Number.isFinite(since)
        ? es ? `Desde que la agregaste: ${percent(since, true)}. ` : `Since you added it: ${percent(since, true)}. `
        : "";
      return {
        title: es
          ? `${symbol}, de tu lista, ${up ? "sube" : "baja"} ${percent(change)} hoy`
          : `${symbol}, on your watchlist, is ${up ? "up" : "down"} ${percent(change)} today`,
        body: sinceText +
          (es ? "Tocá para preguntarle a Porty qué está pasando." : "Tap to ask Porty what's going on."),
        ...askPorty(es ? `¿Qué está pasando con ${symbol}?` : `What's going on with ${symbol}?`),
      };
    }

    case "morning_brief": {
      const signals = (Array.isArray(data.signals) ? data.signals : []) as Data[];
      const top = signals[0];
      const symbol = str(top?.symbol);
      const line = !top
        ? ""
        : str(top.kind) === "drift"
        ? es
          ? `${symbol} pesa ${percent(num(top.current_pct), false, 0)} (tu objetivo: ${percent(num(top.target_pct), false, 0)}).`
          : `${symbol} is ${percent(num(top.current_pct), false, 0)} (your target: ${percent(num(top.target_pct), false, 0)}).`
        : es
        ? `${symbol} pesa ${percent(num(top.weight_pct), false, 0)} de tu cartera.`
        : `${symbol} is ${percent(num(top.weight_pct), false, 0)} of your portfolio.`;
      const more = signals.length - 1;
      const moreText = more <= 0 ? "" : es
        ? more === 1 ? " Y una cosa más." : ` Y ${more} cosas más.`
        : more === 1
        ? " And one more thing."
        : ` And ${more} more things.`;
      return {
        title: signals.length > 1
          ? es ? `Porty te marca ${signals.length} cosas hoy` : `Porty noticed ${signals.length} things today`
          : es
          ? "Porty te marca algo hoy"
          : "Porty noticed something today",
        body: `${line}${moreText} ` + (es ? "Tocá para verlo." : "Tap to see it."),
        route: "home",
        routeArgs: {},
      };
    }

    case "earnings_result": {
      const symbol = str(data.symbol);
      const actual = num(data.eps_actual);
      const estimate = num(data.eps_estimate);
      const surprise = str(data.surprise);
      const detail = Number.isFinite(actual) && Number.isFinite(estimate)
        ? ` (${money(actual)} vs. ${money(estimate)})`
        : "";
      const how = surprise === "beat"
        ? es ? "por encima de lo esperado" : "above expectations"
        : surprise === "miss"
        ? es ? "por debajo de lo esperado" : "below expectations"
        : es ? "en línea con lo esperado" : "in line with expectations";
      // v2 (SEC EDGAR): se sabe que presentó, no cómo le fue contra lo esperado.
      const reported = surprise === "reported";
      return {
        title: es ? `${symbol} presentó resultados` : `${symbol} reported earnings`,
        body: reported
          ? es
            ? "Ya publicó sus resultados del trimestre. Tocá para ver cómo le fue."
            : "Its quarterly results are out. Tap to see how it did."
          : es
          ? `La ganancia por acción quedó ${how}${detail}.`
          : `Earnings per share came in ${how}${detail}.`,
        ...askPorty(
          es ? `¿Cómo le fue a ${symbol} en sus resultados?` : `How did ${symbol}'s earnings go?`,
        ),
      };
    }
  }
}
