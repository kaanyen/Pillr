/**
 * Recomputes partner, period and goal totals from the entries themselves and
 * reports where the stored figures have drifted.
 *
 * The totals users see are maintained by triggers. Triggers can be retried,
 * killed mid-flight, or — as happened here — throw on every invocation for a
 * week without anyone noticing, because a wrong total looks exactly like a
 * right one. This is the thing that notices.
 *
 * Emulator only unless you pass --production, which additionally requires
 * --church and prints what it would do rather than doing it.
 *
 *   export FIRESTORE_EMULATOR_HOST=127.0.0.1:8080
 *   node functions/scripts/reconcile-aggregates.cjs            # report
 *   node functions/scripts/reconcile-aggregates.cjs --fix      # repair
 *
 * --fix also stamps `aggregateApplied` on approved entries that predate the
 * stamp, so that un-approving or deleting them later gives the money back.
 */
/* eslint-disable @typescript-eslint/no-require-imports */
const admin = require("firebase-admin");

const ARGS = process.argv.slice(2);
const FIX = ARGS.includes("--fix");
const PRODUCTION = ARGS.includes("--production");
const CHURCH_ARG = (() => {
  const i = ARGS.indexOf("--church");
  return i >= 0 ? ARGS[i + 1] : null;
})();

if (!process.env.FIRESTORE_EMULATOR_HOST && !PRODUCTION) {
  console.error(
    "Refusing to run outside the emulator.\n" +
      "  export FIRESTORE_EMULATOR_HOST=127.0.0.1:8080\n" +
      "To audit the live project read-only: --production --church <id>"
  );
  process.exit(1);
}
if (PRODUCTION && (!CHURCH_ARG || FIX)) {
  console.error("--production is read-only and needs --church <id>.");
  process.exit(1);
}

/** Money is a double in the documents; compare in pesewas. */
const pesewas = (v) => Math.round(Number(v ?? 0) * 100);
const cedis = (p) => Math.round(p) / 100;
const money = (p) => `GHS ${(p / 100).toLocaleString("en-GH", {minimumFractionDigits: 2})}`;

async function reconcileChurch(db, churchId) {
  const church = db.collection("churches").doc(churchId);

  // Only the fields the sums need: an 800-entry church should not pull 800
  // partner snapshots across the wire to add up four numbers.
  const entries = await church
    .collection("entries")
    .select("status", "amountCedis", "partnerId", "partnershipPeriodId", "partnershipArmId", "aggregateApplied")
    .get();

  const byPartner = new Map();
  const byPeriod = new Map();
  const byGoalKey = new Map();
  const needStamp = [];
  const staleStamp = [];

  for (const doc of entries.docs) {
    const e = doc.data();
    const approved = e.status === "approved";
    const amt = pesewas(e.amountCedis);
    const stamped = pesewas(e.aggregateApplied?.pesewas ?? 0) / 100;

    if (approved) {
      const bump = (map, key) => {
        if (!key) return;
        const cur = map.get(key) ?? {pesewas: 0, count: 0};
        map.set(key, {pesewas: cur.pesewas + amt, count: cur.count + 1});
      };
      bump(byPartner, e.partnerId);
      bump(byPeriod, e.partnershipPeriodId);
      if (e.partnershipPeriodId && e.partnershipArmId) {
        const k = `${e.partnershipPeriodId}|${e.partnershipArmId}`;
        byGoalKey.set(k, (byGoalKey.get(k) ?? 0) + amt);
      }
      if (Number(e.aggregateApplied?.pesewas ?? 0) !== amt) {
        needStamp.push({ref: doc.ref, e, amt});
      }
    } else if (e.aggregateApplied) {
      staleStamp.push({ref: doc.ref});
    }
    void stamped;
  }

  const drift = [];
  const fixes = [];

  const check = async (collection, expectedMap, amountField, countField) => {
    const snap = await church.collection(collection).select(amountField, countField ?? amountField).get();
    for (const doc of snap.docs) {
      const want = expectedMap.get(doc.id) ?? {pesewas: 0, count: 0};
      const have = {
        pesewas: pesewas(doc.data()[amountField]),
        count: countField ? Number(doc.data()[countField] ?? 0) : want.count,
      };
      if (have.pesewas !== want.pesewas || have.count !== want.count) {
        drift.push({
          what: `${collection}/${doc.id}`,
          stored: have,
          actual: want,
        });
        const patch = {[amountField]: cedis(want.pesewas)};
        if (countField) patch[countField] = want.count;
        fixes.push({ref: doc.ref, patch});
      }
    }
  };

  await check("partners", byPartner, "totalApprovedAmount", "entryCount");
  await check("partnership_periods", byPeriod, "totalApprovedAmount", "entryCount");

  const goals = await church.collection("goals").select("partnershipPeriodId", "partnershipArmId", "currentAmountCedis").get();
  for (const doc of goals.docs) {
    const g = doc.data();
    const want = byGoalKey.get(`${g.partnershipPeriodId}|${g.partnershipArmId}`) ?? 0;
    const have = pesewas(g.currentAmountCedis);
    if (have !== want) {
      drift.push({what: `goals/${doc.id}`, stored: {pesewas: have}, actual: {pesewas: want}});
      fixes.push({ref: doc.ref, patch: {currentAmountCedis: cedis(want)}});
    }
  }

  return {entries: entries.size, drift, fixes, needStamp, staleStamp};
}

async function commitAll(db, writes) {
  for (let i = 0; i < writes.length; i += 400) {
    const batch = db.batch();
    for (const w of writes.slice(i, i + 400)) batch.update(w.ref, w.patch);
    await batch.commit();
  }
}

async function main() {
  admin.initializeApp({projectId: process.env.FIREBASE_PROJECT_ID || "thepillr2"});
  const db = admin.firestore();

  const churchIds = CHURCH_ARG
    ? [CHURCH_ARG]
    : (await db.collection("churches").select().get()).docs.map((d) => d.id);

  let totalDrift = 0;
  for (const churchId of churchIds) {
    const r = await reconcileChurch(db, churchId);
    console.log(`\n${churchId} — ${r.entries} entries`);
    if (r.drift.length === 0) {
      console.log("  totals agree with the entries.");
    } else {
      totalDrift += r.drift.length;
      for (const d of r.drift) {
        const delta = d.actual.pesewas - d.stored.pesewas;
        const counts =
          d.actual.count !== undefined && d.stored.count !== undefined && d.actual.count !== d.stored.count ?
            `, count ${d.stored.count} → ${d.actual.count}` :
            "";
        console.log(
          `  ${d.what}: stored ${money(d.stored.pesewas)}, actual ${money(d.actual.pesewas)}` +
            ` (${delta > 0 ? "+" : ""}${money(delta)})${counts}`
        );
      }
    }
    if (r.needStamp.length || r.staleStamp.length) {
      console.log(`  ${r.needStamp.length} approved entries unstamped, ${r.staleStamp.length} stale stamps.`);
    }

    if (FIX) {
      await commitAll(db, r.fixes);
      await commitAll(
        db,
        r.needStamp.map(({ref, e, amt}) => ({
          ref,
          patch: {
            aggregateApplied: {
              partnerId: e.partnerId ?? "",
              periodId: e.partnershipPeriodId ?? "",
              armId: e.partnershipArmId ?? "",
              pesewas: amt,
              at: admin.firestore.Timestamp.now(),
            },
          },
        }))
      );
      await commitAll(db, r.staleStamp.map(({ref}) => ({ref, patch: {aggregateApplied: null}})));
      console.log(
        `  repaired ${r.fixes.length} totals, stamped ${r.needStamp.length}, cleared ${r.staleStamp.length}.`
      );
    }
  }

  if (!FIX && totalDrift > 0) {
    console.log(`\n${totalDrift} figures disagree with the entries. Re-run with --fix to correct them.`);
    process.exitCode = 2;
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
