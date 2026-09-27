#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# Qprint unified build script
# Usage:
#   ./build.sh                     # interactive
#   ./build.sh debug               # all, debug/test
#   ./build.sh release             # all, release
#   ./build.sh debug frontend
#   ./build.sh release customer aab
# Targets: all | backend | frontend | admin | customer | shopkeeper

MODE="${1:-}"
TARGET="${2:-all}"
CUSTOMER_FMT="${3:-apk}"

if [[ -f scripts/google_oauth.config.sh ]]; then
  # shellcheck disable=SC1091
  source scripts/google_oauth.config.sh
fi

if [[ -z "$MODE" ]]; then
  echo "========================================"
  echo "  Qprint Build"
  echo "========================================"
  echo "Mode: 1) debug/test  2) release"
  read -r -p "Enter choice [1-2]: " mode_choice
  if [[ "$mode_choice" == "2" ]]; then MODE=release; else MODE=debug; fi

  echo "Target: 1) all  2) backend  3) frontend  4) admin  5) customer  6) shopkeeper"
  read -r -p "Enter choice [1-6]: " target_choice
  case "$target_choice" in
    2) TARGET=backend ;;
    3) TARGET=frontend ;;
    4) TARGET=admin ;;
    5) TARGET=customer ;;
    6) TARGET=shopkeeper ;;
    *) TARGET=all ;;
  esac

  if [[ "$TARGET" == "customer" ]]; then
    echo "Customer package: 1) APK  2) AAB"
    read -r -p "Enter choice [1-2]: " fmt_choice
    if [[ "$fmt_choice" == "2" ]]; then CUSTOMER_FMT=aab; fi
  fi
fi

case "$MODE" in
  debug|test) MODE=debug ;;
  release) ;;
  *) echo "Unknown mode: $MODE"; exit 1 ;;
esac

echo "Mode=$MODE  Target=$TARGET"

build_backend() {
  echo "-------- Backend (Go) [$MODE] --------"
  pushd backend >/dev/null
  if [[ "$MODE" == "release" ]]; then
    go build -o qprint-api ./cmd/api
  else
    go build -o qprint-api-debug ./cmd/api
  fi
  popd >/dev/null
  echo "Backend OK."
}

build_frontend() {
  echo "-------- Frontend (Next.js) [$MODE] --------"
  pushd frontend >/dev/null
  [[ -d node_modules ]] || npm install
  if [[ "$MODE" == "release" ]]; then
    npm run build
  else
    npm run lint || true
    echo "Debug/test: use ./manage.sh start or npm run dev"
  fi
  popd >/dev/null
  echo "Frontend OK."
}

build_admin() {
  echo "-------- Admin frontend (Next.js) [$MODE] --------"
  pushd admin_frontend >/dev/null
  [[ -d node_modules ]] || npm install
  if [[ "$MODE" == "release" ]]; then
    npm run build
  else
    npm run lint || true
    echo "Debug/test: npm run dev -p 3001"
  fi
  popd >/dev/null
  echo "Admin frontend OK."
}

build_customer() {
  echo "-------- Customer app (Flutter Android) [$MODE] --------"
  pushd customer_app >/dev/null
  flutter pub get
  local base_url="${PROD_BASE_URL:-https://qprint-72wr.onrender.com}"
  if [[ "$MODE" == "debug" ]]; then base_url="http://10.0.2.2:8080"; fi
  local google_id="${GOOGLE_SERVER_CLIENT_ID:-${GOOGLE_WEB_CLIENT_ID:-}}"

  if [[ "$MODE" == "release" ]]; then
    if [[ "$CUSTOMER_FMT" == "aab" ]]; then
      flutter build appbundle --release \
        --dart-define=BASE_URL="$base_url" \
        --dart-define=GOOGLE_SERVER_CLIENT_ID="$google_id"
    else
      flutter build apk --release \
        --dart-define=BASE_URL="$base_url" \
        --dart-define=GOOGLE_SERVER_CLIENT_ID="$google_id"
    fi
  else
    flutter build apk --debug \
      --dart-define=BASE_URL="$base_url" \
      --dart-define=GOOGLE_SERVER_CLIENT_ID="$google_id"
  fi
  popd >/dev/null
  echo "Customer app OK."
}

build_shopkeeper() {
  echo "-------- Shopkeeper app (Flutter Windows) [$MODE] --------"
  echo "Note: Windows shopkeeper builds need Windows + Flutter desktop."
  pushd shopkeeper_app >/dev/null
  flutter pub get
  local base_url="${PROD_BASE_URL:-https://qprint-72wr.onrender.com}"
  if [[ "$MODE" == "debug" ]]; then base_url="http://localhost:8080"; fi
  local google_id="${GOOGLE_DESKTOP_CLIENT_ID:-}"

  if [[ "$MODE" == "release" ]]; then
    flutter build windows --release \
      --dart-define=BASE_URL="$base_url" \
      --dart-define=GOOGLE_DESKTOP_CLIENT_ID="$google_id"
  else
    flutter build windows --debug \
      --dart-define=BASE_URL="$base_url" \
      --dart-define=GOOGLE_DESKTOP_CLIENT_ID="$google_id"
  fi
  popd >/dev/null
  echo "Shopkeeper app OK."
}

case "$TARGET" in
  all)
    build_backend
    build_frontend
    build_admin
    build_customer
    build_shopkeeper
    ;;
  backend) build_backend ;;
  frontend) build_frontend ;;
  admin|admin_frontend) build_admin ;;
  customer|customer_app) build_customer ;;
  shopkeeper|shopkeeper_app) build_shopkeeper ;;
  *) echo "Unknown target: $TARGET"; exit 1 ;;
esac

echo "========================================"
echo "  Build finished ($MODE)"
echo "========================================"
