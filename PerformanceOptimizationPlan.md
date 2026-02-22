# Performance Optimization Plan

Date: 2026-02-22
Scope: Active work approved by Shahar Decisions.
Status: Updated after applying decisions.

## Case 1: Plan Day editor render-path catalog work

**Shahar Decision**:
- Implement tests first (heavy-load performance + functional), then review results before deciding on a code optimization.

Implementation status:
- Added functional and performance tests in:
  - `/Users/shahar/Desktop/code/ClimbingProgram/ClimbingProgramTests/PlanDayCatalogRenderPathTests.swift`
- After tests passed, implemented the render-path optimization in:
  - `/Users/shahar/Desktop/code/ClimbingProgram/ClimbingProgram/features/plans/PlansViews.swift`

Implemented tests:
1. `testGroupingFunctionalBehavior_ManualOrderLoggedAndCatalogFallback`
2. `testGroupingReflectsCatalogChangesAfterRecompute`
3. `testGroupingHeavyLoadPerformance`

Optimization changes applied:
1. Added cached `ExerciseCatalogInfo` metadata in `PlanDayEditorCache`.
2. Updated `groupedChosenExercises()` to use pre-warmed cache metadata instead of fetching catalog entities on render path.
3. Populated exercise-to-activity metadata during cache warmup (`warmCachesIntoCache()`).
4. Removed the unused fetch-heavy helper `sortedChosenExercises()`.

## Case 3: Plan Day cache store unbounded growth

**Shahar Decision**:
- Implement as suggested.

Implementation status:
- Implemented bounded cache behavior in:
  - `/Users/shahar/Desktop/code/ClimbingProgram/ClimbingProgram/features/plans/PlansViews.swift`

Changes applied:
1. Added stale-entry pruning window (TTL).
2. Added max-entry bound with LRU-like trimming.
3. Added memory-pressure cleanup path.
4. Added lifecycle hooks to prune cache during disappear/background.
5. Added cache access tracking to keep active day cache hot.

## Case 4: Daily notes saved on every keystroke

**Shahar Decision**:
- Implement as suggested.

Implementation status:
- Implemented debounced notes persistence with lifecycle flush in:
  - `/Users/shahar/Desktop/code/ClimbingProgram/ClimbingProgram/features/plans/PlansViews.swift`

Changes applied:
1. Debounced note saves (coalesced writes).
2. Persist-on-background and persist-on-disappear safeguards.
3. Pending task cancellation to avoid redundant write storms.
4. Unified pending change flush to reduce save frequency.

## Deferred Cases (Not Implemented Now)

Per decision, these were moved to:
- `/Users/shahar/Desktop/code/ClimbingProgram/docs/Performance_Enhancments_TODO.md`

Moved cases:
1. Case 2
2. Case 5
3. Case 6
4. Case 7
5. Case 8

## Removed From Plan

Per decision, these were removed from active tracking:
1. Case 9
2. Case 10
