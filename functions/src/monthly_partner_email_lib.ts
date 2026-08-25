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
  preview?: boolean;
}): string {
  const sym = opts.currencySymbol || "₵";
  const monthRows = opts.monthArms
    .map(
      (a) => `
    <tr>
      <td style="padding: 6px 0; border-bottom: 1px solid #eee;">${escapeHtml(a.name)}</td>
      <td style="padding: 6px 0; border-bottom: 1px solid #eee; text-align: right;">${escapeHtml(formatMoney(a.amount, sym))}</td>
    </tr>`,
    )
    .join("");
  const ytdRows = opts.ytdArms
    .map(
      (a) => `
    <tr>
      <td style="padding: 6px 0; border-bottom: 1px solid #eee;">${escapeHtml(a.name)}</td>
      <td style="padding: 6px 0; border-bottom: 1px solid #eee; text-align: right;">${escapeHtml(formatMoney(a.amount, sym))}</td>
    </tr>`,
    )
    .join("");
  const previewNote = opts.preview
    ? `<p style="font-size: 12px; color: #888; margin-top: 2.5em;">This is a preview from Pillr. Figures are sample data, not a real giving record.</p>`
    : `<p style="font-size: 12px; color: #888; margin-top: 2.5em;">If you have a question about this summary, reply to this email.</p>`;
  return `
<div style="font-family: Georgia, 'Times New Roman', serif; color: #1a1a1a; max-width: 560px; margin: 0 auto; line-height: 1.5;">
  <p>Dear ${escapeHtml(opts.partnerName)},</p>
  <p>Thank you for your partnership with <strong>${escapeHtml(opts.churchName)}</strong>. Here is a summary of your giving.</p>

  <h3 style="margin: 1.6em 0 0.4em; font-size: 16px;">${escapeHtml(opts.monthLabel)}</h3>
  <table style="width: 100%; border-collapse: collapse; font-size: 15px;">
    ${monthRows}
    <tr>
      <td style="padding: 8px 0; font-weight: bold;">${escapeHtml(opts.monthLabel.split(" ")[0])} total</td>
      <td style="padding: 8px 0; font-weight: bold; text-align: right;">${escapeHtml(formatMoney(opts.monthTotal, sym))}</td>
    </tr>
  </table>

  <h3 style="margin: 1.6em 0 0.4em; font-size: 16px;">Year to date (${opts.year})</h3>
  <table style="width: 100%; border-collapse: collapse; font-size: 15px;">
    ${ytdRows}
    <tr>
      <td style="padding: 8px 0; font-weight: bold;">Year total</td>
      <td style="padding: 8px 0; font-weight: bold; text-align: right;">${escapeHtml(formatMoney(opts.ytdTotal, sym))}</td>
    </tr>
  </table>

  <p style="margin-top: 2em;">With gratitude,<br>${escapeHtml(opts.pastorName)}<br>${escapeHtml(opts.churchName)}</p>
  ${previewNote}
</div>`;
}

export function accumulateEntries(
  entries: EntryRow[],
  monthStart: Date,
  monthEnd: Date,
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
        monthTotal: 0,
        ytdTotal: 0,
      };
      out.set(e.partnerId, row);
    }
    const arm = e.armName.trim() || "Partnership";
    row.ytdTotal = addMoney(row.ytdTotal, e.amount);
    row.ytdByArm.set(arm, addMoney(row.ytdByArm.get(arm) ?? 0, e.amount));
    if (e.dateGiven >= monthStart && e.dateGiven < monthEnd) {
      row.monthTotal = addMoney(row.monthTotal, e.amount);
      row.monthByArm.set(arm, addMoney(row.monthByArm.get(arm) ?? 0, e.amount));
    }
  }
  return out;
}
