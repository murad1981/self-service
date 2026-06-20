#!/usr/bin/env bash
# Create per-environment service accounts:
#   gha-deploy-<env>   : CI/CD deploy identity (assumed by GitHub Actions via WIF)
#   run-runtime-<env>  : Cloud Run service runtime identity
# No keys are created for either — deploy uses WIF, runtime uses the attached SA.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

create_sa() {
  local account_id="$1" display="$2"
  local email="${account_id}@${PROJECT_ID}.iam.gserviceaccount.com"
  if gx iam service-accounts describe "${email}" >/dev/null 2>&1; then
    skip "${email}"
  else
    gx iam service-accounts create "${account_id}" --display-name="${display}"
    ok "created ${email}"
  fi
}

for env in ${ENVS}; do
  log "Service accounts for '${env}'…"
  create_sa "gha-deploy-${env}"  "Self-Serve ${env} CI/CD deploy (WIF)"
  create_sa "run-runtime-${env}" "Self-Serve ${env} Cloud Run runtime"
done
ok "service accounts ready"
