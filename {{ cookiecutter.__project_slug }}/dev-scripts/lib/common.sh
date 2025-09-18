# shellcheck shell=bash

# ---------- basic guards ----------
have() { command -v "$1" >/dev/null 2>&1; }
die() { echo "❌ $*" >&2; exit 1; }

# Codespaces/CI detection
is_headless() { [[ -n "${CODESPACES:-}" || -n "${CI:-}" || -n "${CODESPACE_NAME:-}" ]]; }

# ---------- cross-platform install ----------
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
      have brew || die "Homebrew not found. Install from https://brew.sh/"
      brew update
      brew install --cask google-cloud-sdk || brew install google-cloud-sdk
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
      as_root pacman -Sy --noconfirm google-cloud-cli || die "Install gcloud manually (or use yay)"
      ;;
    linux:alpine)
      die "gcloud is poorly supported on Alpine; use Debian/Ubuntu base."
      ;;
    windows:*)
      if have choco; then choco install -y googlecloudsdk
      elif have scoop; then scoop install googlecloudsdk
      elif have winget; then winget install -e --id Google.CloudSDK
      else die "No Windows package manager (choco/scoop/winget)."
      fi
      ;;
    *) die "Unsupported platform for gcloud auto-install.";;
  esac
}

install_generic() {
  local pkg="$1" plat; plat="$(detect_platform)"
  case "$plat" in
    mac:*)
      have brew || die "Homebrew not found."
      case "$pkg" in
        firebase-tools) npm install -g firebase-tools;;
        *) brew install "$pkg";;
      esac
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
          *) die "No choco recipe for $pkg; try winget/scoop."
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
          *) die "No winget recipe for $pkg."
        esac
      else die "No Windows package manager found for $pkg."
      fi
      ;;
    *) die "Unsupported platform for generic install.";;
  esac
}

require_cmd() {
  local cmd="$1"
  if have "$cmd"; then return 0; fi
  echo "⚠️  '$cmd' not found, installing..."
  case "$cmd" in
    gcloud) install_gcloud;;
    firebase|firebase-tools) install_generic "firebase-tools";;
    jq|curl|git|node|nodejs|npm) install_generic "$cmd";;
    *) die "No installer mapped for '$cmd'.";;
  esac
  have "$cmd" || die "Failed to install '$cmd'."
  echo "✅ Installed '$cmd'."
}

# ---------- firebase wrapper & login ----------
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

# returns the active firebase email or empty; never hard-fails
get_firebase_active() {
  # bail fast if firebase missing, but don't error
  command -v firebase >/dev/null 2>&1 || { echo ""; return 0; }

  # get json (some versions print nothing or non-json when logged out)
  local json
  json="$(firebase login:list --json 2>/dev/null || true)"

  # if no json, return empty safely (works under set -u)
  [[ -n "${json:-}" ]] || { echo ""; return 0; }

  # jq may be missing or filter could fail; protect it
  if command -v jq >/dev/null 2>&1; then
    # try several shapes: current_user or result[] entries marked active/default
    local email
    email="$(
      printf '%s' "$json" | jq -r '
        .current_user.email? //                      # newish shape
        (.result[]? | select(.active==true or .default==true or .isDefault==true)
          | (.email // .user // empty)) //          # older shapes
        empty
      ' 2>/dev/null || true
    )"
    [[ -n "${email:-}" && "$email" != "null" ]] && { printf '%s\n' "$email"; return 0; }
    echo ""; return 0
  else
    # crude fallback: pull first email-looking token
    if [[ "$json" =~ ([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}) ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"; return 0
    fi
    echo ""; return 0
  fi
}






validate_project_id() {
  local id="$1"
  [[ "$id" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]]
}
