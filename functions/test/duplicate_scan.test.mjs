/**
 * The nightly duplicate check counts what the app's Tools scan would find.
 * The cases mirror test/maintenance_test.dart.
 *
 *   firebase emulators:start --only firestore
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node --test functions/test/duplicate_scan.test.mjs
 */
import {describe, it} from "node:test";
import assert from "node:assert/strict";
import {createRequire} from "node:module";
import admin from "firebase-admin";

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("Refusing to run outside the emulator.");
  process.exit(1);
}

const require = createRequire(import.meta.url);
const scan = require("../lib/duplicate_scan.js");

const p = (id, fullName, extra = {}) => ({
  id, fullName, memberId: "", fellowship: "", phones: [], emails: [], ...extra,
});
const count = (list, dismissed = new Set()) => scan.countDuplicates(list, dismissed);
const total = (c) => c.almostCertain + c.likely + c.check;

describe("nightly duplicate rules", () => {
  it("never pairs a partner with itself", () => {
    assert.equal(total(count([p("a", "Paulina Boakye Boateng"), p("b", "Ama Serwaa")])), 0);
  });

  it("matches one phone number written different ways", () => {
    const c = count([
      p("a", "Kofi Boateng", {phones: ["0244123456"]}),
      p("b", "Kofi Boateng", {phones: ["+233 24 412 3456"]}),
    ]);
    assert.equal(c.almostCertain, 1);
  });

  it("matches a merged person's second number", () => {
    const c = count([
      p("a", "Ama Mensah", {phones: ["0241111111", "0242222222"]}),
      p("b", "Ama Mensah", {phones: ["0242222222"]}),
    ]);
    assert.equal(c.almostCertain, 1);
  });

  it("does not take different day names for typos", () => {
    assert.equal(total(count([p("a", "Ama Mensah"), p("b", "Akosua Mensah")])), 0);
    assert.equal(total(count([p("a", "Samuel Yeboah"), p("b", "Daniel Yeboah")])), 0);
  });

  it("finds day-name spellings and short forms", () => {
    assert.equal(total(count([p("a", "Kofi Mensah"), p("b", "Fiifi Mensah")])), 1);
    assert.equal(total(count([p("a", "Ella Kabe"), p("b", "Emmanuella Catherine Kabe")])), 1);
  });

  it("counts a family's shared phone only as one to check", () => {
    const c = count([
      p("a", "Kofi Boateng", {phones: ["0244123456"]}),
      p("b", "Akosua Owusu", {phones: ["0244123456"]}),
    ]);
    assert.deepEqual([c.almostCertain, c.likely, c.check], [0, 0, 1]);
  });

  it("counts one person entered three times as a group", () => {
    const c = count([p("a", "Precious Adedeji"), p("b", "Precious Adedeji"), p("c", "Precious Adedeji")]);
    assert.equal(c.groups, 1);
  });

  it("leaves out pairs marked as two people", () => {
    assert.equal(total(count([p("a", "Yaw Darko"), p("b", "Yaw Darko")], new Set(["a|b"]))), 0);
  });
});

describe("nightly duplicate check against the emulator", () => {
  it("writes the counts for a church, leaving out merged records", async () => {
    if (!admin.apps.length) admin.initializeApp({projectId: "thepillr2"});
    const db = admin.firestore();
    const church = db.doc("churches/dup-scan-test-church");
    await db.recursiveDelete(church);
    await church.set({name: "Dup Scan Church"});
    await church.collection("partners").doc("a").set({fullName: "Yaw Darko", phone: "0244000001"});
    await church.collection("partners").doc("b").set({fullName: "Yaw Darko", phone: "0244000001"});
    await church.collection("partners").doc("c").set({fullName: "Yaw Darko", mergedInto: "a"});
    await scan.scanChurchForDuplicates("dup-scan-test-church");
    const health = (await church.collection("health").doc("duplicates").get()).data();
    assert.equal(health.almostCertain, 1);
    assert.equal(health.open, 1);
    assert.equal(health.partners, 2);
    await db.recursiveDelete(church);
  });
});
