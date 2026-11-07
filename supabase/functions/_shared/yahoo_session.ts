// Sesión de Yahoo Finance (cookie + "crumb"), compartida por el proxy
// `yahoo` y por `market-watch`. Una por instancia de la función (no por
// usuario: Yahoo no sabe nada del usuario, solo de la IP).

import type { Deps } from "./common.ts";

export const yahooSessionConfig = {
  cookieUrl: "https://fc.yahoo.com",
  crumbUrl: "https://query2.finance.yahoo.com/v1/test/getcrumb",
  userAgent:
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
    "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
  /// La sesión de Yahoo dura más, pero renovarla seguido evita arrastrar un
  /// crumb vencido en una instancia que vive mucho.
  sessionTtlMs: 6 * 60 * 60 * 1000,
};

export type YahooSession = { cookie: string; crumb: string; createdAt: number };

let session: YahooSession | null = null;

/// Para los tests: olvidar la sesión entre casos.
export function resetSession() {
  session = null;
}

export async function getSession(
  deps: Pick<Deps, "fetch" | "now">,
  force = false,
): Promise<YahooSession | null> {
  const config = yahooSessionConfig;
  if (!force && session && deps.now() - session.createdAt < config.sessionTtlMs) return session;
  session = null;
  try {
    const cookieRes = await deps.fetch(config.cookieUrl, {
      headers: { "User-Agent": config.userAgent },
      redirect: "manual",
    });
    // fc.yahoo.com responde 404 a propósito: lo que importa es la cookie.
    const cookie = cookieRes.headers
      .getSetCookie()
      .map((c) => c.split(";")[0])
      .filter((c) => c.includes("="))
      .join("; ");
    await cookieRes.body?.cancel();
    if (!cookie) return null;

    const crumbRes = await deps.fetch(config.crumbUrl, {
      headers: { "User-Agent": config.userAgent, Cookie: cookie },
    });
    const crumb = (await crumbRes.text()).trim();
    // Con rate limit, getcrumb devuelve 429 con el texto "Too Many Requests".
    if (crumbRes.status !== 200 || !crumb || crumb.includes(" ") || crumb.length > 64) return null;
    session = { cookie, crumb, createdAt: deps.now() };
    return session;
  } catch {
    return null;
  }
}
