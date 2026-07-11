#!/usr/bin/env bash
# Configure GitHub -> GCP Workload Identity Federation (keyless CI/CD auth).
# Creates one pool + one GitHub OIDC provider, then lets each gha-deploy-<env>
# SA be impersonated ONLY by workflows from ${GITHUB_REPO}.
#
# Security: the provider's attribute-condition pins the exact repository, so no
# other repo (or fork) can mint tokens that assume these identities.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

PN="$(project_number)"
POOL="${WIF_POOL}"
PROVIDER="${WIF_PROVIDER}"

log "Workload Identity Pool '${POOL}'…"
if gx iam workload-identity-pools describe "${POOL}" --location=global >/dev/null 2>&1; then
  skip "${POOL}"
else
  gx iam workload-identity-pools create "${POOL}" \
    --location=global --display-name="GitHub Actions pool"
  ok "created pool ${POOL}"
fi

log "OIDC provider '${PROVIDER}' (issuer: GitHub Actions)…"
if gx iam workload-identity-pools providers describe "${PROVIDER}" \
     --location=global --workload-identity-pool="${POOL}" >/dev/null 2>&1; then
  skip "${PROVIDER}"
else
  gx iam workload-identity-pools providers create-oidc "${PROVIDER}" \
    --location=global \
    --workload-identity-pool="${POOL}" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref,attribute.environment=assertion.environment" \
    --attribute-condition="assertion.repository=='${GITHUB_REPO}'"
  ok "created provider ${PROVIDER}"
fi

PRINCIPAL_REPO="principalSet://iam.googleapis.com/projects/${PN}/locations/global/workloadIdentityPools/${POOL}/attribute.repository/${GITHUB_REPO}"

for env in ${ENVS}; do
  sa="$(deploy_sa_email "${env}")"
  log "Allow ${GITHUB_REPO} to impersonate ${sa}…"
  # POC binding: any workflow run in the repo may assume the deploy SA.
  # PRODUCTION HARDENING (recommended): for the 'production' deploy SA, replace
  # this with an environment- or tag-scoped member, e.g.
  #   principalSet://.../attribute.environment/production
  # and protect that GitHub Environment with required reviewers + tag rules.
  gx iam service-accounts add-iam-policy-binding "${sa}" \
    --role="roles/iam.workloadIdentityUser" \
    --member="${PRINCIPAL_REPO}" >/dev/null
  ok "bound ${env} deploy SA"
done

cat <<EOF

WIF provider resource (use as 'workload_identity_provider' in the deploy workflow):
  projects/${PN}/locations/global/workloadIdentityPools/${POOL}/providers/${PROVIDER}

Per-env deploy service accounts (use as 'service_account'):
EOF
for env in ${ENVS}; do echo "  ${env}: $(deploy_sa_email "${env}")"; done
