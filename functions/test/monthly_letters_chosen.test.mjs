/**
 * Sending a month's letter to chosen partners only, against the Firestore
 * emulator. Runs the sender in-process with live sending off (dry run), so no
 * email leaves.
 *
 *   firebase emulators:start --only firestore
 *   npm --prefix functions run build
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node --test functions/test/monthly_letters_chosen.test.mjs
 */
import {createRequire} from "node:module";
import {before, describe, it} from "node:test";
import assert from "node:assert/strict";

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("Refusing to run outside the emulator.");
  process.exit(1);
}

const CHURCH = "letters-chosen-test-church";
process.env.FUNCTIONS_EMULATOR = "true"; // never send for real
delete process.env.MONTHLY_EMAIL_ALLOW_SEND;
process.env[`RESEND_CHURCH_${CHURCH}`] = "test-key-not-used";

const require = createRequire(import.meta.url);
const admin = require("firebase-admin");
if (!admin.apps.length) admin.initializeApp({projectId: "thepillr2"});
const {runChurchMonthlyEmails} = require("../lib/monthly_partner_email.js");

const db = admin.firestore();
const church = db.doc(`churches/${CHURCH}`);
const delivery = (pid) => church.collection("monthly_email_deliveries").doc(`2026-10_${pid}`);
const report = () => church.collection("monthly_email_reports").doc("2026-10");

async function clear(col) {
  const snap = await church.collection(col).get();
  await Promise.all(snap.docs.map((d) => d.ref.delete()));
}

describe("letters for chosen partners", () => {
  before(async () => {
    for (const c of ["partners", "entries", "monthly_email_deliveries", "monthly_email_reports", "users"]) {
      await clear(c);
    }
    await church.set({
      name: "Letters Test Church",
      timezone: "Africa/Accra",
      settings: {
        sendMonthlyPartnerEmails: true,
        partnerEmailFrom: "giving@letters-test.org",
        primaryPastorUid: "pastor1",
      },
    });
    await church.collection("users").doc("pastor1").set({
      role: "pastor", fullName: "Test Pastor", email: "pastor@letters-test.org",
    });
    const people = {
      p1: "Ama Sent", p2: "Kofi Waiting", p3: "Esi Failed", p4: "Yaw Chosen",
    };
    for (const [id, name] of Object.entries(people)) {
      await church.collection("partners").doc(id).set({
        fullName: name, email: `${id}@example.com`, isActive: true,
      });
      await church.collection("entries").doc(`e-${id}`).set({
        partnerId: id,
        status: "approved",
        amountCedis: 100,
        dateGiven: admin.firestore.Timestamp.fromDate(new Date("2026-10-05T10:00:00Z")),
        armSnapshot: {name: "Tithe"},
      });
    }
    // Ama already got October's letter; Esi's failed on the 15th.
    await delivery("p1").set({partnerId: "p1", yearMonth: "2026-10", status: "sent"});
    await report().set({
      yearMonth: "2026-10",
      failed: [{partnerId: "p3", fullName: "Esi Failed", email: "p3@example.com", error: "mailbox full"}],
    });
  });

  it("sends only to the chosen, again if they already had it, and keeps everyone else", async () => {
    const r = await runChurchMonthlyEmails({
      churchId: CHURCH, year: 2026, month: 10, liveSend: true, onlyPartnerIds: ["p1", "p4"],
    });
    assert.equal(r.skipped, false);
    assert.equal(r.sentNow, 2, "Ama again, and Yaw");
    assert.equal((await delivery("p1").get()).data().status, "dry_run", "Ama's was sent again");
    assert.ok((await delivery("p4").get()).exists, "Yaw was sent");
    assert.equal((await delivery("p2").get()).exists, false, "Kofi was not chosen");

    const rep = (await report().get()).data();
    assert.deepEqual(rep.failed.map((f) => f.partnerId), ["p3"], "Esi's earlier failure is kept");
  });

  it("a normal run still sends to everyone not sent yet", async () => {
    const r = await runChurchMonthlyEmails({churchId: CHURCH, year: 2026, month: 10, liveSend: true});
    // Dry runs never count as sent, so all four go out in this dry run.
    assert.equal(r.sentNow, 4);
    assert.ok((await delivery("p2").get()).exists, "Kofi now has it");
    assert.deepEqual((await report().get()).data().failed, []);
  });
});
