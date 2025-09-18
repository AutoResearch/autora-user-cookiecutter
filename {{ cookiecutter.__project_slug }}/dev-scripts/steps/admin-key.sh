#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
source "$SCRIPT_DIR/config.env"
source "$SCRIPT_DIR/lib/common.sh"

echo "🔐 Locating Firebase Admin SDK service account..."
SA_EMAIL="$(gcloud iam service-accounts list --project="$PROJECT_ID" \
  --filter="displayName:Firebase Admin SDK" --format="value(email)")"

if [ -z "$SA_EMAIL" ]; then
  die "Could not find Firebase Admin SDK service account."
fi

mkdir -p "$(dirname "$SERVICE_ACCOUNT_KEY_FILE")"
if [ -f "$SERVICE_ACCOUNT_KEY_FILE" ]; then
  echo "✅ Service account key already exists: $SERVICE_ACCOUNT_KEY_FILE"
else
  echo "📥 Creating Admin SDK key..."
  if ! gcloud iam service-accounts keys create "$SERVICE_ACCOUNT_KEY_FILE" --iam-account="$SA_EMAIL"; then
    echo "⚠️  Could not create a key (org policy may block it). Skipping."
  fi
fi
