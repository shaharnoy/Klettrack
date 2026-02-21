import assert from "node:assert/strict";
import { parsePlanCsv, buildPlanImportMutations } from "../web/js/utils/planCsvImport.js";

function createStore(entities) {
  return {
    active(name) {
      return entities[name] || [];
    }
  };
}

function runIOSExportToWebImportCheck() {
  const csv = [
    "plan_name,plan_kind,plan_start_date,day_date,weekday,day_type,day_notes,exercise_order,exercise_name,activity_name,training_type_name,exercise_id",
    "Power Block,Weekly,2026-02-01,2026-02-01,Sunday,Power,\"Hard session, short rest\",1,Moonboard Limit,Climbing,Board,11111111-1111-1111-1111-111111111111",
    "Power Block,Weekly,2026-02-01,2026-02-02,Monday,Recovery,No loading,,,,,"
  ].join("\n");

  const parsed = parsePlanCsv(csv);
  assert.equal(parsed.errors.length, 0, `Unexpected parse errors: ${parsed.errors.join("; ")}`);
  assert.equal(parsed.planGroups.length, 1, "Expected a single plan group");

  const group = parsed.planGroups[0];
  assert.equal(group.days.length, 2, "Expected two day rows");

  const store = createStore({
    plans: [],
    plan_kinds: [{ id: "kind-1", name: "Weekly" }],
    day_types: [{ id: "type-1", name: "Power" }, { id: "type-2", name: "Recovery" }],
    activities: [{ id: "activity-1", name: "Climbing" }],
    training_types: [{ id: "training-1", name: "Board", activity_id: "activity-1" }],
    exercises: [{ id: "11111111-1111-1111-1111-111111111111", name: "Moonboard Limit", training_type_id: "training-1" }]
  });

  const result = buildPlanImportMutations({ group, store });
  assert.equal(result.summary.dayCount, 2, "Expected two imported days");
  assert.equal(result.summary.exerciseCount, 1, "Expected one imported exercise row");
}

runIOSExportToWebImportCheck();
console.log("Plan CSV contract check passed: iOS export -> Web import.");
