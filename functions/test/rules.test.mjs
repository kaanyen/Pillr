/**
 * Firestore rules are the whole authorization model and, until this file, not
 * one line of them was tested. These run against the rules emulator on 8080.
 *
 *   firebase emulators:start --only firestore
 *   node --test functions/test/rules.test.mjs
 */
import {readFileSync} from "node:fs";
import {after, before, beforeEach, describe, it} from "node:test";
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

describe("admin fellowship tools", () => {
  before(async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "churches/c1/partners/p1"), {
        churchId: "c1",
        fullName: "Ama Mensah",
        fellowship: "Bethel",
        fellowshipLower: "bethel",
        phone: "0240000000",
        email: "ama@example.com",
      });
    });
  });

  it("lets an admin read a partner", async () => {
    const db = env.authenticatedContext(ADMIN).firestore();
    await assertSucceeds(getDoc(doc(db, "churches/c1/partners/p1")));
  });

  // Fellowship moves run through the fellowshipChange callable, which records
  // them for undo. A direct write would skip that record.
  it("refuses an admin moving a partner directly", async () => {
    const db = env.authenticatedContext(ADMIN).firestore();
    await assertFails(updateDoc(doc(db, "churches/c1/partners/p1"), {
      fellowship: "Zion",
      fellowshipLower: "zion",
      updatedAt: new Date(),
    }));
  });

  it("refuses an admin changing a partner's phone", async () => {
    const db = env.authenticatedContext(ADMIN).firestore();
    await assertFails(updateDoc(doc(db, "churches/c1/partners/p1"), {
      phone: "0241111111",
    }));
  });

  it("refuses staff moving a partner directly", async () => {
    const db = env.authenticatedContext(STAFF).firestore();
    await assertFails(updateDoc(doc(db, "churches/c1/partners/p1"), {
      fellowship: "Zion",
      fellowshipLower: "zion",
      updatedAt: new Date(),
    }));
  });

  it("refuses an admin changing a partner's phone", async () => {
    const db = env.authenticatedContext(ADMIN).firestore();
    await assertFails(updateDoc(doc(db, "churches/c1/partners/p1"), {
      phone: "0241111111",
    }));
  });
});

describe("monthly letters switch", () => {
  before(async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "churches/c1/partners/p2"), {
        churchId: "c1",
        fullName: "Kofi Owusu",
        fellowship: "Zion",
        fellowshipLower: "zion",
        email: "kofi@example.com",
        isActive: true,
      });
    });
  });

  it("lets staff turn a partner's letters off and on", async () => {
    const db = env.authenticatedContext(STAFF).firestore();
    await assertSucceeds(updateDoc(doc(db, "churches/c1/partners/p2"), {
      noMonthlyLetters: true,
      updatedAt: new Date(),
    }));
    await assertSucceeds(updateDoc(doc(db, "churches/c1/partners/p2"), {
      noMonthlyLetters: false,
      updatedAt: new Date(),
    }));
  });

  it("lets a pastor switch them", async () => {
    const db = env.authenticatedContext(PASTOR).firestore();
    await assertSucceeds(updateDoc(doc(db, "churches/c1/partners/p2"), {
      noMonthlyLetters: true,
    }));
  });

  it("refuses staff closing a partner with the same write", async () => {
    const db = env.authenticatedContext(STAFF).firestore();
    await assertFails(updateDoc(doc(db, "churches/c1/partners/p2"), {
      noMonthlyLetters: true,
      isActive: false,
    }));
  });

  it("refuses an admin switching them", async () => {
    const db = env.authenticatedContext(ADMIN).firestore();
    await assertFails(updateDoc(doc(db, "churches/c1/partners/p2"), {
      noMonthlyLetters: true,
    }));
  });
});

describe("staff ledger tools", () => {
  before(async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, "churches/c1/partners/p_keep"), {
        churchId: "c1",
        fullName: "Ama Mensah",
        fullNameLower: "ama mensah",
        fellowship: "Bethel",
        fellowshipLower: "bethel",
        phone: "0240000000",
        isActive: true,
        totalApprovedAmount: 100,
        entryCount: 1,
      });
      await setDoc(doc(db, "churches/c1/partners/p_absorb"), {
        churchId: "c1",
        fullName: "Ama M.",
        isActive: true,
      });
      await setDoc(doc(db, "churches/c1/entries/e_approved"), {
        churchId: "c1",
        createdBy: PASTOR,
        status: "approved",
        partnerId: "p_absorb",
        amountCedis: 100,
      });
      await setDoc(doc(db, "churches/c1/entries/e_dup"), {
        churchId: "c1",
        createdBy: PASTOR,
        status: "approved",
        partnerId: "p_keep",
        amountCedis: 100,
      });
      await setDoc(doc(db, "churches/c1/partnership_periods/per1"), {
        name: "2026",
        totalApprovedAmount: 50,
        entryCount: 1,
      });
    });
  });

  // Partner merges run through the partnerMerge callable.
  it("refuses staff repointing an entry directly", async () => {
    const db = env.authenticatedContext(STAFF).firestore();
    await assertFails(updateDoc(doc(db, "churches/c1/entries/e_approved"), {
      partnerId: "p_keep",
      partnerSnapshot: {fullName: "Ama Mensah"},
      updatedAt: new Date(),
    }));
  });

  it("refuses staff changing an entry amount on the way", async () => {
    const db = env.authenticatedContext(STAFF).firestore();
    await assertFails(updateDoc(doc(db, "churches/c1/entries/e_approved"), {
      partnerId: "p_keep",
      amountCedis: 999,
      updatedAt: new Date(),
    }));
  });

  it("lets staff void a duplicate entry", async () => {
    const db = env.authenticatedContext(STAFF).firestore();
    await assertSucceeds(updateDoc(doc(db, "churches/c1/entries/e_dup"), {
      status: "voided",
      voidedBy: STAFF,
      voidedAt: new Date(),
      voidReason: "Duplicate",
      updatedAt: new Date(),
      editHistory: [{changeDescription: "Entry voided: Duplicate"}],
    }));
  });

  it("refuses staff approving an entry", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "churches/c1/entries/e_pending"), {
        churchId: "c1",
        createdBy: "someone-else",
        status: "pending",
        amountCedis: 10,
      });
    });
    const db = env.authenticatedContext(STAFF).firestore();
    await assertFails(updateDoc(doc(db, "churches/c1/entries/e_pending"), {
      status: "approved",
    }));
  });

  it("refuses staff closing the absorbed partner directly", async () => {
    const db = env.authenticatedContext(STAFF).firestore();
    await assertFails(updateDoc(doc(db, "churches/c1/partners/p_absorb"), {
      isActive: false,
      mergedInto: "p_keep",
      mergedBy: STAFF,
      mergedAt: new Date(),
      updatedAt: new Date(),
    }));
  });


  it("lets staff tidy a partner name", async () => {
    const db = env.authenticatedContext(STAFF).firestore();
    await assertSucceeds(updateDoc(doc(db, "churches/c1/partners/p_keep"), {
      fullName: "Ama Mensah",
      fullNameLower: "ama mensah",
      updatedAt: new Date(),
    }));
  });

  it("lets staff correct partner totals", async () => {
    const db = env.authenticatedContext(STAFF).firestore();
    await assertSucceeds(updateDoc(doc(db, "churches/c1/partners/p_keep"), {
      totalApprovedAmount: 200,
      totalApprovedPesewas: 20000,
      entryCount: 2,
      updatedAt: new Date(),
    }));
  });

  it("lets staff correct period totals", async () => {
    const db = env.authenticatedContext(STAFF).firestore();
    await assertSucceeds(updateDoc(doc(db, "churches/c1/partnership_periods/per1"), {
      totalApprovedAmount: 200,
      totalApprovedPesewas: 20000,
      entryCount: 2,
      updatedAt: new Date(),
    }));
  });

  it("refuses staff renaming a period", async () => {
    const db = env.authenticatedContext(STAFF).firestore();
    await assertFails(updateDoc(doc(db, "churches/c1/partnership_periods/per1"), {
      name: "Sneaky",
    }));
  });
});

describe("staff exchange rates", () => {
  it("lets staff save exchange rates", async () => {
    const db = env.authenticatedContext(STAFF).firestore();
    await assertSucceeds(updateDoc(doc(db, "churches/c1"), {
      settings: {exchangeRates: {USD: 12.5, EUR: 13, GBP: 16}},
      updatedAt: new Date(),
    }));
  });

  it("lets an admin save exchange rates", async () => {
    const db = env.authenticatedContext(ADMIN).firestore();
    await assertSucceeds(updateDoc(doc(db, "churches/c1"), {
      settings: {exchangeRates: {USD: 13, EUR: 14, GBP: 17}},
      updatedAt: new Date(),
    }));
  });

  it("refuses staff turning on monthly partner email", async () => {
    const db = env.authenticatedContext(STAFF).firestore();
    await assertFails(updateDoc(doc(db, "churches/c1"), {
      settings: {sendMonthlyPartnerEmails: true},
      updatedAt: new Date(),
    }));
  });

  it("refuses staff changing the church name", async () => {
    const db = env.authenticatedContext(STAFF).firestore();
    await assertFails(updateDoc(doc(db, "churches/c1"), {
      name: "Staff Church",
    }));
  });
});

describe("monthly partner email reports are function-written", () => {
  it("lets a pastor read a report", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "churches/c1/monthly_email_reports/2026-07"), {
        sent: 1,
        skippedNoEmail: [],
        failed: [],
      });
    });
    const db = env.authenticatedContext(PASTOR).firestore();
    await assertSucceeds(getDoc(doc(db, "churches/c1/monthly_email_reports/2026-07")));
  });

  it("refuses staff reading a report", async () => {
    const db = env.authenticatedContext(STAFF).firestore();
    await assertFails(getDoc(doc(db, "churches/c1/monthly_email_reports/2026-07")));
  });

  it("refuses a pastor writing a report", async () => {
    const db = env.authenticatedContext(PASTOR).firestore();
    await assertFails(
      setDoc(doc(db, "churches/c1/monthly_email_reports/2026-07"), {sent: 99}),
    );
  });
});

describe("bulk change records", () => {
  before(async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, "churches/c1/operations/op1"), {kind: "fellowship.merge", status: "applied"});
      await setDoc(doc(db, "churches/c1/operations/op1/changes/000000"), {seq: 0, path: "x"});
      await setDoc(doc(db, "churches/c1/partners/p_merge"), {churchId: "c1", fullName: "Kofi Asante", isActive: true});
    });
  });

  it("lets staff read an operation and its changes", async () => {
    const db = env.authenticatedContext(STAFF).firestore();
    await assertSucceeds(getDoc(doc(db, "churches/c1/operations/op1")));
    await assertSucceeds(getDoc(doc(db, "churches/c1/operations/op1/changes/000000")));
  });

  it("refuses anyone editing an operation record", async () => {
    const db = env.authenticatedContext(PASTOR).firestore();
    await assertFails(updateDoc(doc(db, "churches/c1/operations/op1"), {status: "undone"}));
    await assertFails(setDoc(doc(db, "churches/c1/operations/op2"), {kind: "partner.merge"}));
    await assertFails(updateDoc(doc(db, "churches/c1/operations/op1/changes/000000"), {path: "y"}));
  });

  it("refuses another church reading an operation", async () => {
    const db = env.authenticatedContext(OUTSIDER).firestore();
    await assertFails(getDoc(doc(db, "churches/c1/operations/op1")));
  });

  it("refuses touching the operation lock", async () => {
    const db = env.authenticatedContext(PASTOR).firestore();
    await assertFails(setDoc(doc(db, "churches/c1/op_locks/records"), {holder: "me"}));
  });

  it("refuses a pastor writing merge fields directly", async () => {
    const db = env.authenticatedContext(PASTOR).firestore();
    await assertFails(updateDoc(doc(db, "churches/c1/partners/p_merge"), {mergedInto: "p_keep"}));
  });

  it("still lets a pastor edit a partner", async () => {
    const db = env.authenticatedContext(PASTOR).firestore();
    await assertSucceeds(updateDoc(doc(db, "churches/c1/partners/p_merge"), {
      phone: "0241234567",
      fellowship: "Zion",
      fellowshipLower: "zion",
    }));
  });
});

describe("duplicate dismissals", () => {
  before(async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      for (const id of ["a|b", "c|d", "e|f"]) {
        await deleteDoc(doc(ctx.firestore(), `churches/c1/duplicate_dismissals/${id}`));
      }
    });
  });

  it("refuses editing a dismissal once made", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "churches/c1/duplicate_dismissals/g|h"), {
        a: "g", b: "h", dismissedBy: STAFF,
      });
    });
    const db = env.authenticatedContext(STAFF).firestore();
    await assertFails(updateDoc(doc(db, "churches/c1/duplicate_dismissals/g|h"), {a: "x"}));
  });

  it("lets staff mark a pair as not the same person", async () => {
    const db = env.authenticatedContext(STAFF).firestore();
    await assertSucceeds(setDoc(doc(db, "churches/c1/duplicate_dismissals/a|b"), {
      a: "a", b: "b", dismissedBy: STAFF, dismissedAt: new Date(),
    }));
  });

  it("refuses a dismissal written in someone else's name", async () => {
    const db = env.authenticatedContext(STAFF).firestore();
    await assertFails(setDoc(doc(db, "churches/c1/duplicate_dismissals/c|d"), {
      a: "c", b: "d", dismissedBy: PASTOR,
    }));
  });

  it("refuses an admin dismissing a pair", async () => {
    const db = env.authenticatedContext(ADMIN).firestore();
    await assertFails(setDoc(doc(db, "churches/c1/duplicate_dismissals/e|f"), {
      a: "e", b: "f", dismissedBy: ADMIN,
    }));
  });
});

describe("partners are never deleted", () => {
  it("refuses a pastor deleting a partner", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "churches/c1/partners/p_del"), {churchId: "c1", fullName: "Yaw Darko"});
    });
    const db = env.authenticatedContext(PASTOR).firestore();
    await assertFails(deleteDoc(doc(db, "churches/c1/partners/p_del")));
  });

  it("still lets a pastor close a partner", async () => {
    const db = env.authenticatedContext(PASTOR).firestore();
    await assertSucceeds(updateDoc(doc(db, "churches/c1/partners/p_del"), {isActive: false}));
  });
});

describe("staff editing a partner", () => {
  const path = "churches/c1/partners/p_edit";
  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), path), {
        churchId: "c1", memberId: "ACC100001", fullName: "Kojo Antwi",
        fullNameLower: "kojo antwi", fellowship: "Bethel", fellowshipLower: "bethel",
        isActive: true, formerMemberIds: ["ACC000009"],
      });
    });
  });
  const staff = () => env.authenticatedContext(STAFF).firestore();
  const pastor = () => env.authenticatedContext(PASTOR).firestore();

  it("lets staff change the name, contacts, address and notes", async () => {
    await assertSucceeds(updateDoc(doc(staff(), path), {
      fullName: "Kojo Antwi Mensah", fullNameLower: "kojo antwi mensah",
      phone: "0241112222", phones: ["0241112222", "0203334444"],
      email: "kojo@example.com", emails: ["kojo@example.com"],
      address: "12 Airport Rd", notes: "Prefers MoMo", updatedAt: new Date(),
    }));
  });

  it("lets staff change the member ID when the old one is kept", async () => {
    await assertSucceeds(updateDoc(doc(staff(), path), {
      memberId: "ACC200002", formerMemberIds: ["ACC000009", "ACC100001"],
    }));
  });

  it("refuses a member ID change that drops the old ID", async () => {
    await assertFails(updateDoc(doc(staff(), path), {memberId: "ACC200002"}));
    await assertFails(updateDoc(doc(pastor(), path), {memberId: "ACC200002"}));
  });

  it("refuses rewriting the old IDs", async () => {
    await assertFails(updateDoc(doc(staff(), path), {formerMemberIds: []}));
    await assertFails(updateDoc(doc(pastor(), path), {
      memberId: "ACC200002", formerMemberIds: ["ACC100001"],
    }));
  });

  it("lets a pastor change the member ID when the old one is kept", async () => {
    await assertSucceeds(updateDoc(doc(pastor(), path), {
      memberId: "ACC200002", formerMemberIds: ["ACC000009", "ACC100001"],
    }));
  });

  it("refuses staff moving the fellowship, but allows fixing its casing", async () => {
    await assertFails(updateDoc(doc(staff(), path), {fellowship: "Zion", fellowshipLower: "zion"}));
    await assertSucceeds(updateDoc(doc(staff(), path), {fellowship: "BETHEL"}));
  });

  it("refuses staff closing a partner", async () => {
    await assertFails(updateDoc(doc(staff(), path), {isActive: false}));
  });

  it("refuses staff writing merge fields", async () => {
    await assertFails(updateDoc(doc(staff(), path), {mergedInto: "p_keep"}));
  });
});

describe("main arms and sub-arms", () => {
  const arms = "churches/c1/partnership_arms";
  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, `${arms}/ministry`), {churchId: "c1", name: "Ministry", sortOrder: 0, isActive: true});
      await setDoc(doc(db, `${arms}/rhapsody`), {churchId: "c1", name: "Rhapsody", sortOrder: 1, isActive: true});
      await setDoc(doc(db, `${arms}/healing`), {churchId: "c1", name: "Healing Streams", sortOrder: 2, isActive: true, parentArmId: "ministry"});
    });
  });
  const pastor = () => env.authenticatedContext(PASTOR).firestore();
  const staff = () => env.authenticatedContext(STAFF).firestore();

  it("lets a pastor put an arm under a main arm", async () => {
    await assertSucceeds(updateDoc(doc(pastor(), `${arms}/rhapsody`), {parentArmId: "ministry", sortOrder: 2}));
  });

  it("lets a pastor make a sub-arm a main arm again", async () => {
    await assertSucceeds(updateDoc(doc(pastor(), `${arms}/healing`), {parentArmId: null}));
  });

  it("refuses an arm counting toward itself", async () => {
    await assertFails(updateDoc(doc(pastor(), `${arms}/rhapsody`), {parentArmId: "rhapsody"}));
  });

  it("refuses a sub-arm under a sub-arm", async () => {
    await assertFails(updateDoc(doc(pastor(), `${arms}/rhapsody`), {parentArmId: "healing"}));
  });

  it("refuses a main arm that does not exist", async () => {
    await assertFails(updateDoc(doc(pastor(), `${arms}/rhapsody`), {parentArmId: "nope"}));
  });

  it("refuses staff rearranging arms", async () => {
    await assertFails(updateDoc(doc(staff(), `${arms}/rhapsody`), {parentArmId: "ministry"}));
  });

  it("still lets a pastor rename an arm that has no main arm", async () => {
    await assertSucceeds(updateDoc(doc(pastor(), `${arms}/ministry`), {name: "Ministries"}));
  });
});
