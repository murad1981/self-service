# Consolidated Implementation Plan — Self-Serve / الخدمة الذاتية

Owning org: **Ministry of Education (KSA)**. Scope: production-direction **POC** — React Native (Expo) mobile app + Spring Boot modular-monolith backend, sharing identity, env naming, and a contract-first API. **Mobile-only — no web surface, no CORS.**

This plan is the output of the §13 planning phase (seven parallel domain agents + a verification/critic pass). It is **gated**: implementation proceeds once the §12 decisions are accepted-by-default-or-resolved and the blocking items in `DECISIONS.md` Part 3 are escalated. See `VERIFICATION.md` for the red-team result.

> Companion docs: [`architecture/`](./architecture/00-overview.md) (7 domain plans) · [`DECISIONS.md`](./DECISIONS.md) · [`RISKS.md`](./RISKS.md) · [`ACCEPTANCE.md`](./ACCEPTANCE.md) · [`VERIFICATION.md`](./VERIFICATION.md)

## Pinned technology (verified June 2026)

- **Mobile:** Expo SDK 56.0.12 / **React Native 0.85** (not 0.86 — ADR-002) / React 19.2 / Hermes v1 / New Architecture mandatory. TypeScript strict, Expo Router, TanStack Query + Zustand, i18next.
- **Backend:** **Java 25 LTS / Spring Boot 4.0.7**, springdoc-openapi 3.0.3 (emits OpenAPI 3.1), Resilience4j `-spring-boot4`, Bucket4j 8.19.0, Flyway 11 (+ Boot-4 starter + `flyway-database-postgresql`), Testcontainers 2.0.5, Firebase Admin 9.9.0, Lombok latest (records-first).
- **Infra:** GCP `me-central2` (Dammam) — all required services verified available, **gated by CNTXT reseller + Invoiced Billing**; fallback me-central1. Cloud Run, Cloud SQL (Postgres), Secret Manager, Cloud KMS, Artifact Registry, Cloud Logging, 3 Firebase projects.
- **Contract:** OpenAPI 3.1, `openapi-typescript` + `openapi-fetch` + `openapi-react-query`, two drift gates.

## Build order rationale

The contract is the spine: every cross-system flow depends on it, so the OpenAPI surface is defined and codegen wired **before** feature work, and each backend endpoint lands with its mobile client slice in the same PR. Identity (Nafath+NIC) precedes biometric because enrollment binds to the NIC-verified identity. Region-agnostic code is built in parallel with (not blocked by) the CNTXT/me-central2 procurement track.

---

## Phase 0 — Foundations & gate clearance (Week 0–1)

**Goal:** repo skeleton, CI spine, environment matrix, and resolve/escalate blockers.

- Monorepo scaffold (`apps/mobile`, `services/backend`, `packages/contracts`, `infra`, `.github/workflows`, `docs`); root Husky + lint-staged + commitlint; CODEOWNERS; branch protection on `main` (trunk-based).
- Encode the **env/identifier matrix** (`D-devops-environments.md` §1) as the single source; CI assertion against drift.
- Backend `pom.xml` + `SelfServeApplication` bootstrap; mobile `app.config.ts` + `eas.json` keyed on `APP_ENV`; ESLint flat config with **`max-lines: 300`**.
- CI skeleton: backend (build/test placeholder), mobile (typecheck/lint placeholder), contracts (drift gate placeholder).
- **Escalate blockers** (`DECISIONS.md` Part 3): Nafath provider/license (R-02), CNTXT/me-central2 onboarding (R-01), DGA Figma access (R-04), namespace confirmation (12.9). Collect user inputs: GitHub repo, GCP service account, Firebase config files.

**Exit:** CI green on empty skeleton; matrix assertion passing; blockers escalated with owners.

## Phase 1 — Contract & auth spine (Week 1–3)

**Goal:** the contract-first pipeline and the JWT/session backbone exist end-to-end.

- Backend: `common` (response wrapper, `ApiError`, exception handler, correlation-ID filter, i18n `MessageSource`, idempotency filter, `CacheProvider`/Caffeine, `RateLimiter`/Bucket4j, `FieldEncryptor`/KMS seams); `configuration` (Security, JWT, OpenAPI, health groups); `auth` module (JWT access+refresh **rotation + reuse-detection**, RBAC, BCrypt); Flyway V1 + seed (roles, QA user).
- Contract: springdoc emits OpenAPI 3.1 → `packages/contracts/openapi/self-serve.v1.yaml` (canonical sort); **drift gate** live. Mobile codegen (`openapi-typescript`+`openapi-fetch`+`openapi-react-query`) → `packages/contracts/generated/ts`; **client-drift gate** live.
- Mobile: networking layer (interceptors, resilience, correlation-ID, secure-store token storage), i18n bootstrap (Arabic-first + I18nManager RTL), navigation skeleton with group gating, Zustand session store.
- Tests: auth/JWT/refresh (both sides), networking layer, correlation-ID propagation.

**Exit:** sign-in token lifecycle works against the generated client; drift gates enforced; ACCEPTANCE "Shared/foundations" largely green.

## Phase 2 — Identity: Nafath + NIC (Week 3–5)

**Goal:** the §4.5/§5.2 identity flow.

- Backend `identity`: `NafathProvider` (initiate→transId+2-digit; status; webhook receiver w/ signature; resolve NIC) behind `common.integration` + Resilience4j; **first-time detection by national-ID registration**; provisioning; `NicIdentity` (KMS-encrypted); Bucket4j Nafath bucket (**≤10/min/tenant**); `users/profile` with **NIC read-only enforcement (reject edits 422)**.
- Mobile: Nafath sign-in screen (2-digit display, waiting/polling/rejected/expired states), first-time sign-up form (NIC pre-filled, NIC read-only), profile screen (NIC read-only). Nafath/NIC first-time state machine.
- Tests: Nafath first-time detection (mock provider), NIC read-only end-to-end, rate-limit, i18n error payloads.

**Exit:** returning vs first-time routing works; NIC fields read-only end-to-end; identity flow demoable with a mocked Nafath provider (live pending R-02).

## Phase 3 — Biometric: enrollment, verify, geofenced check-in (Week 5–8)

**Goal:** the critical §4.6/§5.2 behaviors.

- Backend `biometric`: `FaceMlProvider` (default Cloud Run model service, ADR-004) behind integration+Resilience4j; **enroll (one-time, idempotent), verify, get-status (reinstall-proof source of truth)**; `FaceTemplate` (encrypted embedding, NOT raw image, 1:1 NIC-bound); `ConsentRecord`. `attendance` module: `GeofenceRegion` + admin CRUD + `GeofenceProvider` (CIRCLE for POC, POLYGON-ready); **`/checkin` verifies face match AND in-geofence in one op**, records `CheckInRecord`, tri-state result; check-in retention 90d.
- Mobile: consent UX → one-time face enrollment (gated by server status; never re-prompt on reinstall); polished geofenced check-in (camera + GPS one submit, in/out/no-match feedback, permission/coarse states); `expo-location` purpose strings; `FaceCapture` seam (vision-camera fallback if liveness pulled in).
- `audit` module: append-only events for auth/Nafath/enroll/verify/check-in.
- Tests: reinstall-proof gating (fresh secure-store + new device + server enrolled=true), idempotent enroll, check-in match+in/out-of-region + no-match, geofence client-trust negative test, consent gate.

**Exit:** the two non-negotiable behaviors pass tests and demo (liveness deferred per §12.7, documented).

## Phase 4 — Notifications, audit completion, hardening (Week 8–9)

- Backend `notifications`: `PushProvider` → `FcmPushProvider` (Firebase Admin), device-token register/send, HMS stub. Security headers; finalize idempotency/rate-limit coverage; finalize audit coverage.
- Mobile `expo-notifications` + FCM registration, foreground/background/quit handling + deep-link routing; `PushProvider`/`MapsProvider` HMS-ready seams.
- Cert pinning (prod), optional root/jailbreak detection + obfuscation.
- Tests: notifications, audit append-only, idempotency, health groups.

## Phase 5 — Infra, CI/CD, deploy (Week 9–11)

- `infra`: WIF pool/provider + per-env SAs (deploy + runtime, least-privilege); 3 Cloud Run services (scale-to-zero); Cloud SQL (shared nonprod + isolated prod); KMS key rings; Secret Manager; Artifact Registry; Cloud Logging. me-central2 (or me-central1 fallback per R-01).
- Backend CI/CD: multi-stage Java 25 Docker → WIF → Artifact Registry → Cloud Run per env (`SPRING_PROFILES_ACTIVE`, Secret Manager mounts, Flyway, `/health` smoke). Mobile CI/CD: EAS build per profile → EAS Update per channel → TestFlight/Play internal (non-prod).
- Promotion wiring: qa auto; staging (1 reviewer) + production (2 reviewers, `v*` tags) via GitHub Environments; same-digest backend promotion; OTA-vs-store mobile policy.

## Phase 6 — Docs, blueprint, acceptance (Week 11–12)

- Microservices migration blueprint (decomposition along `api` seams, DB splitting, event-driven, Cloud Run scaling, optional GKE, 1M+ users).
- Cloud Run deployment guide, runbooks, ADR finalization.
- Full ACCEPTANCE checklist walked; coverage gates met; DGA accessibility (WCAG AA) pass; PDPL retention jobs verified.

---

## Milestones

| M | Milestone | End of |
|---|---|---|
| M0 | Repo + CI spine + matrix + blockers escalated | Phase 0 |
| M1 | Contract pipeline + auth spine working | Phase 1 |
| M2 | Nafath + NIC identity flow (mocked provider OK) | Phase 2 |
| M3 | **Reinstall-proof enrollment + geofenced check-in** | Phase 3 |
| M4 | Notifications + audit + client hardening | Phase 4 |
| M5 | Three envs deployed via CI/CD to Cloud Run + EAS | Phase 5 |
| M6 | Docs, migration blueprint, acceptance sign-off | Phase 6 |

## Critical-path dependencies

- **R-02 Nafath** gates Phase 2 *live* (buildable mocked).
- **R-01 CNTXT/me-central2** gates Phase 5 *in-region* provisioning (region-agnostic code unblocked).
- **R-04 DGA Figma** gates the design-system polish across Phases 2–3 (structural screens unblocked).
- **12.9 namespace** must settle before first store submission (Phase 5).
