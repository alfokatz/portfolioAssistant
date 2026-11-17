#!/usr/bin/env bash
# Tests SQL de supabase/tests contra el stack local (igual que el CI).
# Levanta el stack si hace falta. Uso: tools/verify/sql-tests.sh [archivo…]
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
eval "$(tools/verify/supabase-env.sh)"
FILES=("$@")
[ ${#FILES[@]} -eq 0 ] && FILES=(supabase/tests/*_db_test.sql)
for f in "${FILES[@]}"; do
  echo "▶ $f"
  psql "$DB_URL" -v ON_ERROR_STOP=1 -q -f "$f" >/dev/null
  echo "  ✓ ok"
done
