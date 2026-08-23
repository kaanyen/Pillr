# Data Engineer — Critique

**Discipline grade: MODERATE**

Reviewed: `lib/features/entries/bulk_import/`, `functions/src/index.ts`, `firestore.indexes.json`, `lib/features/*/domain/`, `docs/BACKUP.md`.

This grades better than the other five disciplines for an honest reason: at this scale most data-engineering concerns are premature. There is no warehouse to build because there is no volume to warehouse. What is graded here is whether the *foundations* — schema contracts, type fidelity, ingestion quality, and a path off the operational store — will hold when there is. Two of those four will not.

---

## HIGH — Money is a float, end to end

`lib/features/entries/presentation/entry_form_screen.dart:431`
```dart
final amount = double.tryParse(_amount.text.replaceAll(',', ''));
```
`lib/features/entries/bulk_import/bulk_import_parser.dart:141`
```dart
amount = double.tryParse(cleaned);
```
`functions/src/index.ts:664`
```ts
const amount = Number(entry.amountCedis ?? 0);
```

A Dart `double` is IEEE-754 binary64. A Firestore number is the same. `FieldValue.increment` operates on it. Every layer of this pipeline represents currency in a format that cannot exactly represent 0.10.

For a single donation the error is invisible. For `partner.totalApprovedAmount` accumulated over thousands of `increment` calls it is not, and the place it surfaces is an annual partnership report a church presents to its congregation. "The system says ₵1,247,893.0000000002" is a credibility problem, not a rounding problem.

The naming compounds it. `amountCedis`, `currentAmountCedis`, `targetAmountCedis` hardcode one currency into the schema — while `redeemBootstrapInvite` (`:280`) accepts an arbitrary `currency` and `currencySymbol` per church, and `DEFAULT_CURRENCY_SYMBOL` (`:86`) maps GHS, USD, EUR, GBP. You have a multi-currency product whose field names assert a single currency, and no currency code stored on the entry itself. A USD church and a GHS church currently produce records that are indistinguishable once separated from their parent document.

**Fix:** `amountMinor: int` (minor units) plus a required `currency: string` on every monetary document. Do this before there is a second currency in production; the migration cost only rises.

## HIGH — There is no schema contract

Firestore is schemaless, which means the schema lives somewhere or it lives nowhere. Here it lives in three places that do not talk to each other:

1. Dart domain models in `lib/features/*/domain/` (`partner.dart`, `partnership_arm.dart`, `church_settings.dart`).
2. Ad-hoc object literals in `functions/src/index.ts` — `completeRegistration:504` writes a user document with 13 fields, none of them typed against anything.
3. `firestore.rules`, which validates almost nothing (see the security critique).

Nothing enforces agreement. `completeRegistration` writes `avatarUrl: null`, `fcmToken: null`, `lastLoginAt: null`; if the Dart model expects those non-null, or adds a fourteenth field, nothing catches the divergence until a user hits it.

`pubspec.yaml` includes `freezed_annotation` and `json_annotation` — the tooling for generated, validated models is already a dependency. It is being used partially at best, and there is no TypeScript counterpart at all.

**Fix:** define the schema once — JSON Schema or a shared spec — and generate Dart and TypeScript types from it. Failing that, hand-write TS interfaces in `functions/src/types.ts` and use them everywhere, so at least the compiler participates.

## MODERATE — Bulk import is the highest-risk ingestion path and has no server-side validation

`lib/features/entries/bulk_import/` is 16 files — parser, resolver, arm matcher, phone normalizer, session store, commit progress, an xlsx reader hand-rolled over `archive` + `xml`. It is the most substantial single feature in the app and the only bulk write path into the money table.

The client-side work is good. `bulk_import_resolver.dart` handles ambiguous partner matches, `bulk_import_arm_match.dart` does fuzzy arm matching, and — uniquely in this repository — the whole thing has real tests (346 lines across four files).

But every one of those validations runs **on the client**. `bulk_import_commit.dart` then writes entries straight to Firestore, where `firestore.rules:80` accepts anything a pastor sends with no field checks at all. The careful validation is advisory. Anyone bypassing the UI, or hitting a client-side bug, writes unvalidated financial records directly into the ledger.

There is also no import provenance: no `importBatchId` on the created entries, no import-run document recording who imported what file when. When a bad import happens — and with spreadsheets it will — there is no way to identify the affected rows and no way to roll them back. The remediation is manual, row by row, from memory.

**Fix:** route bulk commits through a callable that re-validates server-side. Stamp `importBatchId` on every created entry and write an `import_runs` document with the filename, actor, row count, and timestamp. That single field turns an unbounded incident into a one-query cleanup.

## MODERATE — Number and date parsing accepts more than it should

`bulk_import_parser.dart:141` — `double.tryParse(cleaned)` after stripping formatting. `tryParse` returns null on failure, which is handled, but it also happily accepts `1e10`, `Infinity`, and negative values. Nothing observed rejects a negative amount, and `applyApprovalDeltas` only guards `if (!amount || amount <= 0) return;` — so a negative entry is silently *skipped* rather than rejected, leaving an approved entry that contributes nothing to any total. The entry list and the aggregate disagree, permanently, with no error anywhere.

`:199` — `DateTime.tryParse(t)` handles ISO-8601. Spreadsheets from Ghana are considerably more likely to contain `05/06/2025`, which is ambiguous between two valid readings four weeks apart, and `tryParse` will not tell you which one it picked.

**Fix:** explicit range validation (`amount > 0 && amount < someCeiling`), reject non-finite values, and require an explicit date format selection in the import UI rather than inferring.

## MODERATE — No analytics path off Firestore

Firestore is an operational store optimized for document reads. It cannot answer the questions this product exists to answer:

- Total partnership across all churches by month.
- Retention: partners who gave in period N and also in N+1.
- Which arms outperform, across tenants.
- Any cohort or trend analysis whatsoever.

`firebase_analytics` is in `pubspec.yaml` and `analytics_service.dart` exists, but that captures *product usage* events, not the financial domain data. The GCS exports from `scheduledFirestoreBackup` are backup artifacts — they are in Firestore export format, not queryable, and there is no pipeline consuming them.

Currently the only way to answer "how much was given last quarter" across tenants is to read every entry document.

**Fix:** the standard, cheap answer is the official Firestore→BigQuery extension. Streams changes to BigQuery continuously, gives you SQL over the whole dataset, and does not touch the operational path. It is roughly an hour to set up and it unblocks every analytical question at once — including the reconciliation query the DBA critique asks for.

## MODERATE — Aggregates are the only historical record, and they are mutable

`partner.totalApprovedAmount`, `period.totalApprovedAmount`, `goal.currentAmountCedis` are running totals maintained by `FieldValue.increment`. They are current-state only. There is no time series, no daily snapshot, no immutable fact table.

That means: no trend chart without scanning all entries; no way to answer "what did this partner's total read on 1 March"; and — given the correctness bugs the DBA critique documents — **no way to detect that a total is wrong**, because there is nothing to compare it against.

**Fix:** a nightly snapshot per period into a `period_snapshots` collection (or BigQuery). Cheap, small, and it converts the aggregate from an unverifiable assertion into something with an audit trail.

## MINOR — Denormalized fields with no documented ownership

`fullNameLower` / `fellowshipLower` (maintained by `onPartnerWritten:776`) are the correct Firestore workaround for case-insensitive search. `activity_logs.actorSnapshot` inlines name/role/email, which is right for an audit log — you want the value as-of-the-event.

Neither is documented as deliberate. The trigger also fires on its own writes and terminates only because the second pass computes an empty patch; that is correct today and a comment away from staying correct.

## MINOR — `entries.churchId` is dead weight

Three indexes lead with `churchId` on a subcollection already path-scoped to one church. Either the field is unnecessary — write cost and index cost on the hottest collection for nothing — or it is a vestige of a top-level-collection design. Decide and clean up. (Detailed in the DBA critique.)

## MINOR — No data quality monitoring

No checks for orphaned entries (`partnerId` pointing at a deleted partner), duplicate partners, entries with no period, or aggregate drift. `entry_duplicate_utils.dart` exists on the client for duplicate detection at entry time, which is good, but nothing sweeps the existing data.

**Fix:** a weekly quality job emitting counts. Cheap, and the first run always finds something.

## NOTHING — Done well

- **`entry_duplicate_utils.dart`** plus the `(partnerId, createdBy)` index — duplicate detection designed into the write path rather than bolted on after. Genuinely good.
- **The bulk import architecture.** Separating parser / resolver / arm-matcher / committer, with a session store that survives a page reload, is a properly considered design. It is the best-engineered feature in the repository and it is the only one with real tests.
- **`fullNameLower` / `fellowshipLower`** — the correct idiom for Firestore search.
- **`bulk_import_phone.dart`** — a dedicated phone normalizer. Someone understood that partner identity resolution depends on it.
- **`toTitleCase` mirrored across Dart and TypeScript** — the *intent* is right (normalize at both entry points). The execution is two implementations of one spec with only one tested, which is a QA finding rather than a data-modelling one.
- **`archive` + `xml` over the `excel` package**, with the dependency-conflict reason written in `pubspec.yaml`. Correct decision, documented at the point of confusion.

---

## Priority order

1. Migrate money to integer minor units with an explicit currency code — before a second currency is live.
2. Server-side validation for bulk import; stamp `importBatchId`; record `import_runs`.
3. Firestore→BigQuery extension. One hour, unblocks all analytics and reconciliation.
4. A single generated schema contract shared by Dart and TypeScript.
5. Nightly aggregate snapshots for trend and drift detection.
6. Reject negative and non-finite amounts at every parse site.
7. Explicit date-format selection in the import UI.
8. Weekly data quality sweep.
