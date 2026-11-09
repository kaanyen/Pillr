/**
 * Thank-you messages on approval.
 *   node --test functions/test/giving_messages.test.mjs                  (pure helpers)
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node --test ...               (plus the trigger, against the emulators)
 */
import {createRequire} from "node:module";
import {describe, it, before} from "node:test";
import assert from "node:assert/strict";

const require = createRequire(import.meta.url);
const lib = require("../lib/giving_messages.js");

describe("giving message helpers", () => {
  const v = {firstName: "Ama", amount: "₵500.00", arm: "Tithe", date: "8 November", churchName: "Demo Church"};
  it("fills every word, whatever the capitals", () => {
    assert.equal(lib.fillGivingTokens("[first name]: [AMOUNT] to [Arm] on [date], [Church Name]", v), "Ama: ₵500.00 to Tithe on 8 November, Demo Church");
  });
  it("turns Ghana numbers into the form mNotify wants", () => {
    assert.equal(lib.normalizeGhanaPhone("024 412 3456"), "233244123456");
    assert.equal(lib.normalizeGhanaPhone("+233 24 412 3456"), "233244123456");
    assert.equal(lib.normalizeGhanaPhone("244123456"), "233244123456");
    assert.equal(lib.normalizeGhanaPhone("12345"), null);
    assert.equal(lib.normalizeGhanaPhone(""), null);
  });
  it("counts what a text costs", () => {
    assert.equal(lib.smsParts("x".repeat(160)), 1);
    assert.equal(lib.smsParts("x".repeat(161)), 2);
    assert.equal(lib.smsParts("x".repeat(307)), 3);
  });
  it("escapes the church's words in the email", () => {
    const html = lib.buildApprovalEmailHtml({message: "Hi [First name] <b>", values: v, pastorName: "Pastor"});
    assert.match(html, /Hi Ama &lt;b&gt;/);
    assert.match(html, /₵500.00/);
  });
});

const emulator = !!process.env.FIRESTORE_EMULATOR_HOST;
describe("thanking on approval", {skip: !emulator && "needs the emulators"}, () => {
  const admin = require("firebase-admin");
  if (!admin.apps.length) admin.initializeApp({projectId: "thepillr2"});
  const db = admin.firestore();
  const C = "giving-msg-test-church";
  const church = db.doc(`churches/${C}`);
  const wait = async (ref, ms = 15000) => {
    const until = Date.now() + ms;
    while (Date.now() < until) {
      const s = await ref.get();
      if (s.exists && s.get("sentAt")) return s.data();
      await new Promise((r) => setTimeout(r, 300));
    }
    return (await ref.get()).data();
  };
  before(async () => {
    await church.set({name: "Msg Test Church", settings: {approvalEmailOn: true, approvalSmsOn: true, smsSenderId: "TestChurch", partnerEmailFrom: "giving@test.org", primaryPastorUid: "p1"}});
    await church.collection("partners").doc("pa").set({fullName: "Ama Boateng", email: "ama@example.com", phone: "0244123456"});
    await church.collection("partners").doc("pb").set({fullName: "Kofi Mensah", noMonthlyLetters: true, phone: "0244000000"});
    for (const id of ["e1", "e2", "e3"]) await church.collection("giving_messages").doc(id).delete();
  });
  it("records one message per approved entry, and none while pending", async () => {
    const e = church.collection("entries").doc("e1");
    await e.set({partnerId: "pa", status: "pending", amountCedis: 500, armSnapshot: {name: "Tithe"}, dateGiven: admin.firestore.Timestamp.now(), partnershipPeriodId: "x", partnershipArmId: "y"});
    await new Promise((r) => setTimeout(r, 2500));
    assert.equal((await church.collection("giving_messages").doc("e1").get()).exists, false, "nothing before approval");
    await e.update({status: "approved"});
    const rec = await wait(church.collection("giving_messages").doc("e1"));
    assert.ok(rec, "a record after approval");
    // On the emulator nothing is sent for real; the email has no key here.
    assert.ok(["dry_run", "skipped"].includes(rec.email.status));
    assert.ok(["dry_run", "skipped"].includes(rec.sms.status));
    // Undo and approve again: still one record, not re-sent.
    await e.update({status: "pending"});
    await e.update({status: "approved"});
    await new Promise((r) => setTimeout(r, 2500));
    const again = (await church.collection("giving_messages").doc("e1").get()).data();
    assert.deepEqual(again.sms, rec.sms);
  });
  it("skips a partner whose messages are turned off", async () => {
    await church.collection("entries").doc("e2").set({partnerId: "pb", status: "approved", amountCedis: 50, armSnapshot: {name: "Tithe"}, dateGiven: admin.firestore.Timestamp.now(), partnershipPeriodId: "x", partnershipArmId: "y"});
    const rec = await wait(church.collection("giving_messages").doc("e2"));
    assert.equal(rec.sms.status, "skipped");
    assert.equal(rec.sms.reason, "turned off for this partner");
  });
});
