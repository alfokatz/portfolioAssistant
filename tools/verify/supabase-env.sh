#!/usr/bin/env bash
# Levanta el stack local de Supabase (si no está) e imprime los `export` de sus
# variables, igual que el CI. Uso:  eval "$(tools/verify/supabase-env.sh)"
# Todo lo informativo va a stderr para que stdout sea solo los export.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

if ! docker info >/dev/null 2>&1; then
  echo "[supabase-env] levantando Docker…" >&2
  (dockerd >/var/log/dockerd.log 2>&1 &) || true
  for _ in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 1; done
  docker info >/dev/null 2>&1 || { echo "[supabase-env] Docker no disponible" >&2; exit 1; }
fi

if ! supabase status >/dev/null 2>&1; then
  # La CLI nueva renombró [inbucket] a [local_smtp] (igual que en el CI). Se
  # adapta sobre una copia y se restaura, para no dejar el archivo cambiado.
  cp supabase/config.toml /tmp/porty-config.toml.bak
  sed -i 's/^\[inbucket\]$/[local_smtp]/' supabase/config.toml
  echo "[supabase-env] supabase start (la primera vez baja imágenes, ~3-5 min)…" >&2
  supabase start -x studio,imgproxy,mailpit,logflare,vector,supavisor >&2 || {
    cp /tmp/porty-config.toml.bak supabase/config.toml; exit 1; }
  cp /tmp/porty-config.toml.bak supabase/config.toml
fi

eval "$(supabase status -o env 2>/dev/null)"
# Recién levantado, `status` a veces todavía no devuelve las variables: se
# reintenta un rato y, si siguen vacías, se corta (antes devolvía `export`
# vacíos y psql terminaba conectándose a un socket local que no existe).
for _ in $(seq 1 15); do
  [ -n "${DB_URL:-}" ] && break
  sleep 2
  eval "$(supabase status -o env 2>/dev/null)"
done
if [ -z "${DB_URL:-}" ]; then
  echo "[supabase-env] el stack no devolvió sus variables (supabase status)" >&2
  exit 1
fi
cat <<EOF
export API_URL='$API_URL'
export SUPABASE_URL='$API_URL'
export DB_URL='$DB_URL'
export ANON_KEY='$ANON_KEY'
export SUPABASE_ANON_KEY='$ANON_KEY'
export SERVICE_ROLE_KEY='$SERVICE_ROLE_KEY'
export SUPABASE_SERVICE_ROLE_KEY='$SERVICE_ROLE_KEY'
EOF
