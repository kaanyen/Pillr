/**
 * One-time: set isActive and churchSetupCompletedAt on all existing churches
 * that are missing them, so legacy tenants are not forced through onboarding.
 *
 * npm run migrate-church-setup --prefix functions
 *
 * Requires Admin SDK credentials (same as seed-demo).
 */
/* eslint-disable @typescript-eslint/no-require-imports */
const admin = require("firebase-admin");

const DEFAULT_PROJECT_ID = "thepillr2";

function printCredentialHelp() {
  console.error(`
No working Google credentials found for the Admin SDK.

Option A — Service account JSON (Firebase Console)
  1. https://console.firebase.google.com → your project → Project settings
  2. Tab "Service accounts" → "Generate new private key" → save the .json file
  3. export GOOGLE_APPLICATION_CREDENTIALS="/absolute/path/to/that-file.json"

Option B — No JSON file (Google Cloud CLI)
  1. Install: https://cloud.google.com/sdk/docs/install
  2. gcloud auth application-default login
  3. gcloud config set project ${DEFAULT_PROJECT_ID}
     (or: export FIREBASE_PROJECT_ID=your-project-id)

Then run: npm run migrate-church-setup --prefix functions
`);
}

function resolveProjectId() {
  return (
    process.env.FIREBASE_PROJECT_ID ||
    process.env.GCLOUD_PROJECT ||
    process.env.GOOGLE_CLOUD_PROJECT ||
    DEFAULT_PROJECT_ID
  );
}

async function main() {
  const projectId = resolveProjectId();
  if (!admin.apps.length) {
    admin.initializeApp({ projectId });
  }
  const db = admin.firestore();
  const now = admin.firestore.FieldValue.serverTimestamp();
  const snap = await db.collection("churches").get();
  let n = 0;
  for (const doc of snap.docs) {
    const d = doc.data();
    const patch = {};
    if (d.isActive === undefined) patch.isActive = true;
    if (d.churchSetupCompletedAt === undefined || d.churchSetupCompletedAt === null) {
      patch.churchSetupCompletedAt = now;
    }
    if (Object.keys(patch).length) {
      patch.updatedAt = now;
      await doc.ref.set(patch, { merge: true });
      n++;
      console.log("updated", doc.id, Object.keys(patch).filter((k) => k !== "updatedAt"));
    }
  }
  console.log(`Done. Patched ${n} of ${snap.size} churches.`);
}

main().catch((e) => {
  const msg = String(e?.message || e);
  if (
    msg.includes("Could not load the default credentials") ||
    msg.includes("Could not load credentials") ||
    e?.code === 7 /* PERMISSION_DENIED */ ||
    e?.code === "PERMISSION_DENIED"
  ) {
    printCredentialHelp();
  }
  console.error(e);
  process.exit(1);
});
