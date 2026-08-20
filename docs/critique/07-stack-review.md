# Stack Review — Switch It Out, or Leave It?

Reviewed: `pubspec.yaml`, `functions/package.json`, `firebase.json`, and actual import counts across all 160 Dart files.

Companion to the six role critiques in this directory. Those ask *"is this built correctly?"* This one asks a different question: **is this the right set of tools, and would swapping any of them be worth the disruption?**

---

## Verdict in one paragraph

**Keep the core. Prune the periphery.** Flutter + Firebase + Riverpod + go_router is the correct spine for this product, and switching any of those three would be a serious, self-inflicted mistake at this stage — the problems the other critiques found are *implementation* problems, not *platform* problems, and every one of them survives a migration intact. What genuinely needs attention is the outer ring: **eight declared dependencies are never imported**, four pairs of libraries do the same job twice, and one dependency puts a Google CDN in the critical path of first paint for users in Ghana. That is a day of cleanup, not an architecture project.

The single most important thing on this page: **do not migrate off Firebase to fix bugs that are yours.**

---

## The evidence

I grepped every declared dependency against actual `package:` imports in `lib/`. The counts below are real, not inferred from the manifest.

| Package | Files importing it | Verdict |
|---|---|---|
| `lucide_icons` | 37 | **Keep** |
| `data_table_2` | 8 | **Keep** |
| `shared_preferences` | 5 | **Keep** (consolidate) |
| `flutter_animate` | 4 | **Keep** |
| `pdf` | 3 | **Keep** |
| `hive_flutter` | 2 | **Drop** (consolidate) |
| `printing`, `cached_network_image`, `url_launcher`, `file_picker` | 2 each | **Keep** |
| `archive`, `xml`, `connectivity_plus`, `image_picker`, `share_plus`, `shimmer`, `equatable`, `google_fonts` | 1 each | Mixed — see below |
| `http` | 1 | **Keep** |
| **`dio`** | **0** | **Drop** |
| **`uuid`** | **0** | **Drop** |
| **`freezed_annotation`** | **0** | **Drop or adopt** |
| **`json_annotation`** | **0** | **Drop or adopt** |
| **`fl_chart`** | **0** | **Drop or adopt** |
| **`dropdown_search`** | **0** | **Drop** |
| **`animations`** | **0** | **Drop** |
| **`cupertino_icons`** | **0** | **Drop** |

Eight packages declared and never imported. That is dependency surface you carry in `pubspec.lock`, resolve on every `pub get`, and inherit CVEs from, for zero benefit.

---

## The big question: stay on Firebase?

### Stay. Emphatically.

The temptation to migrate is going to be real, because the DBA and Security critiques both point at Firestore-shaped pain: rules that cost a document read per evaluation, aggregates maintained by at-least-once triggers, no transactions across the read path, no SQL for analytics. It is easy to read those and conclude the database is the problem.

It isn't. Look at what each finding actually blames:

| Finding | Firestore's fault? | Actual cause |
|---|---|---|
| Suspended church can un-suspend itself | No | An unrestricted `allow write` in your rules |
| Aggregates drift | No | No idempotency guard on an at-least-once trigger — documented behavior you didn't handle |
| Deleting an approved entry leaves the money | No | You never wrote an `onDelete` handler |
| Rule evaluation costs reads | Partly | You're not using custom claims, which exist for exactly this |
| No analytics queries | Yes | Genuine Firestore limitation — with a one-hour fix (below) |

Five findings, one of which is really the platform's, and that one has an off-the-shelf answer. **A migration would carry all four of the others across unchanged**, because they'd be reimplemented by the same team under schedule pressure, in an unfamiliar system, without the test suite that would catch the reimplementation going wrong. You'd spend three months to arrive at the same bugs in Postgres.

### What Firebase is genuinely buying you here

Worth being explicit, because it's substantial and it's easy to undervalue what you already have:

- **Offline-first for free.** Firestore's local persistence and `snapshots()` sync are why `connectivity_service.dart` and `offline_banner.dart` are 200 lines instead of a subsystem. For a product whose users are recording donations in Ghana — where connectivity is genuinely intermittent — this is not a nice-to-have. It may be the single most valuable property of the stack.
- **Real-time by default.** The dashboards update live with no websocket infrastructure, no polling, no cache invalidation strategy.
- **Auth you didn't build.** Email/password, token refresh, session management, and the `request.auth` binding that your entire authorization model rests on.
- **Zero servers.** No cluster, no patching, no capacity planning, no on-call for infrastructure. Given the SRE critique found no alerting and no runbook, "there is nothing to page you about at 3am" is doing real work.
- **One vendor, one bill, one console** for auth, database, storage, functions, hosting, push, analytics, and crash reporting.

For a multi-tenant B2B app at single-digit tenants with one developer, that is close to the ideal trade.

### When you *should* revisit this

Not now. Set tripwires and revisit if you hit one:

1. **Cross-tenant analytics becomes a product feature**, not an internal question. (Even then: BigQuery, not migration.)
2. **A single church exceeds ~500k entries** and read costs start dominating the bill.
3. **You need multi-document transactional integrity** across more than Firestore's limits allow — e.g. real double-entry accounting.
4. **A church demands data residency** in a region Firestore doesn't offer, or an on-prem deployment.
5. **Per-tenant point-in-time restore** becomes contractual. Firestore's export model is genuinely weak here (see the SRE critique) and this is the most likely of the five to actually bite you.

None of these are true today. Three of them may never be.

### What "migrating to Supabase/Postgres" would actually cost

Since it's the obvious alternative and worth pricing honestly rather than dismissing:

**You'd gain:** SQL (real analytics, real reconciliation queries, real constraints), `NUMERIC` for money instead of floats, foreign keys, row-level security that's testable with plain SQL, and transactional integrity.

**You'd pay:** rewriting all 160 Dart files' data layer; rebuilding offline sync by hand (this is the big one — it's a subsystem, not a library swap); reimplementing every rule as RLS policy; migrating live tenant data; a new deploy pipeline; and losing Crashlytics, FCM, App Check, and Hosting integration.

Realistically three to six months of one developer's full attention, during which no features ship — to fix problems that are, per the table above, mostly not the database's.

**The honest recommendation:** get the Firestore→BigQuery extension (one hour) and you have SQL over your data without giving up anything. That closes the one genuine platform gap. Revisit the rest in two years.

---

## The rest of the stack

### Flutter — **Keep.** Not close.

One codebase for web, Android, and iOS, from one developer. `firebase.json` shows web is the deployed surface and `app-distribution.yml` shows Android shipping to testers. Doing that natively is three codebases.

The known cost — Flutter web's initial bundle is large — is already mitigated better than most projects manage: `firebase.json`'s cache headers are the best-configured thing in this repository (immutable one-year caching on hashed assets, wasm, and canvaskit; `no-cache` on the entry points). Somebody thought about this.

### Riverpod 3.3.1 — **Keep.**

Used consistently across every feature. The provider-per-concern pattern in `lib/features/*/providers/` is clean and the `AsyncValue` extension in `core/extensions/async_value_ext.dart` shows the idioms are understood.

One caution: Riverpod 3.x is recent and its migration from 2.x was substantial. Pin it exactly (`3.3.1`, not `^3.3.1`) until there's a test suite that would catch a breaking minor. Right now, per the QA critique, nothing would.

### go_router 17 — **Keep, with a note.**

Correct choice for a web-first Flutter app; deep links and browser URLs work properly. The redirect logic in `core/router/` is genuinely sophisticated — `app_router_redirect.dart`, plus four separate cache layers (`user_church_index_cache`, `platform_admin_cache`, `church_tenant_gate_cache`, `route_persistence_listener`).

That sophistication is the note. Those caches exist to avoid re-reading `user_church_index` on every navigation — the same problem the rules layer has. **Custom claims would delete most of this code**, because `churchId` and `role` would ride in the token and need no caching at all. That's a simplification worth taking, and it's the same fix the Security and DBA critiques both ask for. One change, three problems.

### Cloud Functions / TypeScript — **Keep the platform, split the file.**

`functions/src/index.ts` is 1,066 lines holding 18 functions plus PDF generation plus email templates plus title-casing. That's a file, not a module. Split into `invites.ts`, `entries.ts`, `platform.ts`, `pdf.ts`, `email.ts` — and it will make the Functions tests the QA critique asks for far easier to write, because you'll be able to import a unit rather than the world.

Node 20 hits end-of-maintenance in April 2026. Plan Node 22 now; it's a one-line change today and an urgent one later.

### Resend for email — **Keep.**

Good choice: clean API, sensible pricing, better deliverability than rolling your own SMTP. Two implementation notes rather than stack notes: `sendInviteEmail` silently skips when `RESEND_API_KEY` is unset (`index.ts:108`), and interpolates unescaped user input into HTML (`:114`). Both covered elsewhere; neither is Resend's fault.

---

## Redundancies — four pairs doing one job

### `dio` + `http` — **Drop `dio`.**

`dio` is imported by **zero** files. `http` is imported by exactly one (`pdf_branding.dart`, to fetch a logo image). You are carrying a heavyweight HTTP client, with its interceptor and adapter surface, for nothing.

### `hive_flutter` + `shared_preferences` — **Drop Hive.**

Two local key-value stores. `shared_preferences` is used by 5 files (locale, last route, settings, milestone state, onboarding banner). Hive is used by 2 — `main.dart:15` to call `Hive.initFlutter()`, and `bulk_import_session_store.dart` for the actual storage.

Hive is the more capable library, but it's paying for one use case, and `Hive.initFlutter()` is on your **cold-start critical path** in `main()` before `runApp`. The bulk-import draft is a JSON blob; `shared_preferences` stores it fine.

*(If bulk-import drafts grow large enough that `shared_preferences` becomes wrong, invert this: drop `shared_preferences` and move everything to Hive. What you shouldn't do is keep both.)*

### `pdf` (Dart) + `pdfkit` (Node) — **Keep both, reluctantly.**

Genuine duplication: client-side export in `entry_export.dart` / `pdf_report_utils.dart`, server-side period summaries in `functions/src/index.ts`. Two PDF libraries, two layout implementations, two places branding logic has to stay in sync — and they *will* drift, exactly as `toTitleCase` is set up to drift between Dart and TypeScript.

But the use cases are real: client-side export works offline and needs no round trip; server-side generation is triggered by a Firestore event with no client present. Consolidating means either losing offline export or pushing PDF generation into the client for a server-side trigger. Neither is better.

**Keep both, but extract the shared layout spec** — page geometry, colors, section order — into a JSON document both consume, so branding changes land in one place.

### `flutter_animate` + `animations` + `shimmer` — **Drop `animations`.**

Three animation libraries. `flutter_animate` in 4 files, `shimmer` in 1 (`pillr_loading_shimmer.dart`), `animations` in **zero**. Drop the unused one. `shimmer` earns its single use — skeleton loading is the right pattern for a Firestore-backed list.

---

## `google_fonts` — **Switch. This one has a user-visible cost.**

`lib/core/theme/app_typography.dart` calls `GoogleFonts.inter()` in all 10 text styles. By default `google_fonts` **downloads font files from Google's CDN at runtime on first launch** and caches them.

That means:

- **First paint depends on a third-party network request.** Your users are in Ghana; the request goes to a CDN edge, then the font renders. Until it lands, text renders in a fallback and reflows when it arrives.
- **Offline first-launch has no Inter.** The offline-first design the rest of the app takes seriously has a hole in its typography.
- **A privacy claim you probably don't want to make.** Every install pings Google Fonts with an IP address.
- **You're already doing the right thing one directory over.** `pubspec.yaml` bundles `assets/fonts/lucide.ttf` (413 KB) locally, with a comment explaining that the package path was unreliable. The same reasoning applies to Inter and wasn't applied.

**Fix:** download the four Inter weights you actually use, drop them in `assets/fonts/`, declare them in `pubspec.yaml` alongside Lucide, and delete the dependency. Inter's four weights are ~600 KB — a one-time bundle cost that removes a runtime network dependency and a reflow. This is 30 minutes.

---

## `lucide_icons` — **Keep, but you're paying twice**

37 files import it, making it the most-used package in the app. Fine choice.

But `pubspec.yaml` *also* bundles `assets/fonts/lucide.ttf` separately, with a comment noting the package's own asset path was unreliable. So you ship the font file twice — once as your asset, once inside the package — and `uses-material-design: true` bundles Material Icons on top of that, with `cupertino_icons` declared and never imported for good measure.

**Fix:** drop `cupertino_icons`. Check whether `uses-material-design` is still needed (Flutter widgets pull some Material glyphs; check what actually renders). Keep the bundled `lucide.ttf` and the package, since the package provides the constant names and the comment documents a real problem.

---

## The four "adopt or drop" cases

These aren't dead weight — they're decisions someone started and didn't finish. Each needs a call, not a default.

### `freezed_annotation` + `json_annotation` — **Adopt.**

Both declared, neither imported, no `build_runner`, no `.g.dart` or `.freezed.dart` files anywhere. Meanwhile the Data Engineer critique's central finding is that **there is no schema contract** — domain models are hand-written Dart, Cloud Functions write untyped object literals, and nothing keeps them in agreement.

This is that fix, half-installed and abandoned. Finish it: add `build_runner`, generate the models, and get compile-time-checked serialization. Then hand-write matching TypeScript interfaces in `functions/src/types.ts`. That's the cheapest available version of a schema contract.

### `equatable` — **Drop, when Freezed lands.**

One file uses it. Freezed generates equality. Two mechanisms for value equality in one codebase is one too many; pick the generated one.

### `fl_chart` — **Adopt.**

Zero imports. But there are four dashboard screens (`admin`, `pastor`, `staff`, `role`) plus a leaderboard, all rendering **numbers only** — no chart anywhere in the app. For a product about tracking progress toward partnership goals, where `goals` already carries `currentAmountCedis` and `targetAmountCedis`, a progress visualization isn't decoration. Somebody added the dependency intending exactly this and never got to it.

Either build the chart or drop the package. Don't leave it declared as a reminder.

### `dropdown_search` — **Drop.**

Zero imports, and `lib/common/widgets/pillr_searchable_dropdown.dart` — the widget that would have used it — is a stub whose own doc comment reads *"Phase 2 will wire Firestore search."* Phase 4 is in the README. The dependency is a fossil of a plan that changed. `global_search_screen.dart` exists and does the job differently.

### `uuid` — **Drop.**

Zero imports. Firestore generates document IDs (`col.doc()` throughout `functions/src/index.ts`). Nothing needs it.

---

## What's *missing* from the stack

More consequential than anything to remove. Each of these is a gap the other critiques hit from a different angle.

| Missing | Why it matters | Cost |
|---|---|---|
| **Web error tracking** (`sentry_flutter`) | Web is your deployed surface and has *no* crash reporting — `main.dart:31` correctly skips Crashlytics on web, and nothing replaces it. You are blind in production. | ~2 hours |
| **`@firebase/rules-unit-testing`** | 150 lines of rules are your entire authz model, with zero tests. Highest value-per-hour item in the repo. | ~1 day |
| **`firebase-functions-test`** | 1,150 lines of money-handling logic, zero tests. | ~2 days |
| **Emulator suite** (`firebase.json` `emulators` block) | No local dev environment exists. Everything is tested against production. Prerequisite for both rows above. | ~1 hour |
| **Firestore→BigQuery extension** | Closes the one real Firebase gap — SQL for analytics *and* for the reconciliation query the DBA critique needs. | ~1 hour |
| **`eslint`** | `functions/package.json:11` declares a lint script; ESLint isn't a dependency. The script cannot run. | ~30 min |
| **`build_runner`** | Required to make Freezed/json_serializable functional. | ~1 hour |
| **Dependabot** | 40+ direct deps, caret ranges, `pubspec.lock` untouched since June. Nothing watches for CVEs. | ~15 min |

---

## Summary table

| Action | Package(s) | Effort | Why |
|---|---|---|---|
| **Drop** | `dio`, `uuid`, `dropdown_search`, `animations`, `cupertino_icons` | 15 min | Zero imports. Pure surface area. |
| **Drop** | `hive_flutter` | 2 hrs | One use case; costs cold-start time in `main()`. |
| **Drop** | `equatable` | 1 hr | Redundant once Freezed is generating equality. |
| **Switch** | `google_fonts` → bundled Inter | 30 min | Removes a CDN from first paint for users in Ghana. |
| **Adopt** | `freezed_annotation` + `json_annotation` + `build_runner` | 1 day | The schema contract that doesn't currently exist. |
| **Adopt or drop** | `fl_chart` | 1 day / 5 min | Five dashboards, no charts. Decide. |
| **Add** | `sentry_flutter` | 2 hrs | You cannot see production failures on web. |
| **Add** | rules + functions test libs, emulators | 3 days | Covered in the QA critique. |
| **Add** | Firestore→BigQuery extension | 1 hr | Closes the only genuine Firebase limitation. |
| **Add** | `eslint`, Dependabot | 45 min | A declared script that can't run; unwatched CVEs. |
| **Refactor** | Split `functions/src/index.ts` | 3 hrs | 1,066 lines, 18 functions. Blocks testability. |
| **Plan** | Node 20 → 22 | 1 hr | EOL April 2026. |
| **Keep** | Flutter, Firebase, Riverpod, go_router, Resend, Cloud Functions, `lucide_icons`, `data_table_2`, `flutter_animate`, `shimmer`, `pdf`+`pdfkit`, `archive`+`xml` | — | Right calls. Don't relitigate. |

**Total for everything in the "drop" and "switch" rows: under a day.** That's the whole dependency cleanup.

---

## What I would not change, and why it matters

The instinct after reading six critiques grading you CRITICAL and HIGH is to conclude something fundamental is wrong and reach for a rewrite. Resist it.

Every finding in those documents is a **bounded fix inside the current stack**. Restricting a rules write is one line. Adding an idempotency guard is ten. Enforcing App Check is a parameter. Writing rules tests is a day. None of them require a different database, a different framework, or a different language — and all of them would need doing again, from scratch, under worse conditions, on any platform you migrated to.

The stack is not the problem. The stack is the part that's right.
