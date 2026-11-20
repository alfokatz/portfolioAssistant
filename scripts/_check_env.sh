#!/usr/bin/env bash
# Valida env/<entorno>.json antes de buildear. Uso: _check_env.sh <archivo> <APP_ENV esperado>
# Corta si falta el archivo o una clave, si APP_ENV no coincide o si la key
# es la service role (nunca puede ir en la app).
set -euo pipefail
FILE="$1"
EXPECTED="$2"

if [ ! -f "$FILE" ]; then
  echo "✗ Falta $FILE. Copiá $FILE.example y cargá los valores (ver docs/runbooks/build-entornos.md)." >&2
  exit 1
fi

python3 -I - "$FILE" "$EXPECTED" <<'PY'
import base64, json, sys
path, expected = sys.argv[1], sys.argv[2]
try:
    env = json.load(open(path))
except Exception as e:
    sys.exit(f"✗ {path} no es JSON válido: {e}")

def val(k):
    v = env.get(k, "")
    return v.strip() if isinstance(v, str) else ""

errors = []
for k in ("SUPABASE_URL", "SUPABASE_ANON_KEY", "APP_ENV"):
    if not val(k) or "<" in val(k):
        errors.append(f"{k} vacía o con el valor de ejemplo")
if val("APP_ENV") and val("APP_ENV") != expected:
    errors.append(f'APP_ENV es "{val("APP_ENV")}" y este build espera "{expected}"')
url = val("SUPABASE_URL")
if url and not url.startswith("https://"):
    errors.append("SUPABASE_URL tiene que empezar con https://")

key = val("SUPABASE_ANON_KEY")
if key.startswith("sb_secret_"):
    errors.append("SUPABASE_ANON_KEY es una secret key: usá la anon/publishable")
elif key.count(".") == 2:
    try:
        payload = key.split(".")[1]
        payload += "=" * (-len(payload) % 4)
        if json.loads(base64.urlsafe_b64decode(payload)).get("role") == "service_role":
            errors.append("SUPABASE_ANON_KEY es la SERVICE ROLE key: usá la anon")
    except Exception:
        pass

if errors:
    sys.exit("✗ " + path + ":\n  - " + "\n  - ".join(errors))
print(f"✓ {path}: APP_ENV={val('APP_ENV')}  SUPABASE_URL={url}")
PY
