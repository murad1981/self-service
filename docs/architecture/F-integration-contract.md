# F. Integration & Contract — Planning

> Scope §2.3, §2.4, §4.3, §5.2 (integration), §6, §7 (face ML boundary), §13.1.F. Planning only.

Backend (`/services/backend`) is the **single source of truth** for the API contract. The mobile app generates its typed client from the published spec — no hand-written request/response types.

## 1. Contract-first pipeline

```
[1] Backend annotates controllers/DTOs with springdoc-openapi (emits OpenAPI 3.1)
[2] CI `contract:generate` exports spec → /packages/contracts/openapi/self-serve.v1.yaml (canonically sorted)
[3] CI `contract:drift` (backend): diff generated spec vs committed → FAIL if uncommitted delta
[4] On merge: spec committed (versioned, PR-reviewable) + uploaded as build artifact (self-serve-contract@<sha>)
[5] Mobile `client:generate` runs codegen from committed spec → /packages/contracts/generated/ts/
[6] Mobile `client:drift`: regenerate + git diff --exit-code → FAIL if delta
[7] Mobile tsc --strict compiles app against generated types → breaking change = compile error
```

Two drift gates: [3] spec matches backend code; [6]/[7] client matches committed spec. **springdoc** verified for Spring Boot 4.x / Java 21+ / OpenAPI 3.1. Use `springdoc-openapi-starter-webmvc-ui`; pin `info.version=1.0.0`; serve under `/api/v1`. **Pin the emitted spec version to OpenAPI 3.1** explicitly (codegen tools differ on 3.0 vs 3.1) — per verification pass. Swagger UI is a dev/QA aid only — **access-controlled / disabled in production** (mobile-only, §4.12).

## 2. API surface map (under `/api/v1`, standard envelope)

| # | Method | Path | Auth | Request | Success `data` | Notable errors |
|---|---|---|---|---|---|---|
| A1 | POST | `/auth/refresh` | refresh | `{refreshToken}` | `{accessToken, refreshToken, expiresIn}` | TOKEN_EXPIRED/REVOKED 401 |
| A2 | POST | `/auth/logout` | access | `{refreshToken}` | `{revoked:true}` | — |
| A3 | GET | `/auth/session` | access | — | `{userId, roles, faceEnrolled, firstTime}` | — |
| N1 | POST | `/identity/nafath/initiate` | none | `{nationalId}` | `{transId, verificationCode, expiresAt}` | INVALID_NATIONAL_ID 400, NAFATH_RATE_LIMITED 429 |
| N2 | GET | `/identity/nafath/status?transId=` | none | query | `{status, firstTime?, tokens?}` | TRANS_NOT_FOUND 404, TRANS_EXPIRED 410 |
| N3 | POST | `/identity/nafath/webhook` | provider HMAC | signed payload | `{ack:true}` | SIGNATURE_INVALID 401 |
| N4 | GET | `/identity/nic/details` | access | — | `{nationalId, firstName, lastName, dob, gender, ...}` (read-only) | — |
| P1 | GET | `/profile` | access | — | `{nationalId*, firstName*, lastName*, email, phone, preferredLang}` (`*`=read-only) | — |
| P2 | PATCH | `/profile` | access | `{email?, phone?, preferredLang?}` | updated profile | **NIC_FIELD_IMMUTABLE 422**, VALIDATION_ERROR 400 |
| B1 | POST | `/biometric/enroll` | access + `Idempotency-Key` | `{image, consentVersion, deviceId}` | `{enrolled, templateId, enrolledAt}` | ALREADY_ENROLLED 409, FACE_QUALITY_LOW/LIVENESS_FAILED/CONSENT_REQUIRED 422 |
| B2 | GET | `/biometric/enrollment-status` | access | — | `{enrolled, enrolledAt?}` | — |
| B3 | POST | `/biometric/verify` | access | `{image, consentVersion}` | `{match, score, decision}` | NOT_ENROLLED 409, FACE_QUALITY_LOW 422 |
| C1 | GET | `/checkin/geofence-config` | access | — | `{regions:[{id, name, type, center?, radiusM?, polygon?}], updatedAt}` | — |
| C2 | POST | `/checkin` | access | `{image, location:{lat,lng,accuracyM}, capturedAt, consentVersion}` | `{result: ACCEPTED\|FACE_MISMATCH\|OUT_OF_REGION, checkinId?, regionId?, recordedAt?}` | NOT_ENROLLED 409, LOCATION_REQUIRED/FACE_QUALITY_LOW 422 |
| F1 | POST | `/notifications/token` | access | `{token, platform: IOS\|ANDROID\|HMS, provider: FCM\|HMS}` | `{registered:true}` | — |
| F2 | DELETE | `/notifications/token` | access | `{token}` | `{removed:true}` | — |
| F3 | POST | `/notifications/test-send` | access (QA only) | `{title, body}` | `{messageId}` | gated to non-prod |

**Baked-in decisions:** No `/auth/login` with credentials — identity only via Nafath (N1→N2); on COMPLETED, N2 returns `firstTime` + (for returning users) JWT pair. NIC immutability on the contract (P2 schema omits NIC fields + server rejects). Check-in is a single request, tri-state, region decided server-side. Geofence-config fetched, never hardcoded.

## 3. Standard response & error model

```ts
interface ApiResponse<T> {
  success: boolean; data: T | null; error: ApiError | null;
  correlationId: string;   // echoed on every response (§2.3)
  message: string;         // localized (ar/en) per Accept-Language (§5.1.10)
  timestamp: string;       // ISO-8601
}
interface ApiError { code: string; message: string; details?: FieldError[]; correlationId: string; }
interface FieldError { field: string; code: string; message: string; }
```

`code` is a **stable enum** (never localized) — the app switches on `code`, displays `message`. Backend: `@RestControllerAdvice` + `ResponseBodyAdvice` envelope (`common.response`/`common.exception`).

## 4. Correlation-ID design

| Stage | Behavior |
|---|---|
| Header | **`X-Correlation-Id`** (single canonical header) |
| Client | Mobile interceptor generates UUIDv4 **per request**; held for log correlation + error display |
| Backend ingest | Servlet `Filter` (ordered first) reads or generates; puts in **SLF4J MDC** (`correlationId`) so every JSON log carries it |
| Backend propagate | `integration` outbound `RestClient`/`WebClient` forwards the same ID to Nafath/Face ML/FCM |
| Surface | Response envelope + `ApiError` echo `correlationId`; mobile error UI shows short ref |

One ID only (no `X-Request-Id`); future distributed tracing maps onto W3C `traceparent` (out of POC scope).

## 5. Provider abstractions

**Rule (§4.3, §11):** Nafath and Face ML reached only through the backend. Server abstractions wrap external systems; client abstractions wrap device capabilities + transport.

**Server (Java, `common.integration` / per-module SPI):** `NafathProvider` (initiate/status/resolveNicDetails/verifyWebhookSignature), `FaceMlProvider` (enroll/verify), `PushProvider` (sendToToken, platform FCM\|HMS), `GeoEvaluator` (evaluate point vs regions). Impls: `NafathHttpProvider`, `CloudRunFaceProvider` (default) / `VertexAiFaceProvider` / `ThirdPartyFaceProvider` (selectable), `FcmPushProvider` + future `HmsPushProvider`. Resilience4j + correlation in the `integration` layer.

**Client (TS, `apps/mobile/src/core/providers`):** `PushProvider` (FCM today, HMS later), `MapProvider` (Google vs HMS Maps), and thin `IdentityGateway`/`BiometricGateway` over the **generated typed client** (host resilience policy). **No client-side `NafathProvider`/`FaceMlProvider`** — that boundary lives only on the server.

## 6. Face ML boundary (§7)

```
[RN app] --(capture + consent)--> [Backend biometric] --FaceMlProvider--> [External Face ML host (Cloud Run model service, me-central2)]
```

Only `FaceMlProvider` knows the model address/auth/wire format. App-facing contract is the stable OpenAPI surface; model-facing contract is internal/swappable (enroll/verify/check-in-face-leg; location evaluated separately by `GeoEvaluator`, backend ANDs both). Templates/embeddings stored encrypted (KMS), keyed to NIC identity; raw probe images not persisted. **Host default = Cloud Run model service in me-central2 (ADR-004).**

## 7. `/packages/contracts` layout & codegen

```
/packages/contracts
├── openapi/self-serve.v1.yaml      # PUBLISHED SPEC (committed, single source of truth)
├── generated/ts/
│   ├── schema.d.ts                 # openapi-typescript output (types only)
│   └── client/                     # typed fetch wrappers + TanStack Query hooks
├── codegen.config.ts
├── package.json                    # @selfserve/contracts workspace dep for /apps/mobile
└── README.md                       # "do not edit generated/* by hand"
```

Generation runs: backend CI exports spec per PR (drift gate); mobile codegen regenerates per PR (drift gate); devs run `pnpm contracts:generate` locally after spec changes. Drift = `git diff --exit-code` on `openapi/` and `generated/`; `tsc --strict` makes breaking changes a hard compile failure.

## 8. Recommended codegen tool

**Recommendation: `openapi-typescript` + `openapi-fetch` + `openapi-react-query`** (primary), **Orval** (documented fallback). Rationale: project mandates **TanStack Query**; `openapi-react-query` is the first-party binding over `openapi-fetch` (~6kb, type-safe, no generated runtime — only `schema.d.ts`), suiting RN New Arch and keeping the drift diff small; composes with the §4.3 interceptor middleware. Orval is the alternative (also generates MSW mocks for §4.10) at the cost of more generated runtime. Hey API noted as a 2026 watch item. Logged as ADR-005.

## 9. §12 decisions touching integration

| § | Decision | Default |
|---|---|---|
| 12.2 | Face ML host | **Cloud Run model service in me-central2** behind `FaceMlProvider` (ADR-004; agrees with E, overrides B). |
| 12.5 | Nafath provider | Provider the MoE tenant holds; behind `NafathProvider`. Blocking on user to confirm + sandbox creds. |
| 12.8 | Geofence definition | Server config in POC (`GET /checkin/geofence-config`); model supports CIRCLE (center+radius) + POLYGON so admin UI takes over later without contract change. |

## 10. Top risks

1. Nafath webhook reliability/signature spec → support webhook + polling from day one; webhook = enhancement, polling = guaranteed path.
2. Contract-drift false-failures from non-deterministic spec output → canonical sort before diff; pin springdoc + `info.version`.
3. Face ML wire-format churn (host TBD) → behind `FaceMlProvider`; provider contract test with recorded fixtures.
4. Large biometric payloads over RN fetch → cap/compress client-side; longer timeout for `/biometric/*` + `/checkin`; never retry non-idempotent face calls.
5. Localized `message` vs stable `code` confusion → lint/convention: app branches only on `error.code`.
6. HMS push gap → `PushProvider` + `provider` field on `/notifications/token` in the contract now.
7. Correlation-ID not propagated to all outbound legs → enforce in shared `integration` interceptor; integration test asserts header reaches mock provider.

## 11. Definition of Done

See `docs/ACCEPTANCE.md` §Integration/Contract.

**Sources:** [springdoc-openapi](https://springdoc.org/) · [OpenAPI and Spring Boot 4 — Spring I/O 2026](https://2026.springio.net/sessions/openapi-and-spring-boot-4-whats-new/) · [openapi-fetch](https://openapi-ts.dev/openapi-fetch/) · [openapi-react-query](https://openapi-ts.dev/openapi-react-query/) · [Orval React Query](https://orval.dev/docs/guides/react-query/)
