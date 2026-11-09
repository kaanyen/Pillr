/**
 * A partner's own page, against the emulators (Firestore and Functions).
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node --test functions/test/partner_page.test.mjs
 */
import {createRequire} from "node:module";
import {describe, it, before} from "node:test";
import assert from "node:assert/strict";

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("Refusing to run outside the emulator.");
  process.exit(1);
}
const require = createRequire(import.meta.url);
const admin = require("firebase-admin");
if (!admin.apps.length) admin.initializeApp({projectId: "thepillr2"});
const {partnerPageUrl} = require("../lib/partner_page.js");
const db = admin.firestore();
const C = "partner-page-test-church";
const church = db.doc(`churches/${C}`);
const FN = "http://127.0.0.1:5001/thepillr2/us-central1/partnerPage";
const open = async (url) => {
  const key = url.split("/p/")[1];
  const r = await fetch(`${FN}/p/${key}`);
  return {status: r.status, html: await r.text(), headers: r.headers};
};

describe("a partner's own page", () => {
  let url;
  before(async () => {
    await church.set({name: "Page Test Church", currencySymbol: "₵", settings: {partnerPageOn: true}});
    await church.collection("partnership_periods").doc("y26").set({name: "2026", isActive: true});
    await church.collection("partners").doc("pa").set({fullName: "Ama Boateng", isActive: true});
    await church.collection("partners").doc("pb").set({fullName: "Kofi Mensah", isActive: true});
    const at = admin.firestore.Timestamp.fromDate(new Date("2026-10-05T10:00:00Z"));
    const e = (id, pid, amt, status, arm = "Tithe") => church.collection("entries").doc(id).set({
      partnerId: pid, partnershipPeriodId: "y26", status, amountCedis: amt, dateGiven: at, armSnapshot: {name: arm},
    });
    await e("x1", "pa", 200, "approved");
    await e("x2", "pa", 50, "approved", "Building");
    await e("x3", "pa", 999, "pending");
    await e("x4", "pb", 777, "approved");
    url = await partnerPageUrl(C, "pa");
  });

  it("keeps one link per partner, off the partner's record", async () => {
    assert.match(url, /\/p\/[A-Za-z0-9_-]{32}$/);
    assert.equal(await partnerPageUrl(C, "pa"), url);
    assert.equal((await church.collection("partners").doc("pa").get()).get("pageKey"), undefined);
  });

  it("shows only that partner's approved giving", async () => {
    const r = await open(url);
    assert.equal(r.status, 200);
    assert.match(r.html, /Thank you, Ama\./);
    assert.match(r.html, /₵250\.00/);
    assert.doesNotMatch(r.html, /999/, "waiting giving is not shown");
    assert.doesNotMatch(r.html, /777|Kofi/, "nobody else's");
    assert.match(r.headers.get("cache-control"), /no-store/);
  });

  it("stops working when the church switches pages off, or for a made-up key", async () => {
    assert.equal((await open(`x/p/${"a".repeat(32)}`)).status, 404);
    await church.set({settings: {partnerPageOn: false}}, {merge: true});
    assert.equal((await open(url)).status, 404);
    await church.set({settings: {partnerPageOn: true}}, {merge: true});
    assert.equal((await open(url)).status, 200);
  });
});
