/**
 * Seeds arms, partners, a period, and approved entries into the **emulator**
 * so Partners → Ranked → By arm has realistic data to work with.
 *
 * Emulator only — see CLAUDE.md.
 *
 *   export FIRESTORE_EMULATOR_HOST=127.0.0.1:8080
 *   export FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099
 *   npm run seed-demo --prefix functions
 *   npm run seed-ranked-demo --prefix functions
 *
 * --reset removes previously seeded ranked-demo documents first.
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
const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || "thepillr2";
const RESET = process.argv.includes("--reset");
const SEED_TAG = "seed-ranked-demo";

const ARMS = [
  {id: "arm-tithe", name: "Tithe", sortOrder: 0, colorHex: "#2563EB"},
  {id: "arm-missions", name: "Missions", sortOrder: 1, colorHex: "#059669"},
  {id: "arm-building", name: "Building", sortOrder: 2, colorHex: "#D97706"},
];

const PARTNERS = [
  {id: "p-ama", memberId: "ACC-001", fullName: "Ama Boateng", fellowship: "Bethel"},
  {id: "p-kofi", memberId: "ACC-002", fullName: "Kofi Mensah", fellowship: "Bethel"},
  {id: "p-esi", memberId: "ACC-003", fullName: "Esi Adjei", fellowship: "Zion"},
  {id: "p-yaw", memberId: "ACC-004", fullName: "Yaw Owusu", fellowship: "Zion"},
  {id: "p-abena", memberId: "ACC-005", fullName: "Abena Darko", fellowship: "Grace"},
  {id: "p-kwame", memberId: "ACC-006", fullName: "Kwame Asante", fellowship: "Grace"},
  {id: "p-akua", memberId: "ACC-007", fullName: "Akua Frimpong", fellowship: "Hope"},
  {id: "p-kojo", memberId: "ACC-008", fullName: "Kojo Annan", fellowship: "Hope"},
];

/** @type {{ partnerId: string, armId: string, amount: number }[]} */
const APPROVED = [
  {partnerId: "p-ama", armId: "arm-tithe", amount: 1200},
  {partnerId: "p-ama", armId: "arm-missions", amount: 300},
  {partnerId: "p-kofi", armId: "arm-tithe", amount: 800},
  {partnerId: "p-kofi", armId: "arm-building", amount: 150},
  {partnerId: "p-esi", armId: "arm-missions", amount: 950},
  {partnerId: "p-esi", armId: "arm-tithe", amount: 400},
  {partnerId: "p-yaw", armId: "arm-building", amount: 600},
  {partnerId: "p-yaw", armId: "arm-missions", amount: 200},
  {partnerId: "p-abena", armId: "arm-tithe", amount: 500},
  {partnerId: "p-kwame", armId: "arm-missions", amount: 450},
  {partnerId: "p-kwame", armId: "arm-building", amount: 250},
  {partnerId: "p-akua", armId: "arm-tithe", amount: 700},
  {partnerId: "p-kojo", armId: "arm-building", amount: 900},
  {partnerId: "p-kojo", armId: "arm-missions", amount: 100},
];

async function deleteTagged(collection, field, value) {
  const snap = await collection.where(field, "==", value).get();
  for (let i = 0; i < snap.docs.length; i += 400) {
    const batch = admin.firestore().batch();
    for (const d of snap.docs.slice(i, i + 400)) batch.delete(d.ref);
    await batch.commit();
  }
  return snap.size;
}

async function main() {
  admin.initializeApp({projectId: PROJECT_ID});
  const db = admin.firestore();
  const church = db.collection("churches").doc(CHURCH_ID);
  const churchSnap = await church.get();
  if (!churchSnap.exists) {
    console.error(`Church '${CHURCH_ID}' not found. Run seed-demo first.`);
    process.exit(1);
  }

  const usersSnap = await church.collection("users").get();
  const pastor =
    usersSnap.docs.map((d) => ({uid: d.id, ...d.data()})).find((u) => u.role === "pastor") ||
    usersSnap.docs.map((d) => ({uid: d.id, ...d.data()}))[0];
  if (!pastor) {
    console.error("No church user found. Run seed-demo first.");
    process.exit(1);
  }

  if (RESET) {
    const removedEntries = await deleteTagged(
      church.collection("entries"),
      "seededBy",
      SEED_TAG
    );
    for (const arm of ARMS) {
      await church.collection("partnership_arms").doc(arm.id).delete().catch(() => {});
    }
    for (const partner of PARTNERS) {
      await church.collection("partners").doc(partner.id).delete().catch(() => {});
    }
    await church.collection("partnership_periods").doc("period-2026").delete().catch(() => {});
    console.log(`Reset removed ${removedEntries} seeded entries.`);
  }

  const now = admin.firestore.FieldValue.serverTimestamp();
  const start = admin.firestore.Timestamp.fromDate(new Date("2026-01-01T00:00:00Z"));
  const end = admin.firestore.Timestamp.fromDate(new Date("2026-12-31T23:59:59Z"));
  const pastorSnapshot = {
    fullName: pastor.fullName || "Demo Pastor",
    role: "pastor",
  };

  const batch = db.batch();

  for (const arm of ARMS) {
    batch.set(
      church.collection("partnership_arms").doc(arm.id),
      {
        id: arm.id,
        churchId: CHURCH_ID,
        name: arm.name,
        description: null,
        isActive: true,
        colorHex: arm.colorHex,
        sortOrder: arm.sortOrder,
        aliases: [],
        createdBy: pastor.uid,
        createdAt: now,
        updatedAt: now,
        seededBy: SEED_TAG,
      },
      {merge: true}
    );
  }

  batch.set(
    church.collection("partnership_periods").doc("period-2026"),
    {
      id: "period-2026",
      churchId: CHURCH_ID,
      name: "Ministry Year 2026",
      startDate: start,
      endDate: end,
      isActive: true,
      totalApprovedAmount: 0,
      createdBy: pastor.uid,
      createdAt: now,
      updatedAt: now,
      seededBy: SEED_TAG,
    },
    {merge: true}
  );

  for (const partner of PARTNERS) {
    batch.set(
      church.collection("partners").doc(partner.id),
      {
        id: partner.id,
        churchId: CHURCH_ID,
        memberId: partner.memberId,
        fullName: partner.fullName,
        fullNameLower: partner.fullName.toLowerCase(),
        fellowship: partner.fellowship,
        fellowshipLower: partner.fellowship.toLowerCase(),
        email: null,
        phone: null,
        isActive: true,
        entryCount: 0,
        totalApprovedAmount: 0,
        createdBy: pastor.uid,
        createdAt: now,
        updatedAt: now,
        seededBy: SEED_TAG,
      },
      {merge: true}
    );
  }

  await batch.commit();

  /** @type {Map<string, {amount: number, count: number}>} */
  const partnerTotals = new Map();
  /** @type {Map<string, {amount: number, count: number}>} */
  const armTotals = new Map();
  let periodTotal = 0;

  for (let i = 0; i < APPROVED.length; i += 400) {
    const entryBatch = db.batch();
    for (const row of APPROVED.slice(i, i + 400)) {
      const partner = PARTNERS.find((p) => p.id === row.partnerId);
      const arm = ARMS.find((a) => a.id === row.armId);
      const given = admin.firestore.Timestamp.fromDate(
        new Date(Date.UTC(2026, 2, 1 + (i % 20), 12, 0, 0))
      );
      const ref = church.collection("entries").doc();
      entryBatch.set(ref, {
        id: ref.id,
        churchId: CHURCH_ID,
        partnerId: row.partnerId,
        partnerSnapshot: {
          memberId: partner.memberId,
          fullName: partner.fullName,
          fellowship: partner.fellowship,
          email: null,
          phone: null,
        },
        partnershipArmId: row.armId,
        armSnapshot: {name: arm.name},
        partnershipPeriodId: "period-2026",
        periodSnapshot: {
          name: "Ministry Year 2026",
          startDate: start,
          endDate: end,
        },
        amountCedis: row.amount,
        dateGiven: given,
        notes: null,
        status: "approved",
        createdBy: pastor.uid,
        createdBySnapshot: pastorSnapshot,
        createdAt: given,
        updatedAt: given,
        reviewedBy: pastor.uid,
        reviewedBySnapshot: {fullName: pastorSnapshot.fullName},
        reviewedAt: given,
        declineReason: null,
        editHistory: [],
        seededBy: SEED_TAG,
      });

      const p = partnerTotals.get(row.partnerId) ?? {amount: 0, count: 0};
      p.amount += row.amount;
      p.count += 1;
      partnerTotals.set(row.partnerId, p);

      const a = armTotals.get(row.armId) ?? {amount: 0, count: 0};
      a.amount += row.amount;
      a.count += 1;
      armTotals.set(row.armId, a);

      periodTotal += row.amount;
    }
    await entryBatch.commit();
  }

  const totalsBatch = db.batch();
  for (const [partnerId, totals] of partnerTotals) {
    totalsBatch.update(church.collection("partners").doc(partnerId), {
      totalApprovedAmount: totals.amount,
      entryCount: totals.count,
      updatedAt: now,
    });
  }
  totalsBatch.update(church.collection("partnership_periods").doc("period-2026"), {
    totalApprovedAmount: periodTotal,
    updatedAt: now,
  });
  await totalsBatch.commit();

  console.log(`
Ranked demo ready — church: ${CHURCH_ID}
  Period:  Ministry Year 2026
  Arms:    ${ARMS.map((a) => a.name).join(", ")}
  Partners: ${PARTNERS.length}
  Approved entries: ${APPROVED.length}
  Total approved: GHS ${periodTotal.toLocaleString("en-GH", {minimumFractionDigits: 2})}

Sign in: pastor@pillr.dev / DemoPillr1!
Then: Partners → Ranked → By arm
`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
