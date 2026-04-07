/**
 * Seeds a demo church + three Firebase Auth users (admin, pastor, staff).
 * Emails are {role}@{domain}, e.g. admin@pillr.dev
 *
 * Credentials (pick one):
 *   A) Service account JSON:
 *        export GOOGLE_APPLICATION_CREDENTIALS="/path/to/serviceAccount.json"
 *   B) Google Cloud CLI (no JSON file):
 *        gcloud auth application-default login
 *        gcloud config set project YOUR_PROJECT_ID
 *
 * Project id defaults to thepillr2; override with FIREBASE_PROJECT_ID.
 *
 * Run from repo root:
 *   npm run seed-demo --prefix functions
 */
/* eslint-disable @typescript-eslint/no-require-imports */
const admin = require("firebase-admin");

const ROLES = /** @type {const} */ (["admin", "pastor", "staff"]);

const DEMO_PASSWORD = process.env.DEMO_PASSWORD || "DemoPillr1!";
const EMAIL_DOMAIN = (process.env.DEMO_EMAIL_DOMAIN || "pillr.dev").toLowerCase().trim();
const CHURCH_ID = (process.env.DEMO_CHURCH_ID || "demo-church").trim();
const CHURCH_NAME = process.env.DEMO_CHURCH_NAME || "Demo Community Church";

const DEFAULT_PROJECT_ID = "thepillr2";

/**
 * @param {string} role
 */
function emailForRole(role) {
  return `${role}@${EMAIL_DOMAIN}`;
}

/**
 * @param {string} role
 */
function displayNameForRole(role) {
  return `Demo ${role.charAt(0).toUpperCase()}${role.slice(1)}`;
}

/**
 * @param {import("firebase-admin/auth").Auth} authAdmin
 * @param {string} email
 * @param {string} password
 * @param {string} displayName
 */
async function upsertAuthUser(authAdmin, email, password, displayName) {
  try {
    const existing = await authAdmin.getUserByEmail(email);
    await authAdmin.updateUser(existing.uid, {
      password,
      displayName,
      emailVerified: true,
    });
    return existing;
  } catch (e) {
    if (e.code === "auth/user-not-found") {
      return authAdmin.createUser({
        email,
        password,
        displayName,
        emailVerified: true,
      });
    }
    throw e;
  }
}

function resolveProjectId() {
  return (
    process.env.FIREBASE_PROJECT_ID ||
    process.env.GCLOUD_PROJECT ||
    process.env.GOOGLE_CLOUD_PROJECT ||
    DEFAULT_PROJECT_ID
  );
}

function printCredentialHelp() {
  console.error(`
No working Google credentials found for the Admin SDK.

Option A — Service account JSON (Firebase Console)
  1. https://console.firebase.google.com → your project → ⚙️ Project settings
  2. Tab "Service accounts" → "Generate new private key" → save the .json file
  3. export GOOGLE_APPLICATION_CREDENTIALS="/absolute/path/to/that-file.json"

Option B — No JSON file (Google Cloud CLI)
  1. Install: https://cloud.google.com/sdk/docs/install
  2. gcloud auth application-default login
  3. gcloud config set project ${DEFAULT_PROJECT_ID}
     (or: export FIREBASE_PROJECT_ID=your-project-id)

Then run: npm run seed-demo --prefix functions
`);
}

async function main() {
  const projectId = resolveProjectId();

  if (!admin.apps.length) {
    admin.initializeApp({ projectId });
  }

  const auth = admin.auth();
  const db = admin.firestore();

  /** @type {{ role: string, uid: string, email: string, fullName: string }[]} */
  const seeded = [];

  for (const role of ROLES) {
    const email = emailForRole(role);
    const fullName = displayNameForRole(role);
    const userRecord = await upsertAuthUser(auth, email, DEMO_PASSWORD, fullName);
    seeded.push({ role, uid: userRecord.uid, email, fullName });
  }

  const now = admin.firestore.FieldValue.serverTimestamp();
  const pastorEmail = emailForRole("pastor");

  const batch = db.batch();

  batch.set(
    db.doc(`churches/${CHURCH_ID}`),
    {
      id: CHURCH_ID,
      name: CHURCH_NAME,
      slug: "demo-community",
      logoUrl: null,
      primaryColor: "#1A56DB",
      address: null,
      contactEmail: pastorEmail,
      contactPhone: null,
      timezone: "Africa/Accra",
      currency: "GHS",
      currencySymbol: "₵",
      createdAt: now,
      updatedAt: now,
      settings: {
        requireApproval: true,
        allowStaffDeleteOwn: true,
        notifyPastorOnEntry: true,
        notifyStaffOnApproval: true,
      },
    },
    { merge: true },
  );

  for (const { role, uid, email, fullName } of seeded) {
    batch.set(
      db.doc(`user_church_index/${uid}`),
      {
        churchId: CHURCH_ID,
        role,
        updatedAt: now,
      },
      { merge: true },
    );

    batch.set(
      db.doc(`churches/${CHURCH_ID}/users/${uid}`),
      {
        uid,
        churchId: CHURCH_ID,
        role,
        fullName,
        email,
        phone: null,
        avatarUrl: null,
        isActive: true,
        fcmToken: null,
        inviteCodeId: null,
        createdAt: now,
        updatedAt: now,
        lastLoginAt: null,
      },
      { merge: true },
    );
  }

  await batch.commit();

  const rows = seeded
    .map((s) => `  ${s.role.padEnd(8)} ${s.email.padEnd(28)} ${DEMO_PASSWORD}`)
    .join("\n");

  console.log(`
──────────────────────────────────────────────────────────
 Demo data ready — church: ${CHURCH_ID}
 Domain: @${EMAIL_DOMAIN}   Password (all): ${DEMO_PASSWORD}
──────────────────────────────────────────────────────────
 role     email                          password
──────────────────────────────────────────────────────────
${rows}
──────────────────────────────────────────────────────────
`);
}

main().catch((err) => {
  const msg = String(err?.message || err);
  if (
    msg.includes("Could not load the default credentials") ||
    msg.includes("ENOTFOUND") ||
    err?.code === 7 /* PERMISSION_DENIED */ ||
    err?.code === "PERMISSION_DENIED"
  ) {
    printCredentialHelp();
  }
  console.error(err);
  process.exit(1);
});
