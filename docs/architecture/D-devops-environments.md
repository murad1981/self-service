# D. Environments & DevOps — Planning

> Scope §2.1, §2.2, §3, §4.9, §4.11, §5.5, §9, §13.1.D. Planning only.

## 1. Environment / identifier matrix

Three deployed environments named **identically** everywhere. Backend-only `local` profile is not deployed. Bundle id == package per env; production carries the clean identifier; non-prod suffixed for side-by-side install.

| Dimension | qa | staging | production |
|---|---|---|---|
| Spring profile | `qa` | `staging` | `production` |
| iOS scheme | `QA` | `Staging` | `Production` |
| Android flavor | `qa` | `staging` | `production` |
| EAS build profile | `qa` | `staging` | `production` |
| EAS Update channel | `qa` | `staging` | `production` |
| iOS bundle id | `com.selfserve.platform.qa` | `com.selfserve.platform.staging` | `com.selfserve.platform` |
| Android package | `com.selfserve.platform.qa` | `com.selfserve.platform.staging` | `com.selfserve.platform` |
| EN display name | Self-Serve QA | Self-Serve Staging | Self-Serve |
| AR display name | الخدمة الذاتية — اختبار | الخدمة الذاتية — تجريبي | الخدمة الذاتية |
| Cloud Run service | `selfserve-backend-qa` | `selfserve-backend-staging` | `selfserve-backend-prod` |
| Firebase project | `selfserve-qa` | `selfserve-staging` | `selfserve-prod` |
| GitHub Environment | `qa` | `staging` | `production` |
| Deploy trigger | push to `main` (auto) | tag/promotion (1 approver) | tag `v*` (2 approvers) |

A single `<env>` value drives all config: `APP_ENV` → `app.config.ts` (mobile); `SPRING_PROFILES_ACTIVE` (backend). AR suffixes illustrative — confirm copy with MoE/DGA. EAS auto-links build profile → channel → branch of the same name, so identical naming is the path of least resistance.

## 2. Branching & protection (trunk-based, mandatory)

- One long-lived, always-releasable branch `main`; short-lived feature branches (<1–2 days), **squash-merge**.
- Incomplete work behind **feature flags**; **no** `develop`/`release`; releases via **tags**; transient `hotfix/*` only.
- **Branch protection on `main`:** require PR + ≥1 approval (dismiss stale); **CODEOWNERS** per path; required status checks; linear history; no force-push; conversation resolution; signed commits recommended.
- **Required checks** — Backend: `lint`, `typecheck(compile)`, `unit+integration tests`, `build image`. Mobile: `typecheck`, `lint (incl. max-lines 300)`, `unit tests`, `build (dry)`. Shared: `contracts / openapi-drift`.
- Conventional-commit **PR titles** (CI title-lint); **Husky + lint-staged** pre-commit; **commitlint** on `commit-msg`.

## 3. Monorepo layout (default) vs polyrepo

```
/
├── apps/mobile/          # React Native (Expo)
├── services/backend/     # Spring Boot modular monolith
├── packages/contracts/   # OpenAPI 3 spec + generated TS client
├── infra/                # IaC: Cloud Run, Cloud SQL, WIF/IAM, KMS, per-env config
├── .github/workflows/    # backend.yml, mobile.yml, contracts.yml, promote-*.yml
├── .github/CODEOWNERS
├── docs/                 # architecture, ADRs, runbooks, migration blueprint
└── .husky/               # pre-commit, commit-msg
```

**Monorepo rationale (§3.1):** single source for the shared contract; identical env naming enforced in one place; atomic cross-cutting PRs; one CI/CODEOWNERS/protection policy. **Path filtering** keeps pipelines independent: `backend.yml` triggers on `services/backend/**` + `packages/contracts/**`; `mobile.yml` on `apps/mobile/**` + `packages/contracts/**`.

**Polyrepo trade-off (§12.1, default = monorepo):** polyrepo gives independent access control/cadence but makes contract sync cross-repo (drift risk) — for a POC that shares contracts/env naming/CI, monorepo wins. Revisit only if org-level access control becomes a hard requirement.

## 4. Backend CI/CD (`backend.yml`)

PR = build+test only; push to `main`/tags = build → deploy.
1. Checkout + JDK 25 (Temurin) + Maven cache.
2. Lint/static analysis (Spotless/Checkstyle); compile = typecheck.
3. Unit tests (JUnit 5 + Mockito).
4. Integration tests (Spring Boot Test + **Testcontainers PostgreSQL**); JaCoCo gate.
5. **OpenAPI export** → artifact + contract-drift feed.
6. **Multi-stage Docker** (Java 25 runtime, minimal/distroless), tag SHA + env.
7. **WIF auth** (`google-github-actions/auth`, `id-token: write`) — **no SA JSON keys**.
8. Push to **Artifact Registry** (KSA region preferred).
9. **Deploy to Cloud Run** per env (`SPRING_PROFILES_ACTIVE`, Secret Manager mounts, health probes; Flyway runs on startup).
10. Smoke check `/health` readiness; fail deploy on non-200.

**Per-env gating** via GitHub Environments (`qa` auto; staging/production required reviewers). **WIF hardening:** `attribute_condition` pins `assertion.repository_owner` + `assertion.repository`; production SA additionally requires tag ref `refs/tags/v*`; separate least-privilege SA per env.

## 5. Mobile CI/CD (`mobile.yml`)

PR = install→typecheck→lint→tests (+dry build); push/promotion = build+update+submit non-prod.
1. Install (Node + pnpm/npm cache, `expo`/`eas-cli`).
2. Typecheck (`tsc --noEmit`).
3. Lint (ESLint + Prettier, **incl. `max-lines` 300** + import/boundary rules).
4. Unit tests (Jest + RNTL + MSW); coverage thresholds.
5. **Contract-sync check** (generated client vs `packages/contracts`; fail on drift).
6. **EAS Build per env** (`eas build --profile <env>`); config from dynamic `app.config.ts` keyed on `APP_ENV`; EAS env vars/secrets per profile (no committed `.env`); Firebase config injected at build.
7. **EAS Update** to matching channel (`eas update --channel <env>`); bump runtime version on native changes so OTA never ships incompatible JS.
8. **Store submission (non-prod):** `eas submit` → **TestFlight internal** + **Google Play internal track**. Production is gated/explicit.

Auth via `EXPO_TOKEN` (Actions secret); store credentials as EAS/Actions secrets, never in repo.

## 6. Promotion / release

```
PR → squash-merge to main
   → AUTO deploy backend qa + EAS build/update qa + TestFlight/Play internal
   → PROMOTE staging  (GitHub Env "staging", 1 reviewer; tag staging-<n>)
   → PROMOTE production (GitHub Env "production", 2 reviewers; tag v<x.y.z>)
```

- **Promotion = same artifact, new target.** Backend re-tags + deploys the **same image digest** (no rebuild). Mobile uses **OTA within the same runtime version**; a **store build** only when native/runtime version changes.
- **Rollback:** backend redeploy previous digest; mobile `eas update:rollback` / republish prior good update, or promote a prior store build.
- **Hotfix:** transient `hotfix/*` off the release tag → PR to `main` → expedited promotion.

## 7. §12 decisions touching DevOps

| # | Decision | Default | Rationale |
|---|---|---|---|
| 12.1 | Monorepo vs polyrepo | **Monorepo** | Shared contract + env naming + single CI; path-filtered pipelines stay independent. |
| 12.9 | Namespace `com.selfserve.platform` vs `sa.gov.moe.*` | **Keep `com.selfserve.platform`** (user-fixed), reversible | Load-bearing across bundle id/package/base package/Artifact Registry/Firebase. **Decide before first store submission** — change after submission forces new app records + re-enrollment. If MoE mandates gov domain, apply consistently to all 3 env identifiers + backend base package. |

Adjacent: 3 Firebase projects (12.4); shared Cloud SQL qa+staging, isolated prod (12.3); verify `me-central2` per service (12.6).

## 8. Top risks

1. Identifier drift across surfaces → single `<env>` value; CI assertion checks `app.config.ts`/`eas.json`/Spring profiles/Cloud Run names against the canonical matrix.
2. EAS runtime-version mismatch shipping broken OTA → policy: native/SDK changes bump runtime version; OTA only within same runtime version; validate staging before production.
3. WIF misconfig / confused-deputy → pin owner+repo (immutable IDs), restrict prod to tag refs, least-privilege SA per env.
4. Secrets leakage → no `.env`; EAS/Secret Manager/Actions; build-time Firebase injection; secret-scanning + push protection.
5. Testcontainers/Docker unavailable on runners → Docker-enabled runners, image caching, treat integration tests as required.
6. Promotion rebuilds instead of re-promoting tested artifact → promote same digest/update.
7. KSA region service gaps (`me-central2`) → verify per service; document fallback.
8. Namespace change after store submission → resolve before first submission.

## 9. Definition of Done

See `docs/ACCEPTANCE.md` §DevOps.

**Sources:** [How EAS Update works](https://docs.expo.dev/eas-update/how-it-works/) · [EAS branches & channels](https://docs.expo.dev/eas-update/eas-cli/) · [eas.json build profiles](https://docs.expo.dev/build/eas-json/) · [EAS env vars](https://docs.expo.dev/eas/environment-variables/usage/) · [google-github-actions/auth](https://github.com/google-github-actions/auth) · [GCP keyless auth from GitHub Actions](https://cloud.google.com/blog/products/identity-security/enabling-keyless-authentication-from-github-actions) · [GitHub OIDC in GCP](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-google-cloud-platform)
