#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
source "$SCRIPT_DIR/config.env"
source "$SCRIPT_DIR/lib/common.sh"

APP_ID="$(cat .firebase_app_id)"
echo "📦 Exporting Web SDK config to $FIREBASE_CONFIG_FILE"
fb apps:sdkconfig web "$APP_ID" --project "$PROJECT_ID" > "$FIREBASE_CONFIG_FILE"
