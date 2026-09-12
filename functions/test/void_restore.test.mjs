// End-to-end check of the void / restore design against the real triggers.
//
// The whole claim behind voiding is that it needs no new aggregate plumbing:
// `syncEntryAggregates` treats anything that is not `approved` as contributing
// zero, so a status change to `voided` unwinds partner, period and goal totals
// through the same transactional path an edit takes — and restoring puts them
// back. That is a claim about a Cloud Function, so a unit test cannot settle
// it. This drives the actual trigger.

import {strict as assert} from "node:assert";
import test from "node:test";
import admin from "firebase-admin";

// Point at the emulator if nothing else has. Setting it is what makes this
// safe: it is the *absence* of the variable that would let the admin SDK reach
// the live project, so defaulting it here can only ever narrow the blast
// radius. Matches aggregates.test.mjs.
if (!process.env.FIRESTORE_EMULATOR_HOST) {
  process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
}

if (!admin.apps.length) {
  admin.initializeApp({projectId: "thepillr2"});
}
const db = admin.firestore();

const CHURCH = "void-test-church";
const RUN = `voidtest-${Date.now()}`;

const partnerRef = db.doc(`churches/${CHURCH}/partners/${RUN}-partner`);
const periodRef = db.doc(`churches/${CHURCH}/partnership_periods/${RUN}-period`);
const entryRef = db.doc(`churches/${CHURCH}/entries/${RUN}-entry`);

/** Polls until [read] returns [want], or fails saying what it saw. */
async function eventually(label, read, want, timeoutMs = 20000) {
  const started = Date.now();
  let last;
  while (Date.now() - started < timeoutMs) {
    last = await read();
    if (last === want) return;
    await new Promise((r) => setTimeout(r, 250));
  }
  assert.fail(`${label}: expected ${want}, saw ${last} after ${timeoutMs}ms`);
}

const partnerTotal = async () =>
  ((await partnerRef.get()).data()?.totalApprovedAmount ?? 0);
const partnerCount = async () => ((await partnerRef.get()).data()?.entryCount ?? 0);
const periodTotal = async () =>
  ((await periodRef.get()).data()?.totalApprovedAmount ?? 0);

test.before(async () => {
  await partnerRef.set({
    churchId: CHURCH,
    memberId: `${RUN}-M`,
    fullName: "Void Test Partner",
    fellowship: "Testing",
    isActive: true,
    totalApprovedAmount: 0,
    entryCount: 0,
    createdBy: "test",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  await periodRef.set({
    churchId: CHURCH,
    name: "Void Test Period",
    isActive: false,
    totalApprovedAmount: 0,
    entryCount: 0,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
});

test.after(async () => {
  await entryRef.delete().catch(() => {});
  await partnerRef.delete().catch(() => {});
  await periodRef.delete().catch(() => {});
});

test("an approved entry adds its money", async () => {
  await entryRef.set({
    churchId: CHURCH,
    partnerId: partnerRef.id,
    partnerSnapshot: {fullName: "Void Test Partner"},
    partnershipArmId: `${RUN}-arm`,
    armSnapshot: {name: "Testing"},
    partnershipPeriodId: periodRef.id,
    periodSnapshot: {name: "Void Test Period"},
    amountCedis: 250.5,
    dateGiven: admin.firestore.Timestamp.now(),
    status: "approved",
    createdBy: "test",
    createdBySnapshot: {fullName: "Tester"},
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await eventually("partner total after approval", partnerTotal, 250.5);
  await eventually("period total after approval", periodTotal, 250.5);
  await eventually("partner entry count", partnerCount, 1);
});

test("voiding takes the money back out", async () => {
  // Exactly the write the app makes: a status change and a void stamp. No
  // aggregate field is touched by hand.
  await entryRef.update({
    status: "voided",
    voidedBy: "test",
    voidedAt: admin.firestore.FieldValue.serverTimestamp(),
    voidReason: "checking the trigger",
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await eventually("partner total after void", partnerTotal, 0);
  await eventually("period total after void", periodTotal, 0);
  await eventually("partner entry count after void", partnerCount, 0);
});

test("the voided entry is still there, and says why", async () => {
  const snap = await entryRef.get();
  assert.equal(snap.exists, true, "voiding must not delete the record");
  assert.equal(snap.data().status, "voided");
  assert.equal(snap.data().voidReason, "checking the trigger");
  assert.equal(snap.data().amountCedis, 250.5, "the amount is preserved");
});

test("restoring puts the money back", async () => {
  await entryRef.update({
    status: "approved",
    voidedAt: null,
    voidedBy: null,
    voidReason: null,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await eventually("partner total after restore", partnerTotal, 250.5);
  await eventually("period total after restore", periodTotal, 250.5);
  await eventually("partner entry count after restore", partnerCount, 1);
});

test("voiding twice does not double-reverse", async () => {
  await entryRef.update({
    status: "voided",
    voidedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  await eventually("partner total after first void", partnerTotal, 0);

  // A second void writes the same status again. The stamp makes this a no-op;
  // without it the total would go negative.
  await entryRef.update({
    status: "voided",
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  await new Promise((r) => setTimeout(r, 2500));

  assert.equal(await partnerTotal(), 0, "a repeated void must not go negative");
  assert.equal(await periodTotal(), 0);
});
