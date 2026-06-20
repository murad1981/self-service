# Decision Log — ADRs & §12 Open Decisions

Status legend: **Accepted (default)** = proceeding on the recommended default unless the user overrides; **Blocking** = needs user/MoE input or external action before the affected work can complete.

---

## Part 1 — Architecture Decision Records (ADRs)

### ADR-001 — Single bootstrap class `SelfServeApplication`
**Accepted.** Appendix A mentions both `SelfServeApplication` and `SelfServiceApplication.java`. Standardize on **`SelfServeApplication`** under `com.selfserve.platform`; `SelfServiceApplication` is rejected. Flagged per §1.

### ADR-002 — Mobile runtime: Expo SDK 56 / React Native 0.85 (not 0.86)
**Accepted (deviation, verified).** The prompt (§4.1/§11/§12.11) specifies RN 0.86. Verification (June 2026) found **no Expo SDK ships RN 0.86**; Expo SDK 56.0.12 bundles **RN 0.85 / React 19.2 / Hermes v1 / New Architecture mandatory**. Per §3's "verify volatile facts, do not assume" and §12.11, we pin the SDK-56-bundled RN 0.85 and use `npx expo install` + `expo install --check` to keep native deps on the SDK matrix. Implementation team keeps the pin under review against actual Expo SDK 56 release notes at build time.

### ADR-003 — Modular monolith with `api`-package seams + ArchUnit enforcement
**Accepted.** Each backend module exposes a public `api` package (interfaces + DTOs); callers never import another module's entities/repositories. ArchUnit tests enforce boundaries in CI. This makes the future service extraction (1M+ users) mechanical and satisfies the §40/§5 "extraction-ready" intent.

### ADR-004 — Face ML model host: Cloud Run model service in `me-central2`
**Accepted (reconciliation).** The domain plans disagreed: Backend (B) defaulted to Vertex AI; GCP (E) and Integration (F) defaulted to a Cloud Run model service. The verification pass flagged this as the one genuine internal contradiction. **Resolution: Cloud Run model service in `me-central2`**, because it (a) scales to zero → near-zero POC cost (§7), (b) keeps Tier-4 biometric data in-region for PDPL residency (§5.4), and (c) honors the avoid-list (no GKE). It sits behind the `FaceMlProvider` interface, so Vertex AI or a KSA-licensed third party can replace it for production scale with **zero caller changes**. Overrides B's Vertex AI note. Coupled to §12.7 (liveness) and §12.2.

### ADR-005 — Mobile codegen: `openapi-typescript` + `openapi-fetch` + `openapi-react-query`
**Accepted.** Primary stack chosen because the project mandates TanStack Query and this stack emits types-only output (minimal generated runtime → small drift diff, New-Arch-friendly) and composes with the §4.3 interceptor middleware. **Orval** is the documented fallback (also generates MSW mocks for §4.10). Hey API is a watch item.

### ADR-006 — Emitted contract is OpenAPI 3.1; backend = single source of truth
**Accepted.** springdoc (3.0.x library) emits an **OpenAPI 3.1** spec, pinned explicitly so codegen tool support is unambiguous (`openapi-typescript` handles 3.1). Spec is canonically sorted before diffing to avoid false drift failures. Swagger UI is a dev/QA aid only and is **access-controlled/disabled in production** (mobile-only, §4.12).

### ADR-007 — Caching via `CacheProvider` (Caffeine), no managed Redis in POC
**Accepted.** Caffeine in-process behind a `CacheProvider` interface; token-revocation lists and rate-limit counters use it now, with a Memorystore/Redis seam for scale. Honors the §7 avoid-list.

### ADR-008 — Attendance/geofence split from biometric
**Accepted.** `attendance` owns the geofence **definition** (admin CRUD + `GeofenceProvider` interface); `biometric` owns the **check-in operation** and `CheckInRecord`. Check-in calls `GeofenceProvider`, keeping face-match + geofence-eval atomic while giving geofence config its own lifecycle/owner and a clean future extraction boundary.

### ADR-009 — Nafath: mock provider for the POC
**Accepted (user instruction).** The live Nafath integration is not yet available. The POC ships a **`MockNafathProvider`** implementing the `NafathProvider` interface, simulating the complete server-to-server flow: `initiate` returns a `transId` + 2-digit verification code; `status` advances through WAITING → COMPLETED/REJECTED/EXPIRED (driver: configurable delay / QA override endpoint); on COMPLETED it returns **synthetic NIC identity data** from a seeded fixture set; first-time detection runs against the real `users` table. The mock is profile-gated (active in `qa`/`staging`/`local`; production wiring left to the real provider). Because all callers depend only on the interface, swapping in the licensed provider (ELM + TCC, credentials in Secret Manager) requires no caller changes.

### ADR-011 — Single GCP project for the POC; WIF-only auth; infra-as-code in `/infra`
**Accepted (user instruction).** The user provisioned one project (`SelfService`) with a billing account and chose the **infra-as-code + Workload Identity Federation** path. Consequences: (1) all three envs (`qa`/`staging`/`production`) are deployed into the **single project**, separated by env-suffixed resource names and per-env service accounts + scoped IAM; (2) **no long-lived service-account keys** — GitHub Actions authenticates via WIF (GitHub OIDC → `github-pool`/`github-provider`), and the assistant never holds project credentials; (3) **Terraform (`infra/terraform/`) is the default, canonical method for setup and all ongoing cloud operations** — declarative, state-tracked, PR-reviewable; the gcloud scripts (`infra/gcp/`) are a secondary/convenience path only (one tool per project to avoid drift). Both are run by the user with their own auth/ADC; the assistant never holds project credentials. The project is **CNTXT-onboarded with Invoiced Billing**, so the IaC defaults `REGION` to **`me-central2` (Dammam, KSA)** — the PDPL-preferred region for Tier-4 data; `me-central1` (Doha) stays documented only as a standard-billing fallback. Multi-project isolation and three Firebase projects are the production upgrade path.

### ADR-010 — Design system from public DGA resources (no Figma)
**Accepted (user instruction).** The user has no paid Figma account, so the design system is built from the **publicly available DGA Design System and digital/brand guidelines** rather than the two Figma files referenced in §4.8/§12.10. Design tokens (color, typography incl. Arabic type, spacing, radii, elevation), components, and patterns are codified into the RTL-first UI kit from published DGA specs. Any value the public guidelines do not specify is flagged in the UI-kit docs and raised with the user — no generic/invented theme. WCAG AA + RTL accessibility remain required.

---

## Part 2 — §12 Open Decisions (all surfaced with recommended defaults)

| # | Decision | Recommended default | Status |
|---|---|---|---|
| **12.1** | Monorepo vs polyrepo | **Monorepo** — shared contract + identical env naming + single CI; path-filtered workflows keep mobile/backend pipelines independent. Revisit only if org-level access control becomes a hard requirement. | Accepted (default) |
| **12.2** | Face ML model host | **Cloud Run model service in `me-central2`** behind `FaceMlProvider` (ADR-004). Vertex AI / KSA-licensed third party are swap-in scale paths. | Accepted (default) |
| **12.3** | Cloud SQL sharing | **Share one instance for qa+staging** (separate DBs/roles); **isolate production**. Cuts the dominant POC cost while keeping prod isolated. | Accepted (default) |
| **12.3a** | One vs three GCP projects | **RESOLVED — single project for the POC** (user created one project, `SelfService`). All three envs live in one project, separated by env-suffixed resource names + per-env service accounts/IAM (ADR-011). Multi-project isolation is the documented production upgrade path. | Resolved (single project) |
| **12.4** | One vs three Firebase projects | **Three** (one per env) recommended; for the single-project POC, one Firebase project with per-env apps is acceptable. Confirm when FCM work starts. | Accepted (default) |
| **12.5** | Nafath credentials source/provider (SDAIA / TCC / ELM) | **RESOLVED — MOCK for the POC** (user confirmed the live integration is not yet ready). Implement a `MockNafathProvider` behind the `NafathProvider` interface that simulates the full flow (initiate → transId + 2-digit → status transitions WAITING→COMPLETED/REJECTED/EXPIRED → returns synthetic NIC data → first-time detection). The real provider (ELM + TCC license, creds in Secret Manager) drops in later with **zero caller changes** (ADR-009). | Resolved (mock) |
| **12.6** | KSA region availability (`me-central2`) vs fallback | **RESOLVED — use `me-central2` (Dammam)** for Cloud Run / Cloud SQL / KMS / Artifact Registry / Secret Manager (all verified available); IaC defaults to it. `me-central1` (Doha) retained only as a documented fallback. | Resolved (me-central2) |
| **12.6a** | CNTXT reseller + mandatory Invoiced Billing for `me-central2` | **RESOLVED — the `SelfService` project is CNTXT-onboarded with Invoiced Billing**, which unlocks me-central2. | Resolved |
| **12.7** | Liveness detection (in-POC vs deferred) | **Defer for POC.** Build the capture pipeline liveness-ready (vendor slots behind the provider interface). Recommend enabling passive liveness before production; POC check-in is photo-spoofable (documented limitation). | Accepted (default) |
| **12.8** | Geofence definition (static vs admin-managed; radius/polygon; retention) | **Admin-managed, server-defined regions** served via `GET /checkin/geofence-config`. **Model: CIRCLE (center + radius) for the POC, POLYGON-ready (JSONB)** so the admin UI can extend without a contract change. **Check-in record retention: 90 days for the POC**, configurable, subject to PDPL minimization. Client is never trusted to decide in/out-of-region. | Accepted (default) |
| **12.9** | Namespace `com.selfserve.platform` vs `sa.gov.moe.*` | **Keep `com.selfserve.platform`** (user-fixed per §1), treated as reversible. It is load-bearing across bundle id/package/backend base package/Artifact Registry/Firebase, so **decide before first store submission** — changing it post-submission forces new app records + TestFlight/Play re-enrollment. If MoE mandates a government reverse-domain, apply consistently to all three env identifiers and the backend base package. | **Blocking before first store submission** |
| **12.10** | DGA Figma availability | **RESOLVED — use PUBLIC DGA resources, not Figma** (user has no paid Figma account). Build the RTL-first UI kit (tokens + components + patterns + WCAG AA / RTL accessibility) from the **public DGA Design System / brand & digital guidelines**; codify tokens from published specs; flag and document any gap rather than inventing a generic theme (ADR-010). | Resolved (public DGA) |
| **12.11** | Version pins after compatibility verification | **Mobile: Expo SDK 56.0.12 / RN 0.85 (ADR-002). Backend: Java 25 LTS / Spring Boot 4.0.7** (4.1.0 GA'd June 2026 as an optional bump). Full pinned tables in the domain plans. | Accepted (default) |

---

## Part 3 — Blocking items requiring user / MoE action

These do **not** block region-agnostic POC scaffolding, but do block the noted workstreams:

1. ~~**Nafath provider + TCC license + sandbox credentials (12.5)**~~ — **RESOLVED: mock provider for the POC (ADR-009).**
2. ~~**CNTXT / me-central2 onboarding (12.6 / 12.6a)**~~ — **RESOLVED: project is CNTXT-onboarded; IaC uses me-central2 (Dammam).**
3. ~~**DGA Figma file access (12.10)**~~ — **RESOLVED: build from public DGA resources (ADR-010).**
4. **Namespace confirmation (12.9)** — must be settled before the first TestFlight/Play submission.
5. **GCP access for direct CLI interaction (new)** — user has created the `SelfService` project + billing, but this remote sandbox has **no credentials and no browser**. Authentication method is an open decision (service-account key vs interactive device-flow login vs commit infra-as-code for the user/CI to run). Project **ID** (not just display name "SelfService") is also required.
6. **GitHub repo, Firebase config files (§8)** — required inputs the user will provide; injected via Secret Manager / EAS / Actions, never committed.
