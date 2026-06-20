#!/usr/bin/env bash
# Create per-environment Secret Manager secrets as EMPTY placeholders (no values
# committed or printed here). Regional replication for residency. Add versions
# out-of-band, e.g.:
#   printf '%s' "$VALUE" | gcloud secrets versions add selfserve-qa-jwt-signing-key --data-file=- --project=$PROJECT_ID
#
# Nafath secrets are created but stay empty for the POC (mock provider, ADR-009).
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

SECRETS=(
  jwt-signing-key          # backend JWT signing key
  db-password              # Cloud SQL app user password
  firebase-admin-key       # Firebase Admin SDK credential (FCM)
  nafath-app-id            # EMPTY for POC (mock) — real value when integration lands
  nafath-app-key           # EMPTY for POC (mock)
)

for env in ${ENVS}; do
  for s in "${SECRETS[@]}"; do
    name="${PREFIX}-${env}-${s}"
    if gx secrets describe "${name}" >/dev/null 2>&1; then
      skip "${name}"
    else
      gx secrets create "${name}" \
        --replication-policy=user-managed --locations="${REGION}"
      ok "created ${name} (empty)"
    fi
  done
done
log "Secrets created empty. Add values with 'gcloud secrets versions add' (never commit them)."
