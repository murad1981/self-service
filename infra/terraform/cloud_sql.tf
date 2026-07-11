# BILLABLE — off by default. Set create_cloud_sql = true to provision.
# Cloud SQL has no scale-to-zero, so it is the POC cost floor. Smallest viable
# setup per §12.3: one SHARED non-prod instance (qa + staging DBs) + one
# ISOLATED production instance. Create app users / passwords out-of-band and
# store passwords in Secret Manager — never in .tfvars or state.

locals {
  create_sql      = var.create_cloud_sql ? 1 : 0
  nonprod_db_envs = [for e in var.envs : e if e != "production"]
}

resource "google_sql_database_instance" "nonprod" {
  count            = local.create_sql
  name             = "${var.prefix}-sql-nonprod"
  database_version = "POSTGRES_16"
  region           = var.region
  deletion_protection = false
  settings {
    tier              = var.sql_tier
    availability_type = "ZONAL"
    disk_type         = "PD_HDD"
    disk_size         = 10
    backup_configuration {
      enabled = false
    }
  }
  depends_on = [google_project_service.apis]
}

resource "google_sql_database" "nonprod_dbs" {
  for_each = toset(var.create_cloud_sql ? local.nonprod_db_envs : [])
  name     = "${var.prefix}_${each.value}"
  instance = google_sql_database_instance.nonprod[0].name
}

resource "google_sql_database_instance" "prod" {
  count            = local.create_sql
  name             = "${var.prefix}-sql-prod"
  database_version = "POSTGRES_16"
  region           = var.region
  deletion_protection = false
  settings {
    tier              = var.sql_tier
    availability_type = "ZONAL"
    disk_type         = "PD_HDD"
    disk_size         = 10
    backup_configuration {
      enabled = false
    }
  }
  depends_on = [google_project_service.apis]
}

resource "google_sql_database" "prod_db" {
  count    = local.create_sql
  name     = "${var.prefix}_production"
  instance = google_sql_database_instance.prod[0].name
}
