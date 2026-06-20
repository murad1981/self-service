# Terraform — Self-Serve POC foundation (optional)

Declarative equivalent of the non-billable `gcp/` scripts: APIs, Artifact Registry, per-env service accounts, Workload Identity Federation, KMS key rings/keys, Secret Manager placeholders, and least-privilege IAM. **Use either Terraform or the scripts — not both** (avoids state/drift conflicts). Cloud SQL is intentionally excluded (billable; create via `gcp/06-cloud-sql.sh` or add a dedicated module when ready).

## Run

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars   # edit project_id, region, github_repo
gcloud auth application-default login           # Terraform uses your ADC
terraform init
terraform plan
terraform apply
```

Then read the outputs:
```bash
terraform output wif_provider_resource
terraform output deploy_service_accounts
```
Use those in the GitHub Actions deploy workflow (`google-github-actions/auth` with `id-token: write`). See [`../README.md`](../README.md).

## Notes

- `region` defaults to `me-central1`; set `me-central2` only if CNTXT/invoiced-billing onboarded (R-01).
- Secrets are created empty; add versions out-of-band with `gcloud secrets versions add` — never in `.tfvars` or state.
- State contains resource metadata (not secret values); use a remote backend (GCS bucket) for shared/CI use. A local backend is fine for an individual POC run.
- Single-project model; multi-project isolation is the production upgrade path (ADR-011).
