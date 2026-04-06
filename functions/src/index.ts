import * as admin from "firebase-admin";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {Resend} from "resend";

admin.initializeApp();
const db = admin.firestore();

const REGION = "us-central1";

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
    from: "The Pillr <invites@pillr.app>",
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
  const fullName = String(request.data?.fullName ?? "").trim();
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
