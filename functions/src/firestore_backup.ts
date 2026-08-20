import {GoogleAuth} from "google-auth-library";
import {onSchedule} from "firebase-functions/v2/scheduler";

const REGION = "us-central1";

function resolveProjectId(): string {
  return (
    process.env.GCLOUD_PROJECT ||
    process.env.GCP_PROJECT ||
    process.env.FIREBASE_PROJECT_ID ||
    "thepillr2"
  );
}

function resolveBackupBucket(projectId: string): string {
  const raw = process.env.FIRESTORE_BACKUP_BUCKET?.trim();
  if (raw) {
    return raw.replace(/^gs:\/\//, "").replace(/\/$/, "");
  }
  return `${projectId}-firestore-backups`;
}

function exportUriPrefix(bucket: string): string {
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  return `gs://${bucket}/scheduled/${stamp}`;
}

/** Starts an async Firestore export to GCS (long-running operation). */
export async function startFirestoreExport(outputUriPrefix: string): Promise<string> {
  const projectId = resolveProjectId();
  const auth = new GoogleAuth({
    scopes: ["https://www.googleapis.com/auth/cloud-platform"],
  });
  const client = await auth.getClient();
  const token = await client.getAccessToken();
  if (!token.token) {
    throw new Error("Could not obtain access token for Firestore export.");
  }

  const url =
    `https://firestore.googleapis.com/v1/projects/${projectId}` +
    "/databases/(default):exportDocuments";

  const res = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token.token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({outputUriPrefix}),
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Firestore export failed (${res.status}): ${body}`);
  }

  const data = (await res.json()) as {name?: string};
  if (!data.name) {
    throw new Error("Firestore export started but no operation name was returned.");
  }
  return data.name;
}

/**
 * Weekly Firestore export to GCS for long-term backup / compliance.
 * One-time setup: npm run setup-firestore-backup --prefix functions
 */
export const scheduledFirestoreBackup = onSchedule(
  {
    schedule: "0 3 * * 0",
    region: REGION,
    timeZone: "UTC",
  },
  async () => {
    const projectId = resolveProjectId();
    const bucket = resolveBackupBucket(projectId);
    const prefix = exportUriPrefix(bucket);
    const operation = await startFirestoreExport(prefix);
    console.log(
      `Firestore backup started: project=${projectId} uri=${prefix} operation=${operation}`,
    );
  },
);
