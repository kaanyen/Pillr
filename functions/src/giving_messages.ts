/**
 * A thank-you to the partner when a pastor approves their giving: an email,
 * a text, or both, each switched on in Settings · Letters and written in the
 * church's own words.
 *
 * Sent once per entry. `giving_messages/{entryId}` is created before anything
 * goes out, so an approval undone and done again, or a trigger that runs
 * twice, never messages the partner a second time.
 */
import * as admin from "firebase-admin";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {Resend} from "resend";
import {
  buildFromHeader,
  escapeHtml,
  formatMoney,
  isLikelyEmail,
  resendKeyFor,
  shouldSendLive,
} from "./monthly_partner_email_lib";

const REGION = "us-central1";
const db = () => admin.firestore();

export const DEFAULT_APPROVAL = {
  emailSubject: "Thank you for your [Arm] giving",
  emailMessage: "Thank you, [First name]. We have received your [Arm] giving of [Amount] on [Date]. God bless you.",
  smsMessage: "Thank you [First name]. Your [Arm] giving of [Amount] on [Date] has been received. God bless you. [Church name]",
};

export type GivingValues = {
  firstName: string;
  amount: string;
  arm: string;
  date: string;
  churchName: string;
};

/** Fills [First name], [Amount], [Arm], [Date] and [Church name]. */
export function fillGivingTokens(text: string, v: GivingValues): string {
  return text
    .replace(/\[\s*first\s*name\s*\]/gi, v.firstName)
    .replace(/\[\s*amount\s*\]/gi, v.amount)
    .replace(/\[\s*arm\s*\]/gi, v.arm)
    .replace(/\[\s*date\s*\]/gi, v.date)
    .replace(/\[\s*church\s*name\s*\]/gi, v.churchName);
}

/**
 * A Ghanaian number as mNotify wants it: digits only, 233 in front.
 * "024 412 3456", "+233244123456" and "233244123456" all become
 * "233244123456". Null when it is not a phone number.
 */
export function normalizeGhanaPhone(raw: string | null | undefined): string | null {
  const d = String(raw ?? "").replace(/[^\d]/g, "");
  if (/^0\d{9}$/.test(d)) return `233${d.slice(1)}`;
  if (/^233\d{9}$/.test(d)) return d;
  if (/^\d{9}$/.test(d)) return `233${d}`;
  return null;
}

/** How many texts a message costs: 160 letters for one, 153 for each after. */
export function smsParts(text: string): number {
  const n = text.length;
  return n <= 160 ? 1 : Math.ceil(n / 153);
}

/** Who and what to thank, from an approved entry. */
async function valuesFor(churchId: string, entry: admin.firestore.DocumentData) {
  const church = (await db().doc(`churches/${churchId}`).get()).data() ?? {};
  const partner = (await db().doc(`churches/${churchId}/partners/${entry.partnerId}`).get()).data() ?? {};
  const tz = String(church.timezone || "Africa/Accra");
  const given = (entry.dateGiven as Timestamp | undefined)?.toDate() ?? new Date();
  const fullName = String(partner.fullName || entry.partnerSnapshot?.fullName || "");
  const values: GivingValues = {
    firstName: fullName.trim().split(/\s+/)[0] || "friend",
    amount: formatMoney(Number(entry.amountCedis ?? 0), String(church.currencySymbol || "₵")),
    arm: String(entry.armSnapshot?.name || "partnership"),
    date: new Intl.DateTimeFormat("en-GB", {timeZone: tz, day: "numeric", month: "long"}).format(given),
    churchName: String(church.name || "your church"),
  };
  return {church, partner, values};
}

/** The email: the church's words, then the giving it is about, signed. */
export function buildApprovalEmailHtml(opts: {
  message: string;
  values: GivingValues;
  pastorName: string;
  logoUrl?: string | null;
}): string {
  const esc = escapeHtml;
  const navy = "#13426f";
  const font = "Manrope, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif";
  const logo = (opts.logoUrl ?? "").trim();
  const v = opts.values;
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"></head>
<body style="margin: 0; padding: 24px 12px; background: #f1f5f9;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width: 560px; background: #ffffff; border-radius: 20px; font-family: ${font}; color: #333333; line-height: 1.6;">
<tr><td style="padding: 28px 32px 0; font-weight: 700; color: ${navy};">${logo && /^https:\/\//.test(logo) ?
    `<img src="${esc(logo)}" alt="${esc(v.churchName)}" height="40" style="display: block; height: 40px; width: auto; max-width: 160px; border: 0;">` :
    esc(v.churchName)}</td></tr>
<tr><td style="padding: 20px 32px 0; font-size: 16px;">${esc(fillGivingTokens(opts.message, v)).replace(/\n/g, "<br>")}</td></tr>
<tr><td style="padding: 20px 32px 0;"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background: #eef6fe; border-radius: 16px;">
<tr><td style="padding: 14px 18px; font-size: 15px;">${esc(v.arm)} · ${esc(v.date)}</td><td align="right" style="padding: 14px 18px; font-size: 18px; font-weight: 800; color: ${navy};">${esc(v.amount)}</td></tr></table></td></tr>
<tr><td style="padding: 20px 32px 28px; font-size: 15px;"><b style="color: ${navy};">${esc(opts.pastorName)}</b><br><span style="color: #616c8a; font-size: 14px;">${esc(v.churchName)}</span></td></tr>
</table></td></tr></table></body></html>`;
}

async function sendSms(key: string, sender: string, phone: string, message: string): Promise<string | undefined> {
  const res = await fetch(`https://api.mnotify.com/api/sms/quick?key=${encodeURIComponent(key)}`, {
    method: "POST",
    headers: {"Content-Type": "application/json", "Accept": "application/json"},
    body: JSON.stringify({recipient: [phone], sender, message, is_schedule: false, schedule_date: ""}),
  });
  const body = (await res.json().catch(() => ({}))) as {status?: string; code?: string; message?: string; summary?: {_id?: string}};
  if (!res.ok || (body.status && body.status !== "success")) {
    throw new Error(body.message || `mNotify said ${res.status}`);
  }
  return body.summary?._id;
}

type Outcome = {status: "sent" | "dry_run" | "skipped" | "failed"; reason?: string | null};

/**
 * Thanks the partner for one approved entry, by email and text as the church
 * has switched on. Never throws: what happened is written down instead.
 */
export async function sendApprovalMessages(churchId: string, entryId: string, entry: admin.firestore.DocumentData): Promise<void> {
  try {
    const church = (await db().doc(`churches/${churchId}`).get()).data() ?? {};
    const settings = (church.settings ?? {}) as Record<string, unknown>;
    const emailOn = settings.approvalEmailOn === true;
    const smsOn = settings.approvalSmsOn === true;
    if (!emailOn && !smsOn) return;
    if (church.isActive === false) return;

    // Claim the entry first: only one run ever messages for it.
    const record = db().doc(`churches/${churchId}/giving_messages/${entryId}`);
    try {
      await record.create({partnerId: entry.partnerId ?? null, startedAt: FieldValue.serverTimestamp()});
    } catch {
      return;
    }

    const {partner, values} = await valuesFor(churchId, entry);
    const live = shouldSendLive();
    const optedOut = partner.noMonthlyLetters === true;
    const text = (k: string, d: string) => {
      const v = settings[k];
      return typeof v === "string" && v.trim() ? v.trim() : d;
    };

    let email: Outcome = {status: "skipped", reason: emailOn ? null : "off"};
    if (emailOn) {
      const to = String(partner.email || "").trim();
      const fromRaw = String(settings.partnerEmailFrom ?? "").trim();
      const pastorUid = String(settings.primaryPastorUid ?? "").trim();
      const pastor = pastorUid ? (await db().doc(`churches/${churchId}/users/${pastorUid}`).get()).data() : undefined;
      const pastorName = String(pastor?.fullName || "Your pastor");
      const from = fromRaw ? buildFromHeader(fromRaw, pastorName) : "";
      const key = from ? resendKeyFor(from, churchId) : undefined;
      if (optedOut) email = {status: "skipped", reason: "turned off for this partner"};
      else if (!to || !isLikelyEmail(to)) email = {status: "skipped", reason: "no email"};
      else if (!from || !key) email = {status: "skipped", reason: "the letters' From address is not set up"};
      else if (!live) email = {status: "dry_run"};
      else {
        try {
          const resend = new Resend(key);
          const {error} = await resend.emails.send({
            from,
            to,
            replyTo: isLikelyEmail(String(pastor?.email ?? "")) ? String(pastor?.email) : undefined,
            subject: fillGivingTokens(text("approvalEmailSubject", DEFAULT_APPROVAL.emailSubject), values).slice(0, 200),
            html: buildApprovalEmailHtml({
              message: text("approvalEmailMessage", DEFAULT_APPROVAL.emailMessage),
              values,
              pastorName,
              logoUrl: (church.logoUrl as string | undefined) ?? null,
            }),
          });
          email = error ? {status: "failed", reason: error.message || String(error)} : {status: "sent"};
        } catch (e) {
          email = {status: "failed", reason: e instanceof Error ? e.message : String(e)};
        }
      }
    }

    let sms: Outcome = {status: "skipped", reason: smsOn ? null : "off"};
    if (smsOn) {
      const phone = normalizeGhanaPhone(String(partner.phone || (partner.phones ?? [])[0] || ""));
      const sender = String(settings.smsSenderId ?? "").trim();
      const key = process.env.MNOTIFY_API_KEY?.trim();
      if (optedOut) sms = {status: "skipped", reason: "turned off for this partner"};
      else if (!phone) sms = {status: "skipped", reason: "no phone number"};
      else if (!key || !sender) sms = {status: "skipped", reason: "texts are not set up"};
      else if (!live) sms = {status: "dry_run"};
      else {
        try {
          await sendSms(key, sender, phone, fillGivingTokens(text("approvalSmsMessage", DEFAULT_APPROVAL.smsMessage), values));
          sms = {status: "sent"};
        } catch (e) {
          sms = {status: "failed", reason: e instanceof Error ? e.message : String(e)};
        }
      }
    }

    await record.set({email, sms, sentAt: FieldValue.serverTimestamp()}, {merge: true});
  } catch (e) {
    console.error("sendApprovalMessages", churchId, entryId, e);
  }
}

/**
 * Settings · Letters, "Send me a test": the email to the caller's own
 * address, or the text to a number they type, with the words on the page
 * and made-up giving.
 */
export const testApprovalMessage = onCall({region: REGION}, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "You must be signed in.");
  const idx = (await db().doc(`user_church_index/${uid}`).get()).data();
  if (!idx || (idx.role !== "pastor" && idx.role !== "admin")) {
    throw new HttpsError("permission-denied", "Only pastors and admins send test messages.");
  }
  const churchId = String(idx.churchId);
  const church = (await db().doc(`churches/${churchId}`).get()).data() ?? {};
  const settings = (church.settings ?? {}) as Record<string, unknown>;
  const me = (await db().doc(`churches/${churchId}/users/${uid}`).get()).data() ?? {};
  const values: GivingValues = {
    firstName: String(me.fullName || "Ama").trim().split(/\s+/)[0],
    amount: formatMoney(500, String(church.currencySymbol || "₵")),
    arm: "Tithe",
    date: new Intl.DateTimeFormat("en-GB", {day: "numeric", month: "long"}).format(new Date()),
    churchName: String(church.name || "your church"),
  };
  const clip = (v: unknown, n: number) => (typeof v === "string" ? v.slice(0, n) : "");
  const channel = request.data?.channel === "sms" ? "sms" : "email";

  if (channel === "sms") {
    const phone = normalizeGhanaPhone(clip(request.data?.phone, 30));
    if (!phone) throw new HttpsError("invalid-argument", "Type a Ghana phone number, like 024 412 3456.");
    const key = process.env.MNOTIFY_API_KEY?.trim();
    const sender = String(request.data?.senderId ?? settings.smsSenderId ?? "").trim();
    if (!key) throw new HttpsError("failed-precondition", "Texts are not set up yet: the mNotify key is missing on the server.");
    if (!sender) throw new HttpsError("failed-precondition", "Choose a sender name first, the one registered with mNotify.");
    const message = fillGivingTokens(clip(request.data?.message, 480) || DEFAULT_APPROVAL.smsMessage, values);
    if (!shouldSendLive()) return {to: phone, dryRun: true};
    try {
      await sendSms(key, sender, phone, message);
    } catch (e) {
      throw new HttpsError("failed-precondition", `mNotify did not send it: ${e instanceof Error ? e.message : String(e)}`);
    }
    return {to: phone};
  }

  const to = String(request.auth?.token?.email ?? "").trim();
  if (!isLikelyEmail(to)) throw new HttpsError("failed-precondition", "Your account needs an email address.");
  const fromRaw = String(settings.partnerEmailFrom ?? "").trim();
  if (!fromRaw) throw new HttpsError("failed-precondition", "Set the From address under Sending first.");
  const from = buildFromHeader(fromRaw, String(me.fullName || "Pillr"));
  const key = resendKeyFor(from, churchId);
  if (!key) throw new HttpsError("failed-precondition", "Email is not set up for this church's From address.");
  if (!shouldSendLive()) return {to, dryRun: true};
  const {error} = await new Resend(key).emails.send({
    from,
    to,
    subject: `${fillGivingTokens(clip(request.data?.subject, 200) || DEFAULT_APPROVAL.emailSubject, values)} (test)`,
    html: buildApprovalEmailHtml({
      message: clip(request.data?.message, 600) || DEFAULT_APPROVAL.emailMessage,
      values,
      pastorName: String(me.fullName || "Your pastor"),
      logoUrl: (church.logoUrl as string | undefined) ?? null,
    }),
  });
  if (error) throw new HttpsError("failed-precondition", `The email did not send: ${error.message}`);
  return {to};
});
