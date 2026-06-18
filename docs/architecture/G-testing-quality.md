# G. Testing & Quality — Planning

> Scope §4.10, §4.2 (300-line rule), §5.7, §13.1.G. Planning only.

## 1. Mobile test plan

**Stack:** Jest 30 (`jest-expo` preset for SDK 56) + `@testing-library/react-native` (RNTL) + `@testing-library/jest-native`; **MSW 2.x** via `msw/native` (`setupServer`) with RN polyfills (`react-native-url-polyfill` + `TextEncoder`/`fast-text-encoding` shim in the Jest setup file); **Maestro** for optional E2E (YAML flows, accessibility-layer driving, built-in `setLocation`/permission control for geofence + camera flows, run on EAS dev builds).

**New-Architecture considerations:** Jest runs in Node — it does **not** boot the native runtime, render Fabric, or load TurboModules. So: unit/component tests validate logic/state machines/hooks/rendered-tree semantics; native modules (`expo-camera`/`-location`/`-secure-store`/`-notifications`) are **mocked at the adapter/interface boundary** (the provider seams); Fabric sync-render/animation timing is delegated to **Maestro** on dev builds. Query by role/accessibility label/text (carries localized accessibility names — supports the bilingual RTL UI).

**Required targets (from §4.10):**

| Target | Test type | Asserts |
|---|---|---|
| Networking layer + interceptors | Unit + MSW | timeout, retry+backoff+jitter (idempotent only), AbortController cancel, error normalize, correlation-ID injection, per-env base URL |
| Auth / refresh-rotation | Unit + MSW | 401→silent refresh→retry; rotated refresh persisted to secure-store (mocked); single-flight refresh; refresh-fail→logout+revoke |
| Face-enrollment gating | Unit + RNTL nav | server `enrolled=true` ⇒ never prompt (incl. simulated reinstall/new device); `enrolled=false` ⇒ route to enrollment; guard honors server status only |
| Geofenced check-in flow | RNTL + state-machine unit | face+location in one submit; permission-denied/coarse-location states; in-region/out-of-region/no-match each render correct localized feedback; client never evaluates geofence |
| Nafath + NIC first-time state machine | Unit + MSW | initiate→2-digit; poll waiting→completed/rejected/expired; timeout; `firstTime` routes to sign-up vs app |
| Runtime language switch / RTL | RNTL + unit | ar⇄en flips `I18nManager.isRTL`, re-renders strings, RTL layout/icons; default Arabic-first |
| NIC read-only fields | RNTL | national ID/first/last name non-editable; other fields editable |
| Critical components/hooks | RNTL + unit | error/success dialogs (localized), consent gate before capture, DGA token components |

**E2E happy paths (Maestro, optional):** (1) returning-user Nafath sign-in → home; (2) first-time Nafath → sign-up → enrollment → home; (3) check-in in-region (`setLocation`) → success; (4) language switch mid-session.

## 2. Backend test plan

**Stack:** JUnit 5 + Mockito (unit, no Spring context); **Spring Boot Test + Testcontainers PostgreSQL** with **`@ServiceConnection`** (Boot 4 supported); pin a fixed Postgres image (`postgres:16-alpine`). Testcontainers runs Flyway exactly as prod → broken migrations fail the suite (free quality gate). External APIs (Nafath/face ML/FCM) **never called** — mocked at the **provider-interface boundary** (Mockito unit; WireMock or stub `@TestConfiguration` bean behind the RestClient/WebClient + Resilience4j wrapper for integration). Resilience4j behavior (timeout/retry/CB open-close) tested with a controllable stub. `@WebMvcTest` for controller/validation/serialization slices.

**Required coverage (from §5.7):**

| Area | Layer | Cases |
|---|---|---|
| Auth/JWT/refresh | Unit + integration | issue/validate/expiry; **rotation + reuse-detection**; RBAC; 401/403; logout/revocation |
| Nafath + NIC first-time | Integration (mock Nafath) | initiate transId+2-digit; status states; webhook receiver; first-time = NID not registered ⇒ provision; returning ⇒ no provision; rate-limit ~10/min handled |
| Face enroll/verify gating | Integration | enroll one-time + **idempotent** (2nd call no-ops); status keyed to identity, survives simulated reinstall; verify match/no-match; encrypted-at-rest path |
| Geofenced check-in | Integration (mock face ML) | match+in-region ⇒ success recorded; match+out-of-region ⇒ rejected+recorded; no-match ⇒ rejected; **geofence evaluated server-side from server config (client value ignored)**; event to audit/attendance |
| NIC read-only enforcement | Integration | edit national ID/first/last ⇒ rejected server-side; editable fields succeed |
| Cross-cutting | Integration | correlation-ID propagation; i18n ar/en via Accept-Language; idempotency filter; Bucket4j rate-limit; Actuator health groups; audit append-only |

## 3. Quality-gate / lint config

**Mobile:** ESLint + Prettier; TypeScript `strict` (+ `noUncheckedIndexedAccess` recommended); `tsc --noEmit` gate. **`max-lines` HARD RULE = 300** (`{max:300, skipBlankLines:true, skipComments:true}`, severity error, **CI-enforced**); generated client excluded via override. Import/dependency boundaries (`eslint-plugin-boundaries` / `import/no-restricted-paths`) enforce presentation→domain→data + no cross-feature imports. Husky + lint-staged pre-commit; commitlint (conventional commits).

**Backend:** Spotless (format) + Checkstyle/PMD (style) + SpotBugs (bug patterns), all failing the build; optional SonarQube. **ArchUnit** enforces modular-monolith boundaries (no cross-module DB access, package-dependency rules).

**CI enforcement (required checks on `main`):** Mobile `install→typecheck→lint(max-lines,boundaries)→jest --coverage(gate)→contract-drift→EAS build`. Backend `mvn verify (unit+Testcontainers+Flyway)→Spotless/Checkstyle/SpotBugs→coverage gate→contract artifact publish`.

## 4. Coverage thresholds

**Mobile (Jest `coverageThreshold`, CI):** global 80% statements/lines, 75% branches, 80% functions; critical paths (networking, auth/refresh, enrollment-gating, check-in SM, Nafath/NIC SM) → 90% lines / 85% branches. Excluded: generated client, `app.config.ts`, native mocks, fixtures.

**Backend (JaCoCo `check` bound to `verify`):** global 80% line / 70% branch; critical modules (`auth`, `identity`, `biometric`) 90% line / 80% branch. Build fails below threshold. POC starting points — ratchet up, never down.

## 5. Requirement → test matrix

| # | Requirement / flow | Layer | Test type(s) |
|---|---|---|---|
| R1 | Networking resilience | Mobile | Jest unit + MSW |
| R2 | Auth + refresh rotation | Both | Jest+MSW / JUnit+Boot integration |
| R3 | Nafath + NIC first-time detection | Both | Jest+MSW / integration (mock Nafath) |
| R4 | One-time reinstall-proof enrollment (server-truth gating) | Both | RNTL+unit / integration (idempotent, identity-keyed) |
| R5 | Geofenced check-in face+in/out-of-region (server-side) | Both | RNTL+SM / integration (3 cases) |
| R6 | NIC fields read-only end-to-end | Both | RNTL / integration (reject edits) |
| R7 | Runtime language switch + RTL | Mobile | RNTL + unit (I18nManager) |
| R8 | Consent UX before capture | Mobile | RNTL |
| R9 | i18n ar/en via Accept-Language | Backend | Integration |
| R10 | Idempotency keys | Backend | Integration |
| R11 | Rate limiting (auth/Nafath/face) | Backend | Integration |
| R12 | Audit trail append-only | Backend | Integration |
| R13 | Actuator liveness/readiness/startup | Backend | Integration |
| R14 | Flyway migrations valid | Backend | Testcontainers (implicit) |
| R15 | Correlation-ID end-to-end | Both | MSW / integration |
| R16 | OpenAPI contract drift | Shared/CI | Drift gate |
| R17 | Core happy paths | Mobile | Maestro E2E (optional) |
| R18 | Module/layer boundaries | Both | ESLint boundaries / ArchUnit |
| R19 | 300-line rule | Mobile | ESLint max-lines in CI |

## 6. Contract-drift gate

Backend publishes OpenAPI 3.1 to `/packages/contracts` (§2.4/§6); mobile client generated. CI regenerates spec + client and `git diff --exit-code` against committed artifacts — any divergence fails the build. Generated files marked auto-generated, excluded from `max-lines`/coverage. **Required status check on `main`.**

## 7. Top risks

1. New-Arch native behavior untestable in Jest → adapter mocks + Maestro on dev builds; device-level QA budget.
2. MSW RN integration needs polyfills → pin MSW 2.x, lock setup file, smoke-test early; interceptor-level fallback.
3. Reinstall-proof enrollment is highest-risk correctness property → dedicated tests with fresh secure-store + new device token + server `enrolled=true`.
4. Geofence client-trust leak → explicit negative test that spoofed client geofence value is ignored.
5. Biometric/NIC test data is PDPL-sensitive → synthetic templates only; no real IDs/images in fixtures.
6. Java 25 / Boot 4 + Testcontainers alignment → pin versions; `@ServiceConnection` confirmed on Boot 4.
7. Flaky E2E/Testcontainers in CI → Maestro async handling; container reuse + fixed tags; Docker-enabled runners.
8. 300-line rule vs generated files → `skipBlankLines/skipComments`; exclude generated client.

## 8. Definition of Done

See `docs/ACCEPTANCE.md` §Testing/Quality.

**Sources:** [RN testing 2026 — drizz.dev](https://www.drizz.dev/post/react-native-testing) · [MSW React Native](https://mswjs.io/docs/integrations/react-native/) · [Maestro RN](https://docs.maestro.dev/get-started/supported-platform/react-native) · [Testcontainers — Spring Boot docs](https://docs.spring.io/spring-boot/reference/testing/testcontainers.html) · [Jest coverageThreshold](https://jestjs.io/docs/configuration) · [ESLint max-lines](https://eslint.org/docs/latest/rules/max-lines)
