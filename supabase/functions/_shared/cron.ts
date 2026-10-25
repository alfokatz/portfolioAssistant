// Funciones internas (las llama pg_cron vía pg_net, u otra función): se
// autentican con el header `x-cron-secret` contra el secret CRON_SECRET.
// Sin el secret configurado, nadie entra.

import type { Deps } from "./common.ts";

export function isCronRequest(req: Request, deps: Pick<Deps, "env">): boolean {
  const expected = deps.env("CRON_SECRET");
  const given = req.headers.get("x-cron-secret");
  if (!expected || !given) return false;
  const a = new TextEncoder().encode(expected);
  const b = new TextEncoder().encode(given);
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}
