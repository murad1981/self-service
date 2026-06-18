# E. GCP Infrastructure & Cost — Planning

> Scope §5.4, §7, §8, §13.1.E. Near-zero-cost POC with KSA residency preference. Planning only.

## 1. GCP service map (per environment)

Three environments → separate Cloud Run **services**, ideally separate GCP projects (at minimum production isolated). Naming: `selfserve-<env>`.

| Layer | qa | staging | production | Notes |
|---|---|---|---|---|
| GCP project | `selfserve-qa` | `selfserve-staging` | `selfserve-prod` | 3 projects = clean IAM/quota/billing isolation. |
| Cloud Run service | `selfserve-backend-qa` | `selfserve-backend-staging` | `selfserve-backend-prod` | **Scale-to-zero** (`min-instances=0`), `max-instances` low, CPU=1, mem 512Mi–1Gi, concurrency 80. |
| Artifact Registry | shared regional Docker repo | ← | dedicated repo in prod project | Prune old images. |
| Cloud SQL (PostgreSQL) | **shared** `selfserve-sql-nonprod` → DB `selfserve_qa` | ← same instance → DB `selfserve_staging` | **isolated** `selfserve-sql-prod` | Smallest tier; separate DBs/roles on shared nonprod; prod isolated; Flyway per env. |
| Secret Manager | per-project secrets | ← | ← | Free tier ≤6 active versions + ≤10k ops/mo — cache at startup. |
| Cloud KMS | key ring + keys `pii`/`biometric`/`location` | ← | isolated in prod | CMEK envelope encryption; symmetric, software level. |
| Cloud Logging | `_Default`, 30-day | ← | 30-day | Structured JSON + correlation-ID; no BigQuery/Pub/Sub sinks. |
| Firebase project | `selfserve-qa` (FCM) | `selfserve-staging` | `selfserve-prod` | 3 projects; per-env config injected at build; no Firestore (Postgres is system of record). |

**Avoid-list compliance (§7):** no GKE/Kubernetes, no service mesh, no Pub/Sub, no BigQuery, no Memorystore/Redis, no other heavy infra. Caching = in-process Caffeine. **Confirmed honored.**

## 2. me-central2 (Dammam) availability findings

**Critical regional caveat:** access to Dammam `me-central2` is restricted — only **KSA-based customers purchasing through CNTXT** (Google's exclusive KSA reseller) can use it, and **Invoiced Billing is mandatory** (no credit-card billing). This is a **procurement/onboarding gate** that must be cleared before any `me-central2` resource. Surfaced as open decision §12.6 (and §12.6a) and a **HIGH risk** (see `docs/RISKS.md`).

| Service | Available in me-central2? | Fallback | Source |
|---|---|---|---|
| Cloud Run | **Yes** | `me-central1` (Doha) / `me-west1` | Cloud Run locations; Dammam region access |
| Cloud SQL for PostgreSQL | **Yes** | `me-central1` | Cloud SQL region availability |
| Cloud KMS | **Yes** (regional) | `me-central1` | Cloud KMS locations |
| Artifact Registry | **Yes** | `me-central1` | Artifact Registry locations |
| Secret Manager | **Yes** (regional endpoint) | `me-central1` / global w/ replication | Secret Manager locations |
| Firebase — Firestore | **Yes** (not needed) | n/a | Firestore locations |
| Firebase — Cloud Functions | **Likely NOT** (not used by POC) | `me-central1` | Cloud Functions locations |
| Firebase — FCM (push) | **Global** (not region-bound) | n/a | — |

**Net:** all six required infra services are available in `me-central2`. Only residency-relevant gap is Cloud Functions (not used; FCM is global). The binding constraint is **CNTXT/Invoiced-Billing onboarding**, not technical availability. **Fallback if onboarding infeasible: `me-central1` (Doha)** — closest, all services present, but **outside KSA borders → weaker PDPL posture** (escalate to compliance, see C).

## 3. Workload Identity Federation + IAM

**Goal (§8):** no long-lived SA JSON keys; GitHub Actions → OIDC → WIF.

**Per project:** Workload Identity Pool `github-pool`; OIDC provider `github-provider` (issuer `token.actions.githubusercontent.com`); attribute mapping `google.subject=assertion.sub`, `attribute.repository=assertion.repository`, `attribute.ref=assertion.ref`; **attribute condition** restricts to the single repo (and, for prod, the `production` environment / tag refs only).

| SA | Purpose | Roles (least privilege) |
|---|---|---|
| `gha-deploy@<proj>` | CI/CD deploy (via WIF, **no key**) | `run.developer`, `artifactregistry.writer`, `iam.serviceAccountUser`, `cloudsql.client` (migration job). **No secret access.** |
| `run-runtime@<proj>` | Cloud Run runtime identity | `secretmanager.secretAccessor` (scoped), `cloudsql.client`, `cloudkms.cryptoKeyEncrypterDecrypter` (scoped), `logging.logWriter` |

Deploy SA bound via `principalSet://…/attribute.repository/<ORG>/self-serve` with `roles/iam.workloadIdentityUser`. Runtime SA gets `secretAccessor` only on its own env's secrets. Separate projects make prod secrets unreachable from qa/staging. **Production hardening:** GitHub `production` environment + required reviewers; WIF condition restricts prod deploys to protected tag refs.

## 4. Near-zero-cost design + rough estimate

**Levers:** Cloud Run scale-to-zero (free tier 2M req/360k GiB-s/180k vCPU-s per month); **Cloud SQL is the cost floor (no scale-to-zero)** → smallest shared-core/`db-f1-micro`, HDD nonprod, 10 GB, zonal (no HA), no replicas, stop nonprod when idle; **share one instance qa+staging**, isolate prod; Secret Manager within free tier (cache at startup); KMS <$1; Logging within 50 GiB free; Artifact Registry within 0.5 GB free + pruning.

| Item | qa | staging | production |
|---|---|---|---|
| Cloud Run | ~$0–2 | ~$0–2 | ~$2–8 |
| Cloud SQL | shared ~$10–18 (split) | (same instance) | ~$10–20 |
| Secret Manager / KMS / Logging / Artifact Registry | ~$0 / <$1 / $0 / ~$0 | ← | ← |
| **Subtotal** | ~$5–10 | ~$5–10 | ~$12–28 |
| **Total (3 envs)** | | | **~$22–50 / month** |

Biggest lever: stop/size Cloud SQL nonprod when not demoing.

## 5. Face ML model hosting — comparison & recommendation

Model is external/TBD (§4.6, §7) behind the backend `FaceMlProvider`/`FaceProvider` interface so the host is swappable.

| Option | Cost (POC) | Residency | Effort | Notes |
|---|---|---|---|---|
| Vertex AI endpoint | **High** (min always-on node) | me-central2 custom online prediction uncertain → cross-region risk | Med-High | Contradicts near-zero-cost. |
| **Cloud Run model service** | **Low** (scale-to-zero; cold-start latency) | **Strong** (in `me-central2` w/ backend) | Med (containerize model) | **Best cost + residency; honors avoid-list.** |
| Third-party API | Variable per-call | **Weak** (biometric leaves KSA → PDPL) | Low | Only if KSA-hosted vendor + DPA. |

**Recommended default: Cloud Run model service in `me-central2`** (ADR-004), behind `FaceMlProvider` so Vertex AI or a KSA-licensed third party can swap in for production scale later. **This overrides Backend plan B's Vertex AI default** — reconciled per the verification pass.

## 6. §12 decisions touching infra

| # | Decision | Default | Rationale |
|---|---|---|---|
| 12.6 | KSA region availability | **me-central2** (all services verified); **fallback me-central1** if CNTXT onboarding infeasible | Strongest PDPL residency; availability confirmed. |
| 12.6a | CNTXT reseller + Invoiced Billing onboarding | Confirm with MoE/procurement **before** provisioning (blocking) | me-central2 reseller-gated; no credit-card billing. |
| 12.3 | Cloud SQL sharing | Share one instance qa+staging; isolate production | Cuts dominant cost ~⅓; prod isolated. |
| 12.4 | 1 vs 3 Firebase projects | **3 projects** | Clean config/secret isolation; matches §2.2. |
| 12.2 | Face ML host | **Cloud Run model service in me-central2**, behind `FaceMlProvider` | Cost + residency + avoid-list (ADR-004). |

## 7. Top risks

1. **CNTXT onboarding / billing gate (HIGH)** — blocks all me-central2 use; fallback Doha changes PDPL posture. Confirm procurement early.
2. **Cloud SQL cost floor (MED)** — no scale-to-zero; smallest tier, shared nonprod, stop idle.
3. **Cloud Run cold starts on Spring Boot (MED)** — Java 25/Boot 4 cold start; small image, AOT/CDS, optionally `min-instances=1` on prod during demos.
4. **Face ML residency leak (HIGH if third-party)** — default to in-region Cloud Run model service; DPA + KSA hosting for any third party.
5. **me-central2 feature lag (LOW-MED)** — validate exact tier/edition at provisioning.
6. **Secret Manager free-tier overrun (LOW)** — load/cache secrets at startup.

## 8. Definition of Done

See `docs/ACCEPTANCE.md` §Infrastructure.

**Sources:** [Cloud Run locations](https://docs.cloud.google.com/run/docs/locations) · [Dammam region access](https://docs.cloud.google.com/docs/dammam-region-access) · [Cloud SQL Postgres region availability](https://docs.cloud.google.com/sql/docs/postgres/region-availability-overview) · [Cloud KMS locations](https://docs.cloud.google.com/kms/docs/locations) · [Artifact Registry locations](https://cloud.google.com/artifact-registry/docs/repositories/repo-locations) · [Secret Manager locations](https://cloud.google.com/secret-manager/docs/locations) · [Firestore locations](https://firebase.google.com/docs/firestore/locations) · [Cloud Functions for Firebase locations](https://firebase.google.com/docs/functions/locations)
