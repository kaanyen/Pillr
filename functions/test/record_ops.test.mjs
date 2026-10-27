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
    assert.ok(!r.result.formerMemberIds.includes(r.result.newMemberId));
    assert.equal((await entry("e1").get()).get("partnerId"), "keep");
    assert.equal((await entry("e1").get()).get("mergedFromPartnerId"), "dup");
    const keep = (await partner("keep").get()).data();
    assert.equal(keep.phone, "0244123456");
    assert.match(keep.memberId, /^ACC\d{6}$/);
    assert.notEqual(keep.memberId, "ACC001");
    assert.equal(r.result.newMemberId, keep.memberId);
    assert.deepEqual(keep.formerMemberIds, ["ACC001", "ACC002"]);
    assert.deepEqual(keep.phones, ["0244123456"]);
    assert.deepEqual(keep.emails, ["kwame@example.com"]);
    assert.equal(keep.mergedAliases[0].memberId, "ACC001");
    assert.equal(keep.mergedAliases[0].self, true);
    assert.equal(keep.mergedAliases[1].memberId, "ACC002");
    assert.equal((await entry("e1").get()).get("partnerSnapshot").memberId, keep.memberId);
    // The closed record keeps its own ID, so it can be found and separated by it.
    assert.equal((await partner("dup").get()).get("memberId"), "ACC002");
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
    assert.equal((await entry("e2").get()).get("mergedFromPartnerId"), undefined);
    const keep = (await partner("keep").get()).data();
    assert.equal(keep.phone, undefined);
    assert.equal(keep.mergedAliases, undefined);
    assert.equal(keep.memberId, "ACC001");
    assert.equal(keep.formerMemberIds, undefined);
    assert.equal(keep.phones, undefined);
    const dup = (await partner("dup").get()).data();
    assert.equal(dup.isActive, true);
    assert.equal(dup.mergedInto, undefined);
    assert.equal((await partner("older").get()).get("mergedInto"), "dup");
    await eventually(() => amount("dup"), 150, "absorbed total restored");
    await eventually(() => amount("keep"), 0, "kept total restored");
  });
});

describe("merging many records, and separating one by its member ID", () => {
  const amount = async (id) => (await partner(id).get()).get("totalApprovedAmount") ?? 0;

  before(async () => {
    await partner("m1").set({fullName: "Precious Adedeji", memberId: "ACC100001", isActive: true,
      phone: "0241111111"});
    await partner("m2").set({fullName: "Precious Adedeji", memberId: "ACC100002", isActive: true,
      phone: "0242222222", email: "precious@example.com"});
    await partner("m3").set({fullName: "Precious Adedeji", memberId: "ACC100003", isActive: true,
      phone: "+233 24 111 1111", email: "p.adedeji@example.com"});
    for (const [id, pid, amt] of [["g1", "m1", 10], ["g2", "m2", 20], ["g3", "m3", 30], ["g4", "m3", 40]]) {
      await entry(id).set({
        churchId: CHURCH, partnerId: pid, partnerSnapshot: {fullName: "Precious Adedeji"},
        partnershipArmId: "arm1", partnershipPeriodId: "per1",
        amountCedis: amt, status: "approved", createdBy: "seed",
      });
    }
    await eventually(() => amount("m3"), 70, "m3 seeded");
  });

  it("merges three records into one with a new ID and all old IDs kept", async () => {
    const r = await call("partnerMerge", {keepId: "m1", absorbIds: ["m2", "m3"], expectEntries: 3});
    assert.equal(r.result?.moved, 3, JSON.stringify(r));
    const m1 = (await partner("m1").get()).data();
    assert.deepEqual(m1.formerMemberIds, ["ACC100001", "ACC100002", "ACC100003"]);
    // The kept record's own details are saved too, so it can be taken out.
    assert.equal(m1.mergedAliases.length, 3);
    assert.equal(m1.mergedAliases[0].self, true);
    // Every number and email, once each: m3's phone is m1's in another format.
    assert.deepEqual(m1.phones, ["0241111111", "0242222222"]);
    assert.deepEqual(m1.emails, ["precious@example.com", "p.adedeji@example.com"]);
    assert.equal(m1.email, "precious@example.com");
    assert.equal((await entry("g1").get()).get("mergedFromPartnerId"), "m1");
    assert.equal((await entry("g4").get()).get("mergedFromPartnerId"), "m3");
    await eventually(() => amount("m1"), 100, "merged total");
  });

  it("separates one record by its member ID and leaves the rest merged", async () => {
    const r = await call("partnerUnmerge", {memberId: "acc100003"});
    assert.equal(r.result?.moved, 2, JSON.stringify(r));
    const m3 = (await partner("m3").get()).data();
    assert.equal(m3.isActive, true);
    assert.equal(m3.mergedInto, undefined);
    assert.equal(m3.memberId, "ACC100003");
    assert.equal((await entry("g4").get()).get("partnerId"), "m3");
    assert.equal((await entry("g4").get()).get("mergedFromPartnerId"), undefined);
    assert.equal((await entry("g2").get()).get("partnerId"), "m1");
    const m1 = (await partner("m1").get()).data();
    assert.deepEqual(m1.formerMemberIds, ["ACC100001", "ACC100002"]);
    assert.equal(m1.mergedAliases.length, 2);
    // m3's phone stays (m1 has it too); only m3's own email goes.
    assert.deepEqual(m1.phones, ["0241111111", "0242222222"]);
    assert.deepEqual(m1.emails, ["precious@example.com"]);
    await eventually(() => amount("m3"), 70, "separated total");
    await eventually(() => amount("m1"), 30, "remaining total");
  });

  it("undoes the separation", async () => {
    const op = (await church.collection("operations").where("kind", "==", "partner.unmerge").get()).docs[0];
    const r = await call("undoOperation", {opId: op.id});
    assert.equal(r.result?.conflicts, 0, JSON.stringify(r));
    assert.equal((await partner("m3").get()).get("mergedInto"), "m1");
    assert.equal((await entry("g4").get()).get("partnerId"), "m1");
    assert.equal((await entry("g4").get()).get("mergedFromPartnerId"), "m3");
    await eventually(() => amount("m1"), 100, "merged again");
  });

  it("takes out the record that was kept, by its old ID", async () => {
    // m1 was kept in the merge above; its own gift g1 is ₵10 and its phone
    // 0241111111. Taking out ACC100001 rebuilds it as its own record.
    const r = await call("partnerUnmerge", {memberId: "ACC100001"});
    assert.equal(r.result?.moved, 1, JSON.stringify(r));
    const fresh = (await partner(r.result.partnerId).get()).data();
    assert.equal(fresh.memberId, "ACC100001");
    assert.equal(fresh.fullName, "Precious Adedeji");
    assert.equal(fresh.phone, "0241111111");
    assert.equal(fresh.splitFrom, "m1");
    assert.equal((await entry("g1").get()).get("partnerId"), r.result.partnerId);
    const m1 = (await partner("m1").get()).data();
    assert.ok(!m1.formerMemberIds.includes("ACC100001"));
    assert.ok(!m1.mergedAliases.some((a) => a.self));
    await eventually(() => amount(r.result.partnerId), 10, "kept record rebuilt with its gift");
    await eventually(() => amount("m1"), 90, "merged person without it");
  });

  it("undoes taking out the kept record, removing the record it made", async () => {
    const ops = (await church.collection("operations").where("kind", "==", "partner.unmerge").get()).docs;
    const op = ops.find((d) => d.get("summary").wasKeptRecord);
    const madeId = op.get("summary").separatedId;
    const r = await call("undoOperation", {opId: op.id});
    assert.equal(r.result?.conflicts, 0, JSON.stringify(r));
    assert.equal((await partner(madeId).get()).exists, false);
    assert.equal((await entry("g1").get()).get("partnerId"), "m1");
    assert.ok((await partner("m1").get()).get("formerMemberIds").includes("ACC100001"));
    await eventually(() => amount("m1"), 100, "back together");
  });

  it("never gives a retired ID to someone new", async () => {
    const m1 = (await partner("m1").get()).data();
    const all = (await church.collection("partners").get()).docs.map((d) => d.get("memberId"));
    for (const f of m1.formerMemberIds) {
      assert.ok(f !== m1.memberId);
      assert.equal(all.filter((x) => x === f).length <= 1, true);
    }
  });

  it("says plainly when an ID is not a merged record", async () => {
    const r = await call("partnerUnmerge", {memberId: "ACC999999"});
    assert.equal(r.error?.status, "FAILED_PRECONDITION");
  });
});
