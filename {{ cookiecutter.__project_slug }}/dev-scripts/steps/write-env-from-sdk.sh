#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
source "$SCRIPT_DIR/config.env"

echo "🌱 Generating .env from $FIREBASE_CONFIG_FILE"
node <<'EOF'
const fs = require('fs');
const file = process.env.FIREBASE_CONFIG_FILE || 'firebase-config.js';
const text = fs.readFileSync(file, 'utf8');
let cfg = null;
// Try pure JSON
try { const t = text.trim(); if (t.startsWith('{')) cfg = JSON.parse(t); } catch {}
// Fallback: first balanced {...}
if (!cfg) {
  let s = text.indexOf('{'); if (s !== -1) {
    let depth=0, e=-1;
    for (let i=s;i<text.length;i++){
      const ch=text[i];
      if(ch==='{') depth++;
      else if(ch==='}') { depth--; if(!depth){ e=i; break; } }
    }
    if(e!==-1) cfg = JSON.parse(text.slice(s, e+1));
  }
}
if (!cfg) { console.error(`❌ Could not parse Firebase config from ${file}`); process.exit(1); }
const env = `
REACT_APP_apiKey="${cfg.apiKey||''}"
REACT_APP_authDomain="${cfg.authDomain||''}"
REACT_APP_projectId="${cfg.projectId||''}"
REACT_APP_storageBucket="${cfg.storageBucket||''}"
REACT_APP_messagingSenderId="${cfg.messagingSenderId||''}"
REACT_APP_appId="${cfg.appId||''}"
REACT_APP_devNoDb="True"
REACT_APP_useProlificId="False"
REACT_APP_completionCode="complete"
`.trim();
fs.writeFileSync('.env', env + '\n');
console.log('✅ .env written');
EOF
