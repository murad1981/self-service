#!/usr/bin/env bash
# Create a KMS key ring + keys per environment for envelope encryption of
# Tier-4 data: national ID / NIC (pii), face embeddings (biometric), check-in
# location (location). Keys are regional (residency) and software-protected
# (sufficient + cheaper for the POC; switch to HSM for production if required).
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

KEYS=(pii biometric location)

for env in ${ENVS}; do
  ring="${PREFIX}-${env}"
  log "KMS key ring '${ring}' (${REGION})…"
  if gx kms keyrings describe "${ring}" --location="${REGION}" >/dev/null 2>&1; then
    skip "${ring}"
  else
    gx kms keyrings create "${ring}" --location="${REGION}"
    ok "created ring ${ring}"
  fi
  for key in "${KEYS[@]}"; do
    if gx kms keys describe "${key}" --keyring="${ring}" --location="${REGION}" >/dev/null 2>&1; then
      skip "${ring}/${key}"
    else
      gx kms keys create "${key}" \
        --keyring="${ring}" --location="${REGION}" \
        --purpose=encryption --rotation-period=90d --next-rotation-time="$(date -u -d '+90 days' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)"
      ok "created key ${ring}/${key}"
    fi
  done
done
ok "KMS ready"
