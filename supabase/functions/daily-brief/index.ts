// Deploy: supabase functions deploy daily-brief  (solo con OK del usuario)
// Secrets: OPENAI_API_KEY (digests, solo si la caché está vacía); opcional
// NEWS_CONTEXT_MODEL. Nada más: los titulares salen de GDELT y de la caché.
import { defaultDeps } from "../_shared/common.ts";
import { handle } from "./handler.ts";

const deps = defaultDeps();
Deno.serve((req) => handle(req, deps));
