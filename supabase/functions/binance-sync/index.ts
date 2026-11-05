// Deploy: supabase functions deploy binance-sync
// Secrets: ninguno obligatorio. Opcional BINANCE_API_URL (por ejemplo, un
// endpoint alternativo de Binance si la región del proyecto está bloqueada;
// ver docs/runbooks/binance-sync.md).
import { defaultDeps } from "../_shared/common.ts";
import { handle } from "./handler.ts";

const deps = defaultDeps();
Deno.serve((req) => handle(req, deps));
