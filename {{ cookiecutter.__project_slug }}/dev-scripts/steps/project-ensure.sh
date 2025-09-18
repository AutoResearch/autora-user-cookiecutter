#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
source "$SCRIPT_DIR/config.env"
source "$SCRIPT_DIR/lib/common.sh"

echo "📁 Checking/creating Firebase project: $PROJECT_ID"
CREATE_PROJECT_ATTEMPTED=false
if fb projects:create "$PROJECT_ID" --display-name "$DISPLAY_NAME"; then
  echo "✅ Created Firebase project: $PROJECT_ID"
else
  CREATE_PROJECT_ATTEMPTED=true
  echo "⚠️  Project creation failed — assuming it exists and continuing..."
fi



echo "🔐 Setting ADC quota project..."
gcloud auth application-default set-quota-project "$PROJECT_ID" >/dev/null || true
