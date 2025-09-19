#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
source "$SCRIPT_DIR/config.env"
source "$SCRIPT_DIR/lib/common.sh"

# Ensure PROJECT_ID and active gcloud project are set
: "${PROJECT_ID:=$(gcloud config get-value project 2>/dev/null || true)}"
if [ -z "${PROJECT_ID:-}" ]; then
  die "PROJECT_ID is empty and no active gcloud project set."
fi
gcloud config set project "$PROJECT_ID" >/dev/null

echo "🔐 Locating Firebase Admin SDK service account..."

# Try by displayName first (best-case)
SA_EMAIL="$(gcloud iam service-accounts list \
  --filter='displayName=Firebase Admin SDK' \
  --format='value(email)' || true)"

# If displayName filter didn’t work, try by email pattern
if [ -z "${SA_EMAIL:-}" ]; then
  SA_EMAIL="$(gcloud iam service-accounts list \
    --format='value(email)' \
    | awk -v p="$PROJECT_ID" -F' ' '$0 ~ ("^firebase-adminsdk-.*@" p "\\.iam\\.gserviceaccount\\.com$") {print $0; exit}')"
fi

# If still not found, create one
if [ -z "${SA_EMAIL:-}" ]; then
  echo "ℹ️  No Firebase Admin SDK service account found; creating one..."
  # Generate a short suffix to mimic Firebase's style
  SUFFIX="$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c5)"
  SA_ID="firebase-adminsdk-${SUFFIX}"
  gcloud iam service-accounts create "$SA_ID" \
    --display-name="Firebase Admin SDK"

  SA_EMAIL="${SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com"

  # Grant useful roles for local/dev automation (adjust to your org policy)
  echo "🔧 Granting roles to ${SA_EMAIL} (adjust as needed)…"
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/firebase.admin" >/dev/null || true
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/datastore.user" >/dev/null || true
  # If you use Hosting/Storage from this SA, uncomment:
  # gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  #   --member="serviceAccount:${SA_EMAIL}" \
  #   --role="roles/storage.admin" >/dev/null || true
fi

if [ -z "${SA_EMAIL:-}" ]; then
  die "Could not find or create a Firebase Admin SDK service account."
fi

echo "✅ Using service account: ${SA_EMAIL}"

mkdir -p "$(dirname "$SERVICE_ACCOUNT_KEY_FILE")"
if [ -f "$SERVICE_ACCOUNT_KEY_FILE" ]; then
  echo "✅ Service account key already exists: $SERVICE_ACCOUNT_KEY_FILE"
else
  echo "📥 Creating Admin SDK key…"
  if ! gcloud iam service-accounts keys create "$SERVICE_ACCOUNT_KEY_FILE" \
      --iam-account="$SA_EMAIL"; then
    echo "⚠️  Could not create a key (org policy may block it). Skipping."
  fi
fi
