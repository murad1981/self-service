# Infrastructure — Self-Serve POC (GCP)

Infrastructure-as-code for the `SelfService` GCP project. You run it with **your own** credentials; no credentials are ever handed to the assistant or committed (per [§8](../docs/architecture/C-security-compliance.md) and ADR-011).

## Terraform is the default (canonical) method

**Use [`terraform/`](./terraform/) for all setup and ongoing cloud operations.** It is declarative, idempotent, state-tracked, and reviewable in PRs — the source of truth for what exists in the project. New infra changes go through Terraform.

The [`gcp/`](./gcp/) gcloud scripts are a **secondary/convenience path** only — useful for a one-off bootstrap on a machine without Terraform, or for quick manual inspection. **Do not** run the scripts against a project that Terraform manages: two tools mutating the same resources will fight and cause drift. Pick one per project; the default is Terraform.

## Model (single project)

You created one project, so all three environments (`qa` / `staging` / `production`) live in it, separated by **env-suffixed resource names** + **per-env service accounts and scoped IAM**. Multi-project isolation + three Firebase projects is the documented production upgrade path (ADR-011, §12.3a).

## Region & residency

`region` defaults to **`me-central2` (Dammam, KSA)** — the PDPL-preferred region for Tier-4 data. This is valid because the `SelfService` project is **CNTXT-onboarded** with Invoiced Billing (the access requirement for me-central2). `me-central1` (Doha) remains a documented standard-billing fallback but is not used here.

## Run (Terraform — default)

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars   # edit: project_id (the ID, not "SelfService")
gcloud auth application-default login           # Terraform reads these ADC credentials
terraform init
terraform plan
terraform apply
```

Read the outputs (used to wire CI/CD):
```bash
terraform output wif_provider_resource
terraform output deploy_service_accounts
```

- **Prerequisites:** roles to create IAM/SAs/WIF (Owner, or Editor + Project IAM Admin + Workload Identity Pool Admin). Find your project ID: `gcloud projects list --filter='name:SelfService' --format='value(projectId)'`.
- **State:** for shared/CI use, configure a remote backend (GCS bucket). A local backend is fine for a solo POC run. State contains resource metadata, **not** secret values.
- **Billable Cloud SQL** is **off by default**; enable it when ready by setting `create_cloud_sql = true` in `terraform.tfvars` (it is the POC cost floor — no scale-to-zero). See [`terraform/README.md`](./terraform/README.md).

### What Terraform manages

| Resource | Billable? |
|---|---|
| Enabled APIs | no |
| Artifact Registry Docker repo | ~free (storage) |
| `gha-deploy-<env>` + `run-runtime-<env>` service accounts (no keys) | no |
| Workload Identity Federation pool + GitHub OIDC provider + bindings | no |
| KMS key ring + `pii`/`biometric`/`location` keys per env | <$1/mo |
| Secret Manager secrets (empty placeholders, regional) | free tier |
| Least-privilege IAM bindings (runtime + deploy SAs) | no |
| Cloud SQL PostgreSQL (shared non-prod + isolated prod) — **`create_cloud_sql=true`** | **yes** |

Secrets are created **empty**. Add values out-of-band — never commit them or put them in `.tfvars`/state:
```bash
printf '%s' "<value>" | gcloud secrets versions add selfserve-qa-jwt-signing-key --data-file=- --project=<PROJECT_ID>
```
Nafath secrets stay empty for the POC (mock provider, ADR-009).

## Wire CI/CD to WIF (no keys)

Use the Terraform outputs in the backend deploy workflow:

```yaml
permissions:
  contents: read
  id-token: write   # required for OIDC
steps:
  - uses: google-github-actions/auth@v2
    with:
      workload_identity_provider: projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/github-pool/providers/github-provider
      service_account: gha-deploy-${{ env.APP_ENV }}@<PROJECT_ID>.iam.gserviceaccount.com
```

**Production hardening:** scope the production deploy SA to a protected GitHub Environment / tag refs rather than the whole repo (see the WIF binding note in `terraform/main.tf` / `gcp/03-workload-identity-federation.sh`).

## Secondary path (gcloud scripts)

Only if you cannot use Terraform on a given machine. See [`gcp/`](./gcp/) — `cp config.env.example config.env`, edit, then `./bootstrap.sh` (foundation) and `CONFIRM=yes ./06-cloud-sql.sh` (billable). The scripts create the identical resources; never mix them with Terraform on the same project.
