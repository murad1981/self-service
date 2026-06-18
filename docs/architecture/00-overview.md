# Architecture Overview & Index

Planning artifacts for **Self-Serve / الخدمة الذاتية** — MoE (KSA) employee self-service platform. Produced by the §13 planning phase: seven parallel domain planning agents + a verification/critic pass. **No application code yet** (per §13.4 gate).

## Domain plans

| | Domain | File |
|---|---|---|
| A | Mobile architecture | [A-mobile.md](./A-mobile.md) |
| B | Backend architecture & gap-fill | [B-backend.md](./B-backend.md) |
| C | Security, identity & compliance | [C-security-compliance.md](./C-security-compliance.md) |
| D | Environments & DevOps | [D-devops-environments.md](./D-devops-environments.md) |
| E | GCP infrastructure & cost | [E-gcp-infrastructure.md](./E-gcp-infrastructure.md) |
| F | Integration & contract | [F-integration-contract.md](./F-integration-contract.md) |
| G | Testing & quality | [G-testing-quality.md](./G-testing-quality.md) |

## Consolidated artifacts (§13.3)

- [../PLAN.md](../PLAN.md) — consolidated phased implementation plan + build order
- [../DECISIONS.md](../DECISIONS.md) — ADR/decision log + all §12 open decisions with recommended defaults
- [../RISKS.md](../RISKS.md) — risk register
- [../ACCEPTANCE.md](../ACCEPTANCE.md) — definition of done / acceptance criteria per deliverable
- [../VERIFICATION.md](../VERIFICATION.md) — §13.2 verification/critic report + remediation status

## Pinned technology (verified June 2026)

| Layer | Pin | Note |
|---|---|---|
| Mobile | **Expo SDK 56.0.12 / React Native 0.85 / React 19.2 / Hermes v1** | ⚠ Prompt said RN 0.86 — **does not exist in any Expo SDK**; pinned the SDK-56-bundled RN 0.85 (ADR-002 / §12.11). New Arch mandatory. |
| Backend | **Java 25 LTS / Spring Boot 4.0.7** (4.1.0 optional bump) | springdoc 3.0.3, Resilience4j `-spring-boot4` starter, Bucket4j 8.19.0, Flyway 11 (needs Boot-4 starter + postgresql module), Testcontainers 2.0.5, Firebase Admin 9.9.0 |
| Infra | **GCP me-central2 (Dammam)** | All required services available; **gated by CNTXT reseller + Invoiced Billing** (HIGH risk). Fallback me-central1 (Doha, weaker PDPL). |
| Contract | **OpenAPI 3.1** via springdoc → `openapi-typescript`+`openapi-fetch`+`openapi-react-query` | Two drift gates. |

## Top headline items for the user

1. **RN 0.86 → 0.85** version correction (verified, logged).
2. **CNTXT / me-central2 procurement gate** — blocking external dependency for KSA residency.
3. **Nafath licensing** (provider + TCC license + sandbox credentials) — blocking for the identity flow.
4. **DGA Figma file access** — blocking for the design-system build.
5. **Face ML host** reconciled to Cloud Run model service in me-central2 (ADR-004).
