#!/usr/bin/env bash
# Run the non-billable bootstrap in order. Idempotent — safe to re-run.
# Cloud SQL (06) is intentionally NOT included here (billable, opt-in).
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for step in 00-enable-apis 01-artifact-registry 02-service-accounts \
            03-workload-identity-federation 04-kms 05-secret-manager 07-iam-bindings; do
  echo
  echo "============================================================"
  echo "  ${step}"
  echo "============================================================"
  bash "${DIR}/${step}.sh"
done

echo
echo "Bootstrap complete. Billable Cloud SQL is separate:  CONFIRM=yes ${DIR}/06-cloud-sql.sh"
