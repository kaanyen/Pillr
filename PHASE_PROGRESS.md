# Build phases — required vs completed

This file tracks what **`the_pillr_build_doc.md`** calls for versus what exists in the repo. Update it when a phase or milestone changes.

**Legend:** ✅ done · 🟡 partial · ⬜ not started

**Automated checks (run anytime):**

- `flutter analyze` — static analysis; should report no issues.
- `flutter test` — unit/widget tests in `test/`.
- `cd functions && npm run build` — TypeScript Cloud Functions compile.

---

## Phase 1 — Foundation (`the_pillr_build_doc.md` §13)

| Area | Status |
|------|--------|
| **1.1–1.7** | ✅ (see prior revisions; Android flavors, Firebase client, auth, invites, rules file, etc.) |

### How to confirm Phase 1

| Step | What to test | Pass criteria |
|------|----------------|---------------|
| **Project** | `flutter analyze` / `flutter test` | No errors; tests pass. |
| **Auth** | Log in, log out, wrong password, forgot password (valid email) | Redirects to shell after login; sign-out returns to login; errors are readable; reset email path runs without crash. |
| **Routing** | Open `/` (logged in / out), deep-link to `/login`, `/join`, a forbidden route as staff/admin | `/` → dashboard or login; incomplete registration → `/join`; role blocked from financial routes → dashboard. |
| **Invites** | Send invite, list invites, pagination | Invite appears; resend/delete works; no duplicate key errors in console. |
| **Firebase** | App starts on web + one mobile target | Firebase initializes; no blank web page from Crashlytics on web. |
| **Branding** | Cold start (mobile/web) | Splash/launcher present; no crash on launch. |
| **Android env** | `flutter run --flavor development` | App installs; launcher label shows flavor (e.g. `Pillr (dev)`). |

---

## Phase 1.5 — Post–Phase 1 review

| Item | Status |
|------|--------|
| Gap-closure items | ✅ |

### How to confirm Phase 1.5

| Step | What to test | Pass criteria |
|------|----------------|---------------|
| **Root `/`** | Visit `/` authenticated | Lands on dashboard (or join if no index). |
| **Role guards** | As staff/admin, open URLs for partners-only or pastor-only routes | Redirect to `/dashboard` where expected. |
| **Invitations pagination** | Many invites | Change rows per page; page controls move through data. |
| **`APP_ENV`** | Debug run | Console shows `APP_ENV=...` in debug mode (`main.dart`). |

---

## Phase 2 — Core features (`the_pillr_build_doc.md` §14)

| § | Build doc asks for | Status / notes |
|---|-------------------|----------------|
| **2.1** | Arms table, CRUD, delete, toggle, Firestore, activity logging | ✅ `ArmsScreen` + `ArmsRepository` + `logPillrActivity` on create/update/toggle/delete. |
| **2.2** | Periods list, date range create/edit, delete if no entries, single active via `activatePeriod` CF, activity logging | ✅ `PeriodsScreen`, `PeriodsRepository`, callable **`activatePeriod`** (`functions/src/index.ts`), client logging on create/update/delete/activate. |
| **2.3** | Partners list (search/filter), create/edit, pastor deactivate, searchable partner UX, activity logging | ✅ `PartnersListScreen`, `PartnerFormDialog`, `PartnerProfileScreen` + history; search + inactive filter; logging on create/update. |
| **2.4** | Entry form, partner picker + inline create, pending entries, push notify pastor, activity log | ✅ `EntryFormScreen` (`/entries/new`), partner sheet + create partner, **`onEntryCreated`**, **`My entries` / all entries** lists. |
| **2.5** | Pending queue, review UI, approve/decline, **`onEntryStatusChange`** (counters + notify staff), activity logging | ✅ `PendingApprovalsScreen`, `/approvals`, badge; **`EntryDetailScreen`** approve/decline; **`onEntryUpdated`** totals + FCM to author. |
| **2.6** | Staff edit pending/declined → pending; edit history; pastor edit | ✅ `/entries/:id/edit` + **`EntryFormScreen(entryId)`**; detail shows **Edit history**; **`partnerId`** updates on save. |
| **2.7** | Streams, badge live, dashboard stats | ✅ **`pendingApprovalCountProvider`** sidebar badge; pastor + staff dashboards use **live Firestore streams** (counts, totals, mix bar). |

### How to confirm Phase 2 (manual QA)

After **`firebase deploy --only firestore:indexes,firestore:rules,functions`**, run these in order (or as far as your roles allow).

| § | What to test | Pass criteria |
|---|----------------|---------------|
| **Deploy** | Deploy completes; no index errors in Firebase console when running queries | Indexes build; rules deploy; functions show new versions. |
| **2.2 Periods** | Pastor: create two periods, activate one, try delete period **with** an entry referencing it (later) vs **without** | Exactly one `isActive`; delete blocked when entries exist; activate shows confirmation. |
| **2.1 Arms** | Pastor: add arm, toggle inactive, edit, delete | Table updates live; Firestore `partnership_arms` matches UI; activity log rows created (if you inspect `activity_logs`). |
| **2.3 Partners** | Staff: add partner; search/filter; open profile | Partner appears in list; profile shows history (empty until entries). Pastor: edit partner, deactivate | Inactive hidden unless “Show inactive”; edit persists. |
| **2.4 Entries** | Staff: `/entries/new` — pick partner (or create inline), choose arm, submit | New row in **My entries** with status **pending**; document in `churches/{id}/entries` has `churchId`, snapshots, `status: pending`. |
| **FCM pastor** | Pastor user has `fcmToken` on `churches/.../users/{uid}` (optional on web) | After new entry, **onEntryCreated** logs OK in Functions; device with token receives notification (or skip if no token). |
| **2.5 Approvals** | Pastor: `/approvals` — badge count matches pending list; open entry → **Approve** | Entry **approved**; partner/period totals increase (check Firestore); staff receives FCM if token set. **Decline** with reason | status **declined**; reason stored; staff notified. |
| **2.5 Staff list** | Staff: **Entries** shows only own rows; Pastor: see all | Query scope matches role. |
| **2.6 Delete** | Staff: open own **pending** entry → delete | Entry removed; rules allow. |
| **2.6 Edit** | Staff: open **declined** or **pending** own entry → **Edit & resubmit** → change amount → save | Status **pending**; **Edit history** shows prior values; pastor sees entry in queue. Pastor: **Edit** on any entry | Changes persist; history row added. |
| **2.7 Live** | With two browser windows (pastor + staff), staff submits entry | Pastor pending list and badge update without refresh. |
| **2.7 Dashboards** | Pastor and staff open **Dashboard** | Stat cards match Firestore (pending count, approved totals, entry mix / staff totals). |
| **Guards** | Staff opens `/approvals` (URL bar) | Redirect to dashboard. Admin opens `/entries` | Redirect per rules. |

### Automated / ops (Phase 2)

- Deploy **Firestore indexes**: `firebase deploy --only firestore:indexes` (updated for entries + goals queries).
- Deploy **rules**: `firebase deploy --only firestore:rules`.
- Deploy **functions**: `firebase deploy --only functions` (includes `activatePeriod`, `onEntryCreated`, `onEntryUpdated`).

---

## Phase 3 — Roles, dashboards, leaderboard (`the_pillr_build_doc.md` §15)

| Area | Status |
|------|--------|
| Role dashboards, leaderboard, goals UX, admin **activity log UI**, full matrix | 🟡 Shell + Phase 2 data paths; dashboards/leaderboard/goals screens still light vs §15; **`ActivityLogsScreen`** still placeholder. |

### How to confirm Phase 3 (when implemented)

| Step | What to test | Pass criteria |
|------|----------------|---------------|
| **Dashboards** | Pastor / staff / admin each open dashboard | Numbers match Firestore; pending count matches `/approvals`. |
| **Leaderboard** | Pastor opens leaderboard | Ranked data; scoped to church. |
| **Activity logs UI** | Admin opens `/logs` | Filterable list; reads from `activity_logs` only as rules allow. |

---

## Phase 4 — Polish & excellence (`the_pillr_build_doc.md` §16)

| Area | Status |
|------|--------|
| Exports, duplicate detection, church branding settings, 2FA, advanced notifications, performance, a11y, onboarding | ⬜ |

### How to confirm Phase 4 (when implemented)

| Step | What to test | Pass criteria |
|------|----------------|---------------|
| **Exports** | Generate PDF/CSV for each role | Files open; amounts in ₵; church branding if configured. |
| **A11y** | Screen reader / font scaling | Usable; contrast acceptable. |
| **Performance** | Large lists | Pagination/cursors; no jank on scroll. |

---

### Route notes

- **`/approvals`** — Pastor pending queue (staff/admin redirected).
- **`/entries/new`** — New entry form.
- **`/entries/:id`** — Entry detail (approve/decline/delete as rules allow).
- **`/entries/:id/edit`** — Edit entry (staff: pending/declined → resubmit; pastor: any).

### Android builds after flavors

Use `flutter run --flavor development` (etc.) for Android; see `.vscode/launch.json`.

---

*Last updated: Added per-phase testing / verification steps.*
