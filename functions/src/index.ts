import * as admin from "firebase-admin";
import * as functionsV1 from "firebase-functions/v1";
import {getStorage} from "firebase-admin/storage";
import PDFDocument from "pdfkit";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {Resend} from "resend";

admin.initializeApp();
const db = admin.firestore();

const REGION = "us-central1";

/** Matches Dart [TextCaseUtils.toTitleCase] for names and labels. */
function toTitleCase(input: string): string {
  const s = input.trim();
  if (!s) return "";
  return s.split(/\s+/).map(titleCaseWord).join(" ");
}

function titleCaseWord(word: string): string {
  if (!word) return "";
  if (word.includes("-")) return word.split("-").map(titleCaseSegment).join("-");
  if (word.includes("'")) return word.split("'").map(titleCaseSegment).join("'");
  if (/^[A-Za-z]+$/.test(word) && word.length >= 2 && word.length <= 4 && word === word.toUpperCase()) {
    return word.toUpperCase();
  }
  return titleCaseSegment(word);
}

function titleCaseSegment(segment: string): string {
  if (!segment) return "";
  if (/^\d/.test(segment)) return segment;
  if (segment.length === 1) return segment.toUpperCase();
  return segment[0].toUpperCase() + segment.slice(1).toLowerCase();
}

/** Must match a domain verified in Resend (Dashboard → Domains). Default: thepillr.com. */
const RESEND_FROM =
  process.env.RESEND_FROM ?? "The Pillr <invites@thepillr.com>";

function randomCode(): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let s = "";
  for (let i = 0; i < 8; i++) {
    s += chars[Math.floor(Math.random() * chars.length)];
  }
  return s;
}

async function sendInviteEmail(
  toEmail: string,
  churchName: string,
  inviteCode: string,
  role: string,
  inviterName: string,
): Promise<void> {
  const key = process.env.RESEND_API_KEY;
  if (!key) {
    console.warn("RESEND_API_KEY not set; skipping email.");
    return;
  }
  const resend = new Resend(key);
  const joinUrl = `https://thepillr2.web.app/join?code=${inviteCode}`;
  await resend.emails.send({
    from: RESEND_FROM,
    to: toEmail,
    subject: `You're invited to join ${churchName} on Pillr`,
    html: `
      <div style="font-family: Inter, sans-serif; max-width: 560px; margin: 0 auto;">
        <h2>You've been invited to The Pillr</h2>
        <p>${inviterName} has invited you to join <strong>${churchName}</strong> as a <strong>${role}</strong>.</p>
        <p>Your invitation code is:</p>
        <div style="background: #F3F4F6; padding: 24px; border-radius: 8px; text-align: center; margin: 24px 0;">
          <span style="font-size: 32px; font-weight: 700; letter-spacing: 4px; color: #1A56DB;">
            ${inviteCode}
          </span>
        </div>
        <p>This code expires in <strong>4 hours</strong>.</p>
        <a href="${joinUrl}" style="display: inline-block; background: #1A56DB; color: white;
          padding: 12px 24px; border-radius: 8px; text-decoration: none; font-weight: 600;">
          Accept Invitation
        </a>
      </div>`,
  });
}

export const validateInviteCode = onCall({region: REGION}, async (request) => {
  const email = String(request.data?.email ?? "").trim().toLowerCase();
  const code = String(request.data?.code ?? "").trim().toUpperCase();
  if (!email || !code) {
    return {valid: false, message: "Email and code are required."};
  }
  const snap = await db
    .collectionGroup("invite_codes")
    .where("code", "==", code)
    .where("email", "==", email)
    .limit(1)
    .get();
  if (snap.empty) {
    return {valid: false, message: "Invite not found for this email and code."};
  }
  const doc = snap.docs[0];
  const data = doc.data();
  const churchRef = doc.ref.parent.parent;
  if (!churchRef) {
    return {valid: false, message: "Invalid invite path."};
  }
  const churchId = churchRef.id;
  const expiresAt = data.expiresAt as admin.firestore.Timestamp;
  if (data.status !== "pending") {
    return {valid: false, message: "This invite is no longer valid."};
  }
  if (expiresAt.toMillis() < Date.now()) {
    await doc.ref.update({status: "expired"});
    return {valid: false, message: "This invite has expired."};
  }
  const churchSnap = await churchRef.get();
  const churchName = (churchSnap.data()?.name as string) ?? "your church";
  return {
    valid: true,
    churchName,
    churchId,
    role: data.role as string,
    codeId: doc.id,
  };
});

export const completeRegistration = onCall({region: REGION}, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "You must be signed in.");
  }
  const fullName = toTitleCase(String(request.data?.fullName ?? ""));
  const phone = String(request.data?.phone ?? "").trim();
  const codeId = String(request.data?.codeId ?? "").trim();
  const churchId = String(request.data?.churchId ?? "").trim();
  if (!fullName || !codeId || !churchId) {
    throw new HttpsError("invalid-argument", "fullName, codeId, and churchId are required.");
  }
  const inviteRef = db.doc(`churches/${churchId}/invite_codes/${codeId}`);
  const inviteSnap = await inviteRef.get();
  if (!inviteSnap.exists) {
    throw new HttpsError("not-found", "Invite not found.");
  }
  const inv = inviteSnap.data()!;
  const email = (request.auth?.token?.email as string | undefined)?.toLowerCase();
  if (!email || email !== String(inv.email).toLowerCase()) {
    throw new HttpsError("permission-denied", "Signed-in email must match the invitation.");
  }
  if (inv.status !== "pending") {
    throw new HttpsError("failed-precondition", "Invite is not pending.");
  }
  const exp = inv.expiresAt as admin.firestore.Timestamp;
  if (exp.toMillis() < Date.now()) {
    await inviteRef.update({status: "expired"});
    throw new HttpsError("failed-precondition", "Invite has expired.");
  }
  const role = inv.role as string;
  const batch = db.batch();
  const userChurchRef = db.doc(`user_church_index/${uid}`);
  batch.set(userChurchRef, {churchId, role, updatedAt: admin.firestore.FieldValue.serverTimestamp()});
  const userRef = db.doc(`churches/${churchId}/users/${uid}`);
  batch.set(userRef, {
    uid,
    churchId,
    role,
    fullName,
    email,
    phone: phone || null,
    avatarUrl: null,
    isActive: true,
    fcmToken: null,
    inviteCodeId: codeId,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    lastLoginAt: null,
  });
  batch.update(inviteRef, {
    status: "accepted",
    acceptedBy: uid,
    acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  await batch.commit();
  const createdBy = inv.createdBy as string | undefined;
  if (createdBy) {
    try {
      const inviterSnap = await db.doc(`churches/${churchId}/users/${createdBy}`).get();
      const token = inviterSnap.data()?.fcmToken as string | undefined;
      if (token) {
        const roleLabel =
          role === "admin" ? "Admin" : role === "pastor" ? "Pastor" : "Staff";
        await admin.messaging().send({
          token,
          notification: {
            title: "Invitation accepted",
            body: `${fullName} accepted your invitation as ${roleLabel}.`,
          },
        });
      }
    } catch (e) {
      console.warn("FCM invite accepted:", e);
    }
  }
  return {success: true};
});

export const generateInviteCode = onCall({region: REGION}, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "You must be signed in.");
  }
  const targetEmail = String(request.data?.email ?? "").trim().toLowerCase();
  const role = String(request.data?.role ?? "staff").trim().toLowerCase();
  const churchId = String(request.data?.churchId ?? "").trim();
  if (!targetEmail || !role || !churchId) {
    throw new HttpsError("invalid-argument", "email, role, and churchId are required.");
  }
  if (!["admin", "pastor", "staff"].includes(role)) {
    throw new HttpsError("invalid-argument", "Invalid role.");
  }
  const indexSnap = await db.doc(`user_church_index/${uid}`).get();
  if (!indexSnap.exists) {
    throw new HttpsError("permission-denied", "No church membership for this account.");
  }
  const idx = indexSnap.data()!;
  if (idx.churchId !== churchId) {
    throw new HttpsError("permission-denied", "Cannot invite for another church.");
  }
  const inviterRole = idx.role as string;
  if (inviterRole !== "admin" && inviterRole !== "pastor") {
    throw new HttpsError("permission-denied", "Only admins and pastors can invite.");
  }
  const userSnap = await db.doc(`churches/${churchId}/users/${uid}`).get();
  const inviterName = (userSnap.data()?.fullName as string) ?? "A team member";
  const churchSnap = await db.doc(`churches/${churchId}`).get();
  const churchName = (churchSnap.data()?.name as string) ?? "Your church";
  const code = randomCode();
  const now = admin.firestore.Timestamp.now();
  const expiresAt = admin.firestore.Timestamp.fromMillis(now.toMillis() + 4 * 60 * 60 * 1000);
  const col = db.collection(`churches/${churchId}/invite_codes`);
  const newRef = col.doc();
  await newRef.set({
    id: newRef.id,
    churchId,
    code,
    email: targetEmail,
    role,
    createdBy: uid,
    createdBySnapshot: {
      fullName: inviterName,
      role: inviterRole,
    },
    createdAt: now,
    expiresAt,
    status: "pending",
    acceptedBy: null,
    acceptedAt: null,
  });
  await sendInviteEmail(targetEmail, churchName, code, role, inviterName);
  return {success: true, codeId: newRef.id};
});

export const expireInviteCodes = onSchedule({schedule: "every 30 minutes", region: REGION}, async () => {
  const now = admin.firestore.Timestamp.now();
  const expired = await db
    .collectionGroup("invite_codes")
    .where("status", "==", "pending")
    .where("expiresAt", "<", now)
    .get();
  const writer = db.bulkWriter();
  for (const doc of expired.docs) {
    writer.update(doc.ref, {status: "expired"});
  }
  await writer.close();
});

/** Pastor-only: sets exactly one active period for the church. */
export const activatePeriod = onCall({region: REGION}, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "You must be signed in.");
  }
  const churchId = String(request.data?.churchId ?? "").trim();
  const periodId = String(request.data?.periodId ?? "").trim();
  if (!churchId || !periodId) {
    throw new HttpsError("invalid-argument", "churchId and periodId are required.");
  }
  const indexSnap = await db.doc(`user_church_index/${uid}`).get();
  if (!indexSnap.exists) {
    throw new HttpsError("permission-denied", "No church membership.");
  }
  const idx = indexSnap.data()!;
  if (idx.churchId !== churchId || idx.role !== "pastor") {
    throw new HttpsError("permission-denied", "Only pastors can activate periods.");
  }
  const col = db.collection(`churches/${churchId}/partnership_periods`);
  const snap = await col.get();
  if (snap.empty) {
    throw new HttpsError("failed-precondition", "No periods defined.");
  }
  const batch = db.batch();
  const ts = admin.firestore.FieldValue.serverTimestamp();
  for (const doc of snap.docs) {
    batch.update(doc.ref, {
      isActive: doc.id === periodId,
      updatedAt: ts,
    });
  }
  await batch.commit();
  return {success: true};
});

async function applyApprovalDeltas(churchId: string, entry: admin.firestore.DocumentData) {
  const amount = Number(entry.amountCedis ?? 0);
  if (!amount || amount <= 0) return;
  const partnerRef = db.doc(`churches/${churchId}/partners/${entry.partnerId}`);
  const periodRef = db.doc(`churches/${churchId}/partnership_periods/${entry.partnershipPeriodId}`);
  const batch = db.batch();
  batch.update(partnerRef, {
    totalApprovedAmount: admin.firestore.FieldValue.increment(amount),
    entryCount: admin.firestore.FieldValue.increment(1),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  batch.update(periodRef, {
    totalApprovedAmount: admin.firestore.FieldValue.increment(amount),
    entryCount: admin.firestore.FieldValue.increment(1),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  const goals = await db
    .collection(`churches/${churchId}/goals`)
    .where("partnershipPeriodId", "==", entry.partnershipPeriodId)
    .where("partnershipArmId", "==", entry.partnershipArmId)
    .limit(1)
    .get();
  if (!goals.empty) {
    batch.update(goals.docs[0].ref, {
      currentAmountCedis: admin.firestore.FieldValue.increment(amount),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
}

async function notifyPastorsNewEntry(churchId: string, entry: admin.firestore.DocumentData) {
  const users = await db.collection(`churches/${churchId}/users`).where("role", "==", "pastor").get();
  const tokens: string[] = [];
  for (const d of users.docs) {
    const t = d.data().fcmToken as string | undefined;
    if (t) tokens.push(t);
  }
  if (tokens.length === 0) return;
  const amt = Number(entry.amountCedis ?? 0).toFixed(2);
  try {
    await admin.messaging().sendEachForMulticast({
      tokens,
      notification: {
        title: "New partnership entry",
        body: `₵${amt} pending your review`,
      },
    });
  } catch (e) {
    console.warn("FCM notifyPastorsNewEntry:", e);
  }
}

async function notifyStaffEntryReviewed(churchId: string, after: admin.firestore.DocumentData) {
  const createdBy = after.createdBy as string | undefined;
  if (!createdBy) return;
  const userSnap = await db.doc(`churches/${churchId}/users/${createdBy}`).get();
  const token = userSnap.data()?.fcmToken as string | undefined;
  if (!token) return;
  const approved = after.status === "approved";
  try {
    await admin.messaging().send({
      token,
      notification: {
        title: approved ? "Entry approved" : "Entry declined",
        body: approved
          ? "Your partnership entry was approved."
          : (after.declineReason as string) || "Your entry was declined.",
      },
    });
  } catch (e) {
    console.warn("FCM notifyStaffEntryReviewed:", e);
  }
}

// Gen-1 Firestore triggers: Gen-2 uses Eventarc; deploy can fail with "Eventarc Service Agent"
// permission errors on first use. Gen-1 uses the legacy path and avoids that trigger-creation step.

export const onEntryCreated = functionsV1
  .region(REGION)
  .firestore.document("churches/{churchId}/entries/{entryId}")
  .onCreate(async (snap, context) => {
    const data = snap.data();
    if (!data) return;
    const churchId = context.params.churchId as string;
    if (data.status === "approved") {
      await applyApprovalDeltas(churchId, data);
      return;
    }
    if (data.status === "pending") {
      await notifyPastorsNewEntry(churchId, data);
    }
  });

export const onEntryUpdated = functionsV1
  .region(REGION)
  .firestore.document("churches/{churchId}/entries/{entryId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    if (!before || !after) return;
    const churchId = context.params.churchId as string;
    if (before.status === "pending" && after.status === "approved") {
      await applyApprovalDeltas(churchId, after);
    }
    if (before.status === "pending" && (after.status === "approved" || after.status === "declined")) {
      await notifyStaffEntryReviewed(churchId, after);
    }
  });

/** Normalizes partner name casing, keeps `fullNameLower` / `fellowshipLower` in sync. */
export const onPartnerWritten = functionsV1
  .region(REGION)
  .firestore.document("churches/{churchId}/partners/{partnerId}")
  .onWrite(async (change) => {
    const after = change.after.exists ? change.after.data() : null;
    if (!after) return;
    const nFull = toTitleCase(String(after.fullName ?? ""));
    const nFellow = toTitleCase(String(after.fellowship ?? ""));
    const fullNameLower = nFull.toLowerCase();
    const fellowshipLower = nFellow.toLowerCase();
    const patch: Record<string, unknown> = {};
    if (nFull !== String(after.fullName ?? "") || nFellow !== String(after.fellowship ?? "")) {
      patch.fullName = nFull;
      patch.fellowship = nFellow;
    }
    if (after.fullNameLower !== fullNameLower || after.fellowshipLower !== fellowshipLower) {
      patch.fullNameLower = fullNameLower;
      patch.fellowshipLower = fellowshipLower;
    }
    if (after.isActive === undefined) {
      patch.isActive = true;
    }
    if (Object.keys(patch).length === 0) {
      return;
    }
    await change.after.ref.update(patch);
  });

/** Pastor or admin: update another user's role and/or active flag (syncs `user_church_index` for role). */
export const updateChurchMember = onCall({region: REGION}, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "You must be signed in.");
  }
  const churchId = String(request.data?.churchId ?? "").trim();
  const targetUid = String(request.data?.targetUid ?? "").trim();
  const isActive = request.data?.isActive as boolean | undefined;
  const role = request.data?.role as string | undefined;
  if (!churchId || !targetUid) {
    throw new HttpsError("invalid-argument", "churchId and targetUid are required.");
  }
  if (targetUid === uid && role !== undefined) {
    throw new HttpsError("invalid-argument", "You cannot change your own role here.");
  }
  const indexSnap = await db.doc(`user_church_index/${uid}`).get();
  const idx = indexSnap.data();
  if (!idx || idx.churchId !== churchId) {
    throw new HttpsError("permission-denied", "Wrong church.");
  }
  const callerRole = idx.role as string;
  if (callerRole !== "admin" && callerRole !== "pastor") {
    throw new HttpsError("permission-denied", "Only admins and pastors can update members.");
  }
  if (role !== undefined) {
    if (!["admin", "pastor", "staff"].includes(role)) {
      throw new HttpsError("invalid-argument", "Invalid role.");
    }
    if (callerRole === "pastor" && role === "admin") {
      throw new HttpsError("permission-denied", "Pastors cannot assign the admin role.");
    }
  }
  const batch = db.batch();
  const userRef = db.doc(`churches/${churchId}/users/${targetUid}`);
  const targetIndexRef = db.doc(`user_church_index/${targetUid}`);
  const ts = admin.firestore.FieldValue.serverTimestamp();
  if (isActive !== undefined) {
    batch.update(userRef, {isActive, updatedAt: ts});
  }
  if (role !== undefined) {
    batch.update(userRef, {role, updatedAt: ts});
    batch.set(targetIndexRef, {churchId, role, updatedAt: ts}, {merge: true});
  }
  await batch.commit();
  return {success: true};
});

async function fetchImageBuffer(url: string): Promise<Buffer | null> {
  try {
    const res = await fetch(url);
    if (!res.ok) return null;
    const ab = await res.arrayBuffer();
    return Buffer.from(ab);
  } catch {
    return null;
  }
}

async function pastorFcmTokens(churchId: string): Promise<string[]> {
  const users = await db.collection(`churches/${churchId}/users`).where("role", "==", "pastor").get();
  const tokens: string[] = [];
  for (const d of users.docs) {
    const t = d.data().fcmToken as string | undefined;
    if (t) tokens.push(t);
  }
  return tokens;
}

async function generatePeriodSummaryPdf(churchId: string, periodId: string): Promise<void> {
  const periodSnap = await db.doc(`churches/${churchId}/partnership_periods/${periodId}`).get();
  if (!periodSnap.exists) return;
  const period = periodSnap.data()!;
  const churchSnap = await db.doc(`churches/${churchId}`).get();
  const churchData = churchSnap.data();
  const churchName = (churchData?.name as string) ?? "Church";
  const logoUrl = churchData?.logoUrl as string | undefined;
  let logoBuf: Buffer | null = null;
  if (logoUrl) {
    logoBuf = await fetchImageBuffer(logoUrl);
  }

  const entriesSnap = await db
    .collection(`churches/${churchId}/entries`)
    .where("partnershipPeriodId", "==", periodId)
    .where("status", "==", "approved")
    .get();

  const byArm = new Map<string, number>();
  const byPartner = new Map<string, {name: string; amount: number}>();
  let total = 0;
  for (const d of entriesSnap.docs) {
    const e = d.data();
    const amt = Number(e.amountCedis ?? 0);
    total += amt;
    const armId = String(e.partnershipArmId ?? "");
    const armName = String((e.armSnapshot as {name?: string} | undefined)?.name ?? armId);
    byArm.set(armName, (byArm.get(armName) ?? 0) + amt);
    const pid = String(e.partnerId ?? "");
    const pname = String((e.partnerSnapshot as {fullName?: string} | undefined)?.fullName ?? pid);
    const cur = byPartner.get(pid) ?? {name: pname, amount: 0};
    cur.amount += amt;
    byPartner.set(pid, cur);
  }

  const top = [...byPartner.values()].sort((a, b) => b.amount - a.amount).slice(0, 10);

  const buffer: Buffer = await new Promise((resolve, reject) => {
    const docPdf = new PDFDocument({margin: 50});
    const chunks: Buffer[] = [];
    docPdf.on("data", (c: Buffer) => chunks.push(c));
    docPdf.on("end", () => resolve(Buffer.concat(chunks)));
    docPdf.on("error", reject);

    if (logoBuf) {
      docPdf.image(logoBuf, {fit: [160, 52], align: "center"});
      docPdf.moveDown(0.5);
    }
    docPdf.fontSize(18).text(`${churchName} — period summary`, {underline: true});
    docPdf.moveDown();
    docPdf.fontSize(12).text(`Period: ${String(period.name ?? "")}`);
    docPdf.text(`Total approved: ₵${total.toFixed(2)}`);
    docPdf.moveDown();
    docPdf.fontSize(14).text("By arm");
    docPdf.fontSize(11);
    for (const [arm, amt] of [...byArm.entries()].sort((a, b) => b[1] - a[1])) {
      docPdf.text(`• ${arm}: ₵${amt.toFixed(2)}`);
    }
    docPdf.moveDown();
    docPdf.fontSize(14).text("Top contributors");
    docPdf.fontSize(11);
    for (const row of top) {
      docPdf.text(`• ${row.name}: ₵${row.amount.toFixed(2)}`);
    }
    docPdf.end();
  });

  const path = `churches/${churchId}/period_reports/${periodId}.pdf`;
  const bucket = getStorage().bucket();
  await bucket.file(path).save(buffer, {
    contentType: "application/pdf",
    resumable: false,
  });
  const [url] = await bucket.file(path).getSignedUrl({
    action: "read",
    expires: Date.now() + 1000 * 60 * 60 * 24 * 365 * 10,
  });

  await periodSnap.ref.update({
    summaryPdfUrl: url,
    summaryPdfStoragePath: path,
    summaryGeneratedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

/** FCM to pastors when a goal crosses 50%, 75%, or 100% of target (single notification for highest crossed). */
export const onPartnershipGoalUpdated = functionsV1
  .region(REGION)
  .firestore.document("churches/{churchId}/goals/{goalId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    if (!before || !after) return;
    const target = Number(after.targetAmountCedis ?? 0);
    if (target <= 0) return;
    const prevAmt = Number(before.currentAmountCedis ?? 0);
    const nextAmt = Number(after.currentAmountCedis ?? 0);
    if (prevAmt === nextAmt) return;
    const prev = prevAmt / target;
    const next = nextAmt / target;
    const milestones = [0.5, 0.75, 1.0];
    let maxCrossed = 0;
    for (const m of milestones) {
      if (prev < m && next >= m) {
        maxCrossed = Math.max(maxCrossed, m);
      }
    }
    if (maxCrossed === 0) return;

    const churchId = context.params.churchId as string;
    const tokens = await pastorFcmTokens(churchId);
    if (tokens.length === 0) return;

    const periodId = String(after.partnershipPeriodId ?? "");
    const armId = String(after.partnershipArmId ?? "");
    let periodName = periodId;
    let armName = armId;
    try {
      const pSnap = await db.doc(`churches/${churchId}/partnership_periods/${periodId}`).get();
      periodName = (pSnap.data()?.name as string) ?? periodId;
      const aSnap = await db.doc(`churches/${churchId}/partnership_arms/${armId}`).get();
      armName = (aSnap.data()?.name as string) ?? armId;
    } catch (e) {
      console.warn("onPartnershipGoalUpdated label fetch", e);
    }

    const pct = Math.round(maxCrossed * 100);
    try {
      await admin.messaging().sendEachForMulticast({
        tokens,
        notification: {
          title: "Partnership goal milestone",
          body: `${periodName} · ${armName}: ${pct}% of target reached`,
        },
      });
    } catch (e) {
      console.warn("onPartnershipGoalUpdated FCM", e);
    }
  });

/** When a period is deactivated, generate a summary PDF and store it (§16.4.2). */
export const onPartnershipPeriodUpdated = functionsV1
  .region(REGION)
  .firestore.document("churches/{churchId}/partnership_periods/{periodId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    if (!before || !after) return;
    if (before.isActive === true && after.isActive === false) {
      const churchId = context.params.churchId as string;
      const periodId = context.params.periodId as string;
      try {
        await generatePeriodSummaryPdf(churchId, periodId);
      } catch (e) {
        console.error("generatePeriodSummaryPdf", e);
      }
    }
  });

/** Daily digest: one notification to pastors if there are pending entries (§16.4.6). */
export const dailyPendingDigest = onSchedule({schedule: "0 13 * * *", region: REGION}, async () => {
  const churchesSnap = await db.collection("churches").get();
  for (const c of churchesSnap.docs) {
    const churchId = c.id;
    const agg = await db
      .collection(`churches/${churchId}/entries`)
      .where("status", "==", "pending")
      .count()
      .get();
    const n = agg.data().count;
    if (n === 0) continue;
    const users = await db.collection(`churches/${churchId}/users`).where("role", "==", "pastor").get();
    const tokens: string[] = [];
    for (const u of users.docs) {
      const t = u.data().fcmToken as string | undefined;
      if (t) tokens.push(t);
    }
    if (tokens.length === 0) continue;
    try {
      await admin.messaging().sendEachForMulticast({
        tokens,
        notification: {
          title: "Pending partnership entries",
          body: `You have ${n} entr${n === 1 ? "y" : "ies"} awaiting review.`,
        },
      });
    } catch (e) {
      console.warn("dailyPendingDigest FCM", e);
    }
  }
});
