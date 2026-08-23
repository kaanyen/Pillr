/**
 * Firestore rules are the whole authorization model and, until this file, not
 * one line of them was tested. These run against the rules emulator on 8080.
 *
 *   firebase emulators:start --only firestore
 *   node --test functions/test/rules.test.mjs
 */
import {readFileSync} from "node:fs";
import {after, before, describe, it} from "node:test";
import assert from "node:assert/strict";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {doc, getDoc, setDoc, updateDoc, deleteDoc} from "firebase/firestore";

const HOST = (process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080").split(":");

let env;

const PASTOR = "pastor-uid";
const STAFF = "staff-uid";
const ADMIN = "admin-uid";
const OUTSIDER = "other-church-uid";
const SUSPENDED_PASTOR = "suspended-pastor-uid";
const SUSPENDED_ADMIN = "suspended-admin-uid";

/** Membership lives in user_church_index, which rules read on every request. */
async function seedMemberships(ctx) {
  const db = ctx.firestore();
  await setDoc(doc(db, "user_church_index", PASTOR), {churchId: "c1", role: "pastor"});
  await setDoc(doc(db, "user_church_index", STAFF), {churchId: "c1", role: "staff"});
  await setDoc(doc(db, "user_church_index", ADMIN), {churchId: "c1", role: "admin"});
  await setDoc(doc(db, "user_church_index", OUTSIDER), {churchId: "c2", role: "pastor"});
  // A suspended church, with its own pastor and admin, to test the one thing
  // they must not be able to do.
  await setDoc(doc(db, "user_church_index", SUSPENDED_PASTOR), {churchId: "c3", role: "pastor"});
  await setDoc(doc(db, "user_church_index", SUSPENDED_ADMIN), {churchId: "c3", role: "admin"});
  await setDoc(doc(db, "churches/c3"), {name: "Suspended Church", isActive: false});
  await setDoc(doc(db, "churches/c1"), {name: "First Church", isActive: true});
  await setDoc(doc(db, "churches/c2"), {name: "Second Church", isActive: true});
  await setDoc(doc(db, "churches/c1/entries/e1"), {
    churchId: "c1",
    createdBy: STAFF,
    status: "pending",
    amountCedis: 100,
  });
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "pillr-rules-test",
    firestore: {
      host: HOST[0],
      port: Number(HOST[1]),
      rules: readFileSync(new URL("../../firestore.rules", import.meta.url), "utf8"),
    },
  });
  await env.withSecurityRulesDisabled(seedMemberships);
});

after(async () => {
  await env?.cleanup();
});

describe("a church cannot switch itself back on", () => {
  it("refuses a suspended church's pastor turning it back on", async () => {
    const db = env.authenticatedContext(SUSPENDED_PASTOR).firestore();
    await assertFails(updateDoc(doc(db, "churches/c3"), {isActive: true}));
  });

  it("refuses a suspended church's admin turning it back on", async () => {
    const db = env.authenticatedContext(SUSPENDED_ADMIN).firestore();
    await assertFails(updateDoc(doc(db, "churches/c3"), {isActive: true}));
  });

  it("refuses a church suspending itself", async () => {
    const db = env.authenticatedContext(PASTOR).firestore();
    await assertFails(updateDoc(doc(db, "churches/c1"), {isActive: false}));
  });

  it("still allows branding", async () => {
    const db = env.authenticatedContext(PASTOR).firestore();
    await assertSucceeds(updateDoc(doc(db, "churches/c1"), {name: "Renamed", primaryColorHex: "#123456"}));
  });

  it("refuses branding smuggled in with isActive", async () => {
    const db = env.authenticatedContext(SUSPENDED_PASTOR).firestore();
    await assertFails(updateDoc(doc(db, "churches/c3"), {name: "Sneaky", isActive: true}));
  });

  it("refuses deleting the church", async () => {
    const db = env.authenticatedContext(ADMIN).firestore();
    await assertFails(deleteDoc(doc(db, "churches/c1")));
  });
});

describe("one church cannot read another", () => {
  it("refuses a foreign church document", async () => {
    const db = env.authenticatedContext(OUTSIDER).firestore();
    await assertFails(getDoc(doc(db, "churches/c1")));
  });

  it("refuses foreign entries", async () => {
    const db = env.authenticatedContext(OUTSIDER).firestore();
    await assertFails(getDoc(doc(db, "churches/c1/entries/e1")));
  });

  it("refuses an unauthenticated read", async () => {
    const db = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, "churches/c1/entries/e1")));
  });
});

describe("staff cannot approve their own money", () => {
  it("refuses a staff write of status approved", async () => {
    const db = env.authenticatedContext(STAFF).firestore();
    await assertFails(updateDoc(doc(db, "churches/c1/entries/e1"), {status: "approved"}));
  });

  it("refuses a staff entry created as approved", async () => {
    const db = env.authenticatedContext(STAFF).firestore();
    await assertFails(
      setDoc(doc(db, "churches/c1/entries/e2"), {
        churchId: "c1",
        createdBy: STAFF,
        status: "approved",
        reviewedBy: null,
        reviewedAt: null,
        amountCedis: 50,
      })
    );
  });

  it("allows a staff entry created as pending", async () => {
    const db = env.authenticatedContext(STAFF).firestore();
    await assertSucceeds(
      setDoc(doc(db, "churches/c1/entries/e3"), {
        churchId: "c1",
        createdBy: STAFF,
        status: "pending",
        reviewedBy: null,
        reviewedAt: null,
        amountCedis: 50,
      })
    );
  });

  it("lets a pastor approve", async () => {
    const db = env.authenticatedContext(PASTOR).firestore();
    await assertSucceeds(updateDoc(doc(db, "churches/c1/entries/e1"), {status: "approved"}));
  });

  it("refuses staff editing an entry somebody else recorded", async () => {
    const db = env.authenticatedContext(STAFF).firestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "churches/c1/entries/e4"), {
        churchId: "c1",
        createdBy: "someone-else",
        status: "pending",
        amountCedis: 10,
      });
    });
    await assertFails(updateDoc(doc(db, "churches/c1/entries/e4"), {amountCedis: 999, status: "pending"}));
  });
});

describe("the audit log cannot be rewritten", () => {
  it("refuses an update to an activity log", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "churches/c1/activity_logs/l1"), {action: "entry.create"});
    });
    const db = env.authenticatedContext(ADMIN).firestore();
    await assertFails(updateDoc(doc(db, "churches/c1/activity_logs/l1"), {action: "nothing.happened"}));
    await assertFails(deleteDoc(doc(db, "churches/c1/activity_logs/l1")));
  });
});

it("membership itself is not client-writable", async () => {
  const db = env.authenticatedContext(STAFF).firestore();
  await assertFails(setDoc(doc(db, "user_church_index", STAFF), {churchId: "c1", role: "pastor"}));
  assert.ok(true);
});
