#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

ensure_firebase_account() {
  local active; active="$(get_firebase_active)"
  if [ -z "$active" ]; then
    if is_headless; then
      echo "Opening device login for Firebase (headless)..."
      firebase login --no-localhost
    else
      read -r -p "Press Enter to log in to Firebase..." _
      firebase login
    fi
  fi
}

echo "🔐 Checking Firebase login..."
ensure_firebase_account
echo "Logged in to Firebase as: $(get_firebase_active)"
echo "✅ Logged in to gcloud and Firebase."
