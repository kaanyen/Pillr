import * as admin from "firebase-admin";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {Resend} from "resend";
import {
  accumulateEntries,
  armTotalsFromMap,
  buildFromHeader,
  buildPartnerEmailHtml,
  monthsArray,
  type EntryRow,
  isLikelyEmail,
  monthLabel,
  monthRange,
  parseYearMonth,
  previousCalendarMonth,
  resendKeyFor,
  shouldSendLive,
  yearMonthKey,
} from "./monthly_partner_email_lib";
import {loadMainArmNames} from "./arm_groups";

const REGION = "us-central1";

function db(): admin.firestore.Firestore {
  return admin.firestore();
}

function toDate(value: unknown): Date | null {
  if (!value) return null;
  if (value instanceof Date) return value;
  if (value instanceof Timestamp) return value.toDate();
  if (typeof (value as {toDate?: () => Date}).toDate === "function") {
    return (value as {toDate: () => Date}).toDate();
  }
  return null;
}

async function loadApprovedEntries(
  churchId: string,
  from: Date,
  to: Date,
): Promise<EntryRow[]> {
  const rows: EntryRow[] = [];
  // Partners see main arms only: a sub-arm's giving is listed under its main.
  const mainNames = await loadMainArmNames(db(), churchId);
  let last: admin.firestore.QueryDocumentSnapshot | undefined;
  for (;;) {
    let q: admin.firestore.Query = db()
      .collection(`churches/${churchId}/entries`)
      .where("status", "==", "approved")
      .where("dateGiven", ">=", Timestamp.fromDate(from))
      .where("dateGiven", "<", Timestamp.fromDate(to))
      .orderBy("dateGiven", "asc")
      .limit(500);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;
    for (const doc of snap.docs) {
      const d = doc.data();
      const dateGiven = toDate(d.dateGiven);
      if (!dateGiven) continue;
      const armSnap = (d.armSnapshot as {name?: string} | undefined) ?? {};
      rows.push({
        partnerId: String(d.partnerId ?? ""),
        amount: Number(d.amountCedis ?? 0),
        dateGiven,
        armName: mainNames.get(String(d.partnershipArmId ?? "")) ??
          String(armSnap.name ?? "Partnership"),
      });
    }
    last = snap.docs[snap.docs.length - 1];
    if (snap.size < 500) break;
  }
  return rows;
}

type SkipRow = {partnerId: string; fullName: string; memberId: string; amount: number};
type FailRow = {partnerId: string; fullName: string; email: string; error: string; amount?: number};

export type ChurchRunResult = {
  churchId: string;
  yearMonth: string;
  skipped: boolean;
  skipReason?: string;
  sent: number;
  skippedNoEmail: number;
  failed: number;
  dryRun: boolean;
  /** Letters actually sent by this run (not ones sent before). */
  sentNow: number;
};

async function resolvePastor(
  churchId: string,
  primaryPastorUid: string,
): Promise<{fullName: string; email: string} | null> {
  const snap = await db().doc(`churches/${churchId}/users/${primaryPastorUid}`).get();
  if (!snap.exists) return null;
  const d = snap.data() ?? {};
  if (d.role !== "pastor" || d.isActive === false) return null;
  return {
    fullName: String(d.fullName ?? "").trim() || "Pastor",
    email: String(d.email ?? "").trim(),
  };
}

async function sendViaResend(opts: {
  apiKey: string;
  from: string;
  to: string;
  replyTo?: string;
  subject: string;
  html: string;
}): Promise<string | undefined> {
  const resend = new Resend(opts.apiKey);
  const {data, error} = await resend.emails.send({
    from: opts.from,
    to: opts.to,
    replyTo: opts.replyTo || undefined,
    subject: opts.subject,
    html: opts.html,
  });
  if (error) {
    throw new Error(error.message || String(error));
  }
  return data?.id;
}

export async function runChurchMonthlyEmails(opts: {
  churchId: string;
  year?: number;
  month?: number;
  liveSend: boolean;
  /**
   * Send only to these partners, even ones who already got this month's
   * letter. Everyone else keeps what happened to them before.
   */
  onlyPartnerIds?: string[];
}): Promise<ChurchRunResult> {
  const only = opts.onlyPartnerIds ? new Set(opts.onlyPartnerIds) : null;
  const churchSnap = await db().doc(`churches/${opts.churchId}`).get();
  if (!churchSnap.exists) {
    return {
      churchId: opts.churchId,
      yearMonth: "",
      skipped: true,
      sentNow: 0,
      skipReason: "church missing",
      sent: 0,
      skippedNoEmail: 0,
      failed: 0,
      dryRun: !opts.liveSend,
    };
  }
  const church = churchSnap.data() ?? {};
  if (church.isActive === false) {
    return {
      churchId: opts.churchId,
      yearMonth: "",
      skipped: true,
      sentNow: 0,
      skipReason: "inactive",
      sent: 0,
      skippedNoEmail: 0,
      failed: 0,
      dryRun: !opts.liveSend,
    };
  }
  const settings = (church.settings ?? {}) as Record<string, unknown>;
  if (settings.sendMonthlyPartnerEmails !== true) {
    return {
      churchId: opts.churchId,
      yearMonth: "",
      skipped: true,
      sentNow: 0,
      skipReason: "switch off",
      sent: 0,
      skippedNoEmail: 0,
      failed: 0,
      dryRun: !opts.liveSend,
    };
  }
  const timeZone = String(church.timezone || "Africa/Accra");
  const prev = previousCalendarMonth(new Date(), timeZone);
  const year = opts.year ?? prev.year;
  const month = opts.month ?? prev.month;
  const ym = yearMonthKey(year, month);
  const label = monthLabel(year, month);
  const range = monthRange(year, month, timeZone);
  const fromRaw = String(settings.partnerEmailFrom ?? "").trim();
  const primaryPastorUid = String(settings.primaryPastorUid ?? "").trim();
  if (!fromRaw || !primaryPastorUid) {
    await writeReport(opts.churchId, ym, {
      monthLabel: label,
      sent: 0,
      skippedNoEmail: [],
      failed: [],
      dryRun: !opts.liveSend,
      skipReason: "From address or primary pastor is not set",
    });
    return {
      churchId: opts.churchId,
      yearMonth: ym,
      skipped: true,
      sentNow: 0,
      skipReason: "missing from or pastor",
      sent: 0,
      skippedNoEmail: 0,
      failed: 0,
      dryRun: !opts.liveSend,
    };
  }
  const pastor = await resolvePastor(opts.churchId, primaryPastorUid);
  if (!pastor) {
    await writeReport(opts.churchId, ym, {
      monthLabel: label,
      sent: 0,
      skippedNoEmail: [],
      failed: [],
      dryRun: !opts.liveSend,
      skipReason: "Primary pastor not found or inactive",
    });
    return {
      churchId: opts.churchId,
      yearMonth: ym,
      skipped: true,
      sentNow: 0,
      skipReason: "pastor missing",
      sent: 0,
      skippedNoEmail: 0,
      failed: 0,
      dryRun: !opts.liveSend,
    };
  }
  const from = buildFromHeader(fromRaw, pastor.fullName);
  const apiKey = resendKeyFor(from, opts.churchId);
  if (!apiKey) {
    await writeReport(opts.churchId, ym, {
      monthLabel: label,
      sent: 0,
      skippedNoEmail: [],
      failed: [],
      dryRun: !opts.liveSend,
      skipReason: "No Resend API key for this church",
    });
    return {
      churchId: opts.churchId,
      yearMonth: ym,
      skipped: true,
      sentNow: 0,
      skipReason: "no resend key",
      sent: 0,
      skippedNoEmail: 0,
      failed: 0,
      dryRun: !opts.liveSend,
    };
  }

  const churchName = String(church.name || "your church");
  const currencySymbol = String(church.currencySymbol || "₵");
  const entries = await loadApprovedEntries(opts.churchId, range.yearStart, range.end);
  const monthFmt = new Intl.DateTimeFormat("en-US", {timeZone, month: "numeric"});
  const totals = accumulateEntries(entries, range.start, range.end, (d) =>
    Number(monthFmt.format(d)),
  );
  const markColor = String(church.primaryColorHex || church.primaryColor || "");
  const skippedNoEmail: SkipRow[] = [];
  const skippedOptedOut: SkipRow[] = [];
  const failed: FailRow[] = [];
  let sent = 0;
  let sentNow = 0;
  const live = opts.liveSend && shouldSendLive();
  // A run for chosen partners keeps everyone else's earlier failures.
  const earlierFailed = new Map<string, FailRow>();
  if (only) {
    const prev = await db().doc(`churches/${opts.churchId}/monthly_email_reports/${ym}`).get();
    for (const f of (prev.data()?.failed ?? []) as FailRow[]) {
      if (f && f.partnerId) earlierFailed.set(f.partnerId, f);
    }
  }

  for (const [partnerId, row] of totals) {
    if (!(row.monthTotal > 0)) continue;
    const partnerSnap = await db().doc(`churches/${opts.churchId}/partners/${partnerId}`).get();
    const p = partnerSnap.data() ?? {};
    const fullName = String(p.fullName || row.partnerId);
    const memberId = String(p.memberId || "");
    const email = String(p.email || "").trim();
    // The church turned this partner's letters off on their profile.
    if (p.noMonthlyLetters === true) {
      skippedOptedOut.push({partnerId, fullName, memberId, amount: row.monthTotal});
      continue;
    }
    if (!email || !isLikelyEmail(email)) {
      skippedNoEmail.push({partnerId, fullName, memberId, amount: row.monthTotal});
      continue;
    }
    const deliveryRef = db().doc(
      `churches/${opts.churchId}/monthly_email_deliveries/${ym}_${partnerId}`,
    );
    const existing = await deliveryRef.get();
    const alreadySent = existing.exists && existing.data()?.status === "sent";
    if (only && !only.has(partnerId)) {
      if (alreadySent) {
        sent += 1;
      } else if (earlierFailed.has(partnerId)) {
        failed.push(earlierFailed.get(partnerId)!);
      }
      continue;
    }
    if (alreadySent && !only) {
      sent += 1;
      continue;
    }
    const html = buildPartnerEmailHtml({
      partnerName: fullName,
      churchName,
      monthLabel: label,
      year,
      monthArms: armTotalsFromMap(row.monthByArm),
      monthTotal: row.monthTotal,
      ytdArms: armTotalsFromMap(row.ytdByArm),
      ytdTotal: row.ytdTotal,
      ytdByMonth: monthsArray(row.ytdByMonth, month),
      markColor,
      pastorName: pastor.fullName,
      currencySymbol,
    });
    try {
      let resendId: string | undefined;
      if (live) {
        resendId = await sendViaResend({
          apiKey,
          from,
          to: email,
          replyTo: isLikelyEmail(pastor.email) ? pastor.email : undefined,
          subject: `Your ${label} giving — ${churchName}`,
          html,
        });
      }
      await deliveryRef.set({
        partnerId,
        yearMonth: ym,
        email,
        amount: row.monthTotal,
        status: live ? "sent" : "dry_run",
        resendId: resendId ?? null,
        sentAt: FieldValue.serverTimestamp(),
      });
      sent += 1;
      sentNow += 1;
    } catch (e) {
      failed.push({
        partnerId,
        fullName,
        email,
        error: e instanceof Error ? e.message : String(e),
        amount: row.monthTotal,
      });
    }
  }

  await writeReport(opts.churchId, ym, {
    monthLabel: label,
    sent,
    skippedNoEmail,
    skippedOptedOut,
    failed,
    dryRun: !live,
  });

  return {
    churchId: opts.churchId,
    yearMonth: ym,
    skipped: false,
    sent,
    skippedNoEmail: skippedNoEmail.length,
    failed: failed.length,
    dryRun: !live,
    sentNow,
  };
}

async function writeReport(
  churchId: string,
  yearMonth: string,
  data: {
    monthLabel: string;
    sent: number;
    skippedNoEmail: SkipRow[];
    skippedOptedOut?: SkipRow[];
    failed: FailRow[];
    dryRun: boolean;
    skipReason?: string;
  },
): Promise<void> {
  // The same run as counts only, for the admin who looks after the letters.
  await db().doc(`churches/${churchId}/monthly_email_summaries/${yearMonth}`).set({
    yearMonth,
    monthLabel: data.monthLabel,
    sent: data.sent,
    failed: data.failed.length,
    noEmail: data.skippedNoEmail.length,
    turnedOff: (data.skippedOptedOut ?? []).length,
    dryRun: data.dryRun,
    skipReason: data.skipReason ?? null,
    ranAt: FieldValue.serverTimestamp(),
  });
  await db().doc(`churches/${churchId}/monthly_email_reports/${yearMonth}`).set({
    yearMonth,
    monthLabel: data.monthLabel,
    sent: data.sent,
    skippedNoEmailCount: data.skippedNoEmail.length,
    failedCount: data.failed.length,
    skippedNoEmail: data.skippedNoEmail,
    skippedOptedOutCount: (data.skippedOptedOut ?? []).length,
    skippedOptedOut: data.skippedOptedOut ?? [],
    failed: data.failed,
    dryRun: data.dryRun,
    skipReason: data.skipReason ?? null,
    ranAt: FieldValue.serverTimestamp(),
  });
}

async function membership(uid: string): Promise<{churchId: string; role: string}> {
  const snap = await db().doc(`user_church_index/${uid}`).get();
  if (!snap.exists) {
    throw new HttpsError("permission-denied", "No church membership for this account.");
  }
  const d = snap.data()!;
  return {churchId: String(d.churchId), role: String(d.role)};
}

function assertPastorOrAdmin(role: string): void {
  if (role !== "pastor" && role !== "admin") {
    throw new HttpsError("permission-denied", "Only pastors and admins can manage partner emails.");
  }
}

/** 15th of each month, 09:00 Africa/Accra — two weeks after month end. */
export const monthlyPartnerGivingSummary = onSchedule(
  {
    schedule: "0 9 15 * *",
    timeZone: "Africa/Accra",
    region: REGION,
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async () => {
    const churches = await db().collection("churches").get();
    for (const c of churches.docs) {
      try {
        const result = await runChurchMonthlyEmails({
          churchId: c.id,
          liveSend: true,
        });
        console.log("monthlyPartnerGivingSummary", result);
      } catch (e) {
        console.error("monthlyPartnerGivingSummary church", c.id, e);
      }
    }
  },
);

/** One preview to the signed-in user's inbox. Sample figures, real From/pastor. */
export const previewMonthlyPartnerGivingEmail = onCall({region: REGION}, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "You must be signed in.");
  const idx = await membership(uid);
  assertPastorOrAdmin(idx.role);
  const to = String(request.auth?.token?.email ?? "").trim().toLowerCase();
  if (!to || !isLikelyEmail(to)) {
    throw new HttpsError("failed-precondition", "Your account needs an email address.");
  }
  const churchSnap = await db().doc(`churches/${idx.churchId}`).get();
  const church = churchSnap.data() ?? {};
  const settings = (church.settings ?? {}) as Record<string, unknown>;
  const fromRaw = String(settings.partnerEmailFrom ?? "").trim();
  const primaryPastorUid = String(settings.primaryPastorUid ?? "").trim();
  if (!fromRaw || !primaryPastorUid) {
    throw new HttpsError(
      "failed-precondition",
      "Set a From address and a primary pastor, then save.",
    );
  }
  const pastor = await resolvePastor(idx.churchId, primaryPastorUid);
  if (!pastor) {
    throw new HttpsError("failed-precondition", "Primary pastor is missing or inactive.");
  }
  const from = buildFromHeader(fromRaw, pastor.fullName);
  const apiKey = resendKeyFor(from, idx.churchId);
  if (!apiKey) {
    throw new HttpsError(
      "failed-precondition",
      "No Resend key is configured for this church's From domain.",
    );
  }
  const churchName = String(church.name || "your church");
  const currencySymbol = String(church.currencySymbol || "₵");
  const timeZone = String(church.timezone || "Africa/Accra");
  const prev = previousCalendarMonth(new Date(), timeZone);
  const label = monthLabel(prev.year, prev.month);
  const callerSnap = await db().doc(`churches/${idx.churchId}/users/${uid}`).get();
  const previewName =
    String(callerSnap.data()?.fullName ?? "").trim() || "Partner";
  const html = buildPartnerEmailHtml({
    partnerName: previewName,
    churchName,
    monthLabel: label,
    year: prev.year,
    monthArms: [
      {name: "Tithe", amount: 300},
      {name: "Building", amount: 150},
    ],
    monthTotal: 450,
    ytdArms: [
      {name: "Tithe", amount: 2100},
      {name: "Building", amount: 800},
    ],
    ytdTotal: 2900,
    ytdByMonth: Array.from({length: prev.month}, (_, i) =>
      [240, 180, 300, 260, 220, 380, 200, 310, 450, 290, 330, 260][i] ?? 0,
    ),
    markColor: String(church.primaryColorHex || church.primaryColor || ""),
    pastorName: pastor.fullName,
    currencySymbol,
    preview: true,
  });
  const id = await sendViaResend({
    apiKey,
    from,
    to,
    replyTo: isLikelyEmail(pastor.email) ? pastor.email : undefined,
    subject: `Your ${label} giving — ${churchName} (preview)`,
    html,
  });
  return {success: true, id: id ?? null, to};
});

/** Run last month's partner letters for the caller's church. */
export const runMonthlyPartnerGivingSummary = onCall(
  {region: REGION, timeoutSeconds: 300, memory: "512MiB"},
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "You must be signed in.");
    const idx = await membership(uid);
    if (idx.role !== "pastor") {
      throw new HttpsError("permission-denied", "Only pastors can send the monthly partner emails.");
    }
    const rawYm = String(request.data?.yearMonth ?? "").trim();
    const parsed = rawYm ? parseYearMonth(rawYm) : null;
    if (rawYm && !parsed) {
      throw new HttpsError("invalid-argument", "yearMonth must be YYYY-MM.");
    }
    const rawIds = request.data?.partnerIds;
    let onlyPartnerIds: string[] | undefined;
    if (rawIds !== undefined && rawIds !== null) {
      if (!Array.isArray(rawIds) || rawIds.length === 0 || rawIds.length > 500 ||
          !rawIds.every((x) => typeof x === "string" && x.length > 0 && x.length < 200)) {
        throw new HttpsError("invalid-argument", "partnerIds must be a list of partner IDs.");
      }
      onlyPartnerIds = rawIds as string[];
    }
    const result = await runChurchMonthlyEmails({
      churchId: idx.churchId,
      year: parsed?.year,
      month: parsed?.month,
      liveSend: true,
      onlyPartnerIds,
    });
    if (result.skipped) {
      throw new HttpsError(
        "failed-precondition",
        result.skipReason === "switch off"
          ? "Turn on monthly partner emails first."
          : `Could not send: ${result.skipReason ?? "not configured"}.`,
      );
    }
    return result;
  },
);
