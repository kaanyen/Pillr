import * as admin from "firebase-admin";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {GoogleAuth} from "google-auth-library";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {onCall, HttpsError} from "firebase-functions/v2/https";

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

function exportUriPrefix(bucket: string, folder = "scheduled"): string {
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  return `gs://${bucket}/${folder}/${stamp}`;
}

/** Days a backup is kept: the bucket's lifecycle rule deletes it after. */
export const BACKUP_KEEP_DAYS = 365;

async function accessToken(): Promise<string> {
  const auth = new GoogleAuth({scopes: ["https://www.googleapis.com/auth/cloud-platform"]});
  const token = await (await auth.getClient()).getAccessToken();
  if (!token.token) throw new Error("Could not obtain an access token.");
  return token.token;
}

/**
 * Every backup, weekly or by hand, is noted in `backups` so the Backups page
 * can list them and Health can say when the last one finished. The export
 * covers the whole database, every church in it: it is a copy, never a
 * restore, so starting one changes nothing.
 */
async function recordBackup(data: {
  kind: "scheduled" | "manual";
  uri: string;
  operation: string;
  byUid?: string;
  byName?: string;
  churchId?: string;
}): Promise<void> {
  await admin.firestore().collection("backups").add({
    ...data,
    state: "PROCESSING",
    startedAt: FieldValue.serverTimestamp(),
    completedAt: null,
    documents: null,
  });
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
    await recordBackup({kind: "scheduled", uri: prefix, operation});
    console.log(
      `Firestore backup started: project=${projectId} uri=${prefix} operation=${operation}`,
    );
  },
);

async function caller(uid: string | undefined) {
  if (!uid) throw new HttpsError("unauthenticated", "You must be signed in.");
  const idx = await admin.firestore().doc(`user_church_index/${uid}`).get();
  const role = String(idx.get("role") ?? "");
  if (role !== "admin" && role !== "pastor") {
    throw new HttpsError("permission-denied", "Backups are for admins and pastors.");
  }
  const churchId = String(idx.get("churchId") ?? "");
  const user = await admin.firestore().doc(`churches/${churchId}/users/${uid}`).get();
  return {uid, role, churchId, name: String(user.get("fullName") ?? "")};
}

/** Back up now. At most once an hour, whoever asks. */
export const startBackup = onCall({region: REGION}, async (request) => {
  const who = await caller(request.auth?.uid);
  const last = await admin.firestore().collection("backups")
    .orderBy("startedAt", "desc").limit(1).get();
  const at = (last.docs[0]?.get("startedAt") as Timestamp | undefined)?.toMillis() ?? 0;
  if (Date.now() - at < 60 * 60000) {
    throw new HttpsError("failed-precondition", "A backup started less than an hour ago. Try again later.");
  }
  const projectId = resolveProjectId();
  const prefix = exportUriPrefix(resolveBackupBucket(projectId), "manual");
  // The export API is not emulated: on the emulator this would copy the live
  // database. Note a pretend backup instead.
  if (process.env.FUNCTIONS_EMULATOR === "true") {
    await admin.firestore().collection("backups").add({
      kind: "manual", uri: `${prefix}-emulator`, operation: null, state: "SUCCESSFUL",
      startedAt: FieldValue.serverTimestamp(), completedAt: FieldValue.serverTimestamp(),
      documents: 0, byUid: who.uid, byName: who.name, churchId: who.churchId,
    });
    return {uri: prefix, emulator: true};
  }
  const operation = await startFirestoreExport(prefix);
  await recordBackup({
    kind: "manual", uri: prefix, operation,
    byUid: who.uid, byName: who.name, churchId: who.churchId,
  });
  return {uri: prefix};
});

/**
 * Every backup, newest first. Ones still running are checked with Firestore
 * and their record brought up to date: finished, how many documents, or
 * failed and why.
 */
export const listBackups = onCall({region: REGION}, async (request) => {
  await caller(request.auth?.uid);
  const snap = await admin.firestore().collection("backups")
    .orderBy("startedAt", "desc").limit(120).get();
  let token: string | null = null;
  for (const d of snap.docs) {
    if (d.get("state") !== "PROCESSING" || !d.get("operation")) continue;
    try {
      token ??= await accessToken();
      const res = await fetch(`https://firestore.googleapis.com/v1/${d.get("operation")}`, {
        headers: {Authorization: `Bearer ${token}`},
      });
      if (!res.ok) continue;
      const op = (await res.json()) as {
        done?: boolean;
        error?: {message?: string};
        metadata?: {operationState?: string; endTime?: string; progressDocuments?: {completedWork?: string}};
      };
      if (!op.done) continue;
      await d.ref.update({
        state: op.error ? "FAILED" : (op.metadata?.operationState ?? "SUCCESSFUL"),
        error: op.error?.message ?? null,
        completedAt: op.metadata?.endTime ? Timestamp.fromDate(new Date(op.metadata.endTime)) : FieldValue.serverTimestamp(),
        documents: Number(op.metadata?.progressDocuments?.completedWork ?? 0) || null,
      });
    } catch (e) {
      console.warn("listBackups: could not check", d.id, e);
    }
  }
  const fresh = await admin.firestore().collection("backups")
    .orderBy("startedAt", "desc").limit(120).get();
  const ms = (v: unknown) => (v as Timestamp | undefined)?.toMillis?.() ?? null;
  return {
    keepDays: BACKUP_KEEP_DAYS,
    backups: fresh.docs.map((d) => ({
      id: d.id,
      kind: String(d.get("kind") ?? "scheduled"),
      state: String(d.get("state") ?? "PROCESSING"),
      startedAt: ms(d.get("startedAt")),
      completedAt: ms(d.get("completedAt")),
      documents: d.get("documents") ?? null,
      byName: d.get("byName") ?? null,
      error: d.get("error") ?? null,
      folder: String(d.get("uri") ?? "").split("/").slice(-2).join("/"),
    })),
  };
});

