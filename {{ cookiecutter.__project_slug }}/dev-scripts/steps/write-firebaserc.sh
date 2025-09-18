#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

echo "🧭 Writing .firebaserc"
cat > .firebaserc <<EOF
{
  "projects": { "default": "$PROJECT_ID" }
}
EOF
