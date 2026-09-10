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
// Writing to production takes a second, deliberate flag and one church — and
// a --log file, so every figure it changed is on record with its old value.
const CONFIRM_PRODUCTION = ARGS.includes("--confirm-production");
const LOG_ARG = (() => {
  const i = ARGS.indexOf("--log");
  return i >= 0 ? ARGS[i + 1] : null;
})();
if (PRODUCTION && !CHURCH_ARG) {
  console.error("--production needs --church <id>.");
  process.exit(1);
}
if (PRODUCTION && FIX && (!CONFIRM_PRODUCTION || !LOG_ARG)) {
  console.error(
    "--production is read-only. To repair a live church, pass --fix --confirm-production --log <file>\n" +
      "and only with the owner's go-ahead for that run."
  );
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

  // Totals are kept twice — an exact pesewa field, which the app reads first,
  // and the older cedi double. Both must agree with the entries: repairing only
  // the cedi field left the app showing the stale pesewa figure. A document
  // with the right cedi figure but no pesewa field yet is a backfill, not a
  // wrong total, and is reported as such.
  const compare = (doc, want, {cedisField, pesewasField, countField}) => {
    const d = doc.data();
    const exact = typeof d[pesewasField] === "number" ? Math.round(d[pesewasField]) : null;
    const fromCedis = pesewas(d[cedisField]);
    const shown = exact ?? fromCedis;
    const count = countField ? Number(d[countField] ?? 0) : want.count;
    const agrees = exact === want.pesewas && fromCedis === want.pesewas && count === want.count;
    if (agrees) return;
    drift.push({
      what: `${doc.ref.parent.id}/${doc.id}`,
      kind: shown === want.pesewas && count === want.count ? "backfill" : "wrong",
      stored: {pesewas: shown, count: countField ? count : undefined, cedisField: fromCedis},
      actual: {pesewas: want.pesewas, count: countField ? want.count : undefined},
    });
    const patch = {[cedisField]: cedis(want.pesewas), [pesewasField]: want.pesewas};
    if (countField) patch[countField] = want.count;
    // What each patched field held before, so the log can undo any one of them.
    const before = Object.fromEntries(Object.keys(patch).map((k) => [k, d[k] ?? null]));
    fixes.push({ref: doc.ref, patch, before, kind: shown === want.pesewas && count === want.count ? "backfill" : "wrong"});
  };

  const check = async (collection, expectedMap) => {
    const fields = {cedisField: "totalApprovedAmount", pesewasField: "totalApprovedPesewas", countField: "entryCount"};
    const snap = await church.collection(collection).select(...Object.values(fields)).get();
    for (const doc of snap.docs) compare(doc, expectedMap.get(doc.id) ?? {pesewas: 0, count: 0}, fields);
  };

  await check("partners", byPartner);
  await check("partnership_periods", byPeriod);

  const goalFields = {cedisField: "currentAmountCedis", pesewasField: "currentAmountPesewas"};
  const goals = await church.collection("goals")
    .select("partnershipPeriodId", "partnershipArmId", ...Object.values(goalFields)).get();
  for (const doc of goals.docs) {
    const g = doc.data();
    const want = byGoalKey.get(`${g.partnershipPeriodId}|${g.partnershipArmId}`) ?? 0;
    compare(doc, {pesewas: want, count: undefined}, goalFields);
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
      // Wrong figures one by one — these are what a user sees change. Backfills
      // (right figure, pesewa field not yet written) only as a count, or a
      // church of 550 partners buries the handful that matter.
      const wrong = r.drift.filter((d) => d.kind !== "backfill");
      const backfill = r.drift.filter((d) => d.kind === "backfill");
      for (const d of wrong) {
        const delta = d.actual.pesewas - d.stored.pesewas;
        const counts =
          d.actual.count !== undefined && d.stored.count !== undefined && d.actual.count !== d.stored.count ?
            `, count ${d.stored.count} → ${d.actual.count}` :
            "";
        const cedisNote = d.stored.cedisField !== undefined && d.stored.cedisField !== d.stored.pesewas ?
          ` [cedi field ${money(d.stored.cedisField)}]` :
          "";
        console.log(
          `  ${d.what}: shown ${money(d.stored.pesewas)}, actual ${money(d.actual.pesewas)}` +
            ` (${delta > 0 ? "+" : ""}${money(delta)})${counts}${cedisNote}`
        );
      }
      if (backfill.length) {
        console.log(`  ${backfill.length} documents show the right figure but lack the pesewa field (backfill only).`);
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
      if (LOG_ARG) {
        const log = {
          ranAt: new Date().toISOString(),
          project: process.env.FIREBASE_PROJECT_ID || "thepillr2",
          emulator: Boolean(process.env.FIRESTORE_EMULATOR_HOST),
          churchId,
          entriesRead: r.entries,
          totals: r.fixes.map((f) => ({path: f.ref.path, kind: f.kind, before: f.before, after: f.patch})),
          stamped: r.needStamp.map(({ref, amt}) => ({path: ref.path, pesewas: amt})),
          stampsCleared: r.staleStamp.map(({ref}) => ref.path),
        };
        require("fs").writeFileSync(LOG_ARG, JSON.stringify(log, null, 1));
        console.log(`  change log written to ${LOG_ARG}`);
      }
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
