/**
 * One-time move for "who sees what".
 *
 * For every church:
 *  1. Partner and period totals move off the partner and period records
 *     (which staff and admins read) into partner_totals / period_totals
 *     (pastors only), recounted from the approved entries. Run it straight
 *     after the new functions go out; anything approved while it runs is
 *     caught by Health's totals check and a pastor's repair in Tools. Safe
 *     to run twice: a record already right is left alone.
 *  2. Amounts are stripped from old activity log entries, at any depth.
 *  3. Past monthly letter reports get a counts-only summary for admins.
 *
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node functions/scripts/migrate-who-sees-what.cjs [--dry-run]
 *
 * Refuses to run outside the emulator. Running it on the live project needs
 * the owner's explicit yes in that conversation, and a deliberate change here.
 */
// The live project only with both a --live flag and PILLR_LIVE_PROJECT set
// to its name: the owner said yes to this run on 8 November 2026.
const live = process.argv.includes("--live") && process.env.PILLR_LIVE_PROJECT === "thepillr2";
if (!process.env.FIRESTORE_EMULATOR_HOST && !live) {
  console.error("Refusing to run outside the emulator.");
  process.exit(1);
}
if (live && process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("--live with an emulator host set: pick one.");
  process.exit(1);
}

const admin = require("firebase-admin");
const {FieldValue} = require("firebase-admin/firestore");

admin.initializeApp({projectId: "thepillr2"});
console.log(live ? "LIVE project thepillr2" : "emulator " + process.env.FIRESTORE_EMULATOR_HOST);
const db = admin.firestore();
const dryRun = process.argv.includes("--dry-run");

const FIGURES = ["totalApprovedAmount", "totalApprovedPesewas", "entryCount"];
const isFigure = (k) => /amount|total|cedis|pesewa/i.test(k);

function withoutFigures(v) {
  if (Array.isArray(v)) return v.map(withoutFigures);
  if (v && typeof v === "object" && v.constructor === Object) {
    const out = {};
    for (const [k, x] of Object.entries(v)) if (!isFigure(k)) out[k] = withoutFigures(x);
    return out;
  }
  return v;
}

function hasFigures(v) {
  if (Array.isArray(v)) return v.some(hasFigures);
  if (v && typeof v === "object" && v.constructor === Object) {
    return Object.entries(v).some(([k, x]) => isFigure(k) || hasFigures(x));
  }
  return false;
}

/**
 * Sets one record's totals record to what its approved entries add up to,
 * and takes the old figures off the record itself. The old figures are not
 * trusted: some records carry an exact pesewa field of 0 beside a real cedi
 * figure, from before the exact field existed. Recounting from the entries
 * is the totals repair's own rule. True if anything changed.
 */
async function moveTotals(sourceRef, totalsRef, expected) {
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(sourceRef);
    if (!snap.exists) return false;
    const hadFigures = FIGURES.some((f) => f in snap.data());
    const cur = await tx.get(totalsRef);
    const want = expected ?? {pesewas: 0, count: 0};
    const same = cur.exists && Number(cur.get("totalApprovedPesewas")) === want.pesewas &&
      Number(cur.get("entryCount")) === want.count;
    if (!hadFigures && same) return false;
    if (!dryRun) {
      tx.set(totalsRef, {
        totalApprovedPesewas: want.pesewas,
        totalApprovedAmount: want.pesewas / 100,
        entryCount: want.count,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      if (hadFigures) tx.update(sourceRef, Object.fromEntries(FIGURES.map((f) => [f, FieldValue.delete()])));
    }
    return true;
  });
}

/** Approved giving per partner and per period, in whole pesewas. */
async function expectedTotals(church) {
  const byPartner = new Map(); const byPeriod = new Map();
  const add = (m, id, pesewas) => {
    if (!id) return;
    const cur = m.get(id) ?? {pesewas: 0, count: 0};
    m.set(id, {pesewas: cur.pesewas + pesewas, count: cur.count + 1});
  };
  const snap = await church.collection("entries").where("status", "==", "approved").get();
  for (const e of snap.docs) {
    const pesewas = Math.round(Number(e.get("amountCedis") ?? 0) * 100);
    add(byPartner, e.get("partnerId"), pesewas);
    add(byPeriod, e.get("partnershipPeriodId"), pesewas);
  }
  return {byPartner, byPeriod};
}

async function main() {
  const churches = await db.collection("churches").get();
  for (const c of churches.docs) {
    const church = c.ref;
    let partners = 0; let periods = 0; let logs = 0; let summaries = 0;

    const {byPartner, byPeriod} = await expectedTotals(church);
    for (const p of (await church.collection("partners").get()).docs) {
      if (await moveTotals(p.ref, church.collection("partner_totals").doc(p.id), byPartner.get(p.id))) partners++;
    }
    for (const p of (await church.collection("partnership_periods").get()).docs) {
      if (await moveTotals(p.ref, church.collection("period_totals").doc(p.id), byPeriod.get(p.id))) periods++;
    }

    let batch = db.batch(); let n = 0;
    for (const l of (await church.collection("activity_logs").get()).docs) {
      const snap = l.get("entitySnapshot");
      if (!hasFigures(snap)) continue;
      logs++;
      if (!dryRun) {
        batch.update(l.ref, {entitySnapshot: withoutFigures(snap)});
        if (++n === 400) { await batch.commit(); batch = db.batch(); n = 0; }
      }
    }
    if (n > 0) await batch.commit();

    for (const r of (await church.collection("monthly_email_reports").get()).docs) {
      const d = r.data();
      const ref = church.collection("monthly_email_summaries").doc(r.id);
      if ((await ref.get()).exists) continue;
      summaries++;
      if (!dryRun) {
        await ref.set({
          yearMonth: d.yearMonth ?? r.id,
          monthLabel: d.monthLabel ?? r.id,
          sent: Number(d.sent ?? 0),
          failed: Array.isArray(d.failed) ? d.failed.length : Number(d.failedCount ?? 0),
          noEmail: Array.isArray(d.skippedNoEmail) ? d.skippedNoEmail.length : Number(d.skippedNoEmailCount ?? 0),
          turnedOff: Array.isArray(d.skippedOptedOut) ? d.skippedOptedOut.length : Number(d.skippedOptedOutCount ?? 0),
          dryRun: d.dryRun === true,
          skipReason: d.skipReason ?? null,
          ranAt: d.ranAt ?? FieldValue.serverTimestamp(),
        });
      }
    }
    console.log(`${c.id}: ${partners} partners and ${periods} periods moved, ` +
      `${logs} activity entries cleaned, ${summaries} letter summaries${dryRun ? " (dry run)" : ""}`);
  }
}

main().then(() => process.exit(0), (e) => { console.error(e); process.exit(1); });
