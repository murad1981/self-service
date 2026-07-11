#!/usr/bin/env bash
# Delete the POC resources created by the bootstrap scripts to stop cost.
# DESTRUCTIVE + OPT-IN:   CONFIRM=yes ./teardown.sh
# KMS key rings/keys cannot be deleted (only key VERSIONS destroyed); they are
# left in place — key material can be destroyed per key version if required.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
require_confirm

log "Deleting Cloud SQL instances (if any)…"
for inst in "${PREFIX}-sql-nonprod" "${PREFIX}-sql-prod"; do
  gx sql instances delete "${inst}" --quiet >/dev/null 2>&1 && ok "deleted ${inst}" || skip "no ${inst}"
done

log "Deleting secrets…"
for env in ${ENVS}; do
  for s in jwt-signing-key db-password firebase-admin-key nafath-app-id nafath-app-key; do
    gx secrets delete "${PREFIX}-${env}-${s}" --quiet >/dev/null 2>&1 && ok "deleted ${PREFIX}-${env}-${s}" || true
  done
done

log "Deleting service accounts…"
for env in ${ENVS}; do
  for sa in "$(deploy_sa_email "${env}")" "$(runtime_sa_email "${env}")"; do
    gx iam service-accounts delete "${sa}" --quiet >/dev/null 2>&1 && ok "deleted ${sa}" || true
  done
done

log "Deleting Artifact Registry repo…"
gx artifacts repositories delete "${AR_REPO}" --location="${REGION}" --quiet >/dev/null 2>&1 && ok "deleted ${AR_REPO}" || true

log "Note: WIF pool/provider and KMS rings are retained (soft-delete / non-deletable). Disable the WIF provider manually if desired."
ok "teardown complete"
