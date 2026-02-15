# Plan Import Across Web + iOS (Phase 5)

## Summary
Add a cross-platform **Training Plan Import** flow so a plan exported from web can be imported back into web and imported into iOS local data.  
Locked decisions from you:
- **Format:** current CSV schema (no new canonical format in this phase).
- **Import mode:** always create a **new** plan (never merge into existing plan).
- **Missing references:** auto-create placeholders (exercises/day types/kinds) so import still completes.

I aligned this plan with `swiftui-expert-skill` for iOS UX/state and used `supabase-postgres-best-practices` constraints for safe sync mutation batching/validation behavior.

## Scope
1. Web: add `Import CSV` action in Training Plans.
2. iOS: add `Import Plan CSV` in plans toolbar and settings where relevant.
3. Shared behavior parity:
- Parse existing exported CSV rows (one row per exercise, plus empty exercise rows for no-exercise days).
- Build a new plan from imported data.
- Preserve day setup and ordering.
- Create placeholders when linked entities are missing.

## Data/Behavior Spec

### CSV Input Contract (current format)
Accepted headers:
- `plan_name`
- `plan_kind`
- `plan_start_date`
- `day_date`
- `weekday`
- `day_type`
- `day_notes`
- `exercise_order`
- `exercise_name`
- `activity_name`
- `training_type_name`
- `exercise_id`

Rules:
1. Group rows by `(plan_name, plan_start_date)`; import one selected group per action.
2. Group plan days by `day_date`.
3. Day with no exercises is valid when exercise columns are empty.
4. Exercise order precedence:
- Use numeric `exercise_order` when valid.
- Fallback to row order within day.
5. Date parsing accepts `YYYY-MM-DD` only; invalid date rows are skipped and reported.
6. No logs/session/climb history imported.

### Always-create-new-plan policy
1. Import creates a new `Plan` record.
2. Default new name:
- `<plan_name> (Imported)`; collision-safe suffix if needed.
3. Start date:
- default from CSV `plan_start_date`.
- if invalid/missing, fallback to earliest imported `day_date`.
4. Imported plan kind:
- map by existing kind name.
- if missing, create placeholder kind.

### Placeholder policy
When references are missing, auto-create and continue:
1. `day_type` missing:
- create Day Type with imported name.
- assign internal key slug (hidden to users).
- assign default `color_key = gray`.
2. `exercise_id` not found and/or `exercise_name` not found:
- create placeholder exercise with imported `exercise_name` (or `Imported Exercise <n>`).
- attach to placeholder training type/activity when missing.
3. `training_type_name` missing:
- create placeholder training type under mapped/placeholder activity.
4. `activity_name` missing:
- create placeholder activity.
5. Placeholders are tagged in-app as imported placeholders so user can clean up later.

## Web Implementation

### Files
- `/Users/shahar/Desktop/code/ClimbingProgram/web/js/views/plansView.js`
- `/Users/shahar/Desktop/code/ClimbingProgram/web/js/utils/csvExport.js` (reuse parser helpers if present)
- `/Users/shahar/Desktop/code/ClimbingProgram/web/js/utils/` (new parser module)
- `/Users/shahar/Desktop/code/ClimbingProgram/web/js/bootstrap.js` (callback wiring + mutation pipeline)

### Changes
1. Add top action button: `Import CSV` beside existing plan actions.
2. Add file-picker flow (`.csv`) and parse client-side.
3. Show import preview modal:
- detected plan name/date
- days count
- exercises count
- placeholders to be created (activity/type/exercise/day type).
4. Confirm import executes one batched mutation flow:
- create plan
- create placeholder metadata as needed
- create plan_days with `day_type_id`, `daily_notes`, `chosen_exercise_ids`, `exercise_order_by_id`.
5. During import:
- lock Training Plans controls (disabled overlay on plan area).
- show single progress state (not per-row visual churn).
6. On success:
- hydrate once, select imported plan, toast summary.
7. On failure:
- inline error panel in import modal + toast fallback.

## iOS Implementation

### Files
- `/Users/shahar/Desktop/code/ClimbingProgram/ClimbingProgram/features/plans/PlansViews.swift`
- `/Users/shahar/Desktop/code/ClimbingProgram/ClimbingProgram/data/io/` (new `PlanCSV.swift` + document type)
- `/Users/shahar/Desktop/code/ClimbingProgram/ClimbingProgram/data/models/Plans.swift` (no schema changes expected)
- `/Users/shahar/Desktop/code/ClimbingProgram/ClimbingProgram/data/persistence/PlanFactory.swift` (reuse for plan/day creation)
- optional shared import service: `/Users/shahar/Desktop/code/ClimbingProgram/ClimbingProgram/data/io/PlanCSVImportService.swift`

### Changes
1. Add `Import plan from CSV` menu action in Plans toolbar.
2. Add `fileImporter` for CSV in Plans screen.
3. Parse CSV with same rules as web.
4. Build new local `Plan` + `PlanDay` objects with placeholders as needed.
5. Keep main actor-safe updates and observable refresh patterns.
6. Show progress + completion alert with counts:
- days imported
- exercises linked
- placeholders created.

## Sync and Consistency
1. Web import persists via existing sync endpoint using batched mutations.
2. iOS import writes to local SwiftData immediately.
3. iOS sync to cloud remains existing behavior; imported plan will sync on normal sync cycle.
4. No backend schema or Edge Function contract change required.

## Public Interfaces / Internal API Changes
1. Web `renderPlansView(...)` adds:
- `onImportPlanCsv(file)` callback
- `onImportPlanCsvConfirm(payload)` callback (or single combined callback with preview/confirm options).
2. New web utility parser:
- `parsePlanCsv(text) -> { planGroups, warnings, errors }`
- `buildPlanImportMutations(group, store) -> { mutations, summary }`
3. New iOS import utility:
- `PlanCSV.importPlanCSVAsync(...)` (mirrors async style used in `LogCSV`).

## Validation and Error UX
1. Hard failures (stop import):
- unreadable file
- missing required headers
- no valid day rows.
2. Soft failures (continue with warnings):
- bad `exercise_order`
- invalid optional columns per row.
3. Show user-facing report after import:
- created plan name
- skipped rows count
- placeholders created by type.

## Test Cases and Scenarios

### Web
1. Import a CSV previously exported from web: creates new plan with correct dates and exercise order.
2. Import file with unknown exercise IDs: placeholders created, day remains complete.
3. Import file with duplicate day rows/order gaps: deterministic order preserved.
4. Import disabled-state behavior: all plan controls blocked until batch completes.
5. Import large file (8+ weeks): one sync cycle behavior, no per-day flicker/conflict toasts.

### iOS
1. Import same CSV used on web: local plan parity (day count/order/notes/day type names).
2. Unknown refs create placeholders and import succeeds.
3. Invalid CSV headers show clear error alert and no partial writes.
4. Imported plan appears immediately in picker and opens correctly.
5. Subsequent sync sends imported plan without crashes/conflicts.

### Cross-platform parity
1. Export plan on web -> import into iOS -> re-export -> import into web succeeds.
2. Day notes, day types, and exercise ordering survive roundtrip.

## Assumptions and Defaults
1. This phase keeps **current CSV shape**; no v2 migration yet.
2. Recurring templates are not explicitly serialized in current CSV; import reconstructs day-by-day setup only.
3. Placeholder entities are user-editable later in Catalog/Data Manager.
4. Import is one-plan-per-run even if CSV accidentally contains multiple grouped plans.
5. Dates are interpreted in local calendar/time zone but stored as date-only semantics.
