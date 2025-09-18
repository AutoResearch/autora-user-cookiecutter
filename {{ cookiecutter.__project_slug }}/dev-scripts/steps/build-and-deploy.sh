#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
source "$SCRIPT_DIR/config.env"
source "$SCRIPT_DIR/lib/common.sh"

echo "🏗️ Building project..."
npm install
npm run build

echo "🚀 Deploying to Firebase Hosting..."
fb deploy --project "$PROJECT_ID"

URL="https://${PROJECT_ID}.web.app"
echo "✅ Deployment complete!"
echo "🌍 Live at: $URL"
echo "🔑 Admin SDK key (if created): $SERVICE_ACCOUNT_KEY_FILE"
echo "🧪 Web SDK config: $FIREBASE_CONFIG_FILE"
