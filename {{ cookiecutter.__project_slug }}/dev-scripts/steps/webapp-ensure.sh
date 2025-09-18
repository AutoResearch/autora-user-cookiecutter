#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
source "$SCRIPT_DIR/config.env"
source "$SCRIPT_DIR/lib/common.sh"

echo "🔍 Looking for existing Firebase Web App..."
APP_ID="$(fb apps:list --project "$PROJECT_ID" --json \
  | jq -r '.result // [] | .[] | select(.platform=="WEB") | .appId' | head -n1)"

if [ -z "$APP_ID" ] || [ "$APP_ID" = "null" ]; then
  echo "🌐 No Web App found, creating one..."
  CREATE_OUTPUT="$(fb apps:create web "$WEBAPP_NAME" --project "$PROJECT_ID" --json 2>firebase_error.log || true)"
  # persist raw output for debugging
  printf '%s\n' "$CREATE_OUTPUT" > .firebase_app_create_output.json

  # robustly extract appId whether it's top-level or nested under result
  APP_ID="$(printf '%s' "$CREATE_OUTPUT" | jq -r '(.appId // .result.appId // empty)')"

  if [ -z "$APP_ID" ] || [ "$APP_ID" = "null" ]; then
    echo "❌ Failed to extract Web App ID from create output:"
    cat .firebase_app_create_output.json
    echo "ℹ️ Check firebase_error.log for CLI stderr."
    exit 1
  fi
  echo "✅ Created Web App: $APP_ID"
else
  echo "✅ Found existing Web App: $APP_ID"
fi

# persist APP_ID for later steps
echo "$APP_ID" > .firebase_app_id
