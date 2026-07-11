# Verification / Critic Report (§13.2)

A dedicated verification agent red-teamed the consolidated plan against the §13.2 checklist, §11 non-negotiables, and §12 open decisions. This document records the result and the remediation status of every finding.

## Method

The critic judged each checklist item **COVERED / PARTIAL / GAP**, citing the responsible domain plan, and was explicitly tasked to hunt for omissions, cross-domain contradictions, and requirement misreadings, plus three named flags (Face ML host contradiction, RN 0.86 vs 0.85, CNTXT/me-central2 gate).

## Verdict

**Initial result: CONDITIONAL FAIL** — no gaps in *feature coverage* (every §13.2 item and all 13 §5.1 gap-fills addressed; both critical behaviors robustly covered), but the gate did not clear on two grounds §13.4 cares about: one internal contradiction and two incompletely-surfaced §12 decisions.

**After remediation (this document + `DECISIONS.md`): PASS** — all findings are resolved as decision-log/documentation edits (no re-architecture). The one external blocker (CNTXT/me-central2) is correctly diagnosed and escalated, which §13.4 treats as a surfaced decision rather than a plan gap.

## §13.2 checklist — coverage summary

| Checklist item | Verdict |
|---|---|
| Client = MoE, mobile-only, no web surface / no CORS | COVERED |
| Three environments named identically; bundle id == package per env | COVERED |
| Trunk-based development with enforced protections | COVERED |
| Mobile: modular architecture | COVERED |
| Mobile: 300-line rule | COVERED (triple-enforced) |
| Mobile: New Arch + Hermes | COVERED |
| Mobile: Expo dev builds (not Expo Go) | COVERED |
| Mobile: HMS-readiness | COVERED |
| Mobile: networking/resilience layer | COVERED |
| Mobile: DGA design system from Figma | COVERED *(after remediation — see F1)* |
| Mobile: Arabic-first runtime switch + RTL | COVERED |
| Mobile: POC screen set | COVERED |
| Mobile: tests | COVERED |
| One-time reinstall-proof enrollment, backend source of truth | COVERED |
| Geofenced check-in verifies face + location server-side | COVERED |
| Face / Nafath / ML reached only via backend | COVERED |
| Nafath returns NIC; first-time detection by national-ID registration | COVERED |
| NIC fields read-only end-to-end | COVERED |
| Backend: Appendix A baseline | COVERED |
| Backend: all 13 §5.1 gap-fills | COVERED |
| Secrets handling (no repo secrets; Secret Manager/EAS/Actions/WIF) | COVERED |
| GCP cost constraints + avoid-list | COVERED |
| OpenAPI contract + mobile codegen | COVERED |
| Correlation IDs end-to-end | COVERED |
| All §12 open decisions surfaced with defaults | COVERED *(after remediation — see F2/F3)* |

## Findings & remediation status

| # | Finding | Severity | Status |
|---|---|---|---|
| **F1** | **Face ML host contradiction** — Backend (B) defaulted to Vertex AI; GCP (E) + Integration (F) defaulted to Cloud Run model service. The one genuine internal contradiction. | Major (resolvable) | **RESOLVED** — reconciled to **Cloud Run model service in me-central2** behind `FaceMlProvider` (**ADR-004**); B's Vertex AI note overridden. Rationale logged (cost + PDPL residency + avoid-list). |
| **F2** | **§12.8 geofence definition** only partially surfaced — radius/polygon model + check-in retention not stated as a decision with a default. | Minor | **RESOLVED** — `DECISIONS.md` §12.8: admin-managed, **CIRCLE for POC + POLYGON-ready (JSONB)**, **check-in retention 90 days** (configurable, PDPL-minimized). |
| **F3** | **§12.10 DGA Figma availability** not surfaced as an open decision; UI-kit scope did not explicitly state components/patterns + WCAG AA (only tokens). | Minor | **RESOLVED** — `DECISIONS.md` §12.10 added (Figma access is **blocking**; fallback = public DGA guidelines + flag gaps + ask user). `ACCEPTANCE.md` §Mobile now requires **tokens + components + patterns + WCAG AA/RTL**. |
| **F4** | **CNTXT / me-central2 procurement gate** — me-central2 requires KSA reseller + Invoiced Billing; me-central1 fallback weakens PDPL residency. | High (external, not a coverage gap) | **ESCALATED** — `DECISIONS.md` §12.6/§12.6a (blocking) + `RISKS.md` R-01 (High). Region-agnostic POC code proceeds in parallel; in-region provisioning awaits user/MoE action. |
| **F5** | **RN 0.86 vs 0.85** — prompt said 0.86; verification found it does not exist in any Expo SDK. | Not a gap (process correct) | **LOGGED** — **ADR-002 / §12.11**: pinned SDK-56-bundled **RN 0.85**; deviation justified per §3/§12.11; pin kept under review at build time. |
| **F6** | **OpenAPI spec version** — B said springdoc 3.0.3 (library), F said emitted 3.1 (spec). Not a contradiction, but the emitted version should be pinned for codegen-tool support. | Trivial | **RESOLVED** — **ADR-006**: emitted spec pinned to **OpenAPI 3.1**; canonical-sorted before diff. |
| **F7** | **Swagger UI surface** — Appendix A Swagger UI is a doc surface; §4.12/§8 forbid leaking surface. | Trivial (hardening) | **RESOLVED** — **ADR-006**: Swagger UI is dev/QA-only, **access-controlled/disabled in production**. |

## Gate decision (§13.4)

With F1–F3 resolved in the decision log and F4 escalated as a surfaced blocking decision (proceeding on the me-central2 default with a documented me-central1 fallback), the plan **clears the §13.4 gate**: no open *major* gaps remain, and every §12 open decision is surfaced with a recommended default. Implementation may begin in the order in `PLAN.md`, with the four blocking items (`DECISIONS.md` Part 3) tracked and escalated to the user/MoE in parallel.
