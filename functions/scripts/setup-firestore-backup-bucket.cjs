/**
 * One-time setup for scheduled Firestore exports to GCS.
 *
 * Creates the backup bucket, lifecycle retention, and IAM for the Firestore
 * service agent. Also grants the Cloud Functions runtime export permission.
 *
 * Requires Admin credentials (same as seed-demo):
 *   export GOOGLE_APPLICATION_CREDENTIALS="/path/to/serviceAccount.json"
 *   npm run setup-firestore-backup --prefix functions
 *
 * Env:
 *   FIREBASE_PROJECT_ID — default thepillr2
 *   FIRESTORE_BACKUP_BUCKET — default {projectId}-firestore-backups
 *   FIRESTORE_BACKUP_RETENTION_DAYS — default 365
 */
/* eslint-disable @typescript-eslint/no-require-imports */
const {Storage} = require("@google-cloud/storage");
const {GoogleAuth} = require("google-auth-library");
const {execSync} = require("child_process");

const DEFAULT_PROJECT_ID = "thepillr2";
const DEFAULT_RETENTION_DAYS = 365;

function resolveProjectId() {
  return (
    process.env.FIREBASE_PROJECT_ID ||
    process.env.GCLOUD_PROJECT ||
    process.env.GOOGLE_CLOUD_PROJECT ||
    DEFAULT_PROJECT_ID
  );
}

function resolveBucketName(projectId) {
  const raw = process.env.FIRESTORE_BACKUP_BUCKET?.trim();
  if (raw) return raw.replace(/^gs:\/\//, "").replace(/\/$/, "");
  return `${projectId}-firestore-backups`;
}

function retentionDays() {
  const n = Number(process.env.FIRESTORE_BACKUP_RETENTION_DAYS ?? DEFAULT_RETENTION_DAYS);
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : DEFAULT_RETENTION_DAYS;
}

async function getProjectNumber(projectId) {
  const auth = new GoogleAuth({
    scopes: ["https://www.googleapis.com/auth/cloud-platform"],
  });
  const client = await auth.getClient();
  const token = (await client.getAccessToken()).token;
  const res = await fetch(`https://cloudresourcemanager.googleapis.com/v1/projects/${projectId}`, {
    headers: {Authorization: `Bearer ${token}`},
  });
  if (!res.ok) {
    throw new Error(`Could not read project metadata (${res.status}): ${await res.text()}`);
  }
  const data = await res.json();
  return String(data.projectNumber);
}

async function ensureBucket(storage, bucketName, location, days) {
  const bucket = storage.bucket(bucketName);
  const [exists] = await bucket.exists();
  if (!exists) {
    await storage.createBucket(bucketName, {
      location,
      uniformBucketLevelAccess: true,
      lifecycle: {
        rule: [
          {
            action: {type: "Delete"},
            condition: {age: days},
          },
        ],
      },
    });
    console.log(`Created bucket gs://${bucketName} (${location}, delete after ${days} days)`);
    return bucket;
  }

  await bucket.setMetadata({
    lifecycle: {
      rule: [
        {
          action: {type: "Delete"},
          condition: {age: days},
        },
      ],
    },
  });
  console.log(`Bucket gs://${bucketName} exists — lifecycle set to ${days} days`);
  return bucket;
}

async function grantFirestoreAgentBucketAccess(bucket, projectNumber) {
  const firestoreSa = `service-${projectNumber}@gcp-sa-firestore.iam.gserviceaccount.com`;
  const member = `serviceAccount:${firestoreSa}`;
  const role = "roles/storage.admin";

  const [policy] = await bucket.iam.getPolicy({requestedPolicyVersion: 3});
  const bindings = policy.bindings ?? [];
  const existing = bindings.find((b) => b.role === role);
  if (existing) {
    if (!existing.members.includes(member)) {
      existing.members.push(member);
    }
  } else {
    bindings.push({role, members: [member]});
  }
  policy.bindings = bindings;
  await bucket.iam.setPolicy(policy);
  console.log(`Granted ${role} on gs://${bucket.name} to ${firestoreSa}`);
}

async function grantExportRoleToComputeSa(projectId, projectNumber) {
  const computeSa = `${projectNumber}-compute@developer.gserviceaccount.com`;
  const role = "roles/datastore.importExportAdmin";
  const member = `serviceAccount:${computeSa}`;

  try {
    execSync(
      `gcloud projects add-iam-policy-binding ${projectId} ` +
        `--member="${member}" --role="${role}" --condition=None`,
      {stdio: "pipe"},
    );
    console.log(`Granted ${role} to ${computeSa}`);
    return;
  } catch (_) {
    // Fall through to REST API below.
  }

  return grantProjectRoleViaApi(projectId, member, role, computeSa);
}

async function grantProjectRoleViaApi(projectId, member, role, label) {
  const auth = new GoogleAuth({
    scopes: ["https://www.googleapis.com/auth/cloud-platform"],
  });
  const client = await auth.getClient();
  const token = (await client.getAccessToken()).token;

  const getRes = await fetch(
    `https://cloudresourcemanager.googleapis.com/v1/projects/${projectId}:getIamPolicy`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({options: {requestedPolicyVersion: 3}}),
    },
  );
  if (!getRes.ok) {
    throw new Error(`getIamPolicy failed (${getRes.status}): ${await getRes.text()}`);
  }
  const policy = await getRes.json();
  const bindings = policy.bindings ?? [];
  const existing = bindings.find((b) => b.role === role);
  if (existing) {
    if (!existing.members.includes(member)) existing.members.push(member);
  } else {
    bindings.push({role, members: [member]});
  }
  policy.bindings = bindings;

  const setRes = await fetch(
    `https://cloudresourcemanager.googleapis.com/v1/projects/${projectId}:setIamPolicy`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({policy}),
    },
  );
  if (!setRes.ok) {
    console.warn(`
Could not grant ${role} automatically.

Run manually:
  gcloud projects add-iam-policy-binding ${projectId} \\
    --member="${member}" \\
    --role="${role}"
`);
    return;
  }
  console.log(`Granted ${role} to ${label}`);
}

async function main() {
  const projectId = resolveProjectId();
  const bucketName = resolveBucketName(projectId);
  const days = retentionDays();
  const location = process.env.FIRESTORE_BACKUP_LOCATION?.trim() || "us-central1";

  console.log(`Project: ${projectId}`);
  console.log(`Backup bucket: gs://${bucketName}`);
  console.log(`Retention: ${days} days`);

  const projectNumber = await getProjectNumber(projectId);
  const storage = new Storage({projectId});
  const bucket = await ensureBucket(storage, bucketName, location, days);
  await grantFirestoreAgentBucketAccess(bucket, projectNumber);
  await grantExportRoleToComputeSa(projectId, projectNumber);

  console.log(`
Setup complete. Next steps:
  1. Deploy functions (includes scheduledFirestoreBackup — Sundays 03:00 UTC):
       npm run build --prefix functions && firebase deploy --only functions --project ${projectId}
  2. Optional manual test export:
       gcloud firestore export gs://${bucketName}/manual/test --project=${projectId}
  3. See docs/BACKUP.md for restore and monitoring.
`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
