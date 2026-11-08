/**
 * The server side of "who sees what".
 *
 * Staff read only the entries they recorded and admins read none, so the
 * few things that need the whole church run here and answer without the
 * figures behind them:
 *
 * - findSimilarEntries: is this new entry a likely duplicate of one already
 *   in Pillr? Yes or no, per candidate. Staff need it for entries other
 *   staff recorded, which they cannot read.
 * - churchHealth: the admin's Health page. Counts and ages only.
 * - remindPastors: one short note to every pastor that entries are waiting.
 */
import * as admin from "firebase-admin";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {onCall, HttpsError} from "firebase-functions/v2/https";

const REGION = "us-central1";
const db = () => admin.firestore();

async function membership(uid: string): Promise<{churchId: string; role: string}> {
  const snap = await db().doc(`user_church_index/${uid}`).get();
  if (!snap.exists) throw new HttpsError("permission-denied", "No church membership for this account.");
  const d = snap.data()!;
  return {churchId: String(d.churchId), role: String(d.role)};
}

/** The calendar day a moment falls on in the church's time zone. */
export function dayIn(d: Date, timeZone: string): string {
  return new Intl.DateTimeFormat("en-CA", {timeZone, year: "numeric", month: "2-digit", day: "2-digit"}).format(d);
}

export type Candidate = {
  key: string;
  partnerId: string;
  armId: string;
  periodId: string;
  amountCedis: number;
  dateGiven: Date;
};

export type ExistingEntry = {
  partnerId: string;
  partnershipArmId: string;
  partnershipPeriodId: string;
  amountCedis: number;
  dateGiven: Date;
};

/**
 * Same partner, arm and period, the same day, and an amount within 10% —
 * the rule in lib/core/utils/entry_duplicate_utils.dart. Keep them in step.
 */
export function isSimilar(c: Candidate, e: ExistingEntry, timeZone: string): boolean {
  if (e.partnerId !== c.partnerId) return false;
  if (e.partnershipArmId !== c.armId) return false;
  if (e.partnershipPeriodId !== c.periodId) return false;
  if (dayIn(e.dateGiven, timeZone) !== dayIn(c.dateGiven, timeZone)) return false;
  return c.amountCedis >= e.amountCedis * 0.9 && c.amountCedis <= e.amountCedis * 1.1;
}

export const findSimilarEntries = onCall({region: REGION}, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "You must be signed in.");
  const idx = await membership(uid);
  if (idx.role !== "pastor" && idx.role !== "staff") {
    throw new HttpsError("permission-denied", "Only pastors and staff record giving.");
  }
  const raw = request.data?.candidates;
  if (!Array.isArray(raw) || raw.length > 2000) {
    throw new HttpsError("invalid-argument", "candidates must be a list of up to 2000.");
  }
  const candidates: Candidate[] = [];
  for (const r of raw) {
    const ms = Number(r?.dateGivenMs);
    if (typeof r?.key !== "string" || typeof r?.partnerId !== "string" || !r.partnerId ||
        !Number.isFinite(ms) || !Number.isFinite(Number(r?.amountCedis))) {
      throw new HttpsError("invalid-argument", "Each candidate needs a key, partnerId, amount and date.");
    }
    candidates.push({
      key: r.key,
      partnerId: r.partnerId,
      armId: String(r.armId ?? ""),
      periodId: String(r.periodId ?? ""),
      amountCedis: Number(r.amountCedis),
      dateGiven: new Date(ms),
    });
  }
  const church = await db().doc(`churches/${idx.churchId}`).get();
  const timeZone = String(church.get("timezone") || "Africa/Accra");

  const similar: string[] = [];
  const byPartner = new Map<string, Candidate[]>();
  for (const c of candidates) byPartner.set(c.partnerId, [...(byPartner.get(c.partnerId) ?? []), c]);
  for (const [partnerId, cs] of byPartner) {
    const snap = await db().collection(`churches/${idx.churchId}/entries`)
      .where("partnerId", "==", partnerId).get();
    const existing: ExistingEntry[] = snap.docs.map((d) => ({
      partnerId,
      partnershipArmId: String(d.get("partnershipArmId") ?? ""),
      partnershipPeriodId: String(d.get("partnershipPeriodId") ?? ""),
      amountCedis: Number(d.get("amountCedis") ?? 0),
      dateGiven: (d.get("dateGiven") as Timestamp | undefined)?.toDate() ?? new Date(0),
    }));
    for (const c of cs) if (existing.some((e) => isSimilar(c, e, timeZone))) similar.push(c.key);
  }
  // Only which candidates look like duplicates: nothing about the entries
  // they match, who recorded them or for how much.
  return {similar};
});

/** Whole days between two moments. */
const daysBetween = (a: Date, b: Date) => Math.floor((b.getTime() - a.getTime()) / 86400000);

export const churchHealth = onCall({region: REGION, timeoutSeconds: 120, memory: "512MiB"}, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "You must be signed in.");
  const idx = await membership(uid);
  if (idx.role !== "admin" && idx.role !== "pastor") {
    throw new HttpsError("permission-denied", "Health is for admins and pastors.");
  }
  const church = db().doc(`churches/${idx.churchId}`);
  const now = new Date();

  // Waiting entries: how many and how long, never whose or how much.
  const pending = await church.collection("entries").where("status", "==", "pending").get();
  const ages = pending.docs.map((d) => {
    const at = (d.get("createdAt") as Timestamp | undefined)?.toDate() ?? now;
    return daysBetween(at, now);
  });
  const waiting = {
    count: ages.length,
    oldestDays: ages.length ? Math.max(...ages) : 0,
    underWeek: ages.filter((a) => a < 7).length,
    underMonth: ages.filter((a) => a >= 7 && a < 30).length,
    overMonth: ages.filter((a) => a >= 30).length,
  };

  const dupDoc = await church.collection("health").doc("duplicates").get();
  const duplicates = {
    open: Number(dupDoc.get("open") ?? 0),
    checkedAt: (dupDoc.get("checkedAt") as Timestamp | undefined)?.toMillis() ?? null,
  };

  const summary = await church.collection("monthly_email_summaries").orderBy("ranAt", "desc").limit(1).get();
  const s = summary.docs[0];
  const letters = s ? {
    yearMonth: String(s.get("yearMonth") ?? s.id),
    monthLabel: String(s.get("monthLabel") ?? ""),
    sent: Number(s.get("sent") ?? 0),
    failed: Number(s.get("failed") ?? 0),
    noEmail: Number(s.get("noEmail") ?? 0),
    turnedOff: Number(s.get("turnedOff") ?? 0),
    ranAt: (s.get("ranAt") as Timestamp | undefined)?.toMillis() ?? null,
  } : null;

  // Sheets brought in during the last 30 days: name, rows, by whom, when,
  // and how many of their entries still wait. No totals.
  const since = Timestamp.fromDate(new Date(now.getTime() - 30 * 86400000));
  const batches = await church.collection("import_batches")
    .where("createdAt", ">=", since).orderBy("createdAt", "desc").limit(10).get();
  const sheets = [];
  for (const b of batches.docs) {
    const w = await church.collection("entries")
      .where("importBatchId", "==", b.id).where("status", "==", "pending").count().get();
    sheets.push({
      fileName: String(b.get("label") || b.get("fileName") || "A sheet"),
      rows: Number(b.get("entryCount") ?? 0),
      by: String(b.get("createdByName") ?? ""),
      at: (b.get("createdAt") as Timestamp | undefined)?.toMillis() ?? null,
      waiting: w.data().count,
      undone: b.get("undoneAt") != null || b.get("voidedAt") != null,
    });
  }

  // Do the stored totals still match the entries? The answer, not the sums.
  const [approved, partnerTotals, periodTotals] = await Promise.all([
    church.collection("entries").where("status", "==", "approved").get(),
    church.collection("partner_totals").get(),
    church.collection("period_totals").get(),
  ]);
  const expected = (field: string) => {
    const m = new Map<string, number>();
    for (const d of approved.docs) {
      const id = String(d.get(field) ?? "");
      if (!id) continue;
      m.set(id, (m.get(id) ?? 0) + Math.round(Number(d.get("amountCedis") ?? 0) * 100));
    }
    return m;
  };
  const drift = (want: Map<string, number>, stored: admin.firestore.QuerySnapshot) => {
    const have = new Map(stored.docs.map((d) => [d.id,
      Number(d.get("totalApprovedPesewas") ?? Math.round(Number(d.get("totalApprovedAmount") ?? 0) * 100))]));
    let n = 0;
    for (const id of new Set([...want.keys(), ...have.keys()])) {
      if ((want.get(id) ?? 0) !== (have.get(id) ?? 0)) n++;
    }
    return n;
  };
  const totals = {
    partnersOff: drift(expected("partnerId"), partnerTotals),
    periodsOff: drift(expected("partnershipPeriodId"), periodTotals),
  };

  // The last backup that finished. Backups cover the whole database.
  const lastBackupSnap = await db().collection("backups")
    .where("state", "==", "SUCCESSFUL").orderBy("startedAt", "desc").limit(1).get();
  const lb = lastBackupSnap.docs[0];
  const lastBackup = lb ? {
    at: (lb.get("completedAt") as Timestamp | undefined)?.toMillis() ??
      (lb.get("startedAt") as Timestamp | undefined)?.toMillis() ?? null,
    kind: String(lb.get("kind") ?? "scheduled"),
  } : null;
  const reminded = await church.collection("health").doc("reminders").get();
  return {
    waiting,
    duplicates,
    letters,
    sheets,
    totals,
    lastRemindedAt: (reminded.get("lastAt") as Timestamp | undefined)?.toMillis() ?? null,
    lastBackup,
  };
});

export const remindPastors = onCall({region: REGION}, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "You must be signed in.");
  const idx = await membership(uid);
  if (idx.role !== "admin") throw new HttpsError("permission-denied", "Only an admin sends reminders.");
  const church = db().doc(`churches/${idx.churchId}`);
  const marker = church.collection("health").doc("reminders");
  const last = (await marker.get()).get("lastAt") as Timestamp | undefined;
  if (last && Date.now() - last.toMillis() < 20 * 3600000) {
    throw new HttpsError("failed-precondition", "The pastors were reminded today already.");
  }
  const pending = await church.collection("entries").where("status", "==", "pending").get();
  if (pending.empty) throw new HttpsError("failed-precondition", "Nothing is waiting.");
  const now = Date.now();
  const oldest = Math.max(...pending.docs.map((d) =>
    Math.floor((now - ((d.get("createdAt") as Timestamp | undefined)?.toMillis() ?? now)) / 86400000)));
  const n = pending.size;
  const body = `${n} ${n === 1 ? "entry is" : "entries are"} waiting for you` +
    (oldest > 0 ? `, the oldest ${oldest} ${oldest === 1 ? "day" : "days"}.` : ".");

  const pastors = await church.collection("users").where("role", "==", "pastor").get();
  const tokens = pastors.docs.map((d) => d.get("fcmToken") as string | undefined).filter((t): t is string => !!t);
  let delivered = 0;
  if (tokens.length > 0) {
    const r = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: {title: "Entries waiting in Pillr", body},
    });
    delivered = r.successCount;
  }
  const actor = (await church.collection("users").doc(uid).get()).data() ?? {};
  await marker.set({lastAt: FieldValue.serverTimestamp(), by: uid}, {merge: true});
  await church.collection("activity_logs").add({
    churchId: idx.churchId,
    actorUid: uid,
    actorSnapshot: {fullName: String(actor.fullName ?? ""), role: "admin"},
    action: "health.remind",
    entityType: "church",
    entityId: null,
    entitySnapshot: {waiting: n},
    metadata: {source: "server"},
    createdAt: FieldValue.serverTimestamp(),
  });
  return {pastors: pastors.size, delivered, message: body};
});
