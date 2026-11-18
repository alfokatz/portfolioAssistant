#!/usr/bin/env bash
# Setup del entorno cloud de Claude Code para Porty.
# Instala lo que necesitan los agentes para verificar sus cambios solos:
#   - Flutter (misma versión que el CI) con soporte web
#   - Deno (tests de edge functions)
#   - CLI de Supabase (stack local: migraciones + tests SQL; necesita Docker)
# Se pega en la configuración del entorno (Setup script). Es idempotente:
# si algo ya está instalado, lo saltea. No usa secretos.
set -euo pipefail

FLUTTER_VERSION="3.47.9"   # mantener igual que .github/workflows/ci.yml
FLUTTER_DIR="/opt/flutter"
BIN_DIR="/usr/local/bin"

log() { echo "[porty-setup] $*"; }

# 1) Flutter (desde el bucket oficial; github.com puede estar filtrado por el proxy)
if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  log "Instalando Flutter $FLUTTER_VERSION…"
  curl -fsSL --retry 3 \
    "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    | tar -xJ -C /opt
fi
git config --global --add safe.directory "$FLUTTER_DIR" || true
ln -sf "$FLUTTER_DIR/bin/flutter" "$BIN_DIR/flutter"
ln -sf "$FLUTTER_DIR/bin/dart" "$BIN_DIR/dart"
flutter config --no-analytics --enable-web >/dev/null
dart --disable-analytics >/dev/null 2>&1 || true
flutter precache --web --no-android --no-ios --no-linux >/dev/null
log "Flutter: $(flutter --version | head -1)"

# 2) Deno (por npm: dl.deno.land no siempre es accesible)
if ! command -v deno >/dev/null 2>&1; then
  log "Instalando Deno…"
  npm install -g deno >/dev/null
fi
log "Deno: $(deno --version | head -1)"

# 3) CLI de Supabase (el paquete npm baja el binario de GitHub releases)
if ! command -v supabase >/dev/null 2>&1; then
  log "Instalando CLI de Supabase…"
  npm install -g supabase >/dev/null
fi
log "Supabase CLI: $(supabase --version)"

# 4) Docker para `supabase start` (opcional: si no arranca, el stack local no
#    está disponible y la verificación de backend queda para el CI).
if command -v dockerd >/dev/null 2>&1 && ! docker info >/dev/null 2>&1; then
  log "Levantando Docker…"
  (dockerd >/var/log/dockerd.log 2>&1 &) || true
  for _ in $(seq 1 20); do docker info >/dev/null 2>&1 && break; sleep 1; done
fi
if docker info >/dev/null 2>&1; then
  log "Docker: OK"
else
  log "Docker: NO disponible (sin supabase start en este entorno)"
fi

# 5) Dependencias del proyecto (si el repo ya está clonado en el directorio actual)
if [ -f pubspec.yaml ]; then
  log "flutter pub get…"
  flutter pub get >/dev/null
fi

log "Listo."
