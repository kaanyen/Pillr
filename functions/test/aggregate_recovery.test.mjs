// Removing money has to take it back out — under every condition, not just
// the tidy one.
//
// `void_restore.test.mjs` covers the healthy path: an entry the trigger itself
// approved and stamped, voided while everything it points at still exists.
// This covers the states a real church gets into — rows written before the
// aggregate trigger existed, rows a script or a totals repair left unstamped,
// and rows pointing at a period somebody has since deleted — plus the ordinary
// arithmetic of edits, reassignments and goals.
//
// Every test drives the real triggers. Emulator only.

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

// A church per run, so a failed run never poisons the next one.
const CHURCH = `agg-recovery-${Date.now()}`;
const ts = () => admin.firestore.FieldValue.serverTimestamp();

/** Polls until [read] returns [want], or fails saying what it saw. */
async function eventually(label, read, want, timeoutMs = 20000) {
  const started = Date.now();
  let last;
  while (Date.now() - started < timeoutMs) {
    last = await read();
    if (last === want) return;
    await new Promise((r) => setTimeout(r, 200));
  }
  assert.fail(`${label}: expected ${want}, saw ${last} after ${timeoutMs}ms`);
}

/** Waits for the triggers to go quiet, for asserting that nothing moved. */
const settle = (ms = 3500) => new Promise((r) => setTimeout(r, ms));

const total = (ref) => async () => (await ref.get()).data()?.totalApprovedAmount ?? 0;
const count = (ref) => async () => (await ref.get()).data()?.entryCount ?? 0;
const goalTotal = (ref) => async () => (await ref.get()).data()?.currentAmountCedis ?? 0;
const stampOf = async (ref) => (await ref.get()).data()?.aggregateApplied ?? null;
const pesewasOf = (ref) => async () => (await ref.get()).data()?.totalApprovedPesewas ?? 0;
const goalPesewasOf = (ref) => async () => (await ref.get()).data()?.currentAmountPesewas ?? 0;

const round2 = (n) => Math.round(n * 100) / 100;
/** Reads a total at the precision money is actually kept in. */
const toPesewa = (read) => async () => round2(await read());

async function partner(id) {
  const ref = db.doc(`churches/${CHURCH}/partners/${id}`);
  await ref.set({
    churchId: CHURCH, fullName: "Person A", fellowship: "Bethel", isActive: true,
    totalApprovedAmount: 0, entryCount: 0, createdAt: ts(), updatedAt: ts(),
  });
  return ref;
}

async function period(id) {
  const ref = db.doc(`churches/${CHURCH}/partnership_periods/${id}`);
  await ref.set({
    churchId: CHURCH, name: "Ministry Year 2026", isActive: true,
    totalApprovedAmount: 0, entryCount: 0, createdAt: ts(), updatedAt: ts(),
  });
  return ref;
}

async function goal(id, {periodId, armId, target = 500000}) {
  const ref = db.doc(`churches/${CHURCH}/goals/${id}`);
  await ref.set({
    churchId: CHURCH, partnershipPeriodId: periodId, partnershipArmId: armId,
    targetAmountCedis: target, currentAmountCedis: 0, createdAt: ts(), updatedAt: ts(),
  });
  return ref;
}

async function entry(id, {partnerId, periodId, amount, armId = "arm1", status = "approved"}) {
  const ref = db.doc(`churches/${CHURCH}/entries/${id}`);
  await ref.set({
    churchId: CHURCH,
    partnerId, partnerSnapshot: {fullName: "Person A"},
    partnershipArmId: armId, armSnapshot: {name: "Missions"},
    partnershipPeriodId: periodId, periodSnapshot: {name: "Ministry Year 2026"},
    amountCedis: amount,
    dateGiven: admin.firestore.Timestamp.now(),
    status,
    createdBy: "test", createdBySnapshot: {fullName: "Tester"},
    createdAt: ts(), updatedAt: ts(),
  });
  return ref;
}

/** Strips the stamp, leaving the row as an unstamped import or script write. */
async function unstamp(ref) {
  await ref.update({aggregateApplied: admin.firestore.FieldValue.delete()});
  await settle(1200);
}

/** The write the app makes to void a row. */
const VOID = () => ({
  status: "voided", voidedBy: "test", voidedAt: ts(),
  voidReason: "recorded in error", updatedAt: ts(),
});

// ---------------------------------------------------------------------------
// The reported bug: ₵100 + ₵1,000,000, remove the 1,000,000, total must be 100.
// ---------------------------------------------------------------------------

test("an unstamped approved entry gives its money back when voided", async () => {
  const p = await partner("unstamped-void-partner");
  const q = await period("unstamped-void-period");
  await entry("uv-small", {partnerId: p.id, periodId: q.id, amount: 100});
  const big = await entry("uv-big", {partnerId: p.id, periodId: q.id, amount: 1000000});
  await eventually("setup", total(p), 1000100);

  // The state a pre-trigger row, a script write, or a totals repair leaves.
  await unstamp(big);
  await big.update(VOID());

  await eventually("partner total after void", total(p), 100);
  await eventually("period total after void", total(q), 100);
  await eventually("partner entry count", count(p), 1);
});

test("an unstamped approved entry gives its money back when deleted", async () => {
  const p = await partner("unstamped-del-partner");
  const q = await period("unstamped-del-period");
  await entry("ud-small", {partnerId: p.id, periodId: q.id, amount: 100});
  const big = await entry("ud-big", {partnerId: p.id, periodId: q.id, amount: 1000000});
  await eventually("setup", total(p), 1000100);

  await unstamp(big);
  await big.delete();

  await eventually("partner total after delete", total(p), 100);
  await eventually("period total after delete", total(q), 100);
});

test("a deleted period does not swallow the partner's reversal", async () => {
  const p = await partner("gone-period-partner");
  const q = await period("gone-period-period");
  await entry("gp-small", {partnerId: p.id, periodId: q.id, amount: 100});
  const big = await entry("gp-big", {partnerId: p.id, periodId: q.id, amount: 1000000});
  await eventually("setup", total(p), 1000100);

  // Pastors can delete a period (periods_repository.dart:80). The period's own
  // total goes with it; the partner's must still be corrected.
  await q.delete();
  await big.update(VOID());

  await eventually("partner total after void", total(p), 100);
  await eventually("partner entry count", count(p), 1);
});

test("a missing partner does not swallow the period's reversal", async () => {
  // The mirror of the case above: whichever end of the move has lost its
  // document, the end that still has one is still corrected.
  const p = await partner("gone-partner");
  const q = await period("gone-partner-period");
  const e = await entry("gpn-entry", {partnerId: p.id, periodId: q.id, amount: 400});
  await eventually("setup", total(q), 400);

  await p.delete();
  await e.update(VOID());

  await eventually("period total after void", total(q), 0);
  await eventually("period count after void", count(q), 0);
});

// ---------------------------------------------------------------------------
// Idempotence — the property the stamp exists to protect.
// ---------------------------------------------------------------------------

test("voiding twice does not reverse twice", async () => {
  const p = await partner("twice-partner");
  const q = await period("twice-period");
  const e = await entry("twice-entry", {partnerId: p.id, periodId: q.id, amount: 250});
  await eventually("setup", total(p), 250);

  await e.update(VOID());
  await eventually("after first void", total(p), 0);

  await e.update({status: "voided", voidReason: "again", updatedAt: ts()});
  await settle();
  assert.equal(await total(p)(), 0, "a repeated void must not go negative");
  assert.equal(await count(p)(), 0);
});

test("voiding an unstamped entry twice does not reverse twice", async () => {
  const p = await partner("twice-unstamped-partner");
  const q = await period("twice-unstamped-period");
  const e = await entry("tu-entry", {partnerId: p.id, periodId: q.id, amount: 250});
  await eventually("setup", total(p), 250);

  await unstamp(e);
  await e.update(VOID());
  await eventually("after first void", total(p), 0);

  await e.update({status: "voided", voidReason: "again", updatedAt: ts()});
  await settle();
  assert.equal(await total(p)(), 0, "the implied reversal must happen once only");
});

test("restoring a voided entry puts exactly one copy back", async () => {
  const p = await partner("restore-partner");
  const q = await period("restore-period");
  const e = await entry("restore-entry", {partnerId: p.id, periodId: q.id, amount: 640.25});
  await eventually("setup", total(p), 640.25);

  await unstamp(e);
  await e.update(VOID());
  await eventually("voided", total(p), 0);

  await e.update({status: "approved", voidedAt: null, voidedBy: null, voidReason: null, updatedAt: ts()});
  await eventually("restored", total(p), 640.25);
  await eventually("count restored", count(p), 1);
  assert.notEqual(await stampOf(e), null, "a restored entry is stamped again");
});

// ---------------------------------------------------------------------------
// Ordinary arithmetic.
// ---------------------------------------------------------------------------

test("editing the amount moves the difference, not the whole amount", async () => {
  const p = await partner("edit-partner");
  const q = await period("edit-period");
  const e = await entry("edit-entry", {partnerId: p.id, periodId: q.id, amount: 1000000});
  await eventually("setup", total(p), 1000000);

  await e.update({amountCedis: 1000, updatedAt: ts()});
  await eventually("after correction", total(p), 1000);
  await eventually("count unchanged", count(p), 1);
});

test("editing an unstamped amount moves the difference, not the whole amount", async () => {
  const p = await partner("edit-unstamped-partner");
  const q = await period("edit-unstamped-period");
  const e = await entry("eu-entry", {partnerId: p.id, periodId: q.id, amount: 1000000});
  await eventually("setup", total(p), 1000000);

  await unstamp(e);
  await e.update({amountCedis: 1000, updatedAt: ts()});

  await eventually("after correction", total(p), 1000);
  await eventually("count unchanged", count(p), 1);
});

test("declining an approved entry takes the money back out", async () => {
  const p = await partner("decline-partner");
  const q = await period("decline-period");
  const e = await entry("decline-entry", {partnerId: p.id, periodId: q.id, amount: 90});
  await eventually("setup", total(p), 90);

  await e.update({status: "declined", declineReason: "wrong slip", updatedAt: ts()});
  await eventually("after decline", total(p), 0);

  await e.update({status: "approved", declineReason: null, updatedAt: ts()});
  await eventually("after re-approval", total(p), 90);
  await eventually("count after re-approval", count(p), 1);
});

test("moving an entry to another partner moves its money too", async () => {
  const from = await partner("move-from");
  const to = await partner("move-to");
  const q = await period("move-period");
  const e = await entry("move-entry", {partnerId: from.id, periodId: q.id, amount: 300});
  await eventually("setup", total(from), 300);

  await e.update({partnerId: to.id, partnerSnapshot: {fullName: "Person B"}, updatedAt: ts()});

  await eventually("old partner emptied", total(from), 0);
  await eventually("new partner credited", total(to), 300);
  await eventually("old count", count(from), 0);
  await eventually("new count", count(to), 1);
  await eventually("period unchanged", total(q), 300);
});

test("reassigning an entry to another period moves its money too", async () => {
  const p = await partner("reassign-partner");
  const q1 = await period("reassign-from");
  const q2 = await period("reassign-to");
  const e = await entry("reassign-entry", {partnerId: p.id, periodId: q1.id, amount: 750});
  await eventually("setup", total(q1), 750);

  await e.update({partnershipPeriodId: q2.id, periodSnapshot: {name: "2027"}, updatedAt: ts()});

  await eventually("old period emptied", total(q1), 0);
  await eventually("new period credited", total(q2), 750);
  await eventually("partner unchanged", total(p), 750);
  await eventually("partner count unchanged", count(p), 1);
});

test("goal progress follows the money in and back out", async () => {
  const p = await partner("goal-partner");
  const q = await period("goal-period");
  const g = await goal("goal-doc", {periodId: q.id, armId: "arm1"});
  const e = await entry("goal-entry", {partnerId: p.id, periodId: q.id, amount: 1200, armId: "arm1"});
  await eventually("goal credited", goalTotal(g), 1200);

  await unstamp(e);
  await e.update(VOID());
  await eventually("goal reversed", goalTotal(g), 0);
});

test("pesewas survive a round trip", async () => {
  const p = await partner("rounding-partner");
  const q = await period("rounding-period");
  // Thirds of a cedi, and a half-pesewa that has to round the same way twice.
  const amounts = [33.33, 33.33, 33.34, 0.005, 1234.565];
  const refs = [];
  for (const [i, amt] of amounts.entries()) {
    refs.push(await entry(`round-${i}`, {partnerId: p.id, periodId: q.id, amount: amt}));
  }
  const expected = 33.33 + 33.33 + 33.34 + 0.01 + 1234.57;
  await eventually("sum of odd amounts", toPesewa(total(p)), round2(expected));

  for (const ref of refs) await ref.update(VOID());
  await eventually("everything reversed to zero", toPesewa(total(p)), 0);
  await eventually("count back to zero", count(p), 0);

  // The pesewa total is the one the app reads, and it is exact: whole numbers
  // in, whole numbers out, nothing left behind. The cedi mirror alongside it
  // is a double and still carries the residue of its own arithmetic, which is
  // why nothing reads it when the exact field is there.
  assert.equal(await pesewasOf(p)(), 0, "the pesewa total must be exactly zero");
  assert.equal(await pesewasOf(q)(), 0);
});

test("the pesewa total is kept exactly, gift by gift", async () => {
  const p = await partner("exact-partner");
  const q = await period("exact-period");
  const g = await goal("exact-goal", {periodId: q.id, armId: "arm1"});

  // Tenths of a cedi: the amounts a double cannot hold.
  const amounts = [0.1, 0.2, 0.3, 33.33, 1234.57];
  const refs = [];
  for (const [i, amt] of amounts.entries()) {
    refs.push(await entry(`exact-${i}`, {partnerId: p.id, periodId: q.id, amount: amt, armId: "arm1"}));
  }
  const wanted = amounts.reduce((n, a) => n + Math.round(a * 100), 0);
  await eventually("partner pesewas", pesewasOf(p), wanted);
  await eventually("period pesewas", pesewasOf(q), wanted);
  await eventually("goal pesewas", goalPesewasOf(g), wanted);

  for (const ref of refs) await ref.update(VOID());
  await eventually("partner back to nothing", pesewasOf(p), 0);
  await eventually("period back to nothing", pesewasOf(q), 0);
  await eventually("goal back to nothing", goalPesewasOf(g), 0);
});

test("many entries on one partner add up and come back out", async () => {
  const p = await partner("bulk-partner");
  const q = await period("bulk-period");
  const refs = [];
  for (let i = 0; i < 25; i++) {
    refs.push(await entry(`bulk-${i}`, {partnerId: p.id, periodId: q.id, amount: 40}));
  }
  await eventually("bulk applied", total(p), 1000, 40000);
  await eventually("bulk counted", count(p), 25, 40000);

  for (const ref of refs) await ref.update(VOID());
  await eventually("bulk reversed", total(p), 0, 40000);
  await eventually("bulk count reversed", count(p), 0, 40000);
});

test("merging two partners lands on one correct total", async () => {
  // The write sequence `maintenance_repository.mergePartners` makes: repoint
  // the absorbed partner's entries, then mark that partner closed — and write
  // no totals, because the trigger is already moving them. Writing them here
  // as well used to leave the survivor holding both copies.
  const keep = await partner("merge-keep");
  const absorb = await partner("merge-absorb");
  const q = await period("merge-period");
  await entry("merge-k1", {partnerId: keep.id, periodId: q.id, amount: 200});
  const moved = await entry("merge-a1", {partnerId: absorb.id, periodId: q.id, amount: 300});
  await eventually("setup keep", total(keep), 200);
  await eventually("setup absorb", total(absorb), 300);

  await moved.update({partnerId: keep.id, partnerSnapshot: {fullName: "Person A"}, updatedAt: ts()});
  await absorb.update({isActive: false, mergedInto: keep.id, updatedAt: ts()});

  await eventually("survivor holds both gifts once", total(keep), 500);
  await eventually("survivor's count", count(keep), 2);
  await eventually("absorbed partner emptied", total(absorb), 0);
  await eventually("absorbed partner's count", count(absorb), 0);
  await eventually("period unchanged", total(q), 500);
});

test("a pending entry never touches a total, and deleting it changes nothing", async () => {
  const p = await partner("pending-partner");
  const q = await period("pending-period");
  const e = await entry("pending-entry", {partnerId: p.id, periodId: q.id, amount: 5000, status: "pending"});
  await settle();
  assert.equal(await total(p)(), 0, "pending money is not counted");

  await e.delete();
  await settle();
  assert.equal(await total(p)(), 0, "deleting it must not subtract anything");
  assert.equal(await count(p)(), 0);
});
