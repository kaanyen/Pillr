/**
 * Seeds pending partnership entries into the **emulator** so the approval
 * queue has something to work on.
 *
 * Emulator only. `~/.config/gcloud/application_default_credentials.json`
 * grants live write access to the real project, so this refuses to start
 * unless FIRESTORE_EMULATOR_HOST is set — see CLAUDE.md.
 *
 *   export FIRESTORE_EMULATOR_HOST=127.0.0.1:8080
 *   node functions/scripts/seed-pending-entries.cjs [count] [--reset]
 *
 * --reset first deletes every entry this script has written before (they carry
 * `seededBy`), so you get exactly [count] again instead of piling them up.
 *
 * Env: DEMO_CHURCH_ID (default demo-church), COUNT (default 100).
 */
/* eslint-disable @typescript-eslint/no-require-imports */
const admin = require("firebase-admin");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error(
    "Refusing to run outside the emulator.\n" +
      "  export FIRESTORE_EMULATOR_HOST=127.0.0.1:8080"
  );
  process.exit(1);
}

const CHURCH_ID = (process.env.DEMO_CHURCH_ID || "demo-church").trim();
const ARGS = process.argv.slice(2);
const RESET = ARGS.includes("--reset");
const COUNT = Number(ARGS.find((a) => /^\d+$/.test(a)) || process.env.COUNT || 100);
const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || "thepillr2";

// Fixed seed: the same run twice gives the same hundred entries, so a bug
// found on row 57 is still on row 57 when you look again.
let _seed = 20260823;
function rand() {
  _seed = (_seed * 1103515245 + 12345) & 0x7fffffff;
  return _seed / 0x7fffffff;
}
function pick(list) {
  return list[Math.floor(rand() * list.length)];
}

/** Round cedis to the nearest 50, with the odd exact figure. */
function amount() {
  const r = rand();
  if (r < 0.08) return Math.round((rand() * 9000 + 1000) * 100) / 100; // large, uneven
  if (r < 0.3) return (Math.floor(rand() * 10) + 1) * 500;
  return (Math.floor(rand() * 19) + 1) * 50;
}

const NOTES = [
  null, null, null, null,
  "Sunday service",
  "Midweek offering",
  "Paid by MoMo",
  "Pledge instalment",
  "Given at the men's meeting",
];

async function main() {
  admin.initializeApp({ projectId: PROJECT_ID });
  const db = admin.firestore();
  const church = db.collection("churches").doc(CHURCH_ID);

  const [armsSnap, periodsSnap, partnersSnap, usersSnap] = await Promise.all([
    church.collection("partnership_arms").get(),
    church.collection("partnership_periods").where("isActive", "==", true).get(),
    church.collection("partners").limit(500).get(),
    church.collection("users").get(),
  ]);

  const arms = armsSnap.docs
    .map((d) => ({ id: d.id, ...d.data() }))
    .filter((a) => a.isActive !== false);
  const partners = partnersSnap.docs
    .map((d) => ({ id: d.id, ...d.data() }))
    .filter((p) => p.isActive !== false);
  const period = periodsSnap.docs[0]
    ? { id: periodsSnap.docs[0].id, ...periodsSnap.docs[0].data() }
    : null;

  const staff =
    usersSnap.docs.map((d) => ({ uid: d.id, ...d.data() })).find((u) => u.role === "staff") ||
    usersSnap.docs.map((d) => ({ uid: d.id, ...d.data() }))[0];

  const missing = [];
  if (!arms.length) missing.push("an active partnership arm");
  if (!period) missing.push("an active period");
  if (!partners.length) missing.push("at least one partner");
  if (!staff) missing.push("a church user to attribute entries to");
  if (missing.length) {
    console.error(
      `Church '${CHURCH_ID}' is missing ${missing.join(", ")}.\n` +
        "Seed the demo church first: npm run seed-demo --prefix functions"
    );
    process.exit(1);
  }

  // Dates land inside the active period, weighted toward recent, so the queue
  // reads like a backlog rather than a random scatter.
  const start = period.startDate.toDate ? period.startDate.toDate() : new Date(period.startDate);
  const end = period.endDate.toDate ? period.endDate.toDate() : new Date(period.endDate);
  const now = new Date();
  const latest = end < now ? end : now;
  const span = Math.max(1, latest.getTime() - start.getTime());

  const staffSnapshot = {
    fullName: staff.fullName || staff.displayName || "Demo Staff",
    role: staff.role || "staff",
  };

  if (RESET) {
    const old = await church
      .collection("entries")
      .where("seededBy", "==", "seed-pending-entries")
      .get();
    for (let i = 0; i < old.docs.length; i += 400) {
      const batch = db.batch();
      for (const d of old.docs.slice(i, i + 400)) batch.delete(d.ref);
      await batch.commit();
    }
    console.log(`Removed ${old.docs.length} previously seeded entries.`);
  }

  let written = 0;
  let total = 0;
  for (let i = 0; i < COUNT; i += 400) {
    const batch = db.batch();
    for (let j = i; j < Math.min(i + 400, COUNT); j++) {
      const partner = pick(partners);
      const arm = pick(arms);
      const amt = amount();
      const given = new Date(start.getTime() + span * Math.pow(rand(), 0.6));
      const ref = church.collection("entries").doc();
      batch.set(ref, {
        id: ref.id,
        churchId: CHURCH_ID,
        partnerId: partner.id,
        partnerSnapshot: {
          memberId: partner.memberId ?? null,
          fullName: partner.fullName ?? "",
          fellowship: partner.fellowship ?? "",
          email: partner.email ?? null,
          phone: partner.phone ?? null,
        },
        partnershipArmId: arm.id,
        armSnapshot: { name: arm.name ?? "" },
        partnershipPeriodId: period.id,
        periodSnapshot: {
          name: period.name ?? "",
          startDate: admin.firestore.Timestamp.fromDate(start),
          endDate: admin.firestore.Timestamp.fromDate(end),
        },
        amountCedis: amt,
        dateGiven: admin.firestore.Timestamp.fromDate(given),
        notes: pick(NOTES),
        status: "pending",
        createdBy: staff.uid,
        createdBySnapshot: staffSnapshot,
        createdAt: admin.firestore.Timestamp.fromDate(given),
        updatedAt: admin.firestore.Timestamp.fromDate(given),
        reviewedBy: null,
        reviewedBySnapshot: null,
        reviewedAt: null,
        declineReason: null,
        editHistory: [],
        seededBy: "seed-pending-entries",
      });
      written++;
      total += amt;
    }
    await batch.commit();
  }

  console.log(
    `Wrote ${written} pending entries to ${CHURCH_ID} on ${process.env.FIRESTORE_EMULATOR_HOST}.\n` +
      `  Period: ${period.name}\n` +
      `  Arms:   ${arms.map((a) => a.name).join(", ")}\n` +
      `  Total:  GHS ${total.toLocaleString("en-GH", { minimumFractionDigits: 2 })}\n` +
      `  Author: ${staffSnapshot.fullName}`
  );
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
