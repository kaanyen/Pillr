# Build phases — required vs completed

This file tracks what **`the_pillr_build_doc.md`** calls for versus what exists in the repo. Update it when a phase or milestone changes.

**Legend:** ✅ done · 🟡 partial · ⬜ not started

---

## Phase 1 — Foundation (`the_pillr_build_doc.md` §13)

| Area | Build doc asks for | Status / notes |
|------|-------------------|----------------|
| **1.1 Project setup** | Flutter project, dependencies (§3), folder structure (§17) | ✅ |
| | App icons + splash (iOS, Android, Web) | ✅ `flutter_launcher_icons` + `flutter_native_splash`; source `assets/branding/app_icon.png`. |
| | Display name “Pillr” | ✅ Android `@string/app_name`; iOS `CFBundleDisplayName`; web `<title>` + manifest `name`. |
| | Flavors / dev / staging / prod | ✅ **Android:** Gradle `development` / `staging` / `production` (launcher label only; same `applicationId` + one `google-services.json`). **`APP_ENV`** via `--dart-define` + `AppEnvironmentConfig`. **iOS:** no Xcode schemes yet (optional). |
| **1.2 Firebase** | Auth, Firestore, Storage, FCM, Analytics, Crashlytics, platform configs, `main.dart` init | ✅ App initializes Firebase (`firebase_options.dart`, `ensureFirebaseInitialized`). **Analytics:** `logPillrAppOpen()` after init. **Crashlytics:** native only (not web). **Operational:** enable products and upload platform configs in Firebase console as needed. |
| **1.3 Design system** | Colors, typography, spacing, theme, listed widgets | ✅ |
| **1.4 Navigation** | GoRouter, guards, adaptive shell, routes | ✅ |
| **1.5 Auth (subsection)** | Login, logout, persistence, Riverpod auth, errors, password reset | ✅ Email/password login, forgot password (`sendPasswordResetEmail`), `humanizeAuthException`, sign-out in shell, `authState` stream. |
| **1.6 Invites** | Cloud Functions + join UI + invitations + send dialog | ✅ **Repo:** `functions/src/index.ts` — `validateInviteCode`, `completeRegistration`, `generateInviteCode`. **App:** join flow, invitations table + pagination, send dialog. **Deploy:** run `firebase deploy --only functions` for your project. |
| **1.7 Multi-tenancy** | `user_church_index`, scoped queries, rules deployed | ✅ **App:** index-driven providers and church-scoped repositories. **Rules:** `firestore.rules` in repo (matches §8 patterns). **Deploy:** `firebase deploy --only firestore:rules`. |

---

## Phase 1.5 — Post–Phase 1 review (gap closure)

| Item | Status |
|------|--------|
| Root `/`, role redirects, invitations pagination, branding, `APP_ENV`, this doc | ✅ |

---

## Phase 2 — Core features (`the_pillr_build_doc.md` §14)

| § | Area | Status |
|---|------|--------|
| **2.1** | Partnership arms — list, CRUD, toggle, Firestore | ✅ `ArmsScreen` + `ArmsRepository` + `partnership_arms` collection. 🟡 Activity logging on arm actions not wired yet (see §2.1 build doc). |
| **2.2** | Partnership periods | ⬜ Placeholder screen |
| **2.3** | Partner management | ⬜ Placeholder / list TBD |
| **2.4** | Entry recording | ⬜ Placeholders |
| **2.5** | Approval workflow | ⬜ |
| **2.6** | Entry edit / resubmission | ⬜ |
| **2.7** | Real-time streams app-wide | 🟡 Streams used where data exists (e.g. arms, invites); not yet all Phase 2 screens |

---

## Phase 3 — Roles, dashboards, leaderboard (`the_pillr_build_doc.md` §15)

| Area | Status |
|------|--------|
| Role dashboards, leaderboard, goals, partner profile, admin logs, full permission matrix | 🟡 Shell + placeholders / partial UIs; not full §15 behavior |

---

## Phase 4 — Polish & excellence (`the_pillr_build_doc.md` §16)

| Area | Status |
|------|--------|
| Exports, reports, duplicate detection, church branding in settings, 2FA, advanced notifications, performance, a11y, onboarding, production readiness | ⬜ |

---

### Android builds after flavors

Use a flavor for every **Android** build/run, for example:

`flutter run --flavor development` or `flutter build apk --flavor production`.

VS Code: **Pillr (Android, development)** (etc.). Web and generic **device** configs do not pass `--flavor` (use for iOS/desktop or Chrome).

---

*Last updated: Phase 1 items closed in repo; Phase 2.1 partnership arms CRUD implemented; Android Gradle flavors + Analytics app-open + web manifest.*
