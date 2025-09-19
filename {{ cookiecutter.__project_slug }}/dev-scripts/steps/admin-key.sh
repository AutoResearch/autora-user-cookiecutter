# --- Hard prerequisites ---
export CLOUDSDK_CORE_PROJECT="$PROJECT_ID"
export CLOUDSDK_CORE_DISABLE_PROMPTS=1  # never wait for Y/n
echo "🔧 Ensuring IAM API is enabled..."
gcloud services enable iam.googleapis.com --project="$PROJECT_ID" --quiet || {
  echo "❌ Could not enable iam.googleapis.com (need permissions)."; exit 1; }

# Create SA if missing
if [ -z "${SA_EMAIL:-}" ]; then
  echo "ℹ️  No Firebase Admin SDK service account found; creating one..."
  SUFFIX="$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c5)"
  SA_ID="firebase-adminsdk-${SUFFIX}"
  if ! gcloud iam service-accounts create "$SA_ID" \
        --display-name="Firebase Admin SDK" --quiet; then
    echo "❌ Failed to create service account."
    echo "   You likely need the role: roles/iam.serviceAccountAdmin on $PROJECT_ID."
    exit 1
  fi
  SA_EMAIL="${SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com"

  # Wait for eventual consistency (list/read visibility)
  echo "⏳ Waiting for service account to become readable…"
  for i in {1..10}; do
    got="$(gcloud iam service-accounts list \
            --format='value(email)' \
            --filter="email:${SA_EMAIL}" --quiet || true)"
    [ -n "$got" ] && { echo "✅ Created: $SA_EMAIL"; break; }
    sleep 2
  done
  [ -n "${got:-}" ] || { echo "❌ SA creation not visible after 20s."; exit 1; }

  # (Optional) grant roles; handle org-policy failures gracefully
  echo "🔧 Granting roles to ${SA_EMAIL}…"
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/firebase.admin" --quiet || echo "⚠️ grant firebase.admin failed"
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/datastore.user" --quiet || echo "⚠️ grant datastore.user failed"
fi
