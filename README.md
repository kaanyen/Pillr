# Pillr

Multi-tenant church partnership management (Flutter + Firebase). See `the_pillr_build_doc.md` for the full spec.

## Demo login (local / staging)

The app has **no** built-in fake auth. Use the Admin seed script once per Firebase project.

**Credentials — use either A or B:**

**A) Service account JSON (no Cloud SDK required)**  
1. [Firebase Console](https://console.firebase.google.com) → your project → ⚙️ **Project settings** → **Service accounts** → **Generate new private key**.  
2. Save the `.json` somewhere safe (do not commit it).  
3. From the **repository root**:

   ```bash
   export GOOGLE_APPLICATION_CREDENTIALS="/full/absolute/path/to/the-downloaded.json"
   npm run seed-demo --prefix functions
   ```

**B) No JSON file — Google Cloud CLI**  
1. Install [Google Cloud SDK](https://cloud.google.com/sdk/docs/install).  
2. `gcloud auth application-default login`  
3. `gcloud config set project thepillr2` (or your Firebase project id)  
4. `npm run seed-demo --prefix functions`

Set `FIREBASE_PROJECT_ID` if your project id is not `thepillr2`.

3. The seed script creates **three users** in the same demo church (`demo-church` by default). **Role is in the local part of the email:**

   | Role   | Email (default domain)   | Password (all accounts) |
   |--------|---------------------------|-------------------------|
   | admin  | `admin@pillr.dev`         | `DemoPillr1!`           |
   | pastor | `pastor@pillr.dev`        | `DemoPillr1!`           |
   | staff  | `staff@pillr.dev`         | `DemoPillr1!`           |

   Optional env vars: `DEMO_PASSWORD`, `DEMO_EMAIL_DOMAIN` (default `pillr.dev`), `DEMO_CHURCH_ID`, `DEMO_CHURCH_NAME`.

   ```bash
   DEMO_PASSWORD='YourStr0ng!' DEMO_EMAIL_DOMAIN='yourdomain.test' npm run seed-demo --prefix functions
   ```

**Security:** Never commit the service account JSON. Re-running the script resets each demo user’s password to `DEMO_PASSWORD` (or the default).

## Flutter

```bash
flutter pub get
flutter run -d chrome
```

Firebase **Crashlytics** is skipped on **web** in `main.dart` (the plugin has no web implementation).

## Firebase

- Rules: `firestore.rules`
- Indexes: `firestore.indexes.json`
- Cloud Functions: `functions/` (`npm run build`, then `firebase deploy --only functions`)

For invite emails, set `RESEND_API_KEY` in `functions/.env` (see earlier setup notes). The **From** address must use a domain you have **verified in Resend** (Dashboard → Domains). Override with `RESEND_FROM` if needed, e.g. `RESEND_FROM="The Pillr <invites@thepillr.com>"`. The default matches `thepillr.com`, not `pillr.app`.

## Phase 4 — Deploy checklist

1. **Firestore** — `firebase deploy --only firestore:rules,firestore:indexes` (includes `partnerId` + `createdBy` on `entries` for duplicate checks).
2. **Storage** — `firebase deploy --only storage` (new `storage.rules` for church branding + period PDFs).
3. **Functions** — `npm run build --prefix functions && firebase deploy --only functions` (adds `updateChurchMember`, `onPartnershipPeriodUpdated`, `dailyPendingDigest`, period summary PDF).
4. **App Check** — In debug builds, register Android/iOS debug tokens from Logcat / Xcode when prompted. For production, configure Play Integrity / DeviceCheck / App Attest in Firebase Console.
5. **Secrets** — `RESEND_API_KEY` for email; Functions use default Storage bucket for PDF uploads.

See `the_pillr_build_doc.md` §16 for the full Phase 4 feature matrix and `PHASE_PROGRESS.md` for status.

## App Distribution and release

- **Secrets:** `FIREBASE_TOKEN` (from `firebase login:ci`), `FIREBASE_ANDROID_APP_ID`, tester group name (default in CI: `testers` — must exist in Firebase App Distribution).
- **Workflow:** `.github/workflows/app-distribution.yml` (tags `v*` or manual run).
- **iOS:** CI IPA upload is optional when `FIREBASE_IOS_APP_ID` and signing secrets are available; otherwise use TestFlight manually. See [`docs/RELEASE.md`](docs/RELEASE.md).
