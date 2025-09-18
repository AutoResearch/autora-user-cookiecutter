#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/dev-scripts/config.env"
source "$SCRIPT_DIR/dev-scripts//lib/common.sh"

PROJECT_ID="${1:-${PROJECT_ID:-autora}}"

# prompt until valid
echo "📌 Using project ID: $PROJECT_ID"
until validate_project_id "$PROJECT_ID"; do
  echo "❌ Invalid project_id: '$PROJECT_ID'"
  echo "Must be 6–30 chars, lowercase letters, digits, or hyphens; start with a letter."
  read -r -p "Enter a valid project ID: " PROJECT_ID
done

export PROJECT_ID DISPLAY_NAME WEBAPP_NAME REGION BUILD_DIR SERVICE_ACCOUNT_KEY_FILE FIREBASE_CONFIG_FILE

# Execute steps in order

bash "$SCRIPT_DIR/dev-scripts/steps/bootstrap-tools.sh"
bash "$SCRIPT_DIR/dev-scripts/steps/auth-login-firebase.sh"
bash "$SCRIPT_DIR/dev-scripts/steps/project-ensure.sh"
bash "$SCRIPT_DIR/dev-scripts/steps/auth-login-gcloud.sh"
bash "$SCRIPT_DIR/dev-scripts/steps/write-firebaserc.sh"
bash "$SCRIPT_DIR/dev-scripts/steps/webapp-ensure.sh"
bash "$SCRIPT_DIR/dev-scripts/steps/export-sdk-config.sh"
bash "$SCRIPT_DIR/dev-scripts/steps/write-env-from-sdk.sh"
bash "$SCRIPT_DIR/dev-scripts/steps/admin-key.sh"
bash "$SCRIPT_DIR/dev-scripts/steps/firestore-ensure.sh"
bash "$SCRIPT_DIR/dev-scripts/steps/hosting-config.sh"
bash "$SCRIPT_DIR/dev-scripts/steps/build-and-deploy.sh"

echo "🎉 All steps completed."
