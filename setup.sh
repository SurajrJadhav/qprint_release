#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# Qprint one-time setup after git clone (idempotent).
# Usage: ./setup.sh [full|deps|env]
# Note: Sumatra/LibreOffice are Windows-only (use setup.bat bins on Windows).

SCOPE="${1:-full}"

echo "========================================"
echo "  Qprint initial setup ($SCOPE)"
echo "========================================"

copy_if_missing() {
  local src="$1" dst="$2"
  if [[ -f "$dst" ]]; then
    echo "keep  $dst"
    return 0
  fi
  if [[ ! -f "$src" ]]; then
    echo "skip  $dst (no example)"
    return 0
  fi
  cp "$src" "$dst"
  echo "created $dst  (from example - edit me)"
}

do_env() {
  echo "-------- Env files (create if missing) --------"
  copy_if_missing backend/.env.example backend/.env
  copy_if_missing frontend/.env.example frontend/.env.local
  copy_if_missing admin_frontend/.env.example admin_frontend/.env.local
  copy_if_missing customer_app/android/app/google-services.json.example \
    customer_app/android/app/google-services.json
  echo "Edit backend/.env and frontend/.env.local before running."
}

do_deps() {
  echo "-------- Dependencies --------"
  echo "[backend] go mod download..."
  (cd backend && go mod download)
  echo "[backend] OK"

  echo "[frontend] npm install..."
  if [[ -d frontend/node_modules ]]; then
    echo "node_modules already present - skipping"
  else
    (cd frontend && npm install)
  fi
  echo "[frontend] OK"

  echo "[admin_frontend] npm install..."
  if [[ -d admin_frontend/node_modules ]]; then
    echo "node_modules already present - skipping"
  else
    (cd admin_frontend && npm install)
  fi
  echo "[admin_frontend] OK"

  if command -v flutter >/dev/null 2>&1; then
    echo "[customer_app] flutter pub get..."
    (cd customer_app && flutter pub get)
    echo "[shopkeeper_app] flutter pub get..."
    (cd shopkeeper_app && flutter pub get)
  else
    echo "[flutter] not in PATH - skip pub get"
  fi
}

case "$SCOPE" in
  env) do_env ;;
  deps) do_deps ;;
  full)
    do_env
    do_deps
    echo "Windows binaries (Sumatra/LibreOffice): run setup.bat bins on Windows."
    ;;
  bins)
    echo "Sumatra/LibreOffice setup is Windows-only. Use setup.bat bins"
    exit 1
    ;;
  *)
    echo "Unknown option: $SCOPE (full|deps|env)"
    exit 1
    ;;
esac

echo "========================================"
echo "  Setup finished"
echo "========================================"
echo "Next: edit .env files, create DB, then ./manage.sh start or ./build.sh"
echo "Re-run is safe: existing deps are not reinstalled."
