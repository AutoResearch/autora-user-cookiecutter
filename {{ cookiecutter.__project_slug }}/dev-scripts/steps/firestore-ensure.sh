#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
source "$SCRIPT_DIR/config.env"
source "$SCRIPT_DIR/lib/common.sh"

if gcloud firestore databases describe --project="$PROJECT_ID" --format="value(name)" >/dev/null 2>&1; then
  echo "✅ Firestore already initialized"
else
  echo "🔥 Enabling Firestore API and creating database in $REGION..."
  gcloud services enable firestore.googleapis.com --project "$PROJECT_ID"
  gcloud firestore databases create --location="$REGION" --project "$PROJECT_ID"
fi
