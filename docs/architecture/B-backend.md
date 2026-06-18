# B. Backend Architecture & Gap-Fill — Planning

> Appendix A scaffolding + §5 additions for the `com.selfserve.platform` Spring Boot modular monolith. Planning only — versions verified June 2026.

## 1. Pinned versions

| Component | Pinned version | Notes | Source |
|---|---|---|---|
| **Java** | **25 (LTS)** | Spring Boot 4.0/4.1 first-class Java 25 support; compile/run target 25. | Spring Boot 4.0.0 GA |
| **Spring Boot** | **4.0.7** (latest 4.0.x) | 4.0 supported until 2026-12-31. 4.1.0 (2026-06-10) GA — recommend 4.0.7 for POC stability; flag 4.1 as optional bump. | Boot blog; endoflife.date |
| **Spring Framework** | 7.0.x (managed by Boot 4) | GA Nov 2025. | Spring Framework 7.0 GA |
| **springdoc-openapi** | **3.0.3** (v3.x line) | v3.x = Spring Boot 4 / OpenAPI 3.1 / Java 21+. Do NOT use 2.8.x (Boot 3). | springdoc v4 docs |
| **Resilience4j** | **2.2.0+**, `io.github.resilience4j:resilience4j-spring-boot4` | Dedicated Boot4 starter (not -spring-boot3). Requires AOP + Actuator. | Maven; issue #2351 |
| **Bucket4j** | **8.19.0** | `com.bucket4j:bucket4j_jdk17-core`. In-memory only (no Redis). | bucket4j.com |
| **Flyway** | core **11.15.0** + **`spring-boot-starter-flyway` (Boot 4.0.x)** + **`flyway-database-postgresql`** | **CRITICAL: in Boot 4 `flyway-core` alone NO LONGER auto-configures.** | Flyway+Boot4 notes |
| **Testcontainers** | **2.0.5** (+ junit-jupiter + postgresql) | Use `@ServiceConnection`. | Maven; GitHub releases |
| **Lombok** | **1.18.42+** | JDK 25 supported. Prefer Java records for DTOs; keep Lombok-free fallback. | Lombok changelog |
| **Firebase Admin SDK** | **9.9.0** | Behind `PushProvider` (HMS-ready). | Firebase Admin Java notes |
| **PostgreSQL** | 16.x (Cloud SQL smallest tier) | — | — |
| **Maven** | 3.9.x + wrapper | — | — |

> Build note: with Java 25 + Lombok, set `maven-compiler-plugin -parameters` and run Lombok as `annotationProcessorPath`.

## 2. Package / module tree (`com.selfserve.platform`)

DDD modules; each exposes a public `api` package (interfaces + shared DTOs). **No cross-module entity or repository imports.**

```
com.selfserve.platform
├── SelfServeApplication.java        ← STANDARDIZE. Appendix A's "SelfServiceApplication.java" REJECTED (ADR-001).
├── configuration/                   (SecurityConfig, JwtConfig, OpenApiConfig, JacksonConfig,
│                                      CacheConfig, RateLimitConfig, Resilience4jConfig,
│                                      MessageSourceConfig (i18n), ActuatorHealthGroupsConfig)
├── common/                          (shared kernel — no business logic)
│   ├── exception/   (GlobalExceptionHandler, AppException hierarchy)
│   ├── response/    (ApiResponse<T>, ErrorModel, PageResponse<T>)
│   ├── security/    (JwtService, CurrentUser, RoleConstants ADMIN/USER)
│   ├── i18n/        (MessageResolver — ar/en via Accept-Language)
│   ├── idempotency/ (IdempotencyKeyFilter + IdempotencyStore iface)
│   ├── correlation/ (CorrelationIdFilter — MDC)
│   ├── cache/       (CacheProvider iface; CaffeineCacheProvider impl)
│   ├── ratelimit/   (RateLimiter iface; Bucket4jRateLimiter impl)
│   ├── crypto/      (FieldEncryptor iface; KmsEnvelopeEncryptor — Cloud KMS)
│   └── util/, constants/
├── common/integration/              (§5.2 outbound layer)
│   ├── api/         (NafathClient, FaceMlProvider, PushProvider interfaces)
│   ├── http/        (RestClient/WebClient factory + correlation propagation)
│   ├── resilience/  (Resilience4j decorators per provider)
│   └── config/      (per-provider timeouts, base URLs from Secret Manager)
├── auth/            (JWT issue/refresh/revoke; RBAC; BCrypt for QA creds)
├── identity/        (§5.2 Nafath + NIC — NEW: NafathController, WebhookController,
│                     NafathService, FirstTimeDetectionService, NicMappingService,
│                     NafathClient impl, NafathTransaction/NicIdentity entities)
├── users/profile/   (read-only NIC fields enforced server-side; consumes identity.api)
├── biometric/       (§5.2 face + check-in — NEW: FaceController enroll/verify/status,
│                     CheckInController; FaceEnrollmentService [idempotent], FaceVerifyService,
│                     CheckInService [face match AND geofence in one op]; FaceMlProvider impl;
│                     FaceTemplate [encrypted embedding] / CheckInRecord entities)
├── attendance/      (§5.2 geofence DEFINITION + admin CRUD + GeofenceProvider iface;
│                     GeofenceEvaluationService; GeofenceRegion entity. CheckInRecord stays in biometric)
├── notifications/   (PushProvider → FcmPushProvider now, HmsPushProvider stub; DeviceToken)
├── content/         (Appendix A baseline sample CRUD)
└── audit/           (§5.2 NEW append-only: AuditWriter iface, AuditService write-only, AuditEvent)
```

**Inter-module rules:** modules depend only on `*/api` + `common`. Cross-module DB access forbidden (enforced via **ArchUnit** in CI). Each module owns its tables so DB splitting is mechanical at extraction.

## 3. Endpoint inventory (under `/api/v1`, `ApiResponse<T>` wrapper, no CORS)

| Module | Method + Path | Auth | Success | Key errors |
|---|---|---|---|---|
| identity | `POST /auth/nafath/initiate` | none + rate-limited | `{transId, random(2-digit), status:WAITING, expiresAt}` | 400, 429, 503 (CB) |
| identity | `GET /auth/nafath/status/{transId}` | none + rate-limited | `{status, firstTime?, tokens?}` | 404, 410 |
| identity | `POST /auth/nafath/webhook` | provider signature | `200 {}` | 401, 409 |
| identity | `GET /identity/nic` | JWT | NIC fields (read-only) | 401, 404 |
| auth | `POST /auth/refresh` | refresh | `{access, refresh}` (rotated) | 401 |
| auth | `POST /auth/logout` | JWT | `204` | 401 |
| users | `GET /profile` | JWT | profile (NIC read-only) | 401 |
| users | `PUT /profile` | JWT + idem | editable only | **422 if NIC fields changed** |
| biometric | `POST /biometric/face/enroll` | JWT + **Idempotency-Key** | `{enrollmentId, ENROLLED}` | 409 (replay→existing), 422 no consent, 503 |
| biometric | `GET /biometric/face/status` | JWT | `{enrolled, enrolledAt?}` (reinstall-proof) | 401 |
| biometric | `POST /biometric/face/verify` | JWT + rate-limited | `{match, score}` | 422 not enrolled, 429, 503 |
| biometric | `POST /biometric/checkin` | JWT + rate-limited + idem | `{result: SUCCESS\|FACE_MISMATCH\|OUT_OF_REGION, checkInId?, recordedAt}` | 422, 429, 503 |
| attendance | `GET /attendance/geofence` | JWT | `{regions:[...]}` (client never trusts) | 401 |
| attendance | `POST/PUT/DELETE /admin/geofence` | JWT + ADMIN | region | 403 |
| attendance | `GET /attendance/checkins` | JWT | page of records | 401 |
| notifications | `POST/DELETE /notifications/device-token` | JWT | `{id}` / `204` | 401 |
| notifications | `POST /admin/notifications/send` | JWT + ADMIN | `{messageId, accepted, failed}` | 403, 502 |
| actuator | `GET /actuator/health/{liveness,readiness}` | internal | health group | 503 if not ready |

OpenAPI 3 spec exported by springdoc → `/packages/contracts` as a **CI artifact**; drift check gates the build.

## 4. Entity / data model (JPA + Flyway)

| Entity | Module | Sensitivity / encryption |
|---|---|---|
| `User` (id, nationalId unique anchor, roles, status) | users | nationalId sensitive |
| `Role` (ADMIN, USER) | auth | seed data |
| `RefreshToken` (userId, tokenHash, expiresAt, revoked, family) | auth | hash only |
| `NicIdentity` (userId, nationalId, firstName, lastName read-only, nicPayloadEnc) | identity | **KMS-encrypted PII** |
| `NafathTransaction` (transId, nationalId, random2digit, status, expiresAt) | identity | short retention |
| `FaceTemplate` (userId 1:1 NIC-bound, **embeddingEnc NOT raw image**, algoVersion) | biometric | **encrypted, strictest PDPL** |
| `CheckInRecord` (userId, regionId, lat, lng, faceScore, result, correlationId) | biometric | location sensitive |
| `GeofenceRegion` (type CIRCLE/POLYGON, center+radius or polygon JSONB, active) | attendance | server-defined |
| `DeviceToken` (userId, token, platform, locale) | notifications | — |
| `AuditEvent` (actor, action, target, result, timestamp, correlationId, metadata) | audit | **append-only (no UPDATE/DELETE grant)** |
| `ConsentRecord` (userId, type BIOMETRIC/LOCATION, grantedAt, version) | biometric | PDPL consent |
| `IdempotencyKey` (key, userId, endpoint, responseHash, expiresAt) | common | dedupe |

**Seed data** (profile-aware): roles ADMIN/USER; QA test user (qa only) with mock NIC + optional pre-enrolled template stub; default QA geofence region. No seed users in production.

## 5. Key decisions

1. Bootstrap = **`SelfServeApplication`** (single); reject `SelfServiceApplication` (ADR-001).
2. Modular monolith, extraction-ready via `api` packages; **ArchUnit** enforces boundaries.
3. Outbound resilience standardized through `common.integration` + Resilience4j (timeout/retry idempotent-only/CB/bulkhead). Readiness probe reflects CB state.
4. Caching behind `CacheProvider` (Caffeine) — **no Redis**; Memorystore seam later.
5. Rate limiting via `RateLimiter` (Bucket4j in-memory); Nafath tenant bucket sized to **≤10 MFA req/min/tenant** + per-NID throttle.
6. Stateless JWT (access+refresh, rotation, revocation list); RBAC; security headers; **no CORS**.
7. PDPL/crypto: `FieldEncryptor` (KMS envelope) for NIC/embeddings/location; embeddings not raw images; consent capture; retention fields; KSA region preferred.
8. i18n via `MessageSource` (ar/en) from `Accept-Language`.
9. Idempotency-Key filter + store for enroll/check-in/profile/token-register.
10. Actuator liveness/readiness/startup groups; structured JSON logging; `CorrelationIdFilter` (MDC).
11. OpenAPI published (springdoc 3.0.3) → CI artifact; drift gate.
12. Profiles `qa`/`staging`/`production` (+`local`) replace `local/dev/prod`; Flyway needs the Boot 4 starter.

## 6. §12 decisions touching backend

| # | Decision | Default | Rationale |
|---|---|---|---|
| 12.2 | Face ML host | Behind `FaceMlProvider`; **default = Cloud Run model service in KSA region** (reconciled with E/F — see ADR-004). | Cost + residency; reversible. |
| §5.2 | Attendance module split | **`attendance` owns geofence DEFINITION + admin CRUD + `GeofenceProvider`; `biometric` owns check-in op + `CheckInRecord`.** | Distinct lifecycle/owner; clean future extraction; check-in stays atomic. |
| 12.5 | Nafath credentials | Licensed provider creds in Secret Manager; webhook + polling. | Server-to-server only. |
| 12.6 | KSA region | `me-central2`; verify per service. | PDPL residency. |
| 12.8 | Geofence model/retention | Admin-managed regions; CIRCLE for POC, POLYGON-ready (JSONB); check-in retention 90d (configurable). | Server-trusted, not hardcoded. |

## 7. Top risks

1. Flyway Boot 4 auto-config break → pin starter + postgresql module; integration test asserts schema version.
2. Lombok on JDK 25 point releases → latest Lombok, records-first, fallback path.
3. Library lag behind Boot 4 (Resilience4j/Bucket4j/springdoc artifacts) → pinned table; dependency-convergence CI check.
4. Nafath rate limit (~10/min/tenant) → tenant bucket + per-NID throttle + CB; load-test limiter.
5. Biometric/PII PDPL → KMS envelope, embeddings-not-images, consent+retention, append-only audit, KSA residency.
6. Spring Boot 4.0 EOL 2026-12-31 → plan a 4.1.x bump path.
7. Cross-module coupling creep → ArchUnit from day one.
8. Idempotency on check-in/enroll → key store + 1:1 FaceTemplate constraint + DB unique constraints.

## 8. Definition of Done

See `docs/ACCEPTANCE.md` §Backend.

**Sources:** [Spring Boot 4.0.0 GA](https://spring.io/blog/2025/11/20/spring-boot-4-0-0-available-now/) · [Spring Boot 4.1.0](https://spring.io/blog/2026/06/10/spring-boot-4/) · [endoflife.date/spring-boot](https://endoflife.date/spring-boot) · [springdoc v4](https://springdoc.org/v4/) · [Resilience4j Boot4 starter](https://mvnrepository.com/artifact/io.github.resilience4j/resilience4j-spring-boot4) · [Bucket4j](https://bucket4j.com/) · [Flyway + Boot 4](https://pranavkhodanpur.medium.com/flyway-migrations-in-spring-boot-4-x-what-changed-and-how-to-configure-it-correctly-dbe290fa4d47) · [Testcontainers](https://github.com/testcontainers/testcontainers-java/releases) · [Lombok changelog](https://projectlombok.org/changelog) · [Firebase Admin Java](https://firebase.google.com/support/release-notes/admin/java)
