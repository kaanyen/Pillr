/**
 * A partner's own page: all their approved giving in the current period,
 * reached by the button in their monthly letter.
 *
 * The link carries a long random key, made once per partner and kept in
 * `partner_links/{key}` and `partner_link_index/{churchId}_{partnerId}`,
 * which only the server reads. It is never on the partner's record, so
 * staff, who read some partner records, cannot open a partner's page. Anyone holding the link
 * sees that one partner's giving, the same as reading their letter. A pastor
 * can switch the pages off in Settings · Letters, and every link stops
 * working at once.
 */
import * as admin from "firebase-admin";
import {randomBytes} from "node:crypto";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {onRequest} from "firebase-functions/v2/https";
import {escapeHtml, formatMoney} from "./monthly_partner_email_lib";

const REGION = "us-central1";
const db = () => admin.firestore();
const SITE = process.env.PILLR_SITE_URL?.trim() || "https://thepillr.com";

/** The partner's link, made the first time it is needed. */
export async function partnerPageUrl(churchId: string, partnerId: string): Promise<string> {
  const index = db().doc(`partner_link_index/${churchId}_${partnerId}`);
  const existing = String((await index.get()).get("key") ?? "");
  if (/^[A-Za-z0-9_-]{32,}$/.test(existing)) return `${SITE}/p/${existing}`;
  const key = randomBytes(24).toString("base64url");
  const batch = db().batch();
  batch.create(db().doc(`partner_links/${key}`), {churchId, partnerId, createdAt: FieldValue.serverTimestamp()});
  batch.set(index, {key, createdAt: FieldValue.serverTimestamp()});
  await batch.commit();
  return `${SITE}/p/${key}`;
}

export type PageRow = {date: string; arm: string; amount: number};

/** The page itself: plain HTML, quick on any phone, no app to load. */
export function buildPartnerPageHtml(opts: {
  firstName: string;
  churchName: string;
  logoUrl?: string | null;
  periodName: string;
  currencySymbol: string;
  rows: PageRow[];
  byArm: {name: string; amount: number}[];
  total: number;
  updated: string;
}): string {
  const esc = escapeHtml;
  const money = (n: number) => esc(formatMoney(n, opts.currencySymbol || "₵"));
  const logo = (opts.logoUrl ?? "").trim();
  const head = logo && /^https:\/\//.test(logo) ?
    `<img src="${esc(logo)}" alt="${esc(opts.churchName)}" class="logo">` :
    `<div class="church">${esc(opts.churchName)}</div>`;
  return `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<meta name="referrer" content="no-referrer">
<title>Your giving · ${esc(opts.churchName)}</title>
<link rel="preconnect" href="https://fonts.googleapis.com"><link href="https://fonts.googleapis.com/css2?family=Manrope:wght@500;700;800&display=swap" rel="stylesheet">
<style>
:root{--ink:#13426f;--text:#333;--muted:#616c8a;--line:#edf1f5;--tint:#eef6fe;--page:#fcfbf8;--card:#fff}
*{box-sizing:border-box}body{margin:0;background:var(--page);color:var(--text);font:16px/1.55 Manrope,"Segoe UI",Roboto,Helvetica,Arial,sans-serif}
main{max-width:560px;margin:0 auto;padding:28px 16px 40px}
.logo{display:block;height:44px;width:auto;max-width:180px}.church{font-weight:800;color:var(--ink)}
h1{margin:22px 0 4px;font-size:28px;line-height:1.2;color:var(--ink)}.sub{margin:0 0 20px;color:var(--muted)}
.total{background:var(--tint);border-radius:20px;padding:18px 20px;margin-bottom:16px}
.total b{display:block;font-size:30px;color:var(--ink);font-variant-numeric:tabular-nums}
.card{background:var(--card);border:1.5px solid var(--line);border-radius:20px;padding:6px 20px;margin-bottom:16px}
.row{display:flex;justify-content:space-between;gap:12px;padding:12px 0;border-bottom:1px solid var(--line)}.row:last-child{border-bottom:0}
.amt{font-weight:700;color:var(--ink);font-variant-numeric:tabular-nums;white-space:nowrap}
.when{color:var(--muted);font-size:14px}h2{font-size:16px;color:var(--ink);margin:22px 0 8px}
.foot{font-size:13px;color:var(--muted);margin-top:24px}
</style></head><body><main>
${head}
<h1>Thank you, ${esc(opts.firstName)}.</h1>
<p class="sub">Your giving to ${esc(opts.churchName)} in ${esc(opts.periodName)}.</p>
<div class="total">So far<b>${money(opts.total)}</b></div>
${opts.byArm.length > 1 ? `<div class="card">${opts.byArm.map((a) => `<div class="row"><span>${esc(a.name)}</span><span class="amt">${money(a.amount)}</span></div>`).join("")}</div>` : ""}
<h2>Each time you gave</h2>
<div class="card">${opts.rows.length ? opts.rows.map((r) => `<div class="row"><span>${esc(r.arm)}<br><span class="when">${esc(r.date)}</span></span><span class="amt">${money(r.amount)}</span></div>`).join("") : `<div class="row"><span>Nothing recorded yet this year.</span><span></span></div>`}</div>
<p class="foot">Only giving the church has checked is listed; anything newer shows soon. Updated ${esc(opts.updated)}.<br>This page is for you alone. Please do not share the link. Something not right? Reply to your monthly letter.</p>
</main></body></html>`;
}

const gone = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="robots" content="noindex"><title>Link not working</title>
<style>body{margin:0;background:#fcfbf8;color:#333;font:16px/1.55 "Segoe UI",Roboto,Helvetica,Arial,sans-serif}main{max-width:520px;margin:0 auto;padding:48px 16px}h1{color:#13426f;font-size:24px}</style></head>
<body><main><h1>This link is not working</h1><p>It may be old, or the church may have switched these pages off. Your next monthly letter will have a fresh link. If you need your giving sooner, reply to your last letter.</p></main></body></html>`;

export const partnerPage = onRequest({region: REGION, memory: "256MiB", maxInstances: 10}, async (req, res) => {
  res.set("Cache-Control", "private, no-store");
  res.set("Referrer-Policy", "no-referrer");
  res.set("X-Robots-Tag", "noindex, nofollow");
  res.set("X-Content-Type-Options", "nosniff");
  res.set("Content-Type", "text/html; charset=utf-8");
  if (req.method !== "GET" && req.method !== "HEAD") {
    res.status(405).send(gone);
    return;
  }
  const key = String(req.path.split("/").filter(Boolean).pop() ?? "");
  if (!/^[A-Za-z0-9_-]{32,64}$/.test(key)) {
    res.status(404).send(gone);
    return;
  }
  try {
    const link = (await db().doc(`partner_links/${key}`).get()).data();
    if (!link || link.revoked === true) {
      res.status(404).send(gone);
      return;
    }
    const churchId = String(link.churchId);
    const church = (await db().doc(`churches/${churchId}`).get()).data() ?? {};
    const settings = (church.settings ?? {}) as Record<string, unknown>;
    const partner = (await db().doc(`churches/${churchId}/partners/${link.partnerId}`).get()).data();
    const current = (await db().doc(`partner_link_index/${churchId}_${link.partnerId}`).get()).get("key");
    if (settings.partnerPageOn !== true || church.isActive === false || !partner || partner.isActive === false ||
        current !== key) {
      res.status(404).send(gone);
      return;
    }
    const tz = String(church.timezone || "Africa/Accra");
    const periods = await db().collection(`churches/${churchId}/partnership_periods`).where("isActive", "==", true).limit(1).get();
    const period = periods.docs[0];
    const entries = period ? await db().collection(`churches/${churchId}/entries`)
      .where("partnerId", "==", link.partnerId)
      .where("partnershipPeriodId", "==", period.id)
      .where("status", "==", "approved")
      .get() : null;
    const day = new Intl.DateTimeFormat("en-GB", {timeZone: tz, day: "numeric", month: "long", year: "numeric"});
    const list = (entries?.docs ?? [])
      .map((d) => ({
        at: (d.get("dateGiven") as Timestamp | undefined)?.toDate() ?? new Date(0),
        arm: String(d.get("armSnapshot.name") || "Giving"),
        amount: Number(d.get("amountCedis") ?? 0),
      }))
      .sort((a, b) => b.at.getTime() - a.at.getTime());
    const byArm = new Map<string, number>();
    for (const e of list) byArm.set(e.arm, (byArm.get(e.arm) ?? 0) + e.amount);
    const html = buildPartnerPageHtml({
      firstName: String(partner.fullName || "friend").trim().split(/\s+/)[0],
      churchName: String(church.name || "your church"),
      logoUrl: (church.logoUrl as string | undefined) ?? null,
      periodName: String(period?.get("name") || "this year"),
      currencySymbol: String(church.currencySymbol || "₵"),
      rows: list.map((e) => ({date: day.format(e.at), arm: e.arm, amount: e.amount})),
      byArm: [...byArm.entries()].map(([name, amount]) => ({name, amount})).sort((a, b) => b.amount - a.amount),
      total: list.reduce((s, e) => s + e.amount, 0),
      updated: day.format(new Date()),
    });
    res.status(200).send(req.method === "HEAD" ? "" : html);
  } catch (e) {
    console.error("partnerPage", e);
    res.status(500).send(gone);
  }
});
