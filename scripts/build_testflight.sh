#!/usr/bin/env bash
# IPA para TestFlight contra la branch develop de Supabase (pastilla DEV).
# Ver docs/runbooks/build-entornos.md. No usar Archive de Xcode.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
ENV_FILE="env/develop.json"

scripts/_check_env.sh "$ENV_FILE" develop
echo "▶ Buildeando IPA para TestFlight → entorno DEVELOP"
flutter build ipa --release --dart-define-from-file="$ENV_FILE" "$@"
echo "✓ IPA (develop) en build/ios/ipa/"
