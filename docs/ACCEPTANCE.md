# Definition of Done / Acceptance Criteria

Per major deliverable (§10). A deliverable is "done" only when every box is demonstrably true (tests + CI green + manual verification where noted).

## Shared / foundations

- [ ] Monorepo layout (`apps/mobile`, `services/backend`, `packages/contracts`, `infra`, `.github`, `docs`) in place.
- [ ] Three environments named **identically** (`qa`/`staging`/`production`) across Spring profiles, iOS schemes, Android flavors, EAS build profiles, EAS Update channels, Cloud Run services, Firebase projects, GitHub Environments. Backend-only `local` profile excluded from deploy.
- [ ] iOS bundle id **==** Android package per env; production `com.selfserve.platform`; qa/staging suffixed; all three install side-by-side. EN + AR display names per env.
- [ ] CI assertion fails on any drift from the canonical env/identifier matrix.
- [ ] **Correlation ID** generated per request on the client, propagated + MDC-logged on the backend, forwarded to all outbound provider calls, echoed in every response/error.
- [ ] OpenAPI 3.1 spec published to `/packages/contracts`; mobile typed client generated; **contract-drift gate** (regenerate + `git diff --exit-code`) is a required check.
- [ ] No secrets in repo (secret-scanning + push protection pass); Secret Manager (backend) + EAS secrets (mobile) + Actions secrets (CI); Firebase config injected at build; **Workload Identity Federation** over SA JSON keys.

## Mobile (deliverables 1–14)

- [ ] `/apps/mobile` builds via **EAS dev build** (not Expo Go) for all three envs; **New Architecture + Hermes confirmed**; `expo install --check` passes.
- [ ] Feature-sliced clean architecture (presentation/domain/data per feature); cross-feature deep imports rejected by lint.
- [ ] **ESLint `max-lines` = 300** enforced pre-commit + as a required CI check; no source file exceeds 300 lines; TS strict passes.
- [ ] POC screens implemented from the **DGA design system**, Arabic-first + full RTL: Nafath sign-in (2-digit number, waiting/polling), first-time sign-up (NIC pre-filled, **NIC read-only**), one-time face enrollment with consent, geofenced check-in (camera + GPS in one submit, in/out/no-match feedback, permission-denied/coarse states), profile (read-only NIC), reusable error/success dialogs/toasts.
- [ ] DGA UI kit covers **tokens + components + patterns + WCAG AA / RTL accessibility** (extracted from the two Figma files; gaps from public DGA guidelines, flagged).
- [ ] Navigation gated by session + **server-provided enrollment status**; enrollment never re-prompted after reinstall/new device; deep links respect guards.
- [ ] Networking layer: interceptors (auth inject, 401 refresh-rotation, correlation-ID, error normalize), timeouts, retry+backoff+jitter (idempotent only), AbortController, offline awareness, per-env base URLs, backend-mediated provider abstraction, prod cert pinning.
- [ ] Runtime EN⇄AR switch with correct `I18nManager` RTL/LTR (documented reload UX).
- [ ] Tokens in `expo-secure-store` only; no secrets in bundle.
- [ ] HMS-ready: `PushProvider`/`MapsProvider` interfaces with FCM impls + HMS stubs (no HMS build required).
- [ ] Mobile CI/CD: install → typecheck → lint(incl. max-lines) → unit tests → contract-sync → EAS build per env → EAS Update to matching channel → TestFlight/Play internal for non-prod.

## Backend (deliverables 15–27 + Appendix A)

- [ ] Maven build green on **Java 25 + Spring Boot 4.0.7**; all pinned versions resolve; dependency-convergence + **ArchUnit boundary** tests pass. Single bootstrap class `SelfServeApplication`.
- [ ] **Nafath + NIC**: initiate returns transId + 2-digit; status polling reflects WAITING→COMPLETED/REJECTED/EXPIRED; webhook receiver verifies signature; **first-time detection by national-ID registration**; provisioning on first sign-up.
- [ ] **Profile**: `GET` returns NIC fields read-only; `PATCH/PUT` changing any NIC field is **rejected (422)** — covered by a test (end-to-end read-only).
- [ ] **Biometric**: enroll is **idempotent + one-time** (replay returns existing); status is the **reinstall-proof source of truth**; verify returns match/score; **check-in verifies face match AND in-geofence in one operation**, records the event; OUT_OF_REGION + FACE_MISMATCH paths tested; geofence evaluated server-side (spoofed client value ignored — negative test).
- [ ] **Notifications**: device-token register/unregister; FCM send via `PushProvider`; HMS impl is a documented stub seam.
- [ ] Resilience4j on all outbound calls (timeout/retry/CB/bulkhead); CB-open returns 503 + flips readiness. Bucket4j limits on auth/Nafath/face; **Nafath ≤10/min/tenant verified by test**.
- [ ] i18n error payloads bilingual (ar/en) via `Accept-Language`; idempotency keys on enroll/check-in/profile/token; Caffeine cache behind `CacheProvider` (no Redis); security headers; stateless JWT w/ refresh rotation + revocation; **no CORS config present**.
- [ ] Flyway migrations run per profile; seed roles ADMIN/USER + QA user (qa only). NIC, face embeddings (**not raw images**), and location **encrypted at rest (KMS)**; consent + retention fields; audit table **append-only** (no UPDATE/DELETE grant).
- [ ] OpenAPI 3.1 generated by springdoc + published as CI artifact; drift gate. Actuator **liveness/readiness/startup** groups; structured JSON logs with correlation id.
- [ ] **Microservices migration blueprint** delivered (decomposition along `api` seams, per-module schema splitting, event-driven approach, Cloud Run scaling, optional GKE step, 1M+ users).

## Security / compliance

- [ ] JWT access + refresh with **rotation + reuse-detection (family revocation)**; multi-device sessions independently revocable; revocation behind Caffeine interface w/ Redis seam; RBAC enforced; BCrypt.
- [ ] PDPL: national-ID/biometric/location classified Tier-4 sensitive; KMS at rest + TLS; KSA residency (or logged exception); **explicit consent for biometrics + location** captured before first capture; retention/deletion policies defined + enforced.
- [ ] Append-only audit trail (actor/action/target/timestamp/correlation-ID) for auth, Nafath, enroll/verify, check-in.
- [ ] Least-privilege IAM documented per env; deploy SA has no secret access; prod secrets unreachable from qa/staging.

## Infrastructure

- [ ] 3 Cloud Run services (`min-instances=0`), Spring profile = env, in me-central2 (or documented fallback). Cloud SQL: 1 shared nonprod instance (qa+staging separate DBs) + 1 isolated prod, smallest tier, in-region; Flyway per DB.
- [ ] Cloud KMS keys per env for pii/biometric/location; runtime SA `cryptoKeyEncrypterDecrypter` scoped to its env. Secret Manager within free tier. Artifact Registry with image-pruning. Cloud Logging structured JSON + correlation IDs, no BigQuery/Pub/Sub sinks.
- [ ] **Avoid-list audit passes:** no GKE, service mesh, Pub/Sub, BigQuery, managed Redis. Cost guardrail ≤ ~$50/mo with budget alert. Residency posture + CNTXT onboarding status documented.
- [ ] Face ML host behind `FaceMlProvider`; default (Cloud Run model service, me-central2) selectable without caller changes (ADR-004).

## DevOps

- [ ] `main` is the only long-lived branch; protection enforces PR + approval + CODEOWNERS + all required checks + linear history; no `develop`/`release`. Conventional-commit PR titles + Husky/lint-staged/commitlint active.
- [ ] Backend pipeline: PR build+test (incl. Testcontainers) no deploy; main/tag → WIF auth → Artifact Registry → Cloud Run with `SPRING_PROFILES_ACTIVE` + Secret Manager + Flyway + `/health` smoke.
- [ ] Mobile pipeline gates as above; EAS build per profile via dynamic `app.config.ts` + EAS secrets; EAS Update to matching channel; non-prod auto-submit.
- [ ] Promotion: qa auto on merge; staging (1 reviewer) + production (2 reviewers, `v*` tags) via GitHub Environments; backend promotes same image digest; mobile OTA within runtime version else store build; rollback documented. Path filtering proven (backend-only change doesn't trigger mobile pipeline).

## Testing / quality

- [ ] Mobile Jest + RNTL + MSW covers all §4.10 targets (networking, auth/refresh, enrollment gating, check-in face+location, Nafath/NIC first-time SM, language/RTL switch, NIC read-only, consent); coverage ≥80% global / ≥90% critical; optional Maestro E2E for 4 happy paths.
- [ ] Backend JUnit 5 + Mockito + Spring Boot Test + Testcontainers covers all §5.7 areas; external APIs mocked at provider boundary; Flyway validated against real Postgres; JaCoCo ≥80% / ≥90% critical; Spotless/Checkstyle/SpotBugs + ArchUnit pass.
- [ ] Required CI status checks on `main`: lint, typecheck, unit, integration, coverage, contract-drift, build.
