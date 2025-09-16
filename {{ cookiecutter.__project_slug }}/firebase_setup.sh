#!/usr/bin/env bash
set -euo pipefail

# -------------------- DEFAULTS --------------------
PROJECT_ID="${1:-autora}"   # default if missing
DISPLAY_NAME="AutoRA"
WEBAPP_NAME="AutoRA"
REGION="us-central1"
BUILD_DIR="build"
SERVICE_ACCOUNT_KEY_FILE="../researcher_hub/firebase_credentials.json"
FIREBASE_CONFIG_FILE="firebase-config.js"

# -------------------- BASIC BASH GUARD --------------------
if [ -z "${BASH_VERSION-}" ]; then
  echo "This script must be run with bash." >&2
  exit 1
fi

# -------------------- CROSS-PLATFORM INSTALL HELPERS --------------------
have() { command -v "$1" >/dev/null 2>&1; }
as_root() { if have sudo; then sudo "$@"; else "$@"; fi; }

detect_platform() {
  local os="linux" dist=""
  case "${OSTYPE:-}" in
    darwin*) os="mac";;
    msys*|cygwin*) os="windows";;
    linux*) os="linux";;
  esac
  if [[ "$os" == "linux" ]] && [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    dist="${ID:-}"
  fi
  echo "$os:$dist"
}

install_gcloud() {
  local plat; plat="$(detect_platform)"
  case "$plat" in
    mac:*)
      if have brew; then
        brew update
        brew install --cask google-cloud-sdk || brew install google-cloud-sdk
      else
        echo "❌ Homebrew not found. Install from https://brew.sh/ then re-run." >&2; return 1
      fi
      ;;
    linux:ubuntu|linux:debian)
      as_root apt-get update
      as_root apt-get install -y apt-transport-https ca-certificates gnupg curl
      echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
        | as_root tee /etc/apt/sources.list.d/google-cloud-sdk.list >/dev/null
      curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg \
        | as_root gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
      as_root apt-get update
      as_root apt-get install -y google-cloud-cli
      ;;
    linux:fedora|linux:rhel|linux:centos)
      as_root dnf install -y dnf-plugins-core || true
      as_root dnf copr enable -y @google-cloud-sdk/google-cloud-cli || true
      as_root dnf install -y google-cloud-cli || as_root yum install -y google-cloud-cli
      ;;
    linux:arch)
      as_root pacman -Sy --noconfirm google-cloud-cli || { echo "⚠️ Try: yay -S google-cloud-cli" >&2; return 1; }
      ;;
    linux:alpine)
      echo "❌ gcloud not supported well on Alpine; use Debian/Ubuntu base." >&2; return 1
      ;;
    windows:*)
      if have choco; then
        choco install -y googlecloudsdk
      elif have scoop; then
        scoop install googlecloudsdk
      elif have winget; then
        winget install -e --id Google.CloudSDK
      else
        echo "❌ No Windows package manager (choco/scoop/winget). Install gcloud manually." >&2; return 1
      fi
      ;;
    *) echo "❌ Unsupported platform for gcloud auto-install." >&2; return 1;;
  esac
}

install_generic() {
  local pkg="$1" plat; plat="$(detect_platform)"
  case "$plat" in
    mac:*)
      if have brew; then
        case "$pkg" in
          firebase-tools) npm install -g firebase-tools;;
          *) brew install "$pkg";;
        esac
      else
        echo "❌ Homebrew not found; cannot install $pkg automatically." >&2; return 1
      fi
      ;;
    linux:ubuntu|linux:debian)
      as_root apt-get update
      case "$pkg" in
        firebase-tools) have npm || as_root apt-get install -y npm; npm install -g firebase-tools;;
        node|nodejs) as_root apt-get install -y nodejs npm;;
        *) as_root apt-get install -y "$pkg";;
      esac
      ;;
    linux:fedora|linux:rhel|linux:centos)
      case "$pkg" in
        firebase-tools) have npm || as_root dnf install -y nodejs npm || as_root yum install -y nodejs npm; npm install -g firebase-tools;;
        node|nodejs) as_root dnf install -y nodejs npm || as_root yum install -y nodejs npm;;
        *) as_root dnf install -y "$pkg" || as_root yum install -y "$pkg";;
      esac
      ;;
    linux:arch)
      case "$pkg" in
        firebase-tools) as_root pacman -Sy --noconfirm nodejs npm; npm install -g firebase-tools;;
        *) as_root pacman -Sy --noconfirm "$pkg";;
      esac
      ;;
    linux:alpine)
      case "$pkg" in
        firebase-tools) as_root apk add --no-cache nodejs npm; npm install -g firebase-tools;;
        *) as_root apk add --no-cache "$pkg";;
      esac
      ;;
    windows:*)
      if have choco; then
        case "$pkg" in
          firebase-tools) have node || choco install -y nodejs; npm install -g firebase-tools;;
          node|nodejs) choco install -y nodejs;;
          jq|git|curl) choco install -y "$pkg";;
          *) echo "⚠️ No choco recipe for $pkg; try winget/scoop." >&2; return 1;;
        esac
      elif have scoop; then
        case "$pkg" in
          firebase-tools) scoop install nodejs; npm install -g firebase-tools;;
          *) scoop install "$pkg";;
        esac
      elif have winget; then
        case "$pkg" in
          jq) winget install -e --id jqlang.jq;;
          git) winget install -e --id Git.Git;;
          curl) winget install -e --id Curl.Curl;;
          node|nodejs) winget install -e --id OpenJS.NodeJS;;
          firebase-tools) winget install -e --id OpenJS.NodeJS; npm install -g firebase-tools;;
          *) echo "⚠️ No winget recipe for $pkg." >&2; return 1;;
        esac
      else
        echo "❌ No Windows package manager found for $pkg." >&2; return 1
      fi
      ;;
    *) echo "❌ Unsupported platform for generic install." >&2; return 1;;
  esac
}

require_cmd() {
  local cmd="$1"
  if have "$cmd"; then return 0; fi
  echo "⚠️  '$cmd' not found, attempting to install..."
  case "$cmd" in
    gcloud) install_gcloud;;
    firebase|firebase-tools) install_generic "firebase-tools";;
    jq|curl|git|node|nodejs|npm) install_generic "$cmd";;
    *) echo "❌ No installer mapped for '$cmd'." >&2; return 1;;
  esac
  have "$cmd" || { echo "❌ Failed to install '$cmd'." >&2; return 1; }
  echo "✅ Installed '$cmd'."
}

# -------------------- PROJECT ID (RE-PROMPT) --------------------
echo "📌 Using project ID: $PROJECT_ID"
while [[ ! "$PROJECT_ID" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]]; do
  echo "❌ Invalid project_id: '$PROJECT_ID'"
  echo "✅ Must be 6–30 chars, lowercase letters, digits, or hyphens; start with a letter."
  read -r -p "Please enter a valid project ID: " PROJECT_ID
done

# -------------------- TOOLS --------------------
for c in gcloud firebase jq node npm; do require_cmd "$c"; done

# -------------------- FIREBASE WRAPPER --------------------
fb() {
  if [ -n "${FIREBASE_TOKEN:-}" ]; then
    firebase --non-interactive --token "$FIREBASE_TOKEN" "$@"
  elif [ -n "${ACCOUNTS_NONINTERACTIVE:-}" ]; then
    firebase --non-interactive "$@"
  else
    firebase "$@"
  fi
}

get_gcloud_active() { gcloud config get-value account --quiet 2>/dev/null || true; }

_first_email() { grep -Eo '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' | head -n1; }

get_firebase_active() {
  local json email txt
  json="$(fb login:list --json 2>/dev/null || true)"
  if [ -n "$json" ]; then
    email="$(printf '%s' "$json" | jq -r '.result[]? | select((.active==true) or (.default==true) or (.isDefault==true)) | (.email // .user // empty)')" || true
    [ -n "$email" ] && [ "$email" != "null" ] && { printf '%s\n' "$email"; return 0; }
  fi
  txt="$(fb login:list 2>/dev/null || true)"
  email="$(printf '%s\n' "$txt" | _first_email)"
  [ -n "$email" ] && printf '%s\n' "$email"
}

ensure_gcloud_account() {
  local active; active="$(get_gcloud_active)"
  echo "   gcloud active : ${active:-<none>}"
  if [ -z "$active" ]; then
    if [[ -n "${CODESPACES:-}" || -n "${CI:-}" ]]; then
      echo "Opening device login for gcloud (headless)..."
      gcloud auth login --no-launch-browser
    else
      echo "Press Enter to log in to gcloud..."; read -r _
      gcloud auth login
    fi
  fi
}

ensure_firebase_account() {
  local active; active="$(get_firebase_active)"
  echo "   firebase active: ${active:-<none>}"
  if [ -z "$active" ]; then
    if [[ -n "${CODESPACES:-}" || -n "${CI:-}" ]]; then
      echo "Opening device login for Firebase (headless)..."
      firebase login --no-localhost
    else
      echo "Press Enter to log in to Firebase..."; read -r _
      firebase login
    fi
  fi
}

ensure_gcloud_account
ensure_firebase_account
echo "✅ You are logged in to gcloud and Firebase."

# -------------------- PROJECT CREATE/SELECT --------------------
echo "📁 Checking Firebase project: $PROJECT_ID"
CREATE_PROJECT_ATTEMPTED=false
if fb projects:create "$PROJECT_ID" --display-name "$DISPLAY_NAME"; then
  echo "✅ Created Firebase project: $PROJECT_ID"
else
  CREATE_PROJECT_ATTEMPTED=true
  echo "⚠️  Project creation failed — assuming it exists and continuing..."
fi

if ! gcloud config set project "$PROJECT_ID" >/dev/null 2>&1; then
  echo "❌ You don't have access to '$PROJECT_ID'."
  if $CREATE_PROJECT_ATTEMPTED; then
    echo "🛑 Could not create or access the project."; else echo "🛑 Project missing or no access."; fi
  exit 1
fi
echo "✅ gcloud project set: $PROJECT_ID"

echo "🔐 Setting ADC quota project..."
gcloud auth application-default set-quota-project "$PROJECT_ID" >/dev/null

# -------------------- .firebaserc --------------------
echo "🧭 Creating .firebaserc"
cat > .firebaserc <<EOF
{
  "projects": {
    "default": "$PROJECT_ID"
  }
}
EOF

# -------------------- WEB APP --------------------
echo "🔍 Looking for existing Firebase Web App..."
APP_ID="$(fb apps:list --project "$PROJECT_ID" --json | jq -r '.result // [] | .[] | select(.platform=="WEB") | .appId' | head -n1)"

if [ -z "$APP_ID" ]; then
  echo "🌐 No Web App found, creating one..."
  if ! CREATE_OUTPUT="$(fb apps:create web "$WEBAPP_NAME" --project "$PROJECT_ID" --json 2>firebase_error.log)"; then
    echo "❌ firebase apps:create failed:"; cat firebase_error.log; exit 1
  fi
  echo "$CREATE_OUTPUT" > .firebase_app_create_output.json
  APP_ID="$(echo "$CREATE_OUTPUT" | jq -r '.appId')"
  if [ -z "$APP_ID" ] || [ "$APP_ID" = "null" ]; then
    echo "❌ Failed to create Web App. Output:"; cat .firebase_app_create_output.json; exit 1
  fi
else
  echo "✅ Found existing Web App: $APP_ID"
fi

echo "📦 Exporting Web App SDK config to $FIREBASE_CONFIG_FILE"
fb apps:sdkconfig web "$APP_ID" --project "$PROJECT_ID" > "$FIREBASE_CONFIG_FILE"

# -------------------- .env FROM SDK CONFIG --------------------
echo "🌱 Generating .env from $FIREBASE_CONFIG_FILE"
node <<'EOF'
const fs = require('fs');

const file = 'firebase-config.js';
const content = fs.readFileSync(file, 'utf8');

// Try pure JSON first
let cfg = null;
try {
  const trimmed = content.trim();
  if (trimmed.startsWith('{')) cfg = JSON.parse(trimmed);
} catch {}

if (!cfg) {
  // Extract first balanced {...}
  let s = content.indexOf('{');
  if (s !== -1) {
    let depth = 0, e = -1;
    for (let i = s; i < content.length; i++) {
      const ch = content[i];
      if (ch === '{') depth++;
      else if (ch === '}') { depth--; if (!depth) { e = i; break; } }
    }
    if (e !== -1) cfg = JSON.parse(content.slice(s, e + 1));
  }
}

if (!cfg) { console.error(`❌ Could not parse Firebase config from ${file}`); process.exit(1); }

const env = `
REACT_APP_apiKey="${cfg.apiKey || ''}"
REACT_APP_authDomain="${cfg.authDomain || ''}"
REACT_APP_projectId="${cfg.projectId || ''}"
REACT_APP_storageBucket="${cfg.storageBucket || ''}"
REACT_APP_messagingSenderId="${cfg.messagingSenderId || ''}"
REACT_APP_appId="${cfg.appId || ''}"
REACT_APP_devNoDb="True"
REACT_APP_useProlificId="False"
REACT_APP_completionCode="complete"
`.trim();

fs.writeFileSync('.env', env + '\n');
console.log('✅ .env written');
EOF
# pass filename
# (node heredoc runs in same dir; default uses firebase-config.js)

# -------------------- ADMIN SERVICE ACCOUNT --------------------
echo "🔐 Locating Firebase Admin SDK service account..."
SA_EMAIL="$(gcloud iam service-accounts list --project="$PROJECT_ID" \
  --filter="displayName:Firebase Admin SDK" --format="value(email)")"

if [ -z "$SA_EMAIL" ]; then
  echo "❌ Could not find Firebase Admin SDK service account."; exit 1
fi

mkdir -p "$(dirname "$SERVICE_ACCOUNT_KEY_FILE")"
if [ -f "$SERVICE_ACCOUNT_KEY_FILE" ]; then
  echo "✅ Service account key already exists: $SERVICE_ACCOUNT_KEY_FILE"
else
  echo "📥 Creating Admin SDK key..."
  gcloud iam service-accounts keys create "$SERVICE_ACCOUNT_KEY_FILE" --iam-account="$SA_EMAIL"
fi

# -------------------- FIRESTORE ENABLE/CREATE --------------------
if gcloud firestore databases describe --project="$PROJECT_ID" --format="value(name)" >/dev/null 2>&1; then
  echo "✅ Firestore already initialized"
else
  echo "🔥 Enabling Firestore..."
  gcloud services enable firestore.googleapis.com --project "$PROJECT_ID"
  gcloud firestore databases create --location="$REGION" --project "$PROJECT_ID"
fi

# -------------------- HOSTING CONFIG --------------------
echo "📁 Creating firebase.json"
cat > firebase.json <<EOF
{
  "firestore": {
    "rules": "firestore.rules",
    "indexes": "firestore.indexes.json"
  },
  "hosting": {
    "public": "$BUILD_DIR",
    "ignore": ["firebase.json", "**/.*", "**/node_modules/**"],
    "rewrites": [{ "source": "**", "destination": "/index.html" }]
  }
}
EOF

echo "📁 Creating firestore.indexes.json"
cat > firestore.indexes.json <<EOF
{ "indexes": [], "fieldOverrides": [] }
EOF

# -------------------- BUILD & DEPLOY --------------------
echo "🏗️ Building project..."
npm install
npm run build

echo "🚀 Deploying to Firebase Hosting..."
fb deploy --project "$PROJECT_ID"

URL="https://${PROJECT_ID}.web.app"
echo "✅ Deployment complete!"
echo "🌍 Live at: $URL"
echo "🔑 Admin SDK key: $SERVICE_ACCOUNT_KEY_FILE"
echo "🧪 Web SDK config: $FIREBASE_CONFIG_FILE"
