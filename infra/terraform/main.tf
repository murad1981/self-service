locals {
  apis = [
    "serviceusage.googleapis.com", "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com", "iamcredentials.googleapis.com", "sts.googleapis.com",
    "run.googleapis.com", "artifactregistry.googleapis.com", "sqladmin.googleapis.com",
    "secretmanager.googleapis.com", "cloudkms.googleapis.com", "logging.googleapis.com",
    "cloudbuild.googleapis.com",
  ]

  # Flatten env × secret and env × key for for_each.
  env_secrets = { for pair in setproduct(var.envs, var.secret_names) :
    "${pair[0]}-${pair[1]}" => { env = pair[0], secret = pair[1] } }
  env_keys = { for pair in setproduct(var.envs, var.kms_keys) :
    "${pair[0]}-${pair[1]}" => { env = pair[0], key = pair[1] } }

  deploy_sa  = { for e in var.envs : e => "gha-deploy-${e}@${var.project_id}.iam.gserviceaccount.com" }
  runtime_sa = { for e in var.envs : e => "run-runtime-${e}@${var.project_id}.iam.gserviceaccount.com" }

  wif_principal_repo = "principalSet://iam.googleapis.com/projects/${data.google_project.this.number}/locations/global/workloadIdentityPools/${var.wif_pool}/attribute.repository/${var.github_repo}"
}

# --- APIs -------------------------------------------------------------------
resource "google_project_service" "apis" {
  for_each           = toset(local.apis)
  service            = each.value
  disable_on_destroy = false
}

# --- Artifact Registry ------------------------------------------------------
resource "google_artifact_registry_repository" "docker" {
  location      = var.region
  repository_id = var.ar_repo
  format        = "DOCKER"
  description   = "Self-Serve backend container images"
  depends_on    = [google_project_service.apis]
}

# --- Service accounts (no keys) --------------------------------------------
resource "google_service_account" "deploy" {
  for_each     = toset(var.envs)
  account_id   = "gha-deploy-${each.value}"
  display_name = "Self-Serve ${each.value} CI/CD deploy (WIF)"
  depends_on   = [google_project_service.apis]
}

resource "google_service_account" "runtime" {
  for_each     = toset(var.envs)
  account_id   = "run-runtime-${each.value}"
  display_name = "Self-Serve ${each.value} Cloud Run runtime"
  depends_on   = [google_project_service.apis]
}

# --- Workload Identity Federation (GitHub OIDC) -----------------------------
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = var.wif_pool
  display_name              = "GitHub Actions pool"
  depends_on                = [google_project_service.apis]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = var.wif_provider
  display_name                       = "GitHub OIDC"
  attribute_mapping = {
    "google.subject"         = "assertion.sub"
    "attribute.repository"   = "assertion.repository"
    "attribute.ref"          = "assertion.ref"
    "attribute.environment"  = "assertion.environment"
  }
  # Pin to the exact repo so no other repo/fork can mint usable tokens.
  attribute_condition = "assertion.repository=='${var.github_repo}'"
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Let repo workflows impersonate each deploy SA.
# PRODUCTION HARDENING: scope the production member to attribute.environment/production.
resource "google_service_account_iam_member" "deploy_wif" {
  for_each           = google_service_account.deploy
  service_account_id = each.value.name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.wif_principal_repo
}

# --- KMS --------------------------------------------------------------------
resource "google_kms_key_ring" "env" {
  for_each = toset(var.envs)
  name     = "${var.prefix}-${each.value}"
  location = var.region
  depends_on = [google_project_service.apis]
}

resource "google_kms_crypto_key" "keys" {
  for_each        = local.env_keys
  name            = each.value.key
  key_ring        = google_kms_key_ring.env[each.value.env].id
  rotation_period = "7776000s" # 90 days
  purpose         = "ENCRYPT_DECRYPT"
}

# --- Secret Manager (empty placeholders, regional) --------------------------
resource "google_secret_manager_secret" "secrets" {
  for_each  = local.env_secrets
  secret_id = "${var.prefix}-${each.value.env}-${each.value.secret}"
  replication {
    user_managed {
      replicas { location = var.region }
    }
  }
  depends_on = [google_project_service.apis]
}

# --- IAM: runtime SA least privilege ---------------------------------------
resource "google_secret_manager_secret_iam_member" "runtime_secret" {
  for_each  = local.env_secrets
  secret_id = google_secret_manager_secret.secrets[each.key].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${local.runtime_sa[each.value.env]}"
}

resource "google_kms_key_ring_iam_member" "runtime_kms" {
  for_each    = google_kms_key_ring.env
  key_ring_id = each.value.id
  role        = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member      = "serviceAccount:${local.runtime_sa[each.key]}"
}

resource "google_project_iam_member" "runtime_sql" {
  for_each = toset(var.envs)
  project  = var.project_id
  role     = "roles/cloudsql.client"
  member   = "serviceAccount:${local.runtime_sa[each.value]}"
}

resource "google_project_iam_member" "runtime_logs" {
  for_each = toset(var.envs)
  project  = var.project_id
  role     = "roles/logging.logWriter"
  member   = "serviceAccount:${local.runtime_sa[each.value]}"
}

# --- IAM: deploy SA ---------------------------------------------------------
resource "google_project_iam_member" "deploy_run" {
  for_each = toset(var.envs)
  project  = var.project_id
  role     = "roles/run.developer"
  member   = "serviceAccount:${local.deploy_sa[each.value]}"
}

resource "google_service_account_iam_member" "deploy_actas_runtime" {
  for_each           = google_service_account.runtime
  service_account_id = each.value.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${local.deploy_sa[each.key]}"
}

resource "google_artifact_registry_repository_iam_member" "deploy_push" {
  for_each   = toset(var.envs)
  location   = var.region
  repository = google_artifact_registry_repository.docker.repository_id
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${local.deploy_sa[each.value]}"
}
