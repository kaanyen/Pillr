# Database Administrator — Critique

**Discipline grade: HIGH**

Reviewed: `firestore.indexes.json`, `firestore.rules`, `functions/src/index.ts`, `lib/features/*/data/*.dart`, `docs/BACKUP.md`.

The data model is sensible: `churches/{id}` as the tenant root, everything else as subcollections, a `user_church_index/{uid}` lookup for the rules layer. That is the right shape for multi-tenant Firestore and it was clearly thought about. What sits on top of it is not thought about with the same care.

---

## CRITICAL — Financial aggregates are non-idempotent

`functions/src/index.ts:663`

```ts
batch.update(partnerRef, {
  totalApprovedAmount: admin.firestore.FieldValue.increment(amount),
  entryCount: admin.firestore.FieldValue.increment(1),
});
```

This runs from `onEntryCreated` (`:743`) and `onEntryUpdated` (`:762`). **Firestore triggers are at-least-once.** Duplicate delivery is documented, expected behavior — not a rare failure — and there is no guard against it here. No processed-event marker, no `context.eventId` check, no compare-and-set on the entry document.

When a duplicate fires, a ₵500 donation becomes ₵1,000 in `partner.totalApprovedAmount`, `period.totalApprovedAmount`, and `goal.currentAmountCedis`. The entry document still says ₵500. Nothing reconciles them. Nothing alerts. A pastor eventually notices the leaderboard is wrong and has no way to find out why.

**Fix:** write an idempotency marker inside the same transaction — e.g. set `aggregatedEventId` on the entry doc and skip if it already matches. The batch must become a transaction for this to hold.

## CRITICAL — Deleting an approved entry never decrements the totals

`firestore.rules:100` permits pastors to delete any entry, including approved ones. `grep onDelete functions/src/index.ts` returns nothing.

Delete an approved ₵5,000 entry and the money stays in every aggregate forever. There is no compensating write and no path to recompute. This is not a race condition or an edge case — it is the ordinary result of the ordinary "this was entered twice, remove it" workflow, and it is the exact workflow most likely to occur.

**Fix:** an `onDelete` trigger that reverses the deltas when `status == 'approved'`. Better still, forbid hard deletes on approved entries entirely and use a `voided` status, which keeps the financial history auditable.

## CRITICAL — Editing an approved entry's amount corrupts the totals

`onEntryUpdated` (`:762`) handles exactly one transition:

```ts
if (before.status === "pending" && after.status === "approved") {
  await applyApprovalDeltas(churchId, after);
}
```

Meanwhile `firestore.rules:93` lets a pastor update *any* entry, with no field restrictions and no status guard. So:

- **approved → amount changed from 500 to 5000.** No delta applied. Totals stay at 500 while the entry reads 5000.
- **approved → declined.** No reversal. Money stays counted.
- **approved → partnerId changed.** The old partner keeps the credit; the new one never gets it.

Three routine pastor actions, three ways to silently desynchronize the books.

**Fix:** handle the full state machine. On any update to an entry whose before-or-after status is `approved`, compute `delta = after.approvedAmount - before.approvedAmount` and apply that, rather than pattern-matching one happy-path transition.

## HIGH — There is no reconciliation job

Given the three bugs above, aggregate drift is not a possibility — it is a certainty on a long enough timeline. There is no scheduled function that recomputes `totalApprovedAmount` from the underlying entries and compares. There is no drift metric. There is no repair tool.

This is the difference between "we had a bug and fixed the data" and "our historical financial totals are wrong by an unknown amount and always will be."

**Fix:** a nightly `reconcileAggregates` scheduled function that sums approved entries per partner/period/goal, compares to the stored aggregate, logs the delta, and alerts above a threshold. Run it in report-only mode first; you will learn a great deal from the first run.

## HIGH — Money is stored as a JavaScript number

`functions/src/index.ts:664`: `const amount = Number(entry.amountCedis ?? 0);`

`amountCedis` is a Firestore number, which is an IEEE-754 double. Currency in binary floating point accumulates representation error, and `FieldValue.increment` compounds it across thousands of additions. `0.1 + 0.2 !== 0.3` is a joke until it appears in a church's annual partnership report.

The field naming also fights you: `amountCedis` and `currentAmountCedis` hardcode Ghana Cedis, while `redeemBootstrapInvite` (`:280`) accepts an arbitrary `currency` and `currencySymbol` per church. You have a multi-currency product with single-currency field names and no stored currency code on the entry itself.

**Fix:** store integer minor units (`amountMinor: 50000` for ₵500.00) plus an explicit `currency: 'GHS'` on every monetary document. Migrating this later, across live tenants, will be considerably more painful than doing it now.

## HIGH — Unbounded real-time listeners

`lib/features/entries/data/entries_repository.dart:19`

```dart
return _entries(churchId).orderBy('createdAt', descending: true).snapshots()
```

No `.limit()`. This streams **every entry the church has ever recorded** to the client and keeps the listener open. `admin_dashboard_providers.dart:27` does the same to `churches/{id}/users` in order to compute `s.docs.length` — reading N documents to produce one integer, when `.count()` exists and costs a fraction.

At 100 entries this is invisible. At 50,000 it is a multi-megabyte initial sync on every screen open, billed per document read, on mobile connections in a market where data is not cheap.

To the repository's credit, `entries_repository.dart:86` does implement proper cursor pagination with `limit(pageSize + 1)`. The paginated path is correct; the streaming path bypasses it entirely.

**Fix:** `.limit(50)` on every `snapshots()` call. Use `.count()` aggregation queries for counts. Audit all 18 `snapshots()` sites — 15 have a `.limit()` somewhere in the file, which means roughly three do not.

## HIGH — Every rule evaluation costs billed document reads

`firestore.rules:15` — `getUserData()` performs `get(/user_church_index/$(uid))`. This is called by `isRole()`, `belongsToChurch()`, and `getUserChurchId()`, which appear in essentially every rule in the file. Compound conditions like `belongsToChurch(churchId) && isPastorOrAdmin()` invoke it multiple times per evaluation. Firestore caches within a single evaluation but not across the documents in a query.

Storage rules are worse: `storage.rules:5` does a cross-service `firestore.get()` on every single file read, and calls `userChurch()` twice in the write rule.

A paginated list of 50 entries can trigger tens of extra billed reads before returning a row. That is a permanent tax on every operation in the product.

**Fix:** custom claims. `request.auth.token.churchId` and `request.auth.token.role` cost nothing and are already available at rule-evaluation time. Set them in `completeRegistration` and `updateChurchMember`, which are the only two places membership changes.

## MODERATE — The index file is redundant and partly wrong

`firestore.indexes.json` defines 15 indexes, 11 of them on `entries`. Several are strict prefixes of others and are therefore dead weight — Firestore serves a query from any index whose fields are a prefix-compatible superset:

- `(createdBy ASC, createdAt DESC)` is covered by `(createdBy ASC, status ASC, createdAt DESC)`.
- `(status ASC, createdAt DESC)` is covered by `(churchId ASC, status ASC, createdAt DESC)` for the relevant queries.

More telling: three `entries` indexes lead with `churchId`. But `entries` is a subcollection under `churches/{churchId}` with `queryScope: COLLECTION` — the path *already* scopes the query to one church. That `churchId` field is either dead data denormalized into every entry document for no reason, or a leftover from a top-level-collection design that was refactored and never cleaned up. Either way you are paying storage and index-write cost on every entry for a field that no query needs.

Also: `church_bootstrap_invites` has `queryScope: COLLECTION` while `invite_codes` has `COLLECTION_GROUP` — correct in both cases given how they are queried, but worth a comment, because the asymmetry looks like a mistake and someone will "fix" it.

**Fix:** delete the redundant indexes; decide whether `entries.churchId` earns its place. Every index is a write-amplification cost on the hottest collection in the product.

## MODERATE — No TTL policies

`activity_logs` is append-only with `update` and `delete` both denied (`firestore.rules:141-142`) — good for auditability, but it means the collection grows without bound forever. `invite_codes` are marked `expired` by `expireInviteCodes` (`:608`) and then kept indefinitely. `platform_audit_logs` likewise.

Firestore TTL policies are declarative, free, and exist precisely for this.

**Fix:** TTL on `invite_codes` (30 days past expiry) and `church_bootstrap_invites`. For `activity_logs`, define a retention period that satisfies whatever compliance story you are telling churches, and archive to GCS beyond it.

## MODERATE — Denormalized name fields kept in sync by a trigger

`onPartnerWritten` (`:776`) maintains `fullName`, `fellowship`, `fullNameLower`, `fellowshipLower` — four fields derived from two. It also fires on its own writes (`onWrite` + `ref.update()`), which is a self-triggering loop; it terminates only because the second pass computes an empty patch and returns early. That is correct today and one careless edit away from an infinite recursion that bills by the invocation.

`activity_logs` stores `actorSnapshot` (name, role, email) inline. Defensible for an audit log — you want the historical value — but it is not documented as deliberate anywhere, so a future maintainer will "fix" the duplication.

**Fix:** add a guard comment and an explicit recursion check on the trigger. Document the `actorSnapshot` denormalization as intentional.

## MODERATE — Backups are weekly, fire-and-forget, and never restore-tested

`functions/src/firestore_backup.ts:71` — `schedule: "0 3 * * 0"`. Weekly. **Your RPO for financial data is seven days.**

`startFirestoreExport` POSTs to the export API, gets back a long-running-operation name, logs it, and returns. It never polls. If the export fails after acceptance — quota, IAM, bucket permissions — the function has already reported success and there is no alert. You would discover it during a restore.

`docs/BACKUP.md` is otherwise a good document: retention, IAM, verification steps, a manual export command. It has no restore rehearsal, no measured RTO, and no answer for the most common real-world request, which is not "the database is gone" but "one church needs last Tuesday back without touching the other nine tenants." A full Firestore export cannot do that.

**Fix:** daily, not weekly. Poll the operation to completion and alert on failure. Rehearse a restore into a scratch project and write down the measured RTO. For per-tenant recovery, add a `churches/{id}` collection-filtered export.

## MINOR — `expireInviteCodes` has no pagination

`:608` fetches every expired-and-pending invite in one `collectionGroup` query with no limit, then feeds a `BulkWriter`. Fine at current scale; it will eventually exceed memory or the function timeout, and the failure will be silent because there is no alert on scheduled functions.

## MINOR — `dailyPendingDigest` is O(tenants) with unbounded fan-out

`:1034` loops every church, issuing a `count()` and a `users` query each. Sequential, in one invocation, with a default timeout. At 500 churches this times out partway through and the churches late in the iteration order silently stop receiving digests.

**Fix:** fan out per tenant via Pub/Sub or Cloud Tasks.

## NOTHING — Correct as-is

- **Tenant-per-subcollection layout.** The right Firestore multi-tenancy pattern. Path-based isolation is far more robust than field-based filtering.
- **Cursor pagination** in `entries_repository.dart:86` with `limit(pageSize + 1)` for has-more detection. Textbook.
- **`redeemBootstrapInvite` transaction** (`:294`) — re-reads the invite inside the transaction before acting. Correctly prevents double redemption.
- **`fullNameLower` / `fellowshipLower`** for case-insensitive search. Firestore has no case-insensitive queries; this is the standard workaround.
- **`FieldValue.increment`** as the mechanism is right — the problem is idempotency and coverage, not the primitive.

---

## Priority order

1. Idempotency guard on `applyApprovalDeltas`.
2. `onDelete` handler for approved entries.
3. Full state-machine handling in `onEntryUpdated`.
4. Nightly reconciliation job, report-only first.
5. `.limit()` on all unbounded `snapshots()`; `.count()` for counts.
6. Custom claims to eliminate per-rule document reads.
7. Migrate money to integer minor units + explicit currency.
8. Daily backups, polled to completion, with a rehearsed restore.
9. Prune redundant indexes; resolve `entries.churchId`.
10. TTL policies on invite collections.
