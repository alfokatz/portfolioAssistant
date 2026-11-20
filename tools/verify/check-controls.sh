#!/usr/bin/env bash
# Revisa dos reglas de verificación sobre los commits de una rama contra su base:
#  1. Un cambio no modifica sus propios controles: los archivos que juzgan los
#     cambios (REVIEW.md, CLAUDE.md, hooks, settings, CI, tests de seguridad,
#     tools/verify/) van en un PR aparte, sin código de producto.
#  2. Cada commit dice cómo se verificó (línea `Verified:`).
#
#   tools/verify/check-controls.sh [--base main] [--mode observe|enforce]
#
# observe (por defecto): avisa y sale 0. enforce: sale 1 si algo no cumple.
# En GitHub Actions los avisos salen como ::warning / ::error.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

BASE="main"
MODE="${CONTROLS_GATE:-observe}"
while [ $# -gt 0 ]; do
  case "$1" in
    --base) BASE="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    *) echo "uso: $0 [--base <rama>] [--mode observe|enforce]"; exit 64 ;;
  esac
done

REF="origin/$BASE"
git rev-parse --verify --quiet "$REF" >/dev/null || git fetch origin "$BASE" --quiet 2>/dev/null || true
git rev-parse --verify --quiet "$REF" >/dev/null || REF="$BASE"
RANGE="$(git merge-base HEAD "$REF")..HEAD"

CONTROLS='^(REVIEW\.md|CLAUDE\.md|\.claude/(hooks/|settings\.json)|\.github/|test/security/|tools/verify/)'
FILES=$(git diff --name-only "$RANGE")
CTRL=$(echo "$FILES" | grep -E "$CONTROLS" || true)
OTHER=$(echo "$FILES" | grep -vE "$CONTROLS" | grep -v '^$' || true)

say() { # say <warning|error> <mensaje>
  if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::$1::$2"; else echo "[$1] $2"; fi
}
level=$([ "$MODE" = "enforce" ] && echo error || echo warning)
problems=0

if [ -n "$CTRL" ] && [ -n "$OTHER" ]; then
  problems=$((problems + 1))
  say "$level" "Este cambio toca controles ($(echo "$CTRL" | head -5 | tr '\n' ' ')) junto con código ($(echo "$OTHER" | wc -l | tr -d ' ') archivos). Los controles van en un PR aparte."
fi

MISSING=$(git log --format='%h%x09%s%x09%B%x1e' "$RANGE" --no-merges \
  | awk -v RS='\x1e' 'NF && $0 !~ /\nVerified: / && $0 !~ /^[^\t]*\t[^\t]*\tVerified: / { split($0, a, "\t"); gsub(/^\n/, "", a[1]); print a[1] " " a[2] }')
if [ -n "$MISSING" ]; then
  problems=$((problems + 1))
  say "$level" "Commits sin línea Verified: $(echo "$MISSING" | wc -l | tr -d ' ') — $(echo "$MISSING" | head -5 | tr '\n' ';')"
fi

TOTAL=$(git rev-list --count --no-merges "$RANGE")
NONE=$(git log --format=%B "$RANGE" --no-merges | grep -c '^Verified: none' || true)
echo "Commits: $TOTAL · Verified: none → $NONE · sin línea Verified → $(echo -n "$MISSING" | grep -c . || true)"
echo "Controles tocados: $(echo -n "$CTRL" | grep -c . || true) · otros archivos: $(echo -n "$OTHER" | grep -c . || true)"

if [ "$MODE" = "enforce" ] && [ $problems -gt 0 ]; then exit 1; fi
exit 0
