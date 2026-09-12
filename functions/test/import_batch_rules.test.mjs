// What the Imports screen needs to be able to write to a batch.
//
// A batch is provenance: what a file did, who ran it, when. The fields that
// record that must stay unwritable. But naming an import, noting who prepared
// the sheet, moving it to another period and clearing it are all things the
// Imports screen offers, and each one amends the batch document.
import {readFileSync} from "node:fs";
import {after, before, beforeEach, test} from "node:test";
import {assertFails, assertSucceeds, initializeTestEnvironment} from "@firebase/rules-unit-testing";
import {doc, setDoc, updateDoc, deleteDoc} from "firebase/firestore";

const HOST = (process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080").split(":");
const PASTOR = "pastor-uid";
const STAFF = "staff-uid";
const ADMIN = "admin-uid";
const BATCH = "churches/c1/import_batches/b1";
let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "pillr-batch-rules-test",
    firestore: {host: HOST[0], port: Number(HOST[1]),
      rules: readFileSync(new URL("../../firestore.rules", import.meta.url), "utf8")},
  });
});
after(async () => env?.cleanup());

beforeEach(async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "churches/c1"), {name: "First", isActive: true});
    await setDoc(doc(db, "user_church_index", PASTOR), {churchId: "c1", role: "pastor"});
    await setDoc(doc(db, "user_church_index", STAFF), {churchId: "c1", role: "staff"});
    await setDoc(doc(db, "user_church_index", ADMIN), {churchId: "c1", role: "admin"});
    await setDoc(doc(db, BATCH), {
      id: "b1", churchId: "c1", fileName: "march.xlsx", periodName: "2026",
      entryCount: 67, partnersCreated: 4, totalCedis: 12450,
      createdBy: STAFF, createdByName: "Ama Serwaa", preparedBy: null,
      undoneAt: null, removedCount: 0, keptCount: 0,
      label: null, note: null, voidedAt: null, voidedCount: 0,
    });
  });
});

const as = (uid) => doc(env.authenticatedContext(uid).firestore(), BATCH);

test("a pastor can name an import and say who prepared it", async () => {
  await assertSucceeds(updateDoc(as(PASTOR), {
    label: "March Sunday offerings",
    note: "Collected at the second service",
    preparedBy: "Mercy Owusu",
    updatedAt: new Date(),
  }));
});

test("a pastor can record that an import was cleared", async () => {
  await assertSucceeds(updateDoc(as(PASTOR), {
    voidedAt: new Date(), voidedBy: PASTOR, voidedCount: 67,
  }));
});

test("a pastor can record that an import was moved", async () => {
  await assertSucceeds(updateDoc(as(PASTOR), {
    periodName: "Ministry Year 2027", previousPeriodName: "2026",
    reassignedAt: new Date(),
    reassignedBy: PASTOR, reassignedCount: 67, updatedAt: new Date(),
  }));
});

test("staff can close an in-progress import", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), BATCH), {
      id: "b1", churchId: "c1", fileName: "march.xlsx", periodName: "2026",
      entryCount: 0, partnersCreated: 0, totalCedis: 0, skippedCount: 0,
      inProgress: true, createdBy: STAFF, createdByName: "Ama Serwaa",
    });
  });
  await assertSucceeds(updateDoc(as(STAFF), {
    inProgress: false, entryCount: 67, partnersCreated: 4,
    totalCedis: 12450, skippedCount: 3,
  }));
});

test("staff cannot close a finished import", async () => {
  await assertFails(updateDoc(as(STAFF), {
    inProgress: false, entryCount: 1, partnersCreated: 0,
    totalCedis: 1, skippedCount: 0,
  }));
});

test("a pastor can record that an import was corrected", async () => {
  await assertSucceeds(updateDoc(as(PASTOR), {
    lastEditedAt: new Date(), lastEditedBy: PASTOR, lastEditedCount: 4,
    updatedAt: new Date(),
  }));
});

test("a pastor can keep the previous name so a rename can be undone", async () => {
  await assertSucceeds(updateDoc(as(PASTOR), {
    label: "March Sunday offerings", previousLabel: "march.xlsx",
    previousNote: null, updatedAt: new Date(),
  }));
});

test("a pastor can restore a cleared import", async () => {
  await assertSucceeds(updateDoc(as(PASTOR), {
    voidedAt: null, voidedBy: null, voidedCount: 0,
    restoredAt: new Date(), restoredBy: PASTOR, restoredCount: 67,
    updatedAt: new Date(),
  }));
});

test("an admin can clear an import too", async () => {
  await assertSucceeds(updateDoc(as(ADMIN), {
    voidedAt: new Date(), voidedBy: ADMIN, voidedCount: 67,
  }));
});

test("staff can still record an undo", async () => {
  await assertSucceeds(updateDoc(as(STAFF), {
    undoneAt: new Date(), undoneBy: STAFF, removedCount: 12, keptCount: 55,
  }));
});

test("staff cannot rename an import", async () => {
  await assertFails(updateDoc(as(STAFF), {label: "mine now"}));
});

test("what the file did is not rewritable", async () => {
  await assertFails(updateDoc(as(PASTOR), {totalCedis: 1}));
  await assertFails(updateDoc(as(PASTOR), {entryCount: 0}));
  await assertFails(updateDoc(as(PASTOR), {createdByName: "Somebody Else"}));
  await assertFails(updateDoc(as(PASTOR), {fileName: "other.xlsx"}));
  await assertFails(updateDoc(as(ADMIN), {createdBy: ADMIN}));
});

test("a rename that smuggles in a total is refused whole", async () => {
  await assertFails(updateDoc(as(PASTOR), {label: "fine", totalCedis: 999999}));
});

test("an import can never be deleted", async () => {
  await assertFails(deleteDoc(as(PASTOR)));
  await assertFails(deleteDoc(as(ADMIN)));
});
