#!/usr/bin/env bash
# IPA para App Store contra la branch main (producción) de Supabase.
# Ver docs/runbooks/build-entornos.md. No usar Archive de Xcode.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
ENV_FILE="env/prod.json"

scripts/_check_env.sh "$ENV_FILE" prod
echo "▶ Buildeando IPA para App Store → entorno PROD (producción)"
flutter build ipa --release --dart-define-from-file="$ENV_FILE" "$@"
echo "✓ IPA (prod) en build/ios/ipa/"
