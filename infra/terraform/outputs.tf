output "wif_provider_resource" {
  description = "Use as workload_identity_provider in the GitHub Actions deploy workflow."
  value       = "projects/${data.google_project.this.number}/locations/global/workloadIdentityPools/${var.wif_pool}/providers/${var.wif_provider}"
}

output "deploy_service_accounts" {
  description = "Per-env CI/CD deploy SAs (use as service_account in the workflow)."
  value       = local.deploy_sa
}

output "runtime_service_accounts" {
  description = "Per-env Cloud Run runtime SAs."
  value       = local.runtime_sa
}

output "artifact_registry_image_prefix" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${var.ar_repo}"
}

output "cloud_sql_connection_names" {
  description = "Cloud SQL instance connection names (empty unless create_cloud_sql = true)."
  value = var.create_cloud_sql ? {
    nonprod = google_sql_database_instance.nonprod[0].connection_name
    prod    = google_sql_database_instance.prod[0].connection_name
  } : {}
}
