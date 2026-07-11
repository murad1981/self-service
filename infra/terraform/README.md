# Terraform — Self-Serve POC (default IaC)

**This is the default, canonical method for setup and all ongoing cloud operations** (ADR-011). It provisions the full foundation — APIs, Artifact Registry, per-env service accounts, Workload Identity Federation, KMS key rings/keys, Secret Manager placeholders, least-privilege IAM — plus **optional Cloud SQL** (billable, toggle). The `../gcp/` gcloud scripts are only a secondary path; do not run both against the same project.

## Run

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars   # edit project_id (the ID, not "SelfService")
gcloud auth application-default login           # Terraform uses your ADC
terraform init
terraform plan
terraform apply
```

Outputs (use in the GitHub Actions deploy workflow — `google-github-actions/auth` with `id-token: write`):
```bash
terraform output wif_provider_resource
terraform output deploy_service_accounts
terraform output artifact_registry_image_prefix
```
See [`../README.md`](../README.md) for the workflow snippet.

## Cloud SQL (billable, opt-in)

Off by default. Enable in `terraform.tfvars`:
```hcl
create_cloud_sql = true
```
`terraform apply` then creates a shared non-prod instance (qa + staging DBs) and an isolated production instance (smallest tier, zonal, HDD, no backup). It is the POC cost floor (no scale-to-zero). After apply:
```bash
terraform output cloud_sql_connection_names
# create app users + store passwords in Secret Manager out-of-band (never in .tfvars/state):
gcloud sql users create selfserve_app --instance=selfserve-sql-nonprod --password=... --project=<PROJECT_ID>
```
Set `create_cloud_sql = false` and re-apply (or `terraform destroy -target`) to remove it and stop cost.

## Notes

- `region` defaults to `me-central2` (Dammam) — this project is CNTXT-onboarded; `me-central1` is the standard-billing fallback.
- Secrets are created empty; add versions with `gcloud secrets versions add` — never in `.tfvars` or state.
- State contains resource metadata (not secret values). Use a remote backend (GCS bucket) for shared/CI use; a local backend is fine for a solo POC run.
- Single-project model; multi-project isolation is the production upgrade path (ADR-011).
- Re-running `terraform apply` is idempotent — it reconciles to the declared state.
