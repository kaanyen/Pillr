/**
 * The money path, end to end against the emulator.
 *
 * These totals are what the whole product shows: a partner's giving, a
 * period's figure, a goal's progress. They are maintained by triggers, and
 * until this file nothing checked that a trigger ever ran, let alone that it
 * ran once. It is worth the seconds it takes.
 *
 *   firebase emulators:start --only firestore,functions
 *   node --test functions/test/aggregates.test.mjs
 */
import {after, before, describe, it} from "node:test";
import assert from "node:assert/strict";
import admin from "firebase-admin";

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
}

const CHURCH = "aggregate-test-church";
const PARTNER = "p1";
const PERIOD = "per1";
const ARM = "arm1";
const GOAL = "goal1";

admin.initializeApp({projectId: process.env.FIREBASE_PROJECT_ID || "thepillr2"});
const db = admin.firestore();
const church = db.collection("churches").doc(CHURCH);

const entryRef = (id) => church.collection("entries").doc(id);

/** Triggers are asynchronous; give them a moment, then give up loudly. */
async function eventually(read, want, what, timeoutMs = 20000) {
  const started = Date.now();
  let last;
  while (Date.now() - started < timeoutMs) {
    last = await read();
    if (Math.abs(last - want) < 0.005) return;
    await new Promise((r) => setTimeout(r, 150));
  }
  assert.fail(`${what}: expected ${want}, still ${last} after ${timeoutMs}ms`);
}

/** Nothing should move. Waits long enough that a late trigger would be caught. */
async function stays(read, want, what) {
  await new Promise((r) => setTimeout(r, 2500));
  const now = await read();
  assert.ok(Math.abs(now - want) < 0.005, `${what}: expected it to stay ${want}, became ${now}`);
}

const partnerTotal = async () => (await church.collection("partners").doc(PARTNER).get()).data().totalApprovedAmount;
const partnerCount = async () => (await church.collection("partners").doc(PARTNER).get()).data().entryCount;
const periodTotal = async () => (await church.collection("partnership_periods").doc(PERIOD).get()).data().totalApprovedAmount;
const goalTotal = async () => (await church.collection("goals").doc(GOAL).get()).data().currentAmountCedis;

const baseEntry = (amount, status) => ({
  churchId: CHURCH,
  partnerId: PARTNER,
  partnerSnapshot: {fullName: "Ama Boateng"},
  partnershipArmId: ARM,
  armSnapshot: {name: "Missions"},
  partnershipPeriodId: PERIOD,
  periodSnapshot: {name: "Test period"},
  amountCedis: amount,
  dateGiven: admin.firestore.Timestamp.now(),
  status,
  createdBy: "staff-uid",
  createdBySnapshot: {fullName: "Staff", role: "staff"},
  createdAt: admin.firestore.Timestamp.now(),
  updatedAt: admin.firestore.Timestamp.now(),
  editHistory: [],
});

/**
 * Clears the scratch church.
 *
 * Entries go first and are given a moment to settle: deleting an approved
 * entry fires a reversal, and a reversal that arrives after the next run has
 * recreated the partner would land on it — which is exactly the bleed that
 * made these tests fail against a fresh fixture.
 */
async function wipe() {
  const entries = await church.collection("entries").get();
  await Promise.all(entries.docs.map((d) => d.ref.delete()));

  // Wait for the reversals rather than guess at them: the totals returning to
  // zero is the signal that every trigger has landed.
  if (entries.size > 0) {
    const partnerRef = church.collection("partners").doc(PARTNER);
    const until = Date.now() + 30000;
    while (Date.now() < until) {
      const snap = await partnerRef.get();
      if (!snap.exists || Math.abs(Number(snap.data().totalApprovedAmount ?? 0)) < 0.005) break;
      await new Promise((r) => setTimeout(r, 200));
    }
  }

  for (const s of ["partners", "partnership_periods", "partnership_arms", "goals"]) {
    const docs = await church.collection(s).get();
    await Promise.all(docs.docs.map((d) => d.ref.delete()));
  }
  await church.delete();
}

before(async () => {
  await wipe();
  await church.set({name: "Aggregate Test", isActive: true});
  await church.collection("partners").doc(PARTNER).set({fullName: "Ama Boateng", totalApprovedAmount: 0, entryCount: 0});
  await church.collection("partnership_periods").doc(PERIOD).set({name: "Test period", totalApprovedAmount: 0, entryCount: 0, isActive: true});
  await church.collection("partnership_arms").doc(ARM).set({name: "Missions", isActive: true});
  await church.collection("goals").doc(GOAL).set({
    partnershipPeriodId: PERIOD,
    partnershipArmId: ARM,
    targetAmountCedis: 10000,
    currentAmountCedis: 0,
  });
});

after(async () => {
  await wipe();
});

describe("what an entry contributes", () => {
  it("a pending entry contributes nothing", async () => {
    await entryRef("e1").set(baseEntry(250.5, "pending"));
    await stays(partnerTotal, 0, "partner total on a pending entry");
    assert.equal(await periodTotal(), 0);
  });

  it("approving adds it once, to partner, period and goal", async () => {
    await entryRef("e1").update({status: "approved", reviewedBy: "pastor", reviewedAt: admin.firestore.Timestamp.now()});
    await eventually(partnerTotal, 250.5, "partner total after approval");
    await eventually(periodTotal, 250.5, "period total after approval");
    await eventually(goalTotal, 250.5, "goal progress after approval");
    assert.equal(await partnerCount(), 1);
  });

  it("re-writing the same approval adds nothing (the trigger is idempotent)", async () => {
    // What a retried delivery looks like: the same status written again.
    await entryRef("e1").update({status: "approved", notes: "touched"});
    await stays(partnerTotal, 250.5, "partner total on a repeated approval");
    assert.equal(await partnerCount(), 1);
  });

  it("editing the amount moves the totals by the difference", async () => {
    await entryRef("e1").update({amountCedis: 400});
    await eventually(partnerTotal, 400, "partner total after an amount edit");
    await eventually(goalTotal, 400, "goal progress after an amount edit");
    assert.equal(await partnerCount(), 1, "an edit is not a second entry");
  });

  it("sending it back gives the money back", async () => {
    await entryRef("e1").update({status: "declined", declineReason: "wrong partner"});
    await eventually(partnerTotal, 0, "partner total after decline");
    await eventually(periodTotal, 0, "period total after decline");
    await eventually(goalTotal, 0, "goal progress after decline");
    await eventually(partnerCount, 0, "partner entry count after decline");
  });

  it("deleting an approved entry takes its money with it", async () => {
    await entryRef("e2").set(baseEntry(1000, "approved"));
    await eventually(partnerTotal, 1000, "partner total after a direct approved create");
    await entryRef("e2").delete();
    await eventually(partnerTotal, 0, "partner total after deleting an approved entry");
    await eventually(periodTotal, 0, "period total after deleting an approved entry");
    await eventually(partnerCount, 0, "partner entry count after deleting an approved entry");
  });

  it("a hundred approvals land on the period exactly once each", async () => {
    const ids = Array.from({length: 100}, (_, i) => `bulk${i}`);
    let batch = db.batch();
    ids.forEach((id) => batch.set(entryRef(id), baseEntry(10, "pending")));
    await batch.commit();

    batch = db.batch();
    ids.forEach((id) => batch.update(entryRef(id), {status: "approved"}));
    await batch.commit();

    await eventually(periodTotal, 1000, "period total after a hundred approvals", 60000);
    assert.equal(await partnerTotal(), 1000);
    assert.equal(await partnerCount(), 100);
  });
});
