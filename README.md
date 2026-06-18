# Self-Serve · الخدمة الذاتية

**Employee self-service mobile platform for the Ministry of Education (MoE), Saudi Arabia.**

Self-Serve is a **mobile-only** application (iOS + Android now, Huawei/HMS later) that lets MoE
employees verify their identity, enroll their face once, and perform geofenced check-ins. It is
**Arabic-first with full RTL** (English secondary) and follows the **DGA (Saudi Digital Government
Authority) design system**.

> Status: **Proof of Concept (POC)** with production-direction architecture.

## Core user journeys

1. **Sign in via Nafath** — identity verified server-side; Nafath returns NIC identity data.
2. **First-time sign-up** — a short form (pre-filled from NIC) shown only to unregistered employees.
3. **One-time face enrollment** — bound to the NIC-verified identity; never re-prompted on reinstall.
4. **Geofenced check-in** — camera scans the face and submits it with the current GPS location;
   the backend verifies face match **and** that the location is inside the allowed region.
5. **Employee profile** — NIC-sourced fields (national ID, first/last name) are read-only.

## Architecture

A **monorepo** sharing identity, environments, and a contract-first API:

| Part | Stack |
|------|-------|
| **Mobile app** | React Native (Expo), TypeScript strict, New Architecture + Hermes, Expo Router |
| **Backend** | Java + Spring Boot **modular monolith** (`com.selfserve.platform`), evolvable to microservices |
| **Contracts** | Backend publishes **OpenAPI 3**; mobile generates a typed client from it |
| **Infra** | GCP — Cloud Run, Cloud SQL (PostgreSQL), Secret Manager, Cloud KMS, Artifact Registry |

Proposed layout:

```
/apps/mobile          # React Native (Expo) app
/services/backend     # Spring Boot modular monolith
/packages/contracts   # OpenAPI spec + generated clients / shared types
/infra                # IaC, Cloud Run / Cloud SQL config, deployment manifests
/.github/workflows    # CI/CD pipelines
/docs                 # architecture, ADRs, runbooks, migration blueprint
```

## Environments

Three environments, named **identically** across backend, mobile, CI/CD, and GCP:
`qa` · `staging` · `production`. Production is rooted at `com.selfserve.platform`; non-prod use
suffixed identifiers so all three install side-by-side.

## Key principles

- **Trunk-based development** — single releasable `main`, short-lived feature branches, feature flags.
- **Nafath and the face ML model are reached only through the backend** (secrets stay off-device).
- **Face enrollment is one-time and reinstall-proof** — the backend is the source of truth.
- **PDPL-aware** — national ID, biometric, and location data are encrypted and consent-captured;
  KSA region preferred.
- **No secrets in the repo** — Secret Manager (backend), EAS secrets (mobile), GitHub Actions (CI).

## Status

This README seeds the repository. Implementation follows a planned, phased build (mobile, backend,
contracts, and infrastructure). See `/docs` for architecture and decision records as they land.
