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

---

## Part 2 — §12 Open Decisions (all surfaced with recommended defaults)

| # | Decision | Recommended default | Status |
|---|---|---|---|
| **12.1** | Monorepo vs polyrepo | **Monorepo** — shared contract + identical env naming + single CI; path-filtered workflows keep mobile/backend pipelines independent. Revisit only if org-level access control becomes a hard requirement. | Accepted (default) |
| **12.2** | Face ML model host | **Cloud Run model service in `me-central2`** behind `FaceMlProvider` (ADR-004). Vertex AI / KSA-licensed third party are swap-in scale paths. | Accepted (default) |
| **12.3** | Cloud SQL sharing | **Share one instance for qa+staging** (separate DBs/roles); **isolate production**. Cuts the dominant POC cost while keeping prod isolated. | Accepted (default) |
| **12.4** | One vs three Firebase projects | **Three** (one per env) — clean config/secret isolation; matches the §2.2 matrix. | Accepted (default) |
| **12.5** | Nafath credentials source/provider (SDAIA / TCC / ELM) | **Use the licensed provider the MoE tenant already holds** (likely ELM + TCC license); credentials in Secret Manager; abstract behind `NafathProvider` (webhook preferred + polling fallback). **Needs MoE to confirm provider + supply sandbox credentials.** | **Blocking** |
| **12.6** | KSA region availability (`me-central2`) vs fallback | **`me-central2` (Dammam)** for Cloud Run / Cloud SQL / KMS / Artifact Registry / Secret Manager — all verified available. **Fallback `me-central1` (Doha)** only if onboarding is infeasible (outside KSA → weaker PDPL, requires documented risk acceptance). | **Blocking** (see 12.6a) |
| **12.6a** | CNTXT reseller + mandatory Invoiced Billing for `me-central2` | **Confirm CNTXT onboarding + invoiced billing with MoE/procurement before provisioning any `me-central2` resource.** Region-agnostic POC code can proceed in parallel. | **Blocking** |
| **12.7** | Liveness detection (in-POC vs deferred) | **Defer for POC.** Build the capture pipeline liveness-ready (vendor slots behind the provider interface). Recommend enabling passive liveness before production; POC check-in is photo-spoofable (documented limitation). | Accepted (default) |
| **12.8** | Geofence definition (static vs admin-managed; radius/polygon; retention) | **Admin-managed, server-defined regions** served via `GET /checkin/geofence-config`. **Model: CIRCLE (center + radius) for the POC, POLYGON-ready (JSONB)** so the admin UI can extend without a contract change. **Check-in record retention: 90 days for the POC**, configurable, subject to PDPL minimization. Client is never trusted to decide in/out-of-region. | Accepted (default) |
| **12.9** | Namespace `com.selfserve.platform` vs `sa.gov.moe.*` | **Keep `com.selfserve.platform`** (user-fixed per §1), treated as reversible. It is load-bearing across bundle id/package/backend base package/Artifact Registry/Firebase, so **decide before first store submission** — changing it post-submission forces new app records + TestFlight/Play re-enrollment. If MoE mandates a government reverse-domain, apply consistently to all three env identifiers and the backend base package. | **Blocking before first store submission** |
| **12.10** | DGA Figma availability | **Confirm both DGA Figma files are accessible to implementers before the design-system build starts** (blocking for the UI-kit work). **Default if unavailable/incomplete: build from public DGA guidelines, flag each gap, and ask the user** — never invent a generic theme. The UI kit must cover design **tokens + components + patterns + WCAG AA / RTL accessibility**, not tokens alone. | **Blocking** (for design-system work) |
| **12.11** | Version pins after compatibility verification | **Mobile: Expo SDK 56.0.12 / RN 0.85 (ADR-002). Backend: Java 25 LTS / Spring Boot 4.0.7** (4.1.0 GA'd June 2026 as an optional bump). Full pinned tables in the domain plans. | Accepted (default) |

---

## Part 3 — Blocking items requiring user / MoE action

These do **not** block region-agnostic POC scaffolding, but do block the noted workstreams:

1. **Nafath provider + TCC license + sandbox credentials (12.5)** — blocks the live identity flow (mockable for early dev).
2. **CNTXT / me-central2 onboarding + invoiced billing (12.6 / 12.6a)** — blocks KSA-region provisioning; fallback me-central1 requires documented PDPL risk acceptance.
3. **DGA Figma file access (12.10)** — blocks the design-system extraction.
4. **Namespace confirmation (12.9)** — must be settled before the first TestFlight/Play submission.
5. **GitHub repo, GCP account/service account, Firebase config files (§8)** — required inputs the user will provide; injected via Secret Manager / EAS / Actions, never committed.
