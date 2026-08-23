# Pillr — Adversarial Review Index

Six role-based critiques of this repository, written to be harsh rather than encouraging.
Reviewed at commit `583993e` on 2026-08-20.

## The severity scale

Every finding in these documents carries one of five grades:

| Grade | Meaning |
|-------|---------|
| **CRITICAL** | Money, tenant isolation, or data durability is at risk *today*. Ship-blocker. |
| **HIGH** | Will cause an outage, a data-integrity incident, or a breach as soon as you have real users. |
| **MODERATE** | Real cost — in money, velocity, or debugging time. Not yet an emergency. |
| **MINOR** | Sloppiness. Fix it when you touch the file. |
| **NOTHING** | Looked wrong, isn't. Recorded so nobody re-litigates it. |

Discipline grades use the same scale applied to the discipline as a whole.

## Ranking — worst discipline first

| # | Discipline | Grade | The one-line verdict |
|---|-----------|-------|----------------------|
| 1 | [Security Engineer (AppSec)](01-security-engineer.md) | **CRITICAL** | A suspended church can un-suspend itself, App Check is decorative, invite codes come from `Math.random()`, and the audit log is written by the client it is supposed to be auditing. |
| 2 | [QA Engineer](02-qa-engineer.md) | **CRITICAL** | 436 lines of test against ~13,000 lines of product. Zero tests for security rules, zero for Cloud Functions, zero for the money path. `widget_test.dart` asserts `2 + 2 == 4`. |
| 3 | [Database Administrator](03-dba.md) | **HIGH** | Financial aggregates are maintained by non-idempotent triggers with no delete handler and no reconciliation job. The totals your users see *will* drift, and nothing in the system will notice. |
| 4 | [Site Reliability Engineer](04-sre.md) | **HIGH** | The deployed surface is web; web has no crash reporting. No alerts, no SLOs, no runbook, no restore rehearsal, and a backup job that cannot tell you whether the backup succeeded. |
| 5 | [DevOps Engineer](05-devops-engineer.md) | **HIGH** | One Firebase project is dev, staging *and* production. The release workflow is pinned to a Flutter version that cannot compile this app. CI never runs the linter, and the lint script is broken anyway. |
| 6 | [Data Engineer](06-data-engineer.md) | **MODERATE** | Money is stored as a float, schema is enforced nowhere, and the same partner name is denormalized into four places with a trigger to keep them honest. No analytics path off Firestore. |

## If you only do five things

1. **Restrict `churches/{churchId}` writes by field** — today a church pastor can flip their own `isActive` back to `true` after a platform admin suspends them. (`firestore.rules:60`)
2. **Make `applyApprovalDeltas` idempotent** and add an `onDelete` handler. Financial totals are currently best-effort. (`functions/src/index.ts:663`)
3. **Enforce App Check** (`enforceAppCheck: true`) on every callable, and add reCAPTCHA for web. Right now you pay for App Check and get nothing. (`lib/main.dart:18`)
4. **Write Firestore rules tests** against the emulator. Rules are your entire authorization model and not one line of them is tested.
5. **Split production from development** into separate Firebase projects before you have a second real church.

---

## Companion document

[**07 — Stack Review**](07-stack-review.md) — a different question from the six above: not *"is this built correctly?"* but *"are these the right tools, and is anything worth swapping?"*

**Short answer:** keep the core (Flutter, Firebase, Riverpod, go_router), prune the periphery. Eight declared dependencies are never imported, four pairs of libraries do the same job twice, and `google_fonts` puts a CDN request in the critical path of first paint for users in Ghana. Under a day of cleanup.

**Do not migrate off Firebase to fix bugs that are yours.** Four of the five platform-shaped complaints in the critiques above are implementation defects that would survive a migration intact.
