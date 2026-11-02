// Borrado de cuenta desde la app. Ver docs/runbooks/account-deletion.md.
// Deploy: supabase functions deploy delete-account (verify_jwt = false en
// config.toml: valida el JWT ella misma).
// Secrets (ya existen en el proyecto): REVENUECAT_SECRET_API_KEY (sk_… v1),
// SNAPTRADE_CLIENT_ID, SNAPTRADE_CONSUMER_KEY, ETORO_CLIENT_ID,
// ETORO_CLIENT_SECRET. Opcionales: SNAPTRADE_API_URL, ETORO_ENVIRONMENT.
import { defaultDeps } from "../_shared/common.ts";
import { handle } from "./handler.ts";

const base = defaultDeps();
// Acción irreversible: getUser consulta al servidor de Auth y rechaza sesiones
// revocadas (cerrar sesión en todos lados, cambio de clave). El getClaims local
// de defaultDeps aceptaría un access token robado hasta que venza.
const deps = {
  ...base,
  authenticate: async (jwt: string) => {
    const { data, error } = await base.db.auth.getUser(jwt);
    if (error || !data?.user?.id) return null;
    return data.user.id;
  },
};
Deno.serve((req) => handle(req, deps));
