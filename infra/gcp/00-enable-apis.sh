#!/usr/bin/env bash
# Enable the GCP APIs the Self-Serve POC needs. Idempotent (enable is a no-op
# if already enabled).
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

APIS=(
  serviceusage.googleapis.com
  cloudresourcemanager.googleapis.com
  iam.googleapis.com
  iamcredentials.googleapis.com
  sts.googleapis.com
  run.googleapis.com
  artifactregistry.googleapis.com
  sqladmin.googleapis.com
  secretmanager.googleapis.com
  cloudkms.googleapis.com
  logging.googleapis.com
  cloudbuild.googleapis.com
)

log "Enabling ${#APIS[@]} APIs on ${PROJECT_ID} (this can take a minute)…"
gx services enable "${APIS[@]}"
ok "APIs enabled"
