# Quality Assurance Engineer — Critique

**Discipline grade: CRITICAL**

Reviewed: `test/`, `.github/workflows/ci.yml`, `analysis_options.yaml`, `functions/package.json`, `pubspec.yaml`.

---

## The number that ends the argument

```
lib/            160 Dart files
functions/src/  1,150 lines of TypeScript
test/           436 lines, 5 real test files
```

And of those 436 lines, **346 test the bulk-import parser** — one feature, added in the most recent substantive commit. The remaining 90 lines are `text_case_utils_test.dart` (36) and this, in full:

```dart
// test/widget_test.dart
void main() {
  test('sanity', () => expect(2 + 2, 4));
}
```

That file exists to make `flutter test` exit zero. It is a green check that certifies arithmetic.

Someone clearly knows how to write good tests — the bulk-import suite is legitimately decent, with fixtures, edge cases, and a resolver test that covers ambiguity. That makes the rest worse, not better. It is not a skills gap. It is a decision that everything except the feature being actively worked on ships untested.

## CRITICAL — Firestore rules have zero tests

`firestore.rules` is 150 lines and is the **entire** authorization model for the client SDK. Nine collections, five role predicates, overlapping `allow` clauses whose OR-semantics decide whether a staff member can edit an approved entry.

There is no `@firebase/rules-unit-testing` dependency, no emulator config in `firebase.json`, and no rules test anywhere in the repo.

The security critique found a rule that lets a suspended church un-suspend itself (`firestore.rules:60`). A twenty-line rules test would have caught it. So would a test asserting that a staff member cannot read `goals`, or that tenant A cannot read tenant B's `entries` — neither of which is verified by anything today.

Rules are the highest-consequence, lowest-line-count, most-testable artifact in this repository, and they are the least tested.

**Fix:** `firebase emulators:exec` + `@firebase/rules-unit-testing`. One test per `(role × collection × operation)` cell. That is roughly 60 assertions and about a day of work, and it is the single highest-value test investment available to this project.

## CRITICAL — Cloud Functions have zero tests, and the lint script is broken

`functions/package.json` has no `test` script. No Jest, no Mocha, no `firebase-functions-test`. 1,150 lines of business logic — invite redemption, tenant creation, role mutation, and every financial aggregate in the product — verified by nothing but `tsc`.

The lint story is worse than absent:

```json
"lint": "eslint --ext .ts src/",
"devDependencies": { "typescript": "^5.6.3" }
```

ESLint is not a dependency. There is no ESLint config file. `npm run lint` fails with "command not found." And `ci.yml` never calls it anyway, so nobody has noticed.

Untested logic that should have had a test yesterday:

- `redeemBootstrapInvite` (`:253`) — creates a tenant inside a transaction, with at least four early-throw paths.
- `applyApprovalDeltas` (`:663`) — mutates three documents' financial totals with `FieldValue.increment`. No test asserts the arithmetic.
- `updateChurchMember` (`:805`) — role escalation surface.
- `toTitleCase` (`:16`) — deliberately mirrors Dart's `TextCaseUtils`, which *does* have a test (`test/text_case_utils_test.dart`). The TypeScript twin has none. Two implementations of the same spec, one tested. They will diverge.

**Fix:** `firebase-functions-test` in offline mode against the emulator suite. Start with the money path and the invite path.

## CRITICAL — Not one test touches money

Pillr's reason to exist is recording donations accurately. The financial path is:

```
entry created (pending) → pastor approves → applyApprovalDeltas →
  partner.totalApprovedAmount   += amount
  period.totalApprovedAmount    += amount
  goal.currentAmountCedis       += amount
```

Zero tests. Not a unit test on the trigger, not an integration test on the flow, not a widget test on the approval screen.

The DBA critique shows this path is non-idempotent, has no delete handler, and does not reverse on amount edits — every one of which is a bug a modest integration test suite finds in an afternoon. They are unfound because nobody is looking.

## HIGH — No widget tests, no golden tests, no integration tests

160 Dart files. Roughly 60 of them are screens and widgets. Tested: none.

`lib/common/widgets/` alone holds 20 shared components — `pillr_data_table`, `pillr_searchable_dropdown`, `pillr_form_dialog`, `pillr_date_picker`. These are the highest-reuse, highest-blast-radius code in the app. A regression in `pillr_data_table` breaks every list screen simultaneously, and nothing catches it before a user does.

Also missing:

- **`integration_test/`** — no directory. No end-to-end coverage of the flows the README spends 60 lines describing: bootstrap invite → sign up → redeem → onboarding wizard. That is the most complex flow in the product and it is verified by hand, once, by the person who wrote it.
- **Golden tests** — the app has light/dark theming, a full custom design system (`lib/core/theme/`, 6 files), and responsive layouts (`responsive_layout.dart`, `adaptive_sidebar.dart`, `adaptive_bottom_nav.dart`). Visual regressions are invisible to the current suite.
- **Localization tests** — `lib/l10n/` ships English *and* French. Nothing asserts the ARB files are in sync. A missing French key is a runtime failure discovered by a French-speaking user.

## HIGH — CI has no quality gates worth the name

`.github/workflows/ci.yml` runs `flutter analyze`, `flutter test`, and `npm run build`. That's it.

- **No coverage measurement.** `flutter test --coverage` is not run, no threshold enforced, no report uploaded. Coverage is currently somewhere around 3% and nothing in CI would notice if it went to 0%.
- **No lint on functions.** Broken script, never invoked.
- **No rules validation.** Not even `firebase deploy --only firestore:rules --dry-run`. A syntax error in `firestore.rules` reaches production.
- **No emulator suite.** Nothing exercises rules or functions together.
- **No dependency audit.** No Dependabot, no `npm audit`, no `flutter pub outdated`.

The pipeline's honest guarantee is "it compiles."

## HIGH — CI does not pin the Flutter version

`ci.yml:20` uses `channel: stable` with no `flutter-version`. Every run picks up whatever stable is that day. When a Flutter release changes analyzer behavior, CI goes red on a commit that changed nothing, and the reflex will be to distrust CI rather than the toolchain.

Worse, `app-distribution.yml:19` pins `flutter-version: '3.27.0'` — a *different, older* toolchain than CI validated against. The release build and the tested build are not the same build. (See the DevOps critique: that pin also cannot compile this app.)

## MODERATE — Lint config is the untouched Flutter default

`analysis_options.yaml` is the generated stub, every rule commented out. For a 160-file codebase with a design system and strict layering conventions this is far too permissive. Missing at minimum: `prefer_const_constructors`, `avoid_dynamic_calls`, `require_trailing_commas`, `unawaited_futures` (relevant — `activity_log_helper.dart` fires unawaited writes), and `public_member_api_docs` for `lib/common/`.

Consider `very_good_analysis` or `flutter_lints` with a real override block.

## MODERATE — No test fixtures beyond a `.gitkeep`

`test/fixtures/.gitkeep` is the only thing in the fixtures directory. No sample church, no sample entry set, no seeded emulator state. Every future test author starts from zero, which is exactly the friction that keeps a suite this small.

## MINOR — No flakiness or performance baseline

No retry policy, no test timing tracked, no `flutter test --reporter` output retained. Not urgent at 5 test files; will be the moment there are 200.

## NOTHING — Genuinely good

- **`test/bulk_import_resolver_test.dart`** (159 lines) is a properly constructed suite — ambiguity cases, arm-matching, session persistence. It is the standard the rest of the repo should be held to.
- **`concurrency` + `cancel-in-progress`** in `ci.yml` is correct and saves runner minutes.
- **Split flutter/functions jobs** for independent feedback is the right structure.
- **`npm ci` with `cache-dependency-path`** is correct.

---

## Priority order

1. **Firestore rules tests** — highest value per hour in the entire repo. ~1 day.
2. **Cloud Functions tests** for the money path and invite path. ~2 days.
3. **Integration test** for bootstrap → onboarding. ~1 day.
4. **Add `--coverage` to CI** with a floor that ratchets up. Start at 10%. ~1 hour.
5. **Fix the lint script** (add `eslint` + config) and run it in CI. ~1 hour.
6. **Pin `flutter-version` in CI**, matched to the release workflow. ~10 minutes.
7. **Widget tests for `lib/common/widgets/`** — highest reuse first.
8. **Golden tests** for theme and responsive breakpoints.
9. **ARB key-parity test** for `lib/l10n/`.
