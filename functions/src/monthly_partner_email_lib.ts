export type ArmTotal = {name: string; amount: number};

export type EntryRow = {
  partnerId: string;
  amount: number;
  dateGiven: Date;
  armName: string;
};

export type PartnerMonthTotals = {
  partnerId: string;
  monthByArm: Map<string, number>;
  ytdByArm: Map<string, number>;
  /** Giving per calendar month of the year, 1 = January. */
  ytdByMonth: Map<number, number>;
  monthTotal: number;
  ytdTotal: number;
};

const AIRPORT_CITY_DOMAIN = "theairportcitychurch.com";

export function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

export function addMoney(a: number, b: number): number {
  return Math.round((a + b) * 100) / 100;
}

export function formatMoney(amount: number, symbol: string): string {
  const n = amount.toLocaleString("en-GH", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
  return `${symbol}${n}`;
}

export function extractEmail(from: string): string {
  const m = from.match(/<([^>]+)>/);
  return (m ? m[1] : from).trim().toLowerCase();
}

export function isLikelyEmail(value: string): boolean {
  const s = value.trim();
  const at = s.indexOf("@");
  return at > 0 && at < s.length - 1 && !s.includes(" ");
}

export function previousCalendarMonth(
  now: Date,
  timeZone: string,
): {year: number; month: number} {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone,
    year: "numeric",
    month: "numeric",
  }).formatToParts(now);
  const year = Number(parts.find((p) => p.type === "year")?.value);
  const month = Number(parts.find((p) => p.type === "month")?.value);
  if (!year || !month) {
    throw new Error(`Could not read calendar month in ${timeZone}`);
  }
  if (month === 1) return {year: year - 1, month: 12};
  return {year, month: month - 1};
}

function tzOffsetMs(date: Date, timeZone: string): number {
  const dtf = new Intl.DateTimeFormat("en-US", {
    timeZone,
    hour12: false,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  });
  const raw = Object.fromEntries(dtf.formatToParts(date).map((p) => [p.type, p.value]));
  const hour = Number(raw.hour === "24" ? "0" : raw.hour);
  const asUtc = Date.UTC(
    Number(raw.year),
    Number(raw.month) - 1,
    Number(raw.day),
    hour,
    Number(raw.minute),
    Number(raw.second),
  );
  return asUtc - date.getTime();
}

export function zonedMidnight(
  year: number,
  month: number,
  day: number,
  timeZone: string,
): Date {
  const utc = Date.UTC(year, month - 1, day, 0, 0, 0);
  const date = new Date(utc);
  return new Date(utc - tzOffsetMs(date, timeZone));
}

export function monthRange(
  year: number,
  month: number,
  timeZone: string,
): {start: Date; end: Date; yearStart: Date} {
  const start = zonedMidnight(year, month, 1, timeZone);
  const end =
    month === 12
      ? zonedMidnight(year + 1, 1, 1, timeZone)
      : zonedMidnight(year, month + 1, 1, timeZone);
  const yearStart = zonedMidnight(year, 1, 1, timeZone);
  return {start, end, yearStart};
}

export function monthLabel(year: number, month: number): string {
  return new Date(Date.UTC(year, month - 1, 1)).toLocaleDateString("en-GB", {
    month: "long",
    year: "numeric",
    timeZone: "UTC",
  });
}

export function yearMonthKey(year: number, month: number): string {
  return `${year}-${String(month).padStart(2, "0")}`;
}

export function parseYearMonth(raw: string): {year: number; month: number} | null {
  const m = /^(\d{4})-(\d{2})$/.exec(raw.trim());
  if (!m) return null;
  const year = Number(m[1]);
  const month = Number(m[2]);
  if (month < 1 || month > 12) return null;
  return {year, month};
}

export function armTotalsFromMap(byArm: Map<string, number>): ArmTotal[] {
  return [...byArm.entries()]
    .filter(([, amount]) => amount > 0)
    .map(([name, amount]) => ({name, amount}))
    .sort((a, b) => a.name.localeCompare(b.name));
}

export function buildFromHeader(fromRaw: string, pastorName: string): string {
  const trimmed = fromRaw.trim();
  if (!trimmed) return "";
  if (trimmed.includes("<")) return trimmed;
  const name = pastorName.trim();
  if (!name) return trimmed;
  return `${name} <${extractEmail(trimmed)}>`;
}

export function resendKeyFor(from: string, churchId: string): string | undefined {
  const byChurch = process.env[`RESEND_CHURCH_${churchId}`]?.trim();
  if (byChurch) return byChurch;
  const domain = extractEmail(from).split("@")[1] ?? "";
  if (domain === AIRPORT_CITY_DOMAIN) {
    return process.env.RESEND_AIRPORT_CITY_API_KEY?.trim();
  }
  return undefined;
}

export function shouldSendLive(): boolean {
  if (process.env.FUNCTIONS_EMULATOR === "true") {
    return process.env.MONTHLY_EMAIL_ALLOW_SEND === "true";
  }
  return true;
}

/** The church's initials for the mark at the top of the letter. */
export function churchInitials(name: string): string {
  const words = name.trim().split(/\s+/).filter((w) => /[A-Za-z0-9]/.test(w[0] ?? ""));
  return words.slice(0, 2).map((w) => w[0].toUpperCase()).join("") || "P";
}

/** A #rrggbb mark colour, or Pillr navy when the church has none or it is malformed. */
export function markColour(hex: string | undefined | null): string {
  const h = (hex ?? "").trim();
  return /^#[0-9a-fA-F]{6}$/.test(h) ? h : "#13426f";
}

const MONTH_LETTERS = ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"];

/**
 * The monthly thank-you letter, as on the canvas (board 48).
 *
 * Built from tables with inline styles: the one layout every mail client
 * draws the same, Outlook included. Manrope where the reader has it, the
 * system sans otherwise. Only approved giving is in it.
 */
export function buildPartnerEmailHtml(opts: {
  partnerName: string;
  churchName: string;
  monthLabel: string;
  year: number;
  monthArms: ArmTotal[];
  monthTotal: number;
  ytdArms: ArmTotal[];
  ytdTotal: number;
  pastorName: string;
  currencySymbol: string;
  /** Giving per month of the year so far, January first; omitted hides the bars. */
  ytdByMonth?: number[];
  /** The church's mark colour, #rrggbb. */
  markColor?: string;
  preview?: boolean;
}): string {
  const sym = opts.currencySymbol || "₵";
  const esc = escapeHtml;
  const navy = "#13426f";
  const muted = "#616c8a";
  const font = "Manrope, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif";
  const first = opts.partnerName.trim().split(/\s+/)[0] || opts.partnerName;
  const monthName = opts.monthLabel.split(" ")[0];
  const money = (n: number) => esc(formatMoney(n, sym));
  const total = formatMoney(opts.monthTotal, sym);
  const dot = total.lastIndexOf(".");
  const whole = esc(dot < 0 ? total : total.slice(0, dot));
  const cents = esc(dot < 0 ? "" : total.slice(dot));

  const rows = (arms: ArmTotal[]) =>
    arms
      .map(
        (a, i) => `
          <tr>
            <td style="padding: 11px 0; ${i < arms.length - 1 ? "border-bottom: 1px solid #dfe9f3;" : ""} font-size: 15px; color: #333333;">${esc(a.name)}</td>
            <td align="right" style="padding: 11px 0; ${i < arms.length - 1 ? "border-bottom: 1px solid #dfe9f3;" : ""} font-size: 15px; font-weight: 700; color: ${navy}; white-space: nowrap;">${money(a.amount)}</td>
          </tr>`,
      )
      .join("");

  const months = (opts.ytdByMonth ?? []).slice(0, 12);
  const gaveIn = months.filter((v) => v > 0).length;
  const peak = Math.max(1, ...months);
  const bars = months.length
    ? `
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-top: 14px;">
        <tr>${months
          .map((v, i) => {
            const h = v > 0 ? Math.max(6, Math.round((64 * v) / peak)) : 4;
            const last = i === months.length - 1;
            return `
          <td valign="bottom" align="center" style="padding: 0 3px; height: 70px;">
            <div style="width: 22px; max-width: 100%; height: ${h}px; border-radius: 5px; background: ${v > 0 ? (last ? navy : "#bde1f9") : "#edf1f5"}; line-height: ${h}px; font-size: 1px;">&nbsp;</div>
          </td>`;
          })
          .join("")}
        </tr>
        <tr>${months
          .map(
            (_, i) =>
              `<td align="center" style="padding-top: 6px; font-size: 11px; color: ${muted};">${MONTH_LETTERS[i]}</td>`,
          )
          .join("")}
        </tr>
      </table>`
    : "";

  const foot = opts.preview
    ? "This is a preview from Pillr. The figures are examples, not anyone's giving."
    : `Something not right? Reply to this email and it goes to ${esc(opts.pastorName)}. Only approved giving is listed; anything still being checked will show next month.<br>To stop these letters, reply and say so, and the church will turn them off for you.`;

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light only">
<title>Your ${esc(opts.monthLabel)} giving</title>
</head>
<body style="margin: 0; padding: 0; background: #f1f5f9;">
<div style="display: none; max-height: 0; overflow: hidden;">Thank you, ${esc(first)}. You gave ${esc(total)} in ${esc(monthName)}.</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background: #f1f5f9;">
  <tr>
    <td align="center" style="padding: 28px 12px;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width: 620px; background: #ffffff; border-radius: 20px; font-family: ${font}; color: #333333; line-height: 1.6;">
        <tr>
          <td style="padding: 32px 36px 0;">
            <table role="presentation" cellpadding="0" cellspacing="0" border="0">
              <tr>
                <td width="40" height="40" align="center" valign="middle" style="width: 40px; height: 40px; border-radius: 12px; background: ${markColour(opts.markColor)}; color: #ffffff; font-weight: 800; font-size: 14px;">${esc(churchInitials(opts.churchName))}</td>
                <td style="padding-left: 12px; font-weight: 700; font-size: 15px; color: ${navy};">${esc(opts.churchName)}</td>
              </tr>
            </table>
          </td>
        </tr>
        <tr>
          <td style="padding: 28px 36px 0;">
            <h1 style="margin: 0 0 10px; font-size: 28px; line-height: 1.25; color: ${navy}; font-weight: 800;">Thank you, ${esc(first)}.</h1>
            <p style="margin: 0; font-size: 15px;">Here is your giving for ${esc(monthName)}. Every cedi goes to the work you gave it for, and we are grateful for each one.</p>
          </td>
        </tr>
        <tr>
          <td style="padding: 24px 36px 0;">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background: #eef6fe; border-radius: 18px;">
              <tr>
                <td style="padding: 22px 22px 10px;">
                  <div style="font-size: 13px; font-weight: 600; color: ${muted};">You gave in ${esc(monthName)}</div>
                  <div style="font-size: 38px; line-height: 1.2; font-weight: 800; color: ${navy}; margin: 2px 0 8px;">${whole}<span style="font-size: 20px; color: ${muted};">${cents}</span></div>
                  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">${rows(opts.monthArms)}
                  </table>
                </td>
              </tr>
            </table>
          </td>
        </tr>
        <tr>
          <td style="padding: 26px 36px 0;">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
              <tr>
                <td style="font-size: 17px; font-weight: 800; color: ${navy};">Your ${opts.year} so far</td>
                <td align="right" style="font-size: 17px; font-weight: 800; color: ${navy}; white-space: nowrap;">${money(opts.ytdTotal)}</td>
              </tr>
            </table>
            ${months.length ? `<div style="font-size: 13px; color: ${muted};">You gave in ${gaveIn} of ${months.length} ${months.length === 1 ? "month" : "months"}.</div>` : ""}
            ${bars}
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-top: 14px;">${rows(opts.ytdArms)}
            </table>
          </td>
        </tr>
        <tr>
          <td style="padding: 22px 36px 0; font-size: 15px;">
            <p style="margin: 0;">With gratitude,</p>
            <p style="margin: 0; font-weight: 700; color: ${navy};">${esc(opts.pastorName)}</p>
            <p style="margin: 0; font-size: 14px; color: ${muted};">${esc(opts.churchName)}</p>
          </td>
        </tr>
        <tr>
          <td style="padding: 26px 36px 32px;">
            <div style="border-top: 1px solid #edf1f5; padding-top: 16px; font-size: 13px; color: ${muted}; line-height: 1.55;">${foot}</div>
          </td>
        </tr>
      </table>
    </td>
  </tr>
</table>
</body>
</html>`;
}

/** Per-month totals as an array, January first, up to and including [month]. */
export function monthsArray(byMonth: Map<number, number>, month: number): number[] {
  const out: number[] = [];
  for (let m = 1; m <= month; m++) out.push(byMonth.get(m) ?? 0);
  return out;
}

export function accumulateEntries(
  entries: EntryRow[],
  monthStart: Date,
  monthEnd: Date,
  /** Calendar month (1–12) of a date in the church's time zone. */
  monthOf: (d: Date) => number = (d) => d.getUTCMonth() + 1,
): Map<string, PartnerMonthTotals> {
  const out = new Map<string, PartnerMonthTotals>();
  for (const e of entries) {
    if (!e.partnerId || !(e.amount > 0)) continue;
    let row = out.get(e.partnerId);
    if (!row) {
      row = {
        partnerId: e.partnerId,
        monthByArm: new Map(),
        ytdByArm: new Map(),
        ytdByMonth: new Map(),
        monthTotal: 0,
        ytdTotal: 0,
      };
      out.set(e.partnerId, row);
    }
    const arm = e.armName.trim() || "Partnership";
    row.ytdTotal = addMoney(row.ytdTotal, e.amount);
    row.ytdByArm.set(arm, addMoney(row.ytdByArm.get(arm) ?? 0, e.amount));
    const m = monthOf(e.dateGiven);
    row.ytdByMonth.set(m, addMoney(row.ytdByMonth.get(m) ?? 0, e.amount));
    if (e.dateGiven >= monthStart && e.dateGiven < monthEnd) {
      row.monthTotal = addMoney(row.monthTotal, e.amount);
      row.monthByArm.set(arm, addMoney(row.monthByArm.get(arm) ?? 0, e.amount));
    }
  }
  return out;
}
