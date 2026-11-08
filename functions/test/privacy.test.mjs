/** The server's duplicate rule must match the app's (entry_duplicate_utils.dart). */
import {createRequire} from "node:module";
import {describe, it} from "node:test";
import assert from "node:assert/strict";

const require = createRequire(import.meta.url);
const {isSimilar, dayIn} = require("../lib/privacy.js");

const c = {key: "k", partnerId: "p", armId: "a", periodId: "per", amountCedis: 100, dateGiven: new Date("2026-11-01T09:00:00Z")};
const e = {partnerId: "p", partnershipArmId: "a", partnershipPeriodId: "per", amountCedis: 100, dateGiven: new Date("2026-11-01T18:00:00Z")};

describe("findSimilarEntries rule", () => {
  it("matches the same partner, arm, period and day within 10%", () => {
    assert.equal(isSimilar(c, e, "Africa/Accra"), true);
    assert.equal(isSimilar({...c, amountCedis: 109}, e, "Africa/Accra"), true);
    assert.equal(isSimilar({...c, amountCedis: 111}, e, "Africa/Accra"), false);
  });
  it("needs the same arm, period and partner", () => {
    assert.equal(isSimilar({...c, armId: "b"}, e, "Africa/Accra"), false);
    assert.equal(isSimilar({...c, periodId: "x"}, e, "Africa/Accra"), false);
    assert.equal(isSimilar({...c, partnerId: "q"}, e, "Africa/Accra"), false);
  });
  it("compares days in the church's time zone", () => {
    assert.equal(isSimilar({...c, dateGiven: new Date("2026-11-02T00:30:00Z")}, e, "Africa/Accra"), false);
    assert.equal(dayIn(new Date("2026-11-01T23:30:00Z"), "Africa/Lagos"), "2026-11-02");
  });
});
