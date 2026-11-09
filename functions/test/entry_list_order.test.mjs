// The pastor's lists are ordered by the day of the gift, not the day it was
// keyed in.
//
// A staff member submits an entry, a pastor approves it days later. Approving
// does not change `createdAt`, so a list ordered by `createdAt` filed the newly
// approved gift under the day it was typed — below everything entered since,
// and past the end of the first page on a busy church. The pastor's report was
// that staff entries "sometimes don't show up".
//
// These run the query shapes `fetchEntriesPage` builds. NOTE: the emulator
// serves any query regardless of composite indexes, so this pins the ordering
// only — `firestore.indexes.json` still has to carry the matching index, and
// it has to be deployed.

import {strict as assert} from "node:assert";
import test from "node:test";
import admin from "firebase-admin";

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
}
if (!admin.apps.length) {
  admin.initializeApp({projectId: "thepillr2"});
}
const db = admin.firestore();
const CHURCH = `list-order-${Date.now()}`;
const entries = db.collection(`churches/${CHURCH}/entries`);

const day = (d) => admin.firestore.Timestamp.fromDate(new Date(`2026-0${d.m}-${d.d}T09:00:00Z`));

/** [given] is when the gift was made, [keyed] when somebody recorded it. */
async function entry(id, {given, keyed, status = "approved", createdBy = "staff-uid"}) {
  await entries.doc(id).set({
    churchId: CHURCH, partnerId: "p1", partnerSnapshot: {fullName: "Person A"},
    partnershipArmId: "arm1", armSnapshot: {name: "Missions"},
    partnershipPeriodId: "per1", periodSnapshot: {name: "2026"},
    amountCedis: 100,
    dateGiven: day(given),
    createdAt: day(keyed),
    updatedAt: day(keyed),
    status, createdBy, createdBySnapshot: {fullName: "x"},
    reviewedBy: null, reviewedAt: null, declineReason: null,
  });
}

const ids = (snap) => snap.docs.map((d) => d.id);

test.before(async () => {
  // A gift given on the 1st, submitted by staff on the 1st, approved later.
  await entry("staff-gift-1st", {given: {m: 3, d: "01"}, keyed: {m: 3, d: "01"}});
  // Two gifts the pastor recorded on the 10th, given the same day.
  await entry("pastor-gift-10th", {given: {m: 3, d: 10}, keyed: {m: 3, d: 10}, createdBy: "pastor-uid"});
  await entry("pastor-gift-11th", {given: {m: 3, d: 11}, keyed: {m: 3, d: 11}, createdBy: "pastor-uid"});
  // The case in the report: a gift given on the 12th, handed in on a slip and
  // keyed by staff back on the 2nd — the oldest `createdAt` in the church.
  await entry("staff-gift-12th", {given: {m: 3, d: 12}, keyed: {m: 3, d: "02"}});
});

test("the newest gift leads the list, whoever keyed it in and when", async () => {
  const page = await entries
    .where("status", "==", "approved")
    .orderBy("dateGiven", "desc")
    .limit(2)
    .get();

  assert.deepEqual(ids(page), ["staff-gift-12th", "pastor-gift-11th"]);
});

test("a staff gift keyed in first does not sink below later entries", async () => {
  const byDateGiven = ids(await entries.orderBy("dateGiven", "desc").get());
  const byCreatedAt = ids(await entries.orderBy("createdAt", "desc").get());

  assert.equal(byDateGiven[0], "staff-gift-12th", "the most recent gift leads");
  // Ordered the old way the same row sat below both entries the pastor keyed
  // in later, even though its gift is the most recent in the church. On a
  // church with a page of activity between them, that is off the first page.
  assert.equal(byCreatedAt.indexOf("staff-gift-12th"), 2);
  assert.deepEqual(
    byCreatedAt.slice(0, 2), ["pastor-gift-11th", "pastor-gift-10th"],
    "the pastor's own entries always led, which is the asymmetry reported",
  );
});

test("oldest first is still available for the ascending view", async () => {
  const page = await entries.orderBy("dateGiven", "asc").limit(1).get();
  assert.deepEqual(ids(page), ["staff-gift-1st"]);
});

test("one partner's giving history reads newest gift first", async () => {
  const history = await entries
    .where("partnerId", "==", "p1")
    .orderBy("dateGiven", "desc")
    .get();
  assert.equal(ids(history)[0], "staff-gift-12th");
});
