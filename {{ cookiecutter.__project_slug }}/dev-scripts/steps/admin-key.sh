#!/usr/bin/env bash
set -euo pipefail

# Assumes: PROJECT_ID and SCRIPT_DIR are already defined earlier
: "${PROJECT_ID:?PROJECT_ID must be set}"
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"


export CLOUDSDK_CORE_PROJECT="$PROJECT_ID"
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

say() { printf "%s\n" "$*" >&2; }
die() { say "❌ $*"; exit 1; }

# ---- Enable required API once ----
say "🔧 Ensuring IAM API is enabled…"
gcloud services enable iam.googleapis.com --project="$PROJECT_ID" --quiet || \
  die "Could not enable iam.googleapis.com (need permissions)."

# ---- Find existing Admin SDK SA by email pattern (displayName is unreliable) ----
say "🔎 Locating Firebase Admin SDK service account…"
SA_EMAIL="${SA_EMAIL:-}"
if [ -z "${SA_EMAIL:-}" ]; then
  SA_EMAIL="$(gcloud iam service-accounts list --format='value(email)' \
    | awk -v p="$PROJECT_ID" '$0 ~ ("^firebase-adminsdk-.*@" p "\\.iam\\.gserviceaccount\\.com$") {print; exit}' \
    || true)"
fi

# ---- Create SA if missing ----
if [ -z "${SA_EMAIL:-}" ]; then
  say "ℹ️  No Admin SDK SA found; creating…"
  SUFFIX="$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c5)"
  SA_ID="firebase-adminsdk-${SUFFIX}"
  gcloud iam service-accounts create "$SA_ID" \
    --display-name="Firebase Admin SDK" --quiet || \
    die "Failed to create SA; you likely need roles/iam.serviceAccountAdmin."
  SA_EMAIL="${SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com"

  # Wait for eventual consistency so list/keys work
  say "⏳ Waiting for SA to become readable…"
  for _ in {1..10}; do
    got="$(gcloud iam service-accounts list --format='value(email)' \
            --filter="email:${SA_EMAIL}" --quiet || true)"
    [ -n "$got" ] && { say "✅ Created: $SA_EMAIL"; break; }
    sleep 2
  done
fi

[ -n "${SA_EMAIL:-}" ] || die "Could not find or create a Firebase Admin SDK service account."
say "✅ Using service account: ${SA_EMAIL}"

# ---- Output path: parent_of_script_dir/research_hub/firebase_credentials.json ----
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
GRANDPARENT_DIR="$(dirname "$PARENT_DIR")"
OUT_FILE="${GRANDPARENT_DIR}/researcher_hub/firebase_credentials.json"
mkdir -p "$(dirname "$OUT_FILE")"

# Optional: ensure we overwrite the file cleanly
rm -f "$OUT_FILE"

say "🔐 Creating Admin SDK key JSON at: $OUT_FILE"
if ! gcloud iam service-accounts keys create "$OUT_FILE" \
      --iam-account="$SA_EMAIL" --project="$PROJECT_ID" --quiet; then
  die "Key creation failed (often blocked by org policy). Consider SA impersonation or Workload Identity Federation."
fi
chmod 600 "$OUT_FILE" || true
say "✅ Wrote Admin SDK key to: $OUT_FILE"
