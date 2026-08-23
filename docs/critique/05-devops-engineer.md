# DevOps Engineer — Critique

**Discipline grade: HIGH**

Reviewed: `.github/workflows/`, `firebase.json`, `.firebaserc`, `pubspec.yaml`, `functions/package.json`, `docs/RELEASE.md`.

Three workflows exist and two of them are thoughtfully written, with setup comments explaining the secrets and the reasoning. The problem is not effort. It is that the pipeline does not enforce anything, the release workflow is pinned to a toolchain that cannot build this app, and there is exactly one Firebase project standing in for every environment.

---

## CRITICAL — One Firebase project is dev, staging, and production

`.firebaserc` names a single project. `firebase.json` hardcodes `thepillr2` throughout. `lib/firebase_options.dart` has `projectId: 'thepillr2'` for all five platforms. `deploy-firebase.yml:44` passes `--project thepillr2`. `firestore_backup.ts:12` falls back to `"thepillr2"`.

`lib/core/constants/app_environment.dart` defines a three-value `AppEnvironment` enum read from `--dart-define=APP_ENV`. It is used for one thing: a `debugPrint` in `main.dart:26`. There is a concept of environments and no actual environments.

Consequences, all of them live today:

- **Rules are tested in production or not at all.** A mistake in `firestore.rules` — and the security critique found one — reaches real church data on the first deploy.
- **`seed-demo` writes to production.** `README.md` instructs the reader to run it against `thepillr2`, creating `admin@pillr.dev` / `pastor@pillr.dev` / `staff@pillr.dev` with the password `DemoPillr1!` in the same Auth tenant as real users. Those accounts have full pastor and admin rights over the `demo-church` tenant, and the credentials are published in your README.
- **`migrate-church-setup` runs against production** with no dry-run flag and no rehearsal environment.
- **No emulator config in `firebase.json`.** No `emulators` block, no ports. There is no local development environment at all.

**Fix:** create `pillr-dev` and `pillr-staging`. `firebase use --add` for aliases. `--dart-define` the project ID so `firebase_options.dart` is selected per flavor. Add an `emulators` block so the rules and functions tests QA needs (see that critique) have somewhere to run.

## CRITICAL — The release workflow cannot build this app

`.github/workflows/app-distribution.yml:19`

```yaml
flutter-version: '3.27.0'
```

`pubspec.yaml:22`

```yaml
environment:
  sdk: ^3.11.4
```

Flutter 3.27.0 ships Dart 3.6. This app requires Dart 3.11.4 or newer. `flutter pub get` fails on version solving. **The Android release workflow is broken and has been since the SDK constraint was raised** — which means either no `v*` tag has been pushed since, or it has been failing and nobody looked.

Meanwhile `ci.yml:20` uses `channel: stable` with no version pin at all. So CI validates against whatever Flutter released this week, and the release workflow attempts to build with a toolchain from a year ago. The tested artifact and the shipped artifact were never the same artifact even in principle.

**Fix:** pin one explicit `flutter-version` in both workflows, matching a version that satisfies `^3.11.4`. Better: put it in a `.flutter-version` file and read it in both places so drift is structurally impossible.

## HIGH — CI enforces nothing beyond compilation

`ci.yml` runs `flutter analyze`, `flutter test`, and `npm ci && npm run build`.

- **`npm run lint` is never invoked.** It would fail if it were: `functions/package.json:11` declares `"lint": "eslint --ext .ts src/"` and `devDependencies` contains only `typescript`. No ESLint, no config file. A broken script that nobody runs.
- **No coverage** — see the QA critique. `flutter test --coverage` is not run and no threshold exists.
- **No rules validation.** Not even a dry-run deploy. A syntax error in `firestore.rules` is caught by production.
- **No emulator tests**, because there is no emulator config.
- **No dependency scanning.** No Dependabot config, no `npm audit`, no `flutter pub outdated`. `pubspec.yaml` carries 40+ direct dependencies with caret ranges and `pubspec.lock` was last touched in June.
- **No build artifact.** CI never produces the web bundle it is nominally validating, so "it compiles for tests" and "it builds for release" are separately unverified.

## HIGH — Deployment is manual and unrepeatable

`deploy-firebase.yml` is `workflow_dispatch`-only with a free-text `--only` input, and its own header comment describes it as "Optional CD."

So the production deploy procedure is: a human opens the Actions tab, types a comma-separated string from memory, and hopes. There is no promotion pipeline, no gate on CI passing, no tagging of what was deployed, no changelog, no rollback path, and no record of which functions are currently live.

`README.md` documents the real process as a sequence of local commands — `firebase deploy --only firestore:rules,firestore:indexes`, then storage, then functions — run from a developer laptop against production. That is the actual deployment mechanism for this product.

**Fix:** deploy from a tag, gated on CI green. Record the deployed SHA. Document the rollback command. The `--only` input should be a `choice` type with fixed options, which also closes the injection hole below.

## HIGH — `FIREBASE_TOKEN` is the wrong credential

Both deploying workflows authenticate with a `firebase login:ci` token (`deploy-firebase.yml:43`, `app-distribution.yml:31`). That is a long-lived refresh token bound to a **human Google account**, carrying that human's full permissions on every project they can access, with no scoping and no expiry. Firebase has deprecated it.

`deploy-firebase.yml`'s own header comment recommends Workload Identity Federation and links the action — and then the workflow uses the token anyway. The right answer was written down and not taken.

**Fix:** `google-github-actions/auth` with WIF and a deploy-scoped service account. Delete the token secret.

## MODERATE — Command injection via workflow input

`deploy-firebase.yml:44` interpolates `${{ github.event.inputs.only }}` directly into a `run:` block. Anyone who can trigger the workflow can execute arbitrary shell in a runner holding `FIREBASE_TOKEN`. Covered in the security critique; noted here because the fix belongs to this file.

**Fix:** `choice`-type input, or pass through `env:` and quote the variable.

## MODERATE — No branch protection or PR gates evident

`ci.yml` triggers on `pull_request` to `main`/`master`, which is right. But `git log` shows commits landing directly on `main` — including `583993e "Fix flutter analyze lint issues for CI"`, which is the signature of someone pushing to main, watching CI go red, and pushing a fix. No CODEOWNERS, no PR template, no evidence of required status checks.

## MODERATE — Working tree contains uncommitted infrastructure

`git status` at review time:

```
M functions/src/index.ts
M functions/package.json
?? functions/src/firestore_backup.ts
?? functions/scripts/setup-firestore-backup-bucket.cjs
?? docs/BACKUP.md
```

The entire backup-and-compliance feature — the thing standing between you and permanent data loss — exists only on one laptop. If that machine dies, so does it. `README.md` already documents it as though it shipped.

Also tracked and shouldn't be: `.firebase/hosting.YnVpbGQvd2Vi.cache` is a local deploy cache that churns on every build and produces meaningless diffs. `PARTNERSHIP SAMPLE.xlsx` and `background.png` (924 KB) sit in the repo root; the xlsx is gitignored but still present in the working directory.

**Fix:** commit the backup feature today. Add `.firebase/` to `.gitignore`.

## MODERATE — Secrets management is ad hoc

`RESEND_API_KEY` lives in `functions/.env` per the README. Firebase Functions v2 supports `defineSecret` backed by Secret Manager, with versioning, IAM, and audit logging. A `.env` file has none of those, and `sendInviteEmail` (`:108`) silently skips sending when the key is missing rather than failing loudly — so a misconfigured deploy produces an invite system that appears to work and delivers nothing.

`PLATFORM_ADMIN_EMAILS` is more concerning: it is a plain environment variable that grants **platform administrator** rights by email match (`:71-82`). Anyone who can set a function env var can make themselves a platform admin across all tenants.

**Fix:** `defineSecret` for `RESEND_API_KEY`; fail startup if absent. Drop the `PLATFORM_ADMIN_EMAILS` bypass and require a `platform_admins` document.

## MINOR — Node 20 is approaching end of life

`functions/package.json` pins `"node": "20"`. Node 20 leaves maintenance in April 2026. Plan the move to 22.

## MINOR — No containerized or documented local setup

No `Makefile`, no `justfile`, no `scripts/dev.sh`, no devcontainer. Onboarding a second developer means reading three README sections and reproducing them by hand.

## NOTHING — Done well

- **Split CI jobs** for Flutter and Functions with `concurrency` + `cancel-in-progress`. Correct and efficient.
- **`npm ci` with `cache-dependency-path: functions/package-lock.json`.** Exactly right.
- **Hosting cache headers** in `firebase.json` — the best-configured thing in the repo (detailed in the SRE critique).
- **`docs/RELEASE.md`** is a genuinely good document: it names every secret, explains the tester group, and gives an honest manual TestFlight fallback for when iOS signing isn't wired up. That last part — documenting the degraded path so Android CI stays unblocked — is mature thinking.
- **`.gitignore` covering `*-firebase-adminsdk-*.json`** prevented a real credential leak. It worked.
- **`predeploy` hook** in `firebase.json` ensures functions are built before deploy.

---

## Priority order

1. Split dev / staging / production into separate Firebase projects.
2. Fix the Flutter version pin; unify it across both workflows.
3. Commit the backup feature — it exists on one machine.
4. Add `eslint` + config; run lint, coverage, and rules validation in CI.
5. Move CI auth to Workload Identity Federation.
6. Make the `--only` input a `choice`; close the injection.
7. Add an `emulators` block to `firebase.json`.
8. Gate deploys on CI green; deploy from tags; document rollback.
9. `RESEND_API_KEY` to Secret Manager; remove the `PLATFORM_ADMIN_EMAILS` bypass.
10. Branch protection, CODEOWNERS, Dependabot.
