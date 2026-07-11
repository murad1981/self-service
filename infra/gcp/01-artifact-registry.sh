#!/usr/bin/env bash
# Create the Docker Artifact Registry repository for backend images.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

log "Artifact Registry repo '${AR_REPO}' in ${REGION}…"
if gx artifacts repositories describe "${AR_REPO}" --location="${REGION}" >/dev/null 2>&1; then
  skip "${AR_REPO}"
else
  gx artifacts repositories create "${AR_REPO}" \
    --repository-format=docker \
    --location="${REGION}" \
    --description="Self-Serve backend container images"
  ok "created ${AR_REPO}"
fi

log "Image path: ${REGION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPO}/<image>:<tag>"
