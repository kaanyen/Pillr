/**
 * Seeds arms, ~45 partners, and approved giving from January through today
 * into the **emulator** only. One partner carries kwekuanyen@gmail.com; all
 * others have no email.
 *
 *   export FIRESTORE_EMULATOR_HOST=127.0.0.1:8080
 *   export FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099
 *   npm run seed-demo --prefix functions
 *   npm run seed-realistic-demo --prefix functions -- --reset
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
const SEED_TAG = "seed-realistic-demo";
const PERIOD_ID = "period-2026";
const YEAR = 2026;
const END_MONTH = 8;
const END_DAY = 24;

const ARMS = [
  {id: "arm-tithe", name: "Tithe", sortOrder: 0, colorHex: "#2563EB", weight: 0.58},
  {id: "arm-missions", name: "Missions", sortOrder: 1, colorHex: "#059669", weight: 0.27},
  {id: "arm-building", name: "Building", sortOrder: 2, colorHex: "#D97706", weight: 0.15},
];

/** @type {{ id: string, memberId: string, fullName: string, fellowship: string, email: string | null, tier: "whale" | "major" | "regular" }[]} */
const PARTNERS = [
  {id: "p-kweku", memberId: "DCC100001", fullName: "Kweku Anyen", fellowship: "Bethel", email: "kwekuanyen@gmail.com", tier: "whale"},
  {id: "p-ama", memberId: "DCC100002", fullName: "Ama Boateng", fellowship: "Bethel", email: null, tier: "major"},
  {id: "p-kofi", memberId: "DCC100003", fullName: "Kofi Mensah", fellowship: "Bethel", email: null, tier: "major"},
  {id: "p-abena", memberId: "DCC100004", fullName: "Abena Darko", fellowship: "Bethel", email: null, tier: "regular"},
  {id: "p-yaw", memberId: "DCC100005", fullName: "Yaw Owusu", fellowship: "Bethel", email: null, tier: "regular"},
  {id: "p-akosua", memberId: "DCC100006", fullName: "Akosua Frimpong", fellowship: "Bethel", email: null, tier: "regular"},
  {id: "p-kwame", memberId: "DCC100007", fullName: "Kwame Asante", fellowship: "Bethel", email: null, tier: "major"},
  {id: "p-efua", memberId: "DCC100008", fullName: "Efua Osei", fellowship: "Bethel", email: null, tier: "regular"},
  {id: "p-nana", memberId: "DCC100009", fullName: "Nana Agyeman", fellowship: "Bethel", email: null, tier: "regular"},
  {id: "p-adwoa", memberId: "DCC100010", fullName: "Adwoa Sarpong", fellowship: "Bethel", email: null, tier: "regular"},
  {id: "p-esi", memberId: "DCC100011", fullName: "Esi Adjei", fellowship: "Zion", email: null, tier: "major"},
  {id: "p-kojo", memberId: "DCC100012", fullName: "Kojo Annan", fellowship: "Zion", email: null, tier: "major"},
  {id: "p-maame", memberId: "DCC100013", fullName: "Maame Serwaa", fellowship: "Zion", email: null, tier: "regular"},
  {id: "p-kwabena", memberId: "DCC100014", fullName: "Kwabena Ofori", fellowship: "Zion", email: null, tier: "regular"},
  {id: "p-akua", memberId: "DCC100015", fullName: "Akua Frimpong", fellowship: "Zion", email: null, tier: "regular"},
  {id: "p-kwesi", memberId: "DCC100016", fullName: "Kwesi Boateng", fellowship: "Zion", email: null, tier: "regular"},
  {id: "p-afia", memberId: "DCC100017", fullName: "Afia Mensah", fellowship: "Zion", email: null, tier: "regular"},
  {id: "p-samuel", memberId: "DCC100018", fullName: "Samuel Tetteh", fellowship: "Zion", email: null, tier: "major"},
  {id: "p-gifty", memberId: "DCC100019", fullName: "Gifty Owusu", fellowship: "Zion", email: null, tier: "regular"},
  {id: "p-daniel", memberId: "DCC100020", fullName: "Daniel Appiah", fellowship: "Zion", email: null, tier: "regular"},
  {id: "p-grace", memberId: "DCC100021", fullName: "Grace Ampofo", fellowship: "Grace", email: null, tier: "major"},
  {id: "p-michael", memberId: "DCC100022", fullName: "Michael Okyere", fellowship: "Grace", email: null, tier: "regular"},
  {id: "p-priscilla", memberId: "DCC100023", fullName: "Priscilla Baah", fellowship: "Grace", email: null, tier: "regular"},
  {id: "p-emmanuel", memberId: "DCC100024", fullName: "Emmanuel Quaye", fellowship: "Grace", email: null, tier: "major"},
  {id: "p-linda", memberId: "DCC100025", fullName: "Linda Adu", fellowship: "Grace", email: null, tier: "regular"},
  {id: "p-frank", memberId: "DCC100026", fullName: "Frank Amoah", fellowship: "Grace", email: null, tier: "regular"},
  {id: "p-vida", memberId: "DCC100027", fullName: "Vida Nyarko", fellowship: "Grace", email: null, tier: "regular"},
  {id: "p-isaac", memberId: "DCC100028", fullName: "Isaac Bonsu", fellowship: "Grace", email: null, tier: "regular"},
  {id: "p-joyce", memberId: "DCC100029", fullName: "Joyce Antwi", fellowship: "Grace", email: null, tier: "regular"},
  {id: "p-paul", memberId: "DCC100030", fullName: "Paul Osei-Tutu", fellowship: "Hope", email: null, tier: "major"},
  {id: "p-ruth", memberId: "DCC100031", fullName: "Ruth Ofori", fellowship: "Hope", email: null, tier: "regular"},
  {id: "p-seth", memberId: "DCC100032", fullName: "Seth Adom", fellowship: "Hope", email: null, tier: "regular"},
  {id: "p-felicia", memberId: "DCC100033", fullName: "Felicia Darkwah", fellowship: "Hope", email: null, tier: "regular"},
  {id: "p-bright", memberId: "DCC100034", fullName: "Bright Kumi", fellowship: "Hope", email: null, tier: "major"},
  {id: "p-celeste", memberId: "DCC100035", fullName: "Celeste Amoako", fellowship: "Hope", email: null, tier: "regular"},
  {id: "p-henry", memberId: "DCC100036", fullName: "Henry Lamptey", fellowship: "Hope", email: null, tier: "regular"},
  {id: "p-naomi", memberId: "DCC100037", fullName: "Naomi Arthur", fellowship: "Hope", email: null, tier: "regular"},
  {id: "p-david", memberId: "DCC100038", fullName: "David Kyei", fellowship: "Shiloh", email: null, tier: "major"},
  {id: "p-hannah", memberId: "DCC100039", fullName: "Hannah Opare", fellowship: "Shiloh", email: null, tier: "regular"},
  {id: "p-joseph", memberId: "DCC100040", fullName: "Joseph Anane", fellowship: "Shiloh", email: null, tier: "regular"},
  {id: "p-mary", memberId: "DCC100041", fullName: "Mary Tawiah", fellowship: "Shiloh", email: null, tier: "regular"},
  {id: "p-peter", memberId: "DCC100042", fullName: "Peter Nkrumah", fellowship: "Shiloh", email: null, tier: "regular"},
  {id: "p-sarah", memberId: "DCC100043", fullName: "Sarah Donkor", fellowship: "Shiloh", email: null, tier: "regular"},
  {id: "p-tetteh", memberId: "DCC100044", fullName: "Tetteh Acheampong", fellowship: "Shiloh", email: null, tier: "major"},
  {id: "p-wendy", memberId: "DCC100045", fullName: "Wendy Agyei", fellowship: "Shiloh", email: null, tier: "regular"},
];

const WHALE_AMOUNTS = [
  250000, 350000, 500000, 750000, 850000, 1200000, 1500000, 2000000, 2800000, 3500000,
];
const MAJOR_AMOUNTS = [
  15000, 25000, 35000, 50000, 75000, 100000, 125000, 180000, 220000,
];
const REGULAR_AMOUNTS = [
  50, 100, 150, 200, 250, 300, 400, 500, 750, 1000, 1500, 2000, 2500, 3000, 4000, 5000,
  7500, 10000, 12500, 15000,
];

let _rng = 20260101;
function rand() {
  _rng = (_rng * 1103515245 + 12345) & 0x7fffffff;
  return _rng / 0x7fffffff;
}

function pick(list) {
  return list[Math.floor(rand() * list.length)];
}

function roundMoney(n) {
  return Math.round(n * 100) / 100;
}

function daysInMonth(year, month) {
  return new Date(year, month, 0).getDate();
}

function pickArm() {
  const r = rand();
  let acc = 0;
  for (const arm of ARMS) {
    acc += arm.weight;
    if (r <= acc) return arm;
  }
  return ARMS[0];
}

function amountFor(partner, month) {
  if (partner.tier === "whale") {
    if (rand() < 0.45) return pick(WHALE_AMOUNTS);
    if (rand() < 0.35) return pick(MAJOR_AMOUNTS);
    return pick(REGULAR_AMOUNTS.filter((a) => a >= 500));
  }
  if (partner.tier === "major") {
    if (rand() < 0.22) return pick(MAJOR_AMOUNTS);
    if (rand() < 0.12) return roundMoney(rand() * 80000 + 20000);
    return pick(REGULAR_AMOUNTS);
  }
  if (rand() < 0.06) return pick(MAJOR_AMOUNTS.filter((a) => a <= 50000));
  return pick(REGULAR_AMOUNTS);
}

function monthActivityChance(partner, month) {
  if (partner.tier === "whale") return 1;
  if (partner.tier === "major") return 0.88;
  if (month <= 2) return 0.62;
  if (month >= 7) return 0.78;
  return 0.72;
}

function entriesPerMonth(partner) {
  if (partner.tier === "whale") return 2 + Math.floor(rand() * 3);
  if (partner.tier === "major") return 1 + Math.floor(rand() * 3);
  return 1 + Math.floor(rand() * 2);
}

/** @type {{ partnerId: string, armId: string, amount: number, date: Date }[]} */
function buildEntryPlan() {
  /** @type {{ partnerId: string, armId: string, amount: number, date: Date }[]} */
  const rows = [];

  for (let month = 1; month <= END_MONTH; month++) {
    const maxDay = month === END_MONTH ? END_DAY : daysInMonth(YEAR, month);
    for (const partner of PARTNERS) {
      if (rand() > monthActivityChance(partner, month)) continue;

      const count = entriesPerMonth(partner);
      for (let i = 0; i < count; i++) {
        const day = 1 + Math.floor(rand() * maxDay);
        const hour = 8 + Math.floor(rand() * 12);
        const date = new Date(Date.UTC(YEAR, month - 1, day, hour, 0, 0));
        const arm = pickArm();
        rows.push({
          partnerId: partner.id,
          armId: arm.id,
          amount: amountFor(partner, month),
          date,
        });
      }
    }
  }

  rows.sort((a, b) => b.date.getTime() - a.date.getTime());
  return rows;
}

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
  const staff =
    usersSnap.docs.map((d) => ({uid: d.id, ...d.data()})).find((u) => u.role === "staff") ||
    pastor;
  if (!pastor || !staff) {
    console.error("No church user found. Run seed-demo first.");
    process.exit(1);
  }

  if (RESET) {
    const removedEntries = await deleteTagged(
      church.collection("entries"),
      "seededBy",
      SEED_TAG
    );
    const removedRanked = await deleteTagged(
      church.collection("entries"),
      "seededBy",
      "seed-ranked-demo"
    );
    for (const arm of ARMS) {
      await church.collection("partnership_arms").doc(arm.id).delete().catch(() => {});
    }
    for (const partner of PARTNERS) {
      await church.collection("partners").doc(partner.id).delete().catch(() => {});
    }
    await church.collection("partnership_periods").doc(PERIOD_ID).delete().catch(() => {});
    console.log(`Reset removed ${removedEntries + removedRanked} seeded entries.`);
  }

  const now = admin.firestore.FieldValue.serverTimestamp();
  const start = admin.firestore.Timestamp.fromDate(new Date(`${YEAR}-01-01T00:00:00Z`));
  const end = admin.firestore.Timestamp.fromDate(new Date(`${YEAR}-12-31T23:59:59Z`));
  const pastorSnapshot = {fullName: pastor.fullName || "Demo Pastor", role: "pastor"};
  const staffSnapshot = {fullName: staff.fullName || "Demo Staff", role: staff.role || "staff"};

  const setupBatch = db.batch();

  for (const arm of ARMS) {
    setupBatch.set(
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

  setupBatch.set(
    church.collection("partnership_periods").doc(PERIOD_ID),
    {
      id: PERIOD_ID,
      churchId: CHURCH_ID,
      name: "Ministry Year 2026",
      startDate: start,
      endDate: end,
      isActive: true,
      totalApprovedAmount: 0,
      entryCount: 0,
      createdBy: pastor.uid,
      createdAt: now,
      updatedAt: now,
      seededBy: SEED_TAG,
    },
    {merge: true}
  );

  for (const partner of PARTNERS) {
    setupBatch.set(
      church.collection("partners").doc(partner.id),
      {
        id: partner.id,
        churchId: CHURCH_ID,
        memberId: partner.memberId,
        fullName: partner.fullName,
        fullNameLower: partner.fullName.toLowerCase(),
        fellowship: partner.fellowship,
        fellowshipLower: partner.fellowship.toLowerCase(),
        email: partner.email,
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

  await setupBatch.commit();

  const plan = buildEntryPlan();
  /** @type {Map<string, {amount: number, count: number}>} */
  const partnerTotals = new Map();
  let periodTotal = 0;

  for (let i = 0; i < plan.length; i += 400) {
    const entryBatch = db.batch();
    for (const row of plan.slice(i, i + 400)) {
      const partner = PARTNERS.find((p) => p.id === row.partnerId);
      const arm = ARMS.find((a) => a.id === row.armId);
      const given = admin.firestore.Timestamp.fromDate(row.date);
      const ref = church.collection("entries").doc();
      entryBatch.set(ref, {
        id: ref.id,
        churchId: CHURCH_ID,
        partnerId: row.partnerId,
        partnerSnapshot: {
          memberId: partner.memberId,
          fullName: partner.fullName,
          fellowship: partner.fellowship,
          email: partner.email,
          phone: null,
        },
        partnershipArmId: row.armId,
        armSnapshot: {name: arm.name},
        partnershipPeriodId: PERIOD_ID,
        periodSnapshot: {
          name: "Ministry Year 2026",
          startDate: start,
          endDate: end,
        },
        amountCedis: row.amount,
        dateGiven: given,
        notes: null,
        status: "approved",
        createdBy: staff.uid,
        createdBySnapshot: staffSnapshot,
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
      periodTotal += row.amount;
    }
    await entryBatch.commit();
  }

  const totalsBatch = db.batch();
  for (const [partnerId, totals] of partnerTotals) {
    totalsBatch.update(church.collection("partners").doc(partnerId), {
      totalApprovedAmount: roundMoney(totals.amount),
      entryCount: totals.count,
      updatedAt: now,
    });
  }
  totalsBatch.update(church.collection("partnership_periods").doc(PERIOD_ID), {
    totalApprovedAmount: roundMoney(periodTotal),
    entryCount: plan.length,
    updatedAt: now,
  });
  await totalsBatch.commit();

  const kwekuTotal = partnerTotals.get("p-kweku")?.amount ?? 0;
  const fmt = (n) =>
    n.toLocaleString("en-GH", {minimumFractionDigits: 2, maximumFractionDigits: 2});

  console.log(`
Realistic demo ready — church: ${CHURCH_ID}
  Period:     Ministry Year 2026 (Jan 1 – Aug 24, ${YEAR})
  Partners:   ${PARTNERS.length} (1 email: kwekuanyen@gmail.com)
  Entries:    ${plan.length} approved
  Total:      GHS ${fmt(periodTotal)}
  Top giver:  Kweku Anyen — GHS ${fmt(kwekuTotal)}

Sign in: pastor@pillr.dev / DemoPillr1!
Try: Records → By month, Partners → Ranked, Export PDF
`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
