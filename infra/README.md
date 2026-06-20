# Infrastructure — Self-Serve POC (GCP)

Infrastructure-as-code for the `SelfService` GCP project. You run these with **your own** authenticated `gcloud`; no credentials are ever handed to the assistant or committed (per [§8](../docs/architecture/C-security-compliance.md) and ADR-011).

Two equivalent paths — **use one**:
- **`gcp/` — idempotent gcloud scripts** (canonical for the POC; nothing to install beyond `gcloud`).
- **`terraform/` — declarative module** (optional; mirrors the scripts).

## Model (single project)

You created one project, so all three environments (`qa` / `staging` / `production`) live in it, separated by **env-suffixed resource names** + **per-env service accounts and scoped IAM**. Multi-project isolation + three Firebase projects is the documented production upgrade path (ADR-011, §12.3a).

## Region & residency (read before running)

`REGION` defaults to **`me-central1` (Doha)** so the scripts run on a standard billing account. The PDPL-preferred region is **`me-central2` (Dammam, KSA)**, but it is gated by the **CNTXT reseller + mandatory Invoiced Billing** (see [R-01](../docs/RISKS.md)). If your billing is CNTXT-onboarded, set `REGION=me-central2`. Using me-central1 places Tier-4 data outside KSA — document the cross-border risk acceptance with SDAIA safeguards before production.

## Prerequisites

1. Install gcloud and authenticate as yourself:
   ```bash
   gcloud auth login
   gcloud config set project <YOUR_PROJECT_ID>
   ```
2. You need roles to create IAM/SAs/WIF (Owner, or Editor + Project IAM Admin + Workload Identity Pool Admin) on the project.
3. Find your project **ID** (not the display name "SelfService"):
   ```bash
   gcloud projects list --filter='name:SelfService' --format='value(projectId)'
   ```

## Run (gcloud scripts)

```bash
cd infra/gcp
cp config.env.example config.env      # then edit: PROJECT_ID, REGION, GITHUB_REPO
chmod +x *.sh
./bootstrap.sh                         # APIs, Artifact Registry, SAs, WIF, KMS, Secrets, IAM (non-billable)

# Billable, opt-in (Cloud SQL — the POC cost floor):
CONFIRM=yes ./06-cloud-sql.sh

# Tear down to stop cost:
CONFIRM=yes ./teardown.sh
```

`config.env` is gitignored. Every script is idempotent (re-running is safe).

### What gets created

| Step | Resource | Billable? |
|---|---|---|
| 00 | Enable required APIs | no |
| 01 | Artifact Registry Docker repo | ~free (storage) |
| 02 | `gha-deploy-<env>` + `run-runtime-<env>` service accounts (no keys) | no |
| 03 | Workload Identity Federation pool + GitHub OIDC provider + bindings | no |
| 04 | KMS key ring + `pii`/`biometric`/`location` keys per env | <$1/mo |
| 05 | Secret Manager secrets (empty placeholders, regional) | free tier |
| 07 | Least-privilege IAM bindings (runtime + deploy SAs) | no |
| 06 | Cloud SQL PostgreSQL (shared non-prod + isolated prod) | **yes** |

Secrets are created **empty**. Add values out-of-band — never commit them:
```bash
printf '%s' "<value>" | gcloud secrets versions add selfserve-qa-jwt-signing-key --data-file=- --project=<PROJECT_ID>
```
Nafath secrets stay empty for the POC (mock provider, ADR-009).

## Wire CI/CD to WIF (no keys)

After `03` prints the provider resource + per-env deploy SAs, use them in the backend deploy workflow:

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

**Production hardening:** scope the production deploy SA to a protected GitHub Environment / tag refs rather than the whole repo — see the note in `03-workload-identity-federation.sh`.

## Terraform (optional alternative)

See [`terraform/README.md`](./terraform/README.md). Covers the same non-billable foundation (APIs, Artifact Registry, SAs, WIF, KMS, Secrets, IAM). Use **either** Terraform **or** the scripts, not both, to avoid drift.
