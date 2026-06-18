# A. Mobile Architecture — Planning

> Domain plan for §1, §2, §4, §13.1.A. Planning only — no code. Volatile facts verified June 2026.

## A.0 Critical version correction (surfaced to user)

The requirements (§4.1, §11) pin **React Native 0.86**. Verification shows **Expo SDK 56 (released 21 May 2026, latest `expo@56.0.12`) bundles React Native 0.85 + React 19.2**, with the **New Architecture mandatory (no opt-out since SDK 55; legacy removed)** and **Hermes v1 as default engine**. There is no Expo SDK that ships RN 0.86. **Recommended default: stay on the Expo-managed RN 0.85 that SDK 56 bundles** — do not force RN 0.86, which would break the verified compatibility matrix. Logged as §12 open decision (item 11). This is the only material deviation from the prompt's pins.

## 1. Pinned versions (with sources)

| Package | Pinned version | New-Arch | Source |
|---|---|---|---|
| `expo` (SDK 56) | `56.0.12` | mandatory | Expo SDK 56 changelog; npm |
| `react-native` | `0.85.x` (Expo-bundled) | core | SDK 56 changelog (bundles RN 0.85, not 0.86) |
| `react` / `react-dom` | `19.2.0` | n/a | SDK 56 changelog |
| Hermes | v1 (default engine) | required | SDK 56 changelog |
| `expo-router` | SDK-56 bundled (`~6.x`) | yes | Expo Router SDK 55→56 migration docs |
| `expo-camera` | SDK-56 bundled (`~18.x`) | yes | Expo SDK reference / npm |
| `expo-location` | `56.0.15` | yes | npm |
| `expo-secure-store` | `56.0.4` | yes | npm |
| `expo-notifications` | `56.0.18` | yes | npm |
| `expo-localization` | SDK-56 bundled | yes | Expo Localization docs |
| `i18next` / `react-i18next` | `i18next ^25`, `react-i18next ^16` | JS-only | i18n 2026 guides |
| `@tanstack/react-query` | `^5.x` | JS-only | TanStack Query v5 RN docs |
| `zustand` | `^5.x` | JS-only | 2026 Expo stack references |
| `react-native-vision-camera` | `5.0.11` (fallback only) | full Fabric/TurboModules | vision-camera releases |
| `react-native-ssl-public-key-pinning` | latest | yes | library README |
| TS toolchain | TypeScript `~5.x` strict, ESLint 9 flat config, Prettier 3 | n/a | — |

> Pinning rule: use `npx expo install <pkg>` so every Expo module resolves to the SDK 56 `bundledNativeModules` version. Do NOT `npm install` Expo modules directly. Lock with exact `package-lock.json`; CI runs `npx expo install --check` as a gate.

## 2. Folder structure (`/apps/mobile`, feature-sliced clean architecture)

```
/apps/mobile
├── app.config.ts                 # dynamic, env-keyed (qa/staging/production)
├── eas.json                      # build profiles qa|staging|production
├── app/                          # Expo Router file-based routes ONLY (thin)
│   ├── _layout.tsx               # root: providers, i18n/RTL bootstrap, gating
│   ├── (auth)/                   # Nafath sign-in group (unauthenticated)
│   │   ├── _layout.tsx
│   │   ├── sign-in.tsx
│   │   └── nafath-waiting.tsx
│   ├── (enrollment)/             # one-time face enrollment + sign-up group
│   │   ├── _layout.tsx
│   │   ├── sign-up.tsx           # NIC pre-filled, read-only NIC fields
│   │   ├── consent.tsx
│   │   └── enroll-face.tsx
│   ├── (app)/                    # authenticated + enrolled group
│   │   ├── _layout.tsx
│   │   ├── check-in.tsx          # geofenced check-in (camera + location)
│   │   ├── profile.tsx
│   │   └── index.tsx
│   └── +not-found.tsx
├── src/
│   ├── features/                 # SELF-CONTAINED feature slices
│   │   ├── auth/                 # Nafath + session
│   │   │   ├── presentation/     # screens-as-components, hooks, UI
│   │   │   ├── domain/           # use-cases, entities, state machine
│   │   │   └── data/             # repositories, query keys, mappers
│   │   ├── enrollment/           # face enrollment + gating
│   │   ├── checkin/              # face capture + GPS submit
│   │   ├── profile/              # read-only NIC fields
│   │   └── notifications/        # push token registration
│   ├── core/
│   │   ├── network/              # HTTP client, interceptors, resilience
│   │   ├── config/               # env resolution, base URLs
│   │   ├── storage/              # expo-secure-store wrappers
│   │   ├── i18n/                 # i18next init, RTL/I18nManager manager
│   │   ├── providers/            # PushProvider, MapsProvider (HMS-ready)
│   │   └── navigation/           # gating guards, route group helpers
│   ├── design-system/            # DGA UI kit (tokens + components)
│   │   ├── tokens/               # color, typography(AR/EN), spacing, radii, elevation
│   │   ├── components/           # Button, Dialog, Toast, Field… (RTL-first)
│   │   └── theme/                # light/dark, RTL/LTR
│   └── api/                      # GENERATED typed client (from /packages/contracts)
└── tests/                        # Jest + RNTL + MSW; Maestro flows (optional)
```

**Slice boundaries:** each feature exposes a public `index.ts`; `presentation → domain → data` is one-directional. `eslint-plugin-boundaries` / `import/no-restricted-paths` forbids cross-feature deep imports and upward dependency violations.

**300-line hard rule:** ESLint `max-lines: ["error", { max: 300, skipBlankLines: true, skipComments: true }]` across all `.ts/.tsx`. Enforced in `lint-staged` (Husky pre-commit) AND as a required CI status check. Route files in `app/` stay thin (delegate to `src/features/*/presentation`). Companion rules: `max-lines-per-function`, `complexity`, `import/no-cycle`.

## 3. Key architecture decisions

- **Dev builds + CNG, never Expo Go.** `expo prebuild` (Continuous Native Generation) with config plugins for camera/secure-store/Firebase/pinning/HMS. `android/`/`ios/` are generated (gitignored); native config lives in `app.config.ts` plugins. EAS Build for all envs; documented local `prebuild` fallback.
- **New Architecture + Hermes:** mandatory/default in SDK 56. Hermes v1.
- **Navigation:** Expo Router typed routes, groups `(auth)`/`(enrollment)`/`(app)`. Gating in group `_layout.tsx` via `useGate()` reading (1) session from secure-store and (2) **server-provided enrollment status** (never local). Order: unauthenticated → `(auth)`; authenticated + not-enrolled → `(enrollment)`; authenticated + enrolled → `(app)`. Deep links honor the same guards.
- **State:** TanStack Query v5 = server state; Zustand = ephemeral UI/session state. No global mutable singletons.
- **Provider abstraction:** `PushProvider` and `MapsProvider` interfaces with FCM impls now and HMS stubs.
- **Camera choice:** default **`expo-camera`** (capture-then-backend; ML runs server-side). Keep capture behind a `FaceCapture` interface; **fallback `react-native-vision-camera@5.0.11`** if on-device liveness is pulled into POC scope.

## 4. New-Architecture dependency audit

| Dependency | Version | New-Arch status | Notes / fallback |
|---|---|---|---|
| react-native | 0.85 (SDK 56) | Core New Arch | RN 0.86 unavailable in any Expo SDK — use 0.85. |
| expo-router | SDK-56 bundled | Compatible | SDK 56 forbids importing `@react-navigation/*` directly. |
| expo-camera | ~18 | Compatible | Default capture lib. |
| react-native-vision-camera | 5.0.11 | Full Fabric/TurboModules/JSI | Fallback for on-device liveness/frame processors. |
| expo-location | 56.0.15 | Compatible | Foreground GPS for check-in; purpose strings + accuracy/timeout handling. |
| expo-secure-store | 56.0.4 | Compatible | Keychain/Keystore for JWT access+refresh. |
| expo-notifications | 56.0.18 | Compatible | **FCM does NOT deliver to HMS-only (no-GMS) Huawei devices** — abstract behind PushProvider. |
| expo-localization | SDK-56 bundled | Compatible | Device locale source for i18next. |
| i18next / react-i18next | ^25 / ^16 | JS-only | No native code. |
| @tanstack/react-query | ^5 | JS-only | Officially RN-supported. |
| zustand | ^5 | JS-only | No native code. |
| react-native-ssl-public-key-pinning | latest | Compatible | Prod only; disable dev network inspector via `expo-build-properties` in dev. |

No required dependency is New-Arch-incompatible. Only substitution: RN 0.85 (not 0.86).

## 5. §12 open decisions touching mobile (recommended defaults)

- **#1 Monorepo vs polyrepo** → **monorepo**.
- **#7 Liveness vendor** → **defer for POC**; ship consent + capture UX with a `FaceCapture` seam.
- **#9 Namespace** → keep **`com.selfserve.platform`** (+ `.qa`/`.staging`).
- **#10 DGA Figma availability** → **confirm both files accessible before design-system build** (blocking). Gaps filled from public DGA guidelines and flagged, never invented.
- **#11 Version pins** → **RN 0.85 / Expo SDK 56** as verified.
- **#4 Firebase projects** → **three**, config injected at build via EAS secrets.

## 6. Top risks

1. RN 0.86 expectation vs reality (0.85) → pin SDK-56 versions; `expo install --check`.
2. HMS push gap (FCM won't reach no-GMS Huawei) → PushProvider interface now; HMS later.
3. DGA Figma not delivered/incomplete → blocking; fall back to DGA public guidelines with flagged gaps.
4. Reinstall-proof gating must rely solely on backend status → never cache enrollment flag in secure-store.
5. Cert pinning vs dev tooling → prod-only pinning.
6. 300-line rule causing fragmentation → split by responsibility; thin routes.
7. RTL runtime flip needs reload → switch → persist → controlled reload with clear UX.

## 7. Definition of Done (mobile)

See `docs/ACCEPTANCE.md` §Mobile. Highlights: EAS dev builds for all 3 envs installable side-by-side; New Arch + Hermes confirmed; `max-lines=300` enforced; feature-sliced structure; all POC screens Arabic-first + RTL from DGA tokens; navigation gated by server enrollment status; full networking/resilience layer; runtime EN⇄AR switch; tokens in secure-store only; generated typed client with drift gate; tests for all §4.10 targets; HMS-ready provider seams.

**Sources:** [Expo SDK 56 changelog](https://expo.dev/changelog/sdk-56) · [Expo New Architecture guide](https://docs.expo.dev/guides/new-architecture/) · [Expo Router SDK 55→56](https://docs.expo.dev/router/migrate/sdk-55-to-56/) · [vision-camera releases](https://github.com/mrousavy/react-native-vision-camera/releases) · [TanStack Query RN](https://tanstack.com/query/v5/docs/framework/react/react-native) · [Expo push services / HMS limitation](https://docs.expo.dev/guides/using-push-notifications-services/)
