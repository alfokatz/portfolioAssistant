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
      return {
        title: es
          ? `${list} ${one ? "presenta" : "presentan"} resultados mañana`
          : `${list} ${one ? "reports" : "report"} earnings tomorrow`,
        body: es
          ? "Tocá para ver qué se espera."
          : "Tap to see what's expected.",
        ...askPorty(
          es
            ? `¿Qué se espera de los resultados de ${list}?`
            : `What's expected from ${list}'s earnings?`,
        ),
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
      return {
        title: es ? `${symbol} presentó resultados` : `${symbol} reported earnings`,
        body: es
          ? `La ganancia por acción quedó ${how}${detail}.`
          : `Earnings per share came in ${how}${detail}.`,
        ...askPorty(
          es ? `¿Cómo le fue a ${symbol} en sus resultados?` : `How did ${symbol}'s earnings go?`,
        ),
      };
    }
  }
}
