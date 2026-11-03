import {describe, it} from "node:test";
import assert from "node:assert/strict";
import {mainArmNameById} from "../lib/arm_groups.js";

describe("reports name main arms only", () => {
  const names = mainArmNameById([
    {id: "venue", name: "Venue"},
    {id: "logistics", name: "Logistics", parentArmId: "venue"},
    {id: "ministry", name: "Ministry", parentArmId: null},
    {id: "rhapsody", name: "Rhapsody Of Realities", parentArmId: "ministry"},
    {id: "orphan", name: "Old Arm", parentArmId: "deleted"},
  ]);

  it("puts a sub-arm under its main arm", () => {
    assert.equal(names.get("logistics"), "Venue");
    assert.equal(names.get("rhapsody"), "Ministry");
  });

  it("keeps main arms and arms whose main is gone under their own name", () => {
    assert.equal(names.get("venue"), "Venue");
    assert.equal(names.get("ministry"), "Ministry");
    assert.equal(names.get("orphan"), "Old Arm");
  });
});
