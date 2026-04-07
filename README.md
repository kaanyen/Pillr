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

For invite emails, set `RESEND_API_KEY` in `functions/.env` (see earlier setup notes).
