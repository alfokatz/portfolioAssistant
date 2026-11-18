#!/usr/bin/env bash
# E2E de Porty: levanta Supabase local, crea un usuario de prueba, compila la
# app para web apuntando al stack local, la sirve y la maneja con Playwright.
#
#   tools/verify/e2e/run.sh                 # todos los flujos
#   tools/verify/e2e/run.sh login-y-home    # solo esos (separados por coma)
#   E2E_SKIP_BUILD=1 tools/verify/e2e/run.sh  # reusa build/web (si no tocaste lib/)
#
# Capturas y reporte en build/e2e/. Nunca toca Supabase remoto.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
ROOT=$(pwd)
PORT="${E2E_PORT:-8099}"
OUT="$ROOT/build/e2e"
ENV_FILE="env/e2e.json"

eval "$(tools/verify/supabase-env.sh)"

# Usuario de prueba nuevo en cada corrida (así siempre ve el onboarding y una
# cartera vacía): se crea confirmado vía la API admin del stack local.
E2E_EMAIL="e2e+$(date +%s)@porty.test"
E2E_PASSWORD="PortyE2e2026"
curl -fsS -o /dev/null -X POST "$SUPABASE_URL/auth/v1/admin/users" \
  -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$E2E_EMAIL\",\"password\":\"$E2E_PASSWORD\",\"email_confirm\":true,\"user_metadata\":{\"full_name\":\"Prueba E2E\"}}" \
  || { echo "No pude crear el usuario de prueba en $SUPABASE_URL"; exit 1; }

# Entorno e2e (solo claves del stack LOCAL; está en .gitignore).
mkdir -p env
cat > "$ENV_FILE" <<EOF
{"APP_ENV": "develop", "SUPABASE_URL": "$SUPABASE_URL", "SUPABASE_ANON_KEY": "$SUPABASE_ANON_KEY"}
EOF
trap 'rm -f "$ENV_FILE"; [ -n "${SERVER_PID:-}" ] && kill "$SERVER_PID" 2>/dev/null || true' EXIT

if [ "${E2E_SKIP_BUILD:-0}" != "1" ] || [ ! -f build/web/index.html ]; then
  echo "▶ flutter build web ($ENV_FILE, ~2 min)…"
  # --no-web-resources-cdn: CanvasKit va dentro del build (el navegador del
  # entorno cloud no siempre llega a gstatic.com).
  flutter build web --no-pub --no-wasm-dry-run --no-web-resources-cdn --dart-define-from-file="$ENV_FILE" >/tmp/porty-e2e-build.log 2>&1 \
    || { tail -30 /tmp/porty-e2e-build.log; exit 1; }
fi

echo "▶ sirviendo build/web en :$PORT"
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory build/web >/dev/null 2>&1 &
SERVER_PID=$!
for _ in $(seq 1 20); do curl -fsS -o /dev/null "http://127.0.0.1:$PORT/" && break; sleep 0.5; done

echo "▶ flujos E2E"
# Playwright viene preinstalado en el entorno (require global).
NODE_PATH="$(npm root -g)" E2E_URL="http://127.0.0.1:$PORT" E2E_EMAIL="$E2E_EMAIL" \
  E2E_PASSWORD="$E2E_PASSWORD" E2E_OUT="$OUT" E2E_FLOWS="${1:-}" \
  node tools/verify/e2e/flows.mjs
