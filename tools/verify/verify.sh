#!/usr/bin/env bash
# Verificación rápida de un cambio (lo barato primero). La usa la skill
# porty-verify antes de commitear o abrir un PR.
#
#   tools/verify/verify.sh            # cambios sin commitear + commits sobre la base
#   tools/verify/verify.sh --base develop
#   tools/verify/verify.sh --all      # suite completa de Flutter
#
# Qué corre según lo que cambió:
#   - .dart en lib/ o test/  → dart analyze de esos archivos + flutter test de
#                              las carpetas de test relacionadas
#   - assets/translations/    → test/branding + test de traducciones
#   - prompts/catálogo chat   → test/security (allowlist)
#   - supabase/functions/     → deno check + deno test de los tests tocados
#                              (los que necesitan el stack local avisan; ver e2e)
# Imprime un resumen corto y una línea `Verified:` lista para el commit.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

BASE="main"
ALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --base) BASE="$2"; shift 2 ;;
    --all) ALL=1; shift ;;
    *) echo "uso: $0 [--base <rama>] [--all]"; exit 64 ;;
  esac
done

git fetch origin "$BASE" --quiet 2>/dev/null || true
MERGE_BASE=$(git merge-base HEAD "origin/$BASE" 2>/dev/null || echo HEAD)
CHANGED=$( { git diff --name-only "$MERGE_BASE"; git ls-files --others --exclude-standard; } \
  | sort -u | while read -r f; do [ -e "$f" ] && echo "$f"; done)

if [ -z "$CHANGED" ] && [ $ALL -eq 0 ]; then
  echo "Sin cambios contra origin/$BASE."; echo "Verified: none — sin cambios"; exit 0
fi

FAILED=()
RAN=()
step() { # step <etiqueta> <comando...>
  local label="$1"; shift
  echo "▶ $label"
  if "$@" >"/tmp/porty-verify-$$.log" 2>&1; then
    echo "  ✓ ok"; RAN+=("$label")
  else
    echo "  ✗ falló:"; grep -vE "superuser|as root|📎|^  /$" "/tmp/porty-verify-$$.log" | tail -40 | sed 's/^/    /'
    FAILED+=("$label")
  fi
}

DART_FILES=$(echo "$CHANGED" | grep -E '^(lib|test)/.*\.dart$' || true)

if [ $ALL -eq 1 ]; then
  step "flutter analyze" flutter analyze --no-fatal-infos --no-fatal-warnings
  step "flutter test (suite completa)" flutter test --reporter failures-only
else
  if [ -n "$DART_FILES" ]; then
    # shellcheck disable=SC2086
    step "dart analyze (archivos tocados)" dart analyze --fatal-warnings $DART_FILES
  fi

  # Carpetas de test relacionadas: lib/<a>/<b>/… → test/<a>/<b>, más los tests tocados.
  TEST_TARGETS=$(
    {
      echo "$CHANGED" | grep -E '^lib/' | awk -F/ '{print "test/"$2"/"$3}'
      echo "$CHANGED" | grep -E '^test/.*_test\.dart$'
      echo "$CHANGED" | grep -qE '^assets/translations/' && echo "test/branding"
      echo "$CHANGED" | grep -qE '^(assets/prompts/|lib/features/(assistant|genui_core)/)' && echo "test/security"
    } | sort -u | while read -r t; do [ -e "$t" ] && echo "$t"; done
  )
  if [ -n "$TEST_TARGETS" ]; then
    # shellcheck disable=SC2086
    step "flutter test $(echo $TEST_TARGETS)" flutter test --reporter failures-only $TEST_TARGETS
  fi
fi

FN_CHANGED=$(echo "$CHANGED" | grep -E '^supabase/functions/.*\.ts$' || true)
if [ -n "$FN_CHANGED" ]; then
  # shellcheck disable=SC2086
  step "deno check (functions tocadas)" bash -c "cd supabase/functions && deno check $(echo "$FN_CHANGED" | grep -v '/tests/' | sed 's#^supabase/functions/##' | tr '\n' ' ') 2>&1 || exit 1"
  FN_TESTS=$(echo "$FN_CHANGED" | grep '/tests/' | sed 's#^supabase/functions/##' || true)
  for name in $(echo "$FN_CHANGED" | grep -v '/tests/' | awk -F/ '{print $3}' | sort -u); do
    t="supabase/functions/tests/${name//-/_}_test.ts"
    [ -e "$t" ] && FN_TESTS="$FN_TESTS tests/${name//-/_}_test.ts"
  done
  FN_TESTS=$(echo $FN_TESTS | tr ' ' '\n' | sort -u | tr '\n' ' ')
  if [ -n "${FN_TESTS// /}" ]; then
    if [ -z "${SUPABASE_URL:-}" ]; then
      echo "ℹ Sin SUPABASE_URL: los tests de Deno que usan el stack local pueden fallar."
      echo "  Levantalo con: eval \"\$(tools/verify/supabase-env.sh)\""
    fi
    step "deno test $FN_TESTS" bash -c "cd supabase/functions && deno test --allow-net --allow-env --allow-read $FN_TESTS"
  fi
fi

if echo "$CHANGED" | grep -qE '^supabase/(migrations|tests)/'; then
  echo "ℹ Cambió supabase/migrations o supabase/tests: corré tools/verify/sql-tests.sh (necesita el stack local)."
fi

rm -f "/tmp/porty-verify-$$.log"
echo
echo "──────── resumen ────────"
if [ ${#RAN[@]} -eq 0 ] && [ ${#FAILED[@]} -eq 0 ]; then
  echo "Nada que correr para estos archivos (docs/config)."
  echo "Verified: none — sin código ejecutable en el cambio"
  exit 0
fi
[ ${#RAN[@]} -gt 0 ] && printf '✓ %s\n' "${RAN[@]}"
[ ${#FAILED[@]} -gt 0 ] && printf '✗ %s\n' "${FAILED[@]}"
if [ ${#FAILED[@]} -gt 0 ]; then
  echo "Resultado: FALLA"; exit 1
fi
echo "Resultado: OK"
JOINED=$(printf '%s, ' "${RAN[@]}")
echo "Verified: ${JOINED%, }"
