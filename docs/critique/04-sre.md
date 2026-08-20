# Site Reliability Engineer — Critique

**Discipline grade: HIGH**

Reviewed: `lib/main.dart`, `functions/src/`, `firebase.json`, `docs/BACKUP.md`, `docs/RELEASE.md`, CI workflows.

The reliability question for a serverless Firebase app is not "will the servers stay up" — Google handles that. It is: **when something breaks, how long until you know, and how long until you can fix it?** Right now the answer to the first question is "when a pastor emails you," and there is no written answer to the second.

---

## CRITICAL — The deployed platform has no error reporting

`lib/main.dart:31-39`

```dart
if (!kIsWeb) {
  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(kReleaseMode);
  FlutterError.onError = ...
  PlatformDispatcher.instance.onError = ...
}
```

The `!kIsWeb` guard is technically correct — `firebase_crashlytics` genuinely has no web implementation, and the comment explains the blank-page failure it prevents. The problem is what follows from it.

`firebase.json` configures Hosting from `build/web`. `.firebase/hosting.YnVpbGQvd2Vi.cache` shows web deploys have actually happened. Web is your live surface, and on web there is **no crash reporting, no `FlutterError.onError` handler, and no `PlatformDispatcher.onError` handler at all**.

A null-check exception in the entry approval screen produces a red box for the user and complete silence for you. You will find out when someone tells you, if they bother.

**Fix:** add Sentry (`sentry_flutter` supports web) or a `recordError` callable that forwards to Cloud Logging. At minimum, register `FlutterError.onError` on web to log to console *and* an endpoint you can query. This is a few hours of work and it is the difference between operating a service and hoping.

## CRITICAL — There is no alerting on anything

Nothing in this repository configures a single alert.

- **Scheduled functions fail silently.** `scheduledFirestoreBackup` (weekly), `expireInviteCodes` (every 30 min), `dailyPendingDigest` (daily). If any stops running, nothing tells you. The backup is the frightening one: it could be broken for a month and the only symptom would be the absence of new objects in a bucket nobody looks at.
- **Function error rate:** unmonitored.
- **Firestore rule denials:** unmonitored. A spike in denials is your primary signal for both a broken deploy and an active attack.
- **Billing:** no budget alert. The unauthenticated `validateInviteCode` callable (see the security critique) runs a cross-tenant `collectionGroup` query for anyone on the internet who calls it. Combined with unbounded `snapshots()` listeners (see the DBA critique), your bill is a function of how interested a stranger is in your project.

**Fix:** Cloud Monitoring alert policies on function error rate and execution count (alert when a scheduled function's count drops to zero), a GCP budget alert, and a log-based metric on rule denials. This is an afternoon of console work, and it is the highest-leverage reliability spend available.

## HIGH — Backups cannot be verified and have never been restored

`functions/src/firestore_backup.ts:78-83` starts an export, logs the operation name, and returns. It never polls for completion. The Firestore export API accepts the request and does the work asynchronously; a failure after acceptance is invisible to this function, which has already logged success.

`docs/BACKUP.md` is a well-written document — retention, IAM, verification links, a manual export command, an explicit note that exports are for recovery and not single-document undo. What it does not contain:

- **A restore rehearsal.** Nobody has restored this data. An untested backup is a belief, not a control.
- **A measured RTO.** How long to bring a church back after a bad bulk import? Unknown.
- **A stated RPO.** Weekly exports mean **seven days of financial data loss** in the worst case. That is not stated anywhere, and no church has agreed to it.
- **Per-tenant restore.** The realistic incident is one church needing yesterday back. A full-database export cannot serve that without clobbering nine other tenants.

**Fix:** poll the LRO to completion and alert on failure. Move to daily. Rehearse a restore into a scratch project this quarter and write down the number. Add collection-filtered per-tenant exports.

## HIGH — No SLOs, no error budget, no dashboards

There is no statement anywhere of what "working" means for Pillr. No availability target, no latency target, no success-rate target for the money path.

Without an SLO, every incident is argued from scratch and every performance question is a matter of opinion. The specific ones worth defining:

- Entry submission success rate (this is the product).
- Entry approval → aggregate update latency (the trigger path with all the correctness problems).
- Invite email delivery rate — Resend failures are caught and `console.warn`ed at `:130` and swallowed. A user who never receives their code cannot join, and you will never know it happened.
- App cold-start on web (Flutter web payloads are large; `firebase.json` caches them well, but first load is still the number that decides whether people use this).

**Fix:** three SLOs, a Cloud Monitoring dashboard, and a monthly review.

## HIGH — Silent failure is the default error-handling pattern

The codebase consistently catches and swallows:

```ts
} catch (e) { console.warn("FCM notifyPastorsNewEntry:", e); }   // :715
} catch (e) { console.warn("FCM invite accepted:", e); }          // :544
} catch (e) { console.error("generatePeriodSummaryPdf", e); }     // :1028
if (!key) { console.warn("RESEND_API_KEY not set; skipping email."); return; }  // :108
```

And on the client, `activity_log_helper.dart:19`: `if (user == null || profile == null) return;`

Individually each is defensible — you should not fail an approval because a push notification failed. Collectively they mean the system degrades quietly and continuously. If `RESEND_API_KEY` were unset in production, **every invite email would silently vanish** and the only trace would be a `console.warn` in a log nobody has an alert on. Onboarding would appear to be broken for reasons nobody could explain.

**Fix:** keep the catch, but emit a metric alongside every one. `console.warn` is not observability; a counter you can alert on is.

## HIGH — No runbooks, no on-call, no incident process

`docs/` contains `BACKUP.md` and `RELEASE.md`. There is no `RUNBOOK.md`, no incident log, no escalation path, no documented rollback procedure.

Questions with no written answer today:

- A bad Firestore rules deploy locks every user out. How do you roll back? (There is no rules versioning in the repo and no previous-known-good artifact.)
- The aggregate totals are wrong for one church. What is the repair procedure? (There isn't one — see the DBA critique.)
- A tenant reports data they did not create. How do you investigate? (The audit log is client-written and forgeable — see the security critique.)
- Cloud Functions deploy half-succeeds. Which functions are live? (No deploy manifest, no version tracking.)

**Fix:** one `docs/RUNBOOK.md` with the five most likely incidents and the exact commands for each. Even a rough one changes the character of an outage.

## MODERATE — Single region, single project, no failover

`REGION = "us-central1"` is hardcoded in `functions/src/index.ts:12` and `firestore_backup.ts:4`. Firestore is in whatever region `thepillr2` was created in.

Two observations. First, a `us-central1` regional outage takes Pillr fully offline with no failover and no status page. That is an accepted risk at this scale — but it should be an accepted risk, not an unnoticed one.

Second, and more practically: this product is built for Ghana Cedis, defaults to `GHS`, and formats amounts with ₵. Your users are in West Africa and every request crosses the Atlantic twice. `europe-west1` would roughly halve round-trip latency for them. Nobody appears to have measured this.

**Fix:** measure real user latency from the target market. Consider `europe-west1`. Regardless, hoist the region into config rather than two hardcoded constants.

## MODERATE — Capacity and cost characteristics are unknown

No load test, no cost model, no per-tenant cost estimate. Given what the DBA critique found — unbounded listeners, per-rule document reads, an O(tenants) daily digest — the per-church cost curve is almost certainly superlinear, and nobody knows the constant.

**Fix:** model the cost of one church at 10, 100, and 1,000 entries. It is an hour of arithmetic and it will change your priorities.

## MODERATE — No health check, no status page

Hosting rewrites `**` to `index.html` (`firebase.json`), so *every* URL returns 200 with the Flutter shell — including paths that should 404. There is no `/healthz`, no synthetic monitoring, no uptime check. An external monitor pointed at this site cannot distinguish "healthy" from "JavaScript bundle is broken and the app renders a blank page."

**Fix:** a static `/health.json` excluded from the rewrite, plus a Cloud Monitoring uptime check.

## MINOR — Structured logging is absent

Every log statement is a plain string. No request IDs, no `churchId` field, no severity discipline. Correlating a user's report to a log entry means grepping by timestamp and hoping.

**Fix:** log JSON objects. Cloud Logging parses them into queryable fields for free.

## NOTHING — Done well

- **Hosting cache headers** (`firebase.json:44-74`) are genuinely well-configured: `no-cache` on `index.html`, `flutter_bootstrap.js`, and `manifest.json`; `immutable` with a one-year max-age on hashed assets, wasm, and canvaskit. This is exactly right for Flutter web and it is the single most competent piece of ops configuration in the repository.
- **Gen-1 Firestore triggers with an explanatory comment** (`:741`) — the note about Eventarc service-agent permission failures on first deploy is real, correct, and the kind of thing that saves the next person half a day.
- **`concurrency` + `cancel-in-progress`** in `ci.yml`.
- **Crashlytics gated on `kReleaseMode`** — correct; debug crashes should not pollute production data.
- **`connectivity_service.dart` + `offline_banner.dart`** — offline awareness is built in, which matters a great deal for the target market.

---

## Priority order

1. Error reporting on web. You are blind on your primary platform.
2. Alerts: function error rate, scheduled-function heartbeat, billing budget.
3. Poll backup operations to completion; alert on failure; move to daily.
4. Rehearse one restore. Write down the RTO.
5. `docs/RUNBOOK.md` covering the five likeliest incidents.
6. Metrics alongside every swallowed exception.
7. Three SLOs and a dashboard.
8. Health endpoint plus an uptime check.
9. Measure latency from Ghana; reconsider the region.
