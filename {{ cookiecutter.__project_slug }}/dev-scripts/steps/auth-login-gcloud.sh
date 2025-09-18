#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

ensure_gcloud_account() {
  local active; active="$(get_gcloud_active)"
  if [ -z "$active" ]; then
    if is_headless; then
      echo "Opening device login for gcloud (headless)..."
      gcloud gcloud auth application-default login --no-launch-browser
    else
      read -r -p "Press Enter to log in to gcloud..." _
      gcloud gcloud auth application-default login
    fi
  fi
}

echo "🔐 Checking gcloud login..."
ensure_gcloud_account
echo "Logged in to gcloud as: $(get_gcloud_active)"

if ! gcloud config set project "$PROJECT_ID" >/dev/null 2>&1; then
  echo "❌ You don't have access to '$PROJECT_ID'."
  if $CREATE_PROJECT_ATTEMPTED; then
    echo "🛑 Could not create or access the project."
  else
    echo "🛑 Project missing or no access."
  fi
  exit 1
fi
echo "✅ gcloud project set: $PROJECT_ID"