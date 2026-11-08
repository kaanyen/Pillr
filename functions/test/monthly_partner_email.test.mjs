/**
 * Pure helpers for monthly partner giving emails. Needs a prior
 * `npm run build` so `lib/monthly_partner_email.js` exists.
 */
import {createRequire} from "node:module";
import {describe, it} from "node:test";
import assert from "node:assert/strict";

const require = createRequire(import.meta.url);
const lib = require("../lib/monthly_partner_email_lib.js");

describe("monthly partner email helpers", () => {
  it("steps back a calendar month in Accra", () => {
    const prev = lib.previousCalendarMonth(new Date("2026-08-15T09:00:00Z"), "Africa/Accra");
    assert.equal(prev.year, 2026);
    assert.equal(prev.month, 7);
  });

  it("rolls December back to the previous year", () => {
    const prev = lib.previousCalendarMonth(new Date("2026-01-15T09:00:00Z"), "Africa/Accra");
    assert.equal(prev.year, 2025);
    assert.equal(prev.month, 12);
  });

  it("builds an Accra month range that is UTC+0", () => {
    const r = lib.monthRange(2026, 7, "Africa/Accra");
    assert.equal(r.start.toISOString(), "2026-07-01T00:00:00.000Z");
    assert.equal(r.end.toISOString(), "2026-08-01T00:00:00.000Z");
    assert.equal(r.yearStart.toISOString(), "2026-01-01T00:00:00.000Z");
  });

  it("sums approved month vs year-to-date by arm", () => {
    const monthStart = new Date("2026-07-01T00:00:00Z");
    const monthEnd = new Date("2026-08-01T00:00:00Z");
    const totals = lib.accumulateEntries(
      [
        {partnerId: "p1", amount: 100, dateGiven: new Date("2026-06-10T00:00:00Z"), armName: "Tithe"},
        {partnerId: "p1", amount: 200, dateGiven: new Date("2026-07-05T00:00:00Z"), armName: "Tithe"},
        {partnerId: "p1", amount: 50, dateGiven: new Date("2026-07-20T00:00:00Z"), armName: "Building"},
        {partnerId: "p2", amount: 10, dateGiven: new Date("2026-07-02T00:00:00Z"), armName: "Tithe"},
      ],
      monthStart,
      monthEnd,
    );
    const p1 = totals.get("p1");
    assert.equal(p1.monthTotal, 250);
    assert.equal(p1.ytdTotal, 350);
    assert.equal(p1.monthByArm.get("Tithe"), 200);
    assert.equal(p1.monthByArm.get("Building"), 50);
    assert.equal(p1.ytdByArm.get("Tithe"), 300);
  });

  it("escapes names in the letter", () => {
    const html = lib.buildPartnerEmailHtml({
      partnerName: '<script>Ama Boateng',
      churchName: "Airport & City",
      monthLabel: "July 2026",
      year: 2026,
      monthArms: [{name: "Tithe", amount: 10}],
      monthTotal: 10,
      ytdArms: [{name: "Tithe", amount: 10}],
      ytdTotal: 10,
      pastorName: "Pastor",
      currencySymbol: "₵",
    });
    assert.equal(html.includes("<script>"), false);
    // The letter greets by first name; that name is escaped too.
    assert.equal(html.includes("Thank you, &lt;script&gt;Ama."), true);
    assert.equal(html.includes("Airport &amp; City"), true);
  });

  it("draws the year as month bars with the last month darkest", () => {
    const html = lib.buildPartnerEmailHtml({
      partnerName: "Ama Boateng",
      churchName: "Demo Community Church",
      monthLabel: "October 2026",
      year: 2026,
      monthArms: [{name: "Tithe", amount: 800}],
      monthTotal: 800,
      ytdArms: [{name: "Tithe", amount: 1600}],
      ytdTotal: 1600,
      ytdByMonth: lib.monthsArray(new Map([[1, 800], [10, 800]]), 10),
      markColor: "not-a-colour",
      pastorName: "Demo Pastor",
      currencySymbol: "₵",
    });
    assert.equal(html.includes("Thank you, Ama."), true);
    assert.equal(html.includes("You gave in 2 of 10 months."), true);
    assert.equal(html.includes(">DC<"), true);
    // A malformed mark colour falls back to navy.
    assert.equal(html.includes("background: #13426f; color: #ffffff"), true);
    assert.equal(html.toLowerCase().includes("gift"), false);
  });

  it("totals giving by month in the church's time zone", () => {
    const totals = lib.accumulateEntries(
      [{partnerId: "p", amount: 50, dateGiven: new Date("2026-09-30T23:30:00Z"), armName: "Tithe"}],
      new Date("2026-10-01T00:00:00Z"),
      new Date("2026-11-01T00:00:00Z"),
      () => 10,
    );
    assert.equal(totals.get("p").ytdByMonth.get(10), 50);
    assert.deepEqual(lib.monthsArray(totals.get("p").ytdByMonth, 3), [0, 0, 0]);
  });

  it("uses the Airport City key for that domain", () => {
    const prev = process.env.RESEND_AIRPORT_CITY_API_KEY;
    process.env.RESEND_AIRPORT_CITY_API_KEY = "re_test";
    try {
      const key = lib.resendKeyFor(
        "Partner Appreciation <pastor@theairportcitychurch.com>",
        "some-church",
      );
      assert.equal(key, "re_test");
      assert.equal(lib.resendKeyFor("Other <a@example.com>", "some-church"), undefined);
    } finally {
      if (prev === undefined) delete process.env.RESEND_AIRPORT_CITY_API_KEY;
      else process.env.RESEND_AIRPORT_CITY_API_KEY = prev;
    }
  });
});
