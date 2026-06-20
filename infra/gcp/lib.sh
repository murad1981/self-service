#!/usr/bin/env bash
# Shared helpers for the Self-Serve GCP bootstrap scripts.
# Sourced by every NN-*.sh script. Idempotent-by-design: every "create" first
# checks existence, so re-running any script is safe.
set -euo pipefail

# --- load config ------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/config.env" ]]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/config.env"
else
  echo "ERROR: ${SCRIPT_DIR}/config.env not found. Run: cp config.env.example config.env && edit it." >&2
  exit 1
fi

: "${PROJECT_ID:?set PROJECT_ID in config.env}"
: "${REGION:?set REGION in config.env}"
: "${GITHUB_REPO:?set GITHUB_REPO in config.env}"
: "${ENVS:?set ENVS in config.env}"
: "${PREFIX:?set PREFIX in config.env}"

if [[ "${PROJECT_ID}" == "REPLACE_WITH_PROJECT_ID" ]]; then
  echo "ERROR: edit config.env and set a real PROJECT_ID." >&2
  exit 1
fi

# --- logging ----------------------------------------------------------------
log()  { printf '\033[1;34m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
ok()   { printf '\033[1;32m  ✓\033[0m %s\n' "$*"; }
skip() { printf '\033[1;33m  =\033[0m %s (exists)\n' "$*"; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# Resolve project number once (used for WIF principalSet members).
project_number() {
  gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)'
}

# Service-account email helpers.
deploy_sa_email()  { echo "gha-deploy-${1}@${PROJECT_ID}.iam.gserviceaccount.com"; }
runtime_sa_email() { echo "run-runtime-${1}@${PROJECT_ID}.iam.gserviceaccount.com"; }

# Guard for billable / destructive scripts.
require_confirm() {
  if [[ "${CONFIRM:-no}" != "yes" ]]; then
    die "This script creates billable or destructive resources. Re-run with: CONFIRM=yes $0"
  fi
}

gx() { gcloud --project="${PROJECT_ID}" "$@"; }
