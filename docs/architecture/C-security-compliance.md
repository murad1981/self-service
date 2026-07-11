# C. Security, Identity & Compliance — Planning

> Scope §4.4, §4.5, §4.6, §4.12, §5.1(1,2,6,7,8), §5.3, §5.4, §8. National-ID + biometric + location data. Planning only.

## 1. Threat model summary

| Asset | Primary threats | Mitigations |
|---|---|---|
| **Face templates/embeddings** (PDPL Tier-4) | Template theft → spoofing; raw-image leakage; unauthorized reuse | Store **embeddings, never raw images**; envelope-encrypt with **Cloud KMS** keyed to identity; least-privilege column access; never returned to client; audit reads; KSA storage |
| **National ID (NIC) + name** (Tier-4) | Enumeration, harvesting, tampering of read-only fields | Server-side immutability; RBAC-scoped endpoints; rate-limit Nafath initiate; audit; encrypt at rest |
| **Check-in location / events** | Spoof/replay; falsified attendance | **Client never trusted** — server evaluates geofence; bind to face match in one transaction; idempotency; correlation-ID; audit who/when/where/result |
| **JWT access + refresh** | Theft, replay, refresh reuse, priv-esc | Short-lived access; **rotating** refresh + **reuse detection** (family revocation); `expo-secure-store`; server-validated RBAC; revocation list (Caffeine→Redis seam) |
| **Nafath credentials** | Secret leakage, tenant impersonation | **Server-to-server only**; Secret Manager; never on device/repo; WIF for CI; rotation runbook |
| **Consent records** | Repudiation; forged consent | Server-side immutable consent record (subject, scope, version, timestamp, correlation-ID) before first capture; append-only |
| **Audit trail** | Tampering, insider deletion | **Append-only** (no UPDATE/DELETE grant); actor/action/target/timestamp/correlation-ID |
| **Mobile app / transport** | MITM, rooted-device tampering, RE | **Cert pinning (prod)**; optional root/jailbreak detection + obfuscation; TLS 1.2+; no secrets in JS bundle; least-privilege perms |
| **Sensitive endpoints** | Brute force, DoS, Nafath quota exhaustion | **Bucket4j** per-endpoint + per-identity; respect **Nafath ~10 MFA req/min/tenant** |

## 2. Nafath server-to-server sequence

1. Client → `POST /auth/nafath/initiate {nationalId}` (+ Correlation-ID); pre-check Bucket4j.
2. Backend → Nafath MFA request (App ID/Key from **Secret Manager**); respect tenant rate limit; 429 → `RATE_LIMITED` + retry-after.
3. Nafath → returns `transId` + **2-digit random**. Backend persists pending verification (transId ↔ correlationId ↔ nationalId hash, status=WAITING, TTL).
4. Backend → Client returns `transId` + 2-digit number to display; user approves the matching number in **Nafath app**.
5. User approves/rejects in Nafath.
6. **Resolution — webhook (preferred):** `POST /auth/nafath/webhook` (validate signature/allowlist, match transId, set COMPLETED/REJECTED). **Polling fallback:** `GET /auth/nafath/status/{transId}`.
7. On COMPLETED, backend retrieves **NIC identity data**.
8. **First-time detection:** is national ID already registered? Not → `firstTime=true` → sign-up form (NIC pre-filled) → finalize → trigger one-time face enrollment. Registered → issue JWTs → enter app.
9. **Statuses:** WAITING, COMPLETED, REJECTED, EXPIRED, ERROR (Resilience4j retry/CB), RATE_LIMITED. All bilingual. Audit every transition.

Licensing (§12.5): provider = **SDAIA direct or ELM**, **TCC license** required; credentials in Secret Manager per env.

## 3. Biometric / enrollment trust & gating

- **Backend = single source of truth** for "already enrolled." Client fetches status on every launch/login; **if enrolled, never re-prompt** — including after reinstall/new device. Navigation gated by server status (not local flags).
- **One-time enrollment**, triggered after first sign-up, **bound to NIC-verified identity** (not device) → reinstall-proof. **Idempotency key** prevents duplicates.
- **Store embeddings/templates, not raw images.** KMS envelope-encrypted, keyed to identity. Never leave the backend; client gets only match/no-match or check-in result.
- **Consent gate:** explicit biometric + location consent before first capture; server-side immutable consent record is a precondition.
- **Geofenced check-in trust:** single request carries face + GPS. Server (a) face-matches vs enrolled template AND (b) evaluates location vs **server-defined geofence**. Both must pass; event recorded. Replay/spoof mitigations: short-lived request, idempotency, correlation-ID, audit.
- **Liveness (§12.7):** design optional step now; **default = deferred for POC**; pipeline liveness-ready (vendor slots behind provider interface). Enable before production.
- **On-device (§4.12):** tokens in `expo-secure-store`; **cert pinning (prod)**; optional root/jailbreak detection + obfuscation; **optional device-biometric unlock (distinct from face identity)**; least-privilege permissions with purpose strings.

## 4. JWT / session / RBAC

- **Access token** short-lived (rec. **15 min**), stateless, carries roles.
- **Refresh token** longer-lived (rec. **30 days**), **rotation on every use**; **token family** + **reuse detection** → reuse of a rotated-out token revokes the whole family.
- **Revocation list** behind cache interface — **Caffeine now, Memorystore/Redis later** (also rate-limit counters). Logout revokes current family; per-device families so one logout doesn't kill all sessions.
- **Multi-device:** one family per device/session; list/revoke individually.
- **BCrypt** for any local/QA passwords; **RBAC** ADMIN/USER server-validated; stateless; no CORS.

## 5. PDPL controls matrix

PDPL enforceable since **14 Sep 2024**; biometric/national ID = **Tier-4 sensitive**; explicit consent + enhanced controls; **data residency** in KSA unless exempt; cross-border needs SDAIA-approved SCCs + risk assessment; biometric **retention minimized**.

| Data type | Classification | Encryption (rest/transit) | Residency | Consent | Retention |
|---|---|---|---|---|---|
| National ID + NIC name | Tier-4 | KMS / TLS | KSA (`me-central2`) | Implicit via Nafath; purpose recorded | While account active; delete on offboarding/erasure |
| Face template/embedding | Tier-4 biometric | **KMS envelope, embeddings only** / TLS | KSA | **Explicit, separate** before capture | Minimize; delete/anonymize on withdrawal; max TTL |
| Check-in location + events | Sensitive | KMS / TLS | KSA | **Explicit location consent** | Defined attendance/audit retention (§12.8); purge per policy |
| Verification/check-in/audit logs | Sensitive | KMS / TLS | KSA | Processing notice | Audit window then purge; audit append-only |

Cross-cutting: least-privilege per data class; KSA region (verify `me-central2` per service, §12.6); any cross-border processing (non-KSA ML host) is an open decision requiring SDAIA SCC/assessment.

## 6. Secrets & IAM

- **No secrets in repo** — secret-scanning + push protection in CI.
- **Backend runtime:** GCP **Secret Manager** (Nafath keys, DB creds, Firebase Admin, JWT signing key); KMS keys for encryption.
- **CI:** GitHub Actions encrypted secrets/environments; **Workload Identity Federation** over SA JSON keys.
- **Mobile builds:** **EAS secrets**; Firebase config injected at build, never committed.
- **Least-privilege IAM (per-env SAs):**
  - Runtime SA: `secretmanager.secretAccessor` (scoped), `cloudkms.cryptoKeyEncrypterDecrypter` (scoped), `cloudsql.client`, `logging.logWriter`.
  - CI/deploy SA (via WIF): `run.admin`/`run.developer`, `artifactregistry.writer`, `iam.serviceAccountUser` — no owner/editor, no secret access.
  - Bindings scoped to specific secret/key/service resources; 3 isolated env projects.

## 7. §12 decisions touching security

- **12.5 Nafath provider** → **ELM + TCC license** default; confirm MoE tenant/license (likely blocking).
- **12.7 Liveness** → **defer for POC**; pipeline liveness-ready; enable before production.
- **12.2 Face ML host (security angle)** → **KSA-region host (Cloud Run model service)** to keep biometric data resident; non-KSA triggers PDPL cross-border SCC.
- **12.6 KSA region** → `me-central2`; verify per service.
- **12.8 Geofence + retention** → server-managed (admin) geofence; explicit check-in retention TTL.

## 8. Top risks

1. **Nafath licensing/credentials unavailable** (TCC + provider tenant) — blocks identity flow; confirm with MoE early.
2. **KSA-region service gaps** (`me-central2`) → residency vs functionality; PDPL-compliant fallback.
3. **Biometric residency breach** if ML hosted outside KSA without SCC — Tier-4 violation.
4. **Liveness deferred** → check-in spoofable via photo/replay in POC; document limitation; gate production on liveness.
5. **Refresh-token theft on compromised device** → mitigated by rotation + reuse detection + family revocation; residual.
6. **Audit-trail tampering** → append-only DB grants; consider write-once export.
7. **Retention non-compliance** → automated purge jobs.

## 9. Definition of Done

See `docs/ACCEPTANCE.md` §Security/Compliance.

**Sources:** [PDPL transition ends 14 Sep 2024 — Morgan Lewis](https://www.morganlewis.com/pubs/2024/09/saudi-arabia-personal-data-protection-law-transition-period-ends-september-14) · [PDPL cross-border — King & Spalding](https://www.kslaw.com/news-and-insights/international-personal-data-transfers-under-saudi-arabias-data-protection-law) · [Saudi cross-border rules — Trade.gov](https://www.trade.gov/market-intelligence/saudi-arabia-ict-cross-border-data-transfer-rules-now-under-enforcement) · [Biometric privacy — Midad](https://midadadvance.com/understanding-saudi-arabias-biometric-data-privacy-regulations/) · [Nafath API (rate limit, transId) — azakaw](https://documentation.azakaw.com/docs/apis/core/nafath) · [SDAIA Nafath guide](https://sdaia.gov.sa/en/Services/ServicesGuidelines/SingleSignontoGovernmentPrivateServices.pdf) · [Nafath provider (ELM/SDAIA, TCC) — signit.sa](https://help.signit.sa/en/how-to-integrate-custom-nafath-provider)
