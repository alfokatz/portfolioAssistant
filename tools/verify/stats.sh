#!/usr/bin/env bash
# "Revisar a los revisores": cuánto de lo que entra está verificado y cuánto
# se revierte o se arregla después. Correlo cada tanto (ej. una vez al mes) y
# usalo para decidir si la compuerta pasa de observe a enforce o si REVIEW.md
# necesita reglas nuevas.
#
#   tools/verify/stats.sh [desde]   # por defecto: "30 days ago"
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SINCE="${1:-30 days ago}"

total=$(git log --since="$SINCE" --no-merges --format=%h | wc -l | tr -d ' ')
verified=$(git log --since="$SINCE" --no-merges --format=%B | grep -c '^Verified: ' || true)
none=$(git log --since="$SINCE" --no-merges --format=%B | grep -c '^Verified: none' || true)
reverts=$(git log --since="$SINCE" --no-merges --format=%s | grep -ciE '^(revert|revierte)' || true)
fixes=$(git log --since="$SINCE" --no-merges --format=%s | grep -ciE '^(fix|arregl|corrig|hotfix)' || true)

echo "Desde: $SINCE"
echo "Commits:                 $total"
echo "  con Verified:          $verified (de esos, 'none': $none)"
echo "  sin línea Verified:    $((total - verified))"
echo "  reverts:               $reverts"
echo "  fixes:                 $fixes"
echo
echo "Fixes recientes (¿alguno debería ser una regla de REVIEW.md?):"
git log --since="$SINCE" --no-merges --format='  %h %s' | grep -iE ' (fix|arregl|corrig|hotfix|revert)' | head -15

LOG=.claude/verify-gate.log
if [ -f "$LOG" ]; then
  echo
  echo "Compuerta de verificación (hook Stop), turnos que terminaron sin verificar:"
  echo "  total: $(wc -l < "$LOG" | tr -d ' ')"
  echo "  archivos más frecuentes:"
  grep -o '"files":\[[^]]*\]' "$LOG" | grep -oE '"[^"]+"' | grep -v '"files"' | sort | uniq -c | sort -rn | head -5 | sed 's/^/    /'
fi
