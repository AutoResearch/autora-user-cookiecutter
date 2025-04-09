#!/bin/bash

set -e

# --- DEFAULTS & ARGUMENTS ---
PROJECT_ID="${1:-autora}"  # default if $1 is empty
DISPLAY_NAME="AutoRA"
WEBAPP_NAME="AutoRA"
REGION="us-central1"
BUILD_DIR="build"
SERVICE_ACCOUNT_KEY_FILE="../researcher_hub/firebase_credentials.json"
FIREBASE_CONFIG_FILE="firebase-config.js"

echo "📌 Using project ID: $PROJECT_ID"

# --- VALIDATE PROJECT ID ---
if [[ ! "$PROJECT_ID" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]]; then
  echo "❌ Invalid project_id: '$PROJECT_ID'"
  echo "✅ Must be 6–30 characters, lowercase letters, digits, or hyphens. No uppercase."
  exit 1
fi

# --- CREATE PROJECT IF NEEDED ---
echo "📁 Checking if Firebase project exists or can be created: $PROJECT_ID"
CREATE_PROJECT_ATTEMPTED=false

if firebase projects:create "$PROJECT_ID" --display-name "$DISPLAY_NAME"; then
  echo "✅ Created Firebase project: $PROJECT_ID"
else
  CREATE_PROJECT_ATTEMPTED=true
  echo "⚠️  Project creation failed — assuming it already exists and continuing..."
fi

# Confirm access by trying to set the gcloud project (if this fails, you're not allowed to use it)
if ! gcloud config set project "$PROJECT_ID" &>/dev/null; then
  echo "❌ You don't have access to project '$PROJECT_ID'."
  if $CREATE_PROJECT_ATTEMPTED; then
    echo "🛑 Could not create or access the project. Exiting."
  else
    echo "🛑 Project does not exist or you do not have access. Exiting."
  fi
  exit 1
fi

echo "✅ Firebase project is ready to use: $PROJECT_ID"

# --- SET GCLOUD CONTEXT ---
echo "🔁 Setting gcloud project..."
gcloud config set project "$PROJECT_ID"

echo "🔐 Setting quota project for ADC..."
gcloud auth application-default set-quota-project "$PROJECT_ID"

# --- CREATE .firebaserc ---
echo "🧭 Creating .firebaserc"
cat > .firebaserc <<EOF
{
  "projects": {
    "default": "$PROJECT_ID"
  }
}
EOF

# --- CREATE OR REUSE WEB APP ---
echo "🔍 Looking for existing Firebase Web App..."
APP_ID=$(firebase apps:list --project "$PROJECT_ID" --json | jq -r '.result // [] | .[] | select(.platform=="WEB") | .appId' | head -n 1)

if [ -z "$APP_ID" ]; then
  echo "🌐 No Web App found, creating one..."
  CREATE_OUTPUT=$(firebase apps:create web "$WEBAPP_NAME" --project "$PROJECT_ID" --json 2>&1)
  echo "$CREATE_OUTPUT" > .firebase_app_create_output.json

  APP_ID=$(echo "$CREATE_OUTPUT" | jq -r '.appId')

  if [ -z "$APP_ID" ] || [ "$APP_ID" == "null" ]; then
    echo "❌ Failed to create Web App. Output was:"
    cat .firebase_app_create_output.json
    exit 1
  fi
else
  echo "✅ Found existing Web App with ID: $APP_ID"
fi

echo "📦 Exporting Web App SDK config..."
firebase apps:sdkconfig web "$APP_ID" --project "$PROJECT_ID" > "$FIREBASE_CONFIG_FILE"

echo "📦 Exporting Web App SDK config to $FIREBASE_CONFIG_FILE"
firebase apps:sdkconfig web "$APP_ID" --project "$PROJECT_ID" > "$FIREBASE_CONFIG_FILE"

echo "🌱 Generating .env.local from $FIREBASE_CONFIG_FILE"
node <<EOF
const fs = require('fs');

// Read the Firebase config JS file
const content = fs.readFileSync('${FIREBASE_CONFIG_FILE}', 'utf8');

// Extract JSON from firebase.initializeApp({...});
const match = content.match(/firebase\.initializeApp\((\{[\s\S]*?\})\);/);
if (!match || !match[1]) {
  console.error('❌ Failed to extract Firebase config from ${FIREBASE_CONFIG_FILE}');
  process.exit(1);
}

const config = JSON.parse(match[1]);

const env = \`
REACT_APP_apiKey="\${config.apiKey}"
REACT_APP_authDomain="\${config.authDomain}"
REACT_APP_projectId="\${config.projectId}"
REACT_APP_storageBucket="\${config.storageBucket}"
REACT_APP_messagingSenderId="\${config.messagingSenderId}"
REACT_APP_appId="\${config.appId}"
REACT_APP_devNoDb="True"
REACT_APP_useProlificId="False"
REACT_APP_completionCode="complete"
\`.trim();

fs.writeFileSync('.env', env + '\\n');
console.log('✅ .env.local written');
EOF


# --- FETCH OR REUSE FIREBASE ADMIN SERVICE ACCOUNT ---
echo "🔐 Locating Firebase Admin SDK service account..."
SA_EMAIL=$(gcloud iam service-accounts list \
  --project="$PROJECT_ID" \
  --filter="displayName:Firebase Admin SDK" \
  --format="value(email)")

if [ -z "$SA_EMAIL" ]; then
  echo "❌ Could not find Firebase Admin SDK service account."
  exit 1
fi

if [ -f "$SERVICE_ACCOUNT_KEY_FILE" ]; then
  echo "✅ Service account key file already exists: $SERVICE_ACCOUNT_KEY_FILE"
else
  echo "📥 Creating Admin SDK key..."
  gcloud iam service-accounts keys create "$SERVICE_ACCOUNT_KEY_FILE" \
    --iam-account="$SA_EMAIL"
fi

# --- ENABLE FIRESTORE + CREATE DB IF NEEDED ---
if gcloud firestore databases describe --project="$PROJECT_ID" --format="value(name)" &> /dev/null; then
  echo "✅ Firestore already initialized"
else
  echo "🔥 Enabling Firestore..."
  gcloud services enable firestore.googleapis.com
  gcloud firestore databases create --location="$REGION"
fi

# --- SETUP HOSTING ---
echo "📁 Creating firebase.json"
cat > firebase.json <<EOF
{
  "firestore": {
    "rules": "firestore.rules",
    "indexes": "firestore.indexes.json"
  },
  "hosting": {
    "public": "build",
    "ignore": [
      "firebase.json",
      "**/.*",
      "**/node_modules/**"
    ],
    "rewrites": [
      {
        "source": "**",
        "destination": "/index.html"
      }
    ]
  }
}
EOF

echo "📁 Creating firestore.indexes.json"
cat > firestore.indexes.json <<EOF
{
  "indexes": [],
  "fieldOverrides": []
}
EOF

# --- BUILD AND DEPLOY ---
echo "🏗️ Building project..."
npm install
npm run build

echo "🚀 Deploying to Firebase Hosting..."
firebase deploy

URL="https://${PROJECT_ID}.web.app"
echo "✅ Deployment complete!"
echo "🌍 Live at: $URL"
echo "🔑 Admin SDK key: $SERVICE_ACCOUNT_KEY_FILE"
echo "🧪 Web SDK config: $FIREBASE_CONFIG_FILE"
