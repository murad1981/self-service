# Risk Register

Severity: **High** (can block delivery / breach a non-negotiable), **Med** (material schedule/quality impact), **Low** (manageable). Each risk has an owner-domain and mitigation.

| # | Risk | Sev | Domain | Mitigation |
|---|---|---|---|---|
| R-01 | ~~CNTXT / me-central2 procurement gate.~~ **RESOLVED — the `SelfService` project is CNTXT-onboarded with Invoiced Billing; IaC provisions in me-central2 (Dammam).** Residual: confirm each service's exact tier/edition availability at provisioning time. | Low (was High) | E / C | Validate tier/edition during provisioning; keep me-central1 only as a documented break-glass fallback. |
| R-02 | ~~Nafath licensing/credentials unavailable.~~ **RESOLVED — POC uses a `MockNafathProvider` (ADR-009).** Residual: the mock must faithfully mirror the real status/error semantics so the swap is seamless. | Low (was High) | C | Mock behind `NafathProvider`; contract test against documented Nafath semantics; real provider drops in with no caller changes. |
| R-03 | **Biometric residency breach.** Sending Tier-4 face data to a non-KSA host without SDAIA SCC + risk assessment violates PDPL. | **High** | C / E | Default Face ML host = in-region Cloud Run model service (ADR-004). Any third party requires KSA hosting + DPA + SCC. |
| R-04 | ~~DGA Figma files not delivered.~~ **RESOLVED — build from public DGA resources (ADR-010);** no Figma. Residual: public guidelines may under-specify some tokens/components. | Low (was High) | A | Codify tokens from published DGA specs; flag each gap in UI-kit docs + ask user; never invent a generic theme; keep WCAG AA + RTL. |
| R-05 | **Liveness deferred in POC.** Check-in is photo/replay-spoofable without liveness. | Med | C | Documented POC limitation. Pipeline liveness-ready behind provider interface; enable passive liveness before production. |
| R-06 | **RN 0.86 expectation vs reality (0.85).** Forcing 0.86 would break the verified New-Arch dependency matrix. | Med | A | Pin SDK-56-bundled RN 0.85 (ADR-002); `expo install --check` CI gate; keep pin under review vs Expo release notes. |
| R-07 | **Flyway Boot 4 auto-config break.** `flyway-core` alone no longer auto-configures in Boot 4 → migrations silently skipped. | Med | B | Pin `spring-boot-starter-flyway` + `flyway-database-postgresql`; integration test asserts schema version on startup. |
| R-08 | **Library lag behind Spring Boot 4.** Wrong artifacts (Resilience4j `-spring-boot3`, Bucket4j non-JDK-suffixed, springdoc 2.8.x) cause runtime failures. | Med | B | Pinned versions table; dependency-convergence CI check. |
| R-09 | **Nafath rate limit (~10 MFA req/min/tenant).** Exceeding locks the integration. | Med | B / C | Tenant-level Bucket4j bucket + per-NID throttle + circuit breaker; load-test the limiter. |
| R-10 | **Lombok on JDK 25 point releases.** Annotation-processor breakage history. | Med | B | Latest Lombok as `annotationProcessorPath`; prefer Java records for DTOs; Lombok-free fallback ready. |
| R-11 | **Cloud Run cold starts (Spring Boot / Java 25).** Hurts Nafath/check-in latency during demos with scale-to-zero. | Med | E | Small image, AOT/CDS; optionally `min-instances=1` on prod during demo windows. |
| R-12 | **Identifier drift across the ~8 env surfaces.** A single misnamed channel/scheme/profile silently breaks OTA targeting or deploys. | Med | D | Single `<env>` value drives all config; CI assertion checks app.config.ts / eas.json / Spring profiles / Cloud Run names against the canonical matrix. |
| R-13 | **EAS runtime-version mismatch.** OTA update incompatible with installed binary. | Med | D | Policy: native/SDK changes bump runtime version; OTA only within same runtime version; validate staging channel before promoting to production. |
| R-14 | **WIF misconfiguration / confused-deputy.** Over-broad attribute condition lets other repos assume the GCP identity. | Med | D / E | Pin `repository_owner` + `repository` (immutable IDs); restrict prod SA to tag refs; least-privilege SA per env. |
| R-15 | **Secrets leakage** (Firebase config / SA keys / Nafath keys committed). | Med | C / D | No `.env` in repo; Secret Manager + EAS + Actions secrets; build-time Firebase injection; secret-scanning + push protection; WIF over JSON keys. |
| R-16 | **Reinstall-proof enrollment correctness.** Easy to accidentally trust client/device state and re-prompt. | Med | A / B | Gating reads server status on every launch; never cache enrollment flag locally; dedicated tests with fresh secure-store + new device token + server `enrolled=true`. |
| R-17 | **Geofence client-trust leak.** Client must never decide in-region. | Med | B / F | Server evaluates from server config; explicit negative test that spoofed client geofence value is ignored. |
| R-18 | **Cross-module coupling creep** defeats extraction goal. | Med | B | ArchUnit boundary tests from day one (ADR-003). |
| R-19 | **Contract-drift false failures** from non-deterministic springdoc output. | Low | F | Canonical sort before diff; pin springdoc + `info.version`; pin emitted spec to OpenAPI 3.1 (ADR-006). |
| R-20 | **Large biometric payloads over RN fetch.** Base64 images inflate request size; stress timeouts/retries. | Low | F / A | Cap/compress capture client-side; longer per-call timeout for `/biometric/*` + `/checkin`; never retry non-idempotent face calls. |
| R-21 | **Cloud SQL cost floor** (no scale-to-zero). | Low | E | Smallest tier, shared nonprod instance, stop when idle; budget alert. |
| R-22 | **New-Arch native behavior untestable in Jest** (Fabric/TurboModules). | Low | G | Adapter-boundary mocks + Maestro on dev builds; device-level QA budget. |
| R-23 | **MSW RN integration needs polyfills** / potentially incomplete. | Low | G | Pin MSW 2.x; lock polyfill setup; smoke-test early; interceptor-level fallback. |
| R-24 | **PDPL retention non-compliance** (templates/logs kept too long). | Low | C | Defined retention/deletion policies; automated purge jobs; check-in retention default 90d (§12.8). |
| R-25 | **Spring Boot 4.0 EOL 2026-12-31.** Short support window. | Low | B | Plan a 4.1.x bump path (4.1 GA June 2026); stay on the 4.x train. |
| R-26 | **No GCP credentials in the remote sandbox.** Project `SelfService` + billing exist, but this ephemeral session has no service account / ADC / metadata identity and no browser for OAuth, so direct gcloud interaction is blocked until an auth method is chosen. Pasting a long-lived SA key into the session is a secret-in-transcript risk and conflicts with §8 (WIF, no long-lived keys). | Med | E | Choose auth approach (see open question). Prefer committing idempotent infra-as-code + WIF (§8) over long-lived keys; if a key is used for the sandbox, scope it least-privilege and delete after. Project **ID** (not display name) required. |

## Highest-priority escalations (require user / MoE action)

1. **R-26** Provide the GCP project **ID** (not display name) and run the `infra/` bootstrap with your own gcloud auth.
2. **R-03** Face ML residency (resolved by ADR-004 default; re-opens if a third-party host is chosen).
3. **12.9** Namespace (`com.selfserve.platform` vs `sa.gov.moe.*`) — settle before first store submission.

*(R-01 CNTXT/me-central2, R-02 Nafath, and R-04 DGA Figma resolved — see ADR-011 / ADR-009 / ADR-010.)*
