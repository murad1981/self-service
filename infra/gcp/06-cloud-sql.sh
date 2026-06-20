#!/usr/bin/env bash
# BILLABLE + OPT-IN. Cloud SQL has no scale-to-zero, so it is the POC cost floor.
# Creates the smallest viable PostgreSQL setup per the plan (§12.3):
#   - one SHARED non-prod instance with separate DBs for qa + staging
#   - one ISOLATED production instance
# Run only when you are ready to incur cost:   CONFIRM=yes ./06-cloud-sql.sh
#
# NOTE: in me-central2, Cloud SQL requires the CNTXT/invoiced-billing onboarding
# (R-01). On me-central1 it works with standard billing.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
require_confirm

TIER="${SQL_TIER:-db-f1-micro}"   # smallest shared-core; adjust if the API rejects it for your edition
DBVER="POSTGRES_16"

create_instance() {
  local name="$1"
  if gx sql instances describe "${name}" >/dev/null 2>&1; then
    skip "instance ${name}"; return
  fi
  log "Creating Cloud SQL instance ${name} (${TIER}, zonal, HDD)…"
  gx sql instances create "${name}" \
    --database-version="${DBVER}" \
    --tier="${TIER}" \
    --region="${REGION}" \
    --storage-type=HDD --storage-size=10 \
    --availability-type=zonal \
    --no-backup
  ok "created ${name}"
}

create_db() {
  local instance="$1" db="$2"
  if gx sql databases describe "${db}" --instance="${instance}" >/dev/null 2>&1; then
    skip "db ${instance}/${db}"
  else
    gx sql databases create "${db}" --instance="${instance}"
    ok "created db ${instance}/${db}"
  fi
}

NONPROD="${PREFIX}-sql-nonprod"
PROD="${PREFIX}-sql-prod"

create_instance "${NONPROD}"
create_db "${NONPROD}" "${PREFIX}_qa"
create_db "${NONPROD}" "${PREFIX}_staging"

create_instance "${PROD}"
create_db "${PROD}" "${PREFIX}_production"

cat <<EOF

Done. Next steps (do NOT commit secrets):
  1. Create an app DB user per env and store its password in Secret Manager:
       gcloud sql users create selfserve_app --instance=${NONPROD} --password=... --project=${PROJECT_ID}
       printf '%s' "<password>" | gcloud secrets versions add ${PREFIX}-qa-db-password --data-file=- --project=${PROJECT_ID}
  2. Cloud Run connects via the Cloud SQL connector using the instance connection name:
       gcloud sql instances describe ${NONPROD} --format='value(connectionName)' --project=${PROJECT_ID}
  3. To stop cost when idle:  gcloud sql instances patch ${NONPROD} --activation-policy=NEVER --project=${PROJECT_ID}
EOF
