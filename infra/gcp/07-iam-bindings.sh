#!/usr/bin/env bash
# Grant least-privilege IAM to the per-env service accounts.
#   runtime SA: read its own env's secrets, use its own env's KMS keys,
#               connect to Cloud SQL, write logs.
#   deploy  SA: deploy Cloud Run, push images, act-as the runtime SA.
# Bindings are scoped to env-specific resources wherever the API allows it.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

SECRETS=(jwt-signing-key db-password firebase-admin-key nafath-app-id nafath-app-key)

for env in ${ENVS}; do
  rt="$(runtime_sa_email "${env}")"
  dp="$(deploy_sa_email "${env}")"
  ring="${PREFIX}-${env}"
  log "IAM for '${env}'…"

  # runtime: per-secret accessor (scoped, not project-wide)
  for s in "${SECRETS[@]}"; do
    gx secrets add-iam-policy-binding "${PREFIX}-${env}-${s}" \
      --member="serviceAccount:${rt}" --role="roles/secretmanager.secretAccessor" >/dev/null
  done
  ok "runtime ${env}: secretAccessor on ${#SECRETS[@]} secrets"

  # runtime: KMS encrypt/decrypt scoped to this env's key ring
  gx kms keyrings add-iam-policy-binding "${ring}" --location="${REGION}" \
    --member="serviceAccount:${rt}" --role="roles/cloudkms.cryptoKeyEncrypterDecrypter" >/dev/null
  ok "runtime ${env}: KMS encrypterDecrypter on ${ring}"

  # runtime: Cloud SQL client + log writer (project-level roles)
  gx projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${rt}" --role="roles/cloudsql.client" --condition=None >/dev/null
  gx projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${rt}" --role="roles/logging.logWriter" --condition=None >/dev/null
  ok "runtime ${env}: cloudsql.client + logging.logWriter"

  # deploy: run.developer + act-as runtime SA + push images
  gx projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${dp}" --role="roles/run.developer" --condition=None >/dev/null
  gx iam service-accounts add-iam-policy-binding "${rt}" \
    --member="serviceAccount:${dp}" --role="roles/iam.serviceAccountUser" >/dev/null
  gx artifacts repositories add-iam-policy-binding "${AR_REPO}" --location="${REGION}" \
    --member="serviceAccount:${dp}" --role="roles/artifactregistry.writer" >/dev/null
  ok "deploy ${env}: run.developer + serviceAccountUser + artifactregistry.writer"
done
ok "IAM bindings applied (deploy SAs have NO secret access by design)"
