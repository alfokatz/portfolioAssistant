#!/usr/bin/env bash
# Deja ios/Flutter/Generated.xcconfig apuntando al entorno elegido para hacer
# el Archive desde Xcode. Uso: scripts/prepare_xcode.sh develop|prod
# Correrlo SIEMPRE justo antes de Product → Archive (ver
# docs/runbooks/build-entornos.md): Xcode usa los DART_DEFINES de la última
# corrida de Flutter.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
ENV="${1:-}"
case "$ENV" in
  develop|prod) ;;
  *) echo "Uso: scripts/prepare_xcode.sh develop|prod" >&2; exit 1 ;;
esac
ENV_FILE="env/$ENV.json"

scripts/_check_env.sh "$ENV_FILE" "$ENV"
echo "▶ Preparando Xcode para el entorno $(echo "$ENV" | tr '[:lower:]' '[:upper:]')"
flutter build ios --release --config-only --dart-define-from-file="$ENV_FILE" "${@:2}"

# Confirma lo que va a usar Xcode, leyendo los defines que quedaron escritos.
DEFINES=$(grep '^DART_DEFINES=' ios/Flutter/Generated.xcconfig | cut -d= -f2-)
GOT_ENV=""; GOT_URL=""
IFS=',' read -ra PARTS <<< "$DEFINES"
for p in "${PARTS[@]}"; do
  kv=$(echo "$p" | base64 --decode 2>/dev/null || true)
  case "$kv" in
    APP_ENV=*) GOT_ENV="${kv#APP_ENV=}" ;;
    SUPABASE_URL=*) GOT_URL="${kv#SUPABASE_URL=}" ;;
  esac
done
if [ "$GOT_ENV" != "$ENV" ]; then
  echo "✗ Generated.xcconfig quedó con APP_ENV='$GOT_ENV' (esperaba '$ENV')." >&2
  exit 1
fi
echo "✓ Xcode listo: APP_ENV=$GOT_ENV  SUPABASE_URL=$GOT_URL"
echo "  Ahora en Xcode: Product → Archive (sin correr flutter run/build en el medio)."
