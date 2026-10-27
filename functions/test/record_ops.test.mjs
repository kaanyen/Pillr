/**
 * Fellowship and partner merges, and their undo, end to end against the
 * emulators: the callables, the rules they bypass, and the totals trigger that
 * follows a repointed entry.
 *
 *   firebase emulators:start --only auth,firestore,functions
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
 *     node --test functions/test/record_ops.test.mjs
 */
import {after, before, describe, it} from "node:test";
import assert from "node:assert/strict";
import admin from "firebase-admin";

if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
  console.error("Refusing to run outside the emulator.");
  process.exit(1);
}

const PROJECT = "thepillr2";
const FUNCTIONS = `http://127.0.0.1:5001/${PROJECT}/us-central1`;
const AUTH = `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}`;
const CHURCH = "record-ops-test-church";

admin.initializeApp({projectId: PROJECT});
const db = admin.firestore();
const church = db.doc(`churches/${CHURCH}`);
const partner = (id) => church.collection("partners").doc(id);
const entry = (id) => church.collection("entries").doc(id);

const tokens = {};

async function signIn(role) {
  const email = `record-ops-${role}@pillr.test`;
  let user;
  try {
    user = await admin.auth().getUserByEmail(email);
  } catch {
    user = await admin.auth().createUser({email, password: "DemoPillr1!"});
  }
  await db.doc(`user_church_index/${user.uid}`).set({churchId: CHURCH, role});
  await church.collection("users").doc(user.uid).set({fullName: `Test ${role}`, email, role});
  const res = await fetch(
    `${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake`,
    {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({email, password: "DemoPillr1!", returnSecureToken: true}),
    },
  );
  tokens[role] = (await res.json()).idToken;
}

/** Calls a callable; returns {result} or {error: {status, message}}. */
async function call(name, data, role = "pastor") {
  const res = await fetch(`${FUNCTIONS}/${name}`, {
    method: "POST",
    headers: {"content-type": "application/json", authorization: `Bearer ${tokens[role]}`},
    body: JSON.stringify({data: {churchId: CHURCH, ...data}}),
  });
  return res.json();
}

async function eventually(read, want, what, timeoutMs = 20000) {
  const started = Date.now();
  let last;
  while (Date.now() - started < timeoutMs) {
    last = await read();
    if (JSON.stringify(last) === JSON.stringify(want)) return;
    await new Promise((r) => setTimeout(r, 150));
  }
  assert.fail(`${what}: expected ${JSON.stringify(want)}, still ${JSON.stringify(last)}`);
}

const fellowshipOf = async (id) => (await partner(id).get()).get("fellowship");
const catalog = async () => (await church.get()).get("settings.fellowshipNames");

async function wipe() {
  await db.recursiveDelete(church);
}

before(async () => {
  await wipe();
  await church.set({name: "Record Ops Church", settings: {fellowshipNames: ["Bethel", "Zion", "Grace"]}});
  for (const role of ["pastor", "staff", "admin"]) await signIn(role);
});

after(async () => {
  await wipe();
});

describe("fellowship merge", () => {
  before(async () => {
    await partner("a1").set({fullName: "Ama One", fellowship: "Bethel", isActive: true});
    await partner("a2").set({fullName: "Ama Two", fellowship: "bethel", isActive: true});
    await partner("a3").set({fullName: "Ama Inactive", fellowship: "Bethel", isActive: false});
    await partner("z1").set({fullName: "Zed One", fellowship: "Zion", isActive: true});
  });

  it("refuses when the screen was out of date, and writes nothing", async () => {
    const r = await call("fellowshipChange", {kind: "merge", fromNames: ["Bethel"], toName: "Zion", expectActive: 5});
    assert.equal(r.error?.status, "FAILED_PRECONDITION");
    assert.equal(await fellowshipOf("a1"), "Bethel");
    const ops = await church.collection("operations").get();
    assert.equal(ops.size, 0);
  });

  it("moves inactive partners too, drops the old name, and records it", async () => {
    const r = await call("fellowshipChange", {kind: "dissolve", fromNames: ["Bethel"], toName: "Zion", expectActive: 2});
    assert.ok(r.result?.opId, JSON.stringify(r));
    assert.equal(r.result.moved, 2);
    assert.equal(r.result.inactiveMoved, 1);
    for (const id of ["a1", "a2", "a3"]) assert.equal(await fellowshipOf(id), "Zion");
    assert.deepEqual(await catalog(), ["Grace", "Zion"]);
    const op = await church.collection("operations").doc(r.result.opId).get();
    assert.equal(op.get("status"), "applied");
    assert.equal((await op.ref.collection("changes").get()).size, 4);
    const logs = await church.collection("activity_logs").where("action", "==", "fellowship.dissolve").get();
    assert.equal(logs.size, 1);
  });

  it("undoes it, leaving alone a partner edited since", async () => {
    const op = (await church.collection("operations").where("kind", "==", "fellowship.dissolve").get()).docs[0];
    await partner("a2").update({fellowship: "Grace", fellowshipLower: "grace"});
    const r = await call("undoOperation", {opId: op.id});
    assert.equal(r.result?.conflicts, 1, JSON.stringify(r));
    assert.equal(await fellowshipOf("a1"), "Bethel");
    assert.equal(await fellowshipOf("a3"), "Bethel");
    assert.equal(await fellowshipOf("a2"), "Grace");
    // Untouched since, so it goes back exactly as it was stored.
    assert.deepEqual(await catalog(), ["Bethel", "Zion", "Grace"]);
    assert.equal((await op.ref.get()).get("status"), "undone");
  });

  it("refuses undoing twice", async () => {
    const op = (await church.collection("operations").where("kind", "==", "fellowship.dissolve").get()).docs[0];
    const r = await call("undoOperation", {opId: op.id});
    assert.equal(r.error?.status, "FAILED_PRECONDITION");
  });

  it("moves picked partners and keeps the old group listed", async () => {
    const r = await call("fellowshipChange", {kind: "move", partnerIds: ["a1", "z1"], toName: "Grace"}, "staff");
    assert.equal(r.result?.moved, 2, JSON.stringify(r));
    assert.equal(await fellowshipOf("a1"), "Grace");
    assert.ok((await catalog()).includes("Bethel"));
  });

  it("refuses while another change holds the lock", async () => {
    await church.collection("op_locks").doc("records").set({holder: "x", acquiredAt: admin.firestore.Timestamp.now()});
    const r = await call("fellowshipChange", {kind: "rename", fromNames: ["Grace"], toName: "Grace Hall"});
    assert.equal(r.error?.status, "ABORTED");
    await church.collection("op_locks").doc("records").delete();
  });
});

describe("partner merge", () => {
  const amount = async (id) => (await partner(id).get()).get("totalApprovedAmount") ?? 0;

  before(async () => {
    await church.collection("partnership_periods").doc("per1").set({name: "2026", isActive: true});
    await church.collection("partnership_arms").doc("arm1").set({name: "Building"});
    await partner("keep").set({fullName: "Kwame Mensah", fellowship: "Zion", memberId: "ACC001", isActive: true});
    await partner("dup").set({fullName: "Kwame Mensah", fellowship: "Zion", memberId: "ACC002",
      phone: "0244123456", email: "kwame@example.com", isActive: true});
    await partner("older").set({fullName: "K. Mensah", isActive: false, mergedInto: "dup"});
    for (const [id, amt] of [["e1", 100], ["e2", 50]]) {
      await entry(id).set({
        churchId: CHURCH, partnerId: "dup", partnerSnapshot: {fullName: "Kwame Mensah"},
        partnershipArmId: "arm1", partnershipPeriodId: "per1",
        amountCedis: amt, status: "approved", createdBy: "seed",
      });
    }
    await eventually(() => amount("dup"), 150, "dup total after seeding");
  });

  it("refuses an admin", async () => {
    const r = await call("partnerMerge", {keepId: "keep", absorbId: "dup"}, "admin");
    assert.equal(r.error?.status, "PERMISSION_DENIED");
  });

  it("moves entries, fills blanks, closes the duplicate and follows the chain", async () => {
    const r = await call("partnerMerge", {keepId: "keep", absorbId: "dup", expectEntries: 2}, "staff");
    assert.equal(r.result?.moved, 2, JSON.stringify(r));
    assert.deepEqual(r.result.filled, ["phone", "email"]);
    assert.equal((await entry("e1").get()).get("partnerId"), "keep");
    const keep = (await partner("keep").get()).data();
    assert.equal(keep.phone, "0244123456");
    assert.equal(keep.memberId, "ACC001");
    assert.equal(keep.mergedAliases[0].memberId, "ACC002");
    const dup = (await partner("dup").get()).data();
    assert.equal(dup.isActive, false);
    assert.equal(dup.mergedInto, "keep");
    assert.equal((await partner("older").get()).get("mergedInto"), "keep");
    await eventually(() => amount("keep"), 150, "kept total");
    await eventually(() => amount("dup"), 0, "absorbed total");
  });

  it("refuses merging an already-merged record", async () => {
    const r = await call("partnerMerge", {keepId: "keep", absorbId: "dup"});
    assert.equal(r.error?.status, "FAILED_PRECONDITION");
  });

  it("undoes the merge and the money follows back", async () => {
    const op = (await church.collection("operations").where("kind", "==", "partner.merge").get()).docs[0];
    const r = await call("undoOperation", {opId: op.id}, "staff");
    assert.equal(r.result?.conflicts, 0, JSON.stringify(r));
    assert.equal((await entry("e2").get()).get("partnerId"), "dup");
    const keep = (await partner("keep").get()).data();
    assert.equal(keep.phone, undefined);
    assert.equal(keep.mergedAliases, undefined);
    const dup = (await partner("dup").get()).data();
    assert.equal(dup.isActive, true);
    assert.equal(dup.mergedInto, undefined);
    assert.equal((await partner("older").get()).get("mergedInto"), "dup");
    await eventually(() => amount("dup"), 150, "absorbed total restored");
    await eventually(() => amount("keep"), 0, "kept total restored");
  });
});
