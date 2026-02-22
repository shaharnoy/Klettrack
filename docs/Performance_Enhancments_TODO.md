# Performance Enhancements TODO

Date: 2026-02-22
Source: Deferred from `PerformanceOptimizationPlan.md` per Shahar Decisions.
Scope: Cases intentionally not implemented now, but retained for future optimization cycles.

## Case 2: Quick Progress sheet fetches all sessions while rendering

File references:
- `/Users/shahar/Desktop/code/ClimbingProgram/ClimbingProgram/features/plans/PlansViews.swift:1973`
- `/Users/shahar/Desktop/code/ClimbingProgram/ClimbingProgram/features/plans/PlansViews.swift:1984`

1. Issue
`rows()` fetches all `Session` records and flattens them each time body reads `let recent = rows().suffix(10)`.

2. Why it is important
This can block sheet presentation and scrolling in the progress screen, especially if session volume is high. It also duplicates work because `load()` calls `rows()` again.

3. How to reproduce in the app
1. Build a dataset with many sessions (for example 2000+ sessions and many items).
2. Open a plan day and open quick progress for an exercise.
3. Repeat opening/closing the progress sheet several times.
4. Observe delayed sheet presentation or temporary freezes.
5. Confirm in Time Profiler that session fetch/flatten/sort repeats on the main thread during presentation.

4. Suggested solution
Query only relevant records for the selected exercise and date window, and compute once per sheet lifecycle. Avoid calling fetch-heavy methods from body; load asynchronously in `.task(id:)` and render from state.

5. Potential down/upstream impact
Upstream impact: data query semantics must remain equivalent (same ordering and notes inclusion).
Downstream impact: faster sheet open time and less jank in chart/list updates.

6. Tests to add
Performance test: quick-progress open latency with large seeded session history.
Functional test: verify recent logs and chart points match baseline logic for the same exercise.
Regression test: ensure reopening sheet does not refetch entire dataset unnecessarily.

## Case 5: Combined Log list recomputes full grouping during render

File references:
- `/Users/shahar/Desktop/code/ClimbingProgram/ClimbingProgram/features/sessions/LogView.swift:1010`
- `/Users/shahar/Desktop/code/ClimbingProgram/ClimbingProgram/features/sessions/LogView.swift:1036`
- `/Users/shahar/Desktop/code/ClimbingProgram/ClimbingProgram/features/sessions/LogView.swift:1042`

1. Issue
`groupedData` and `sortedDates` are computed properties rebuilding dictionary/grouping repeatedly. Body then re-reads `groupedData` in `ForEach`.

2. Why it is important
With larger histories, repeated O(N) recomputation during list updates/scrolling causes visible jank and can look like hangs.

3. How to reproduce in the app
1. Import or seed many sessions and climbs across many dates.
2. Open the combined log screen and scroll quickly.
3. Perform row deletions and return to the list.
4. Observe hitching and delayed row interactions.

4. Suggested solution
Compute grouped view-model data once per source change (memoized/state-backed), not per render pass. Rebuild only when sessions/climbEntries actually change.

5. Potential down/upstream impact
Upstream impact: invalidation logic must be reliable after edits/deletes.
Downstream impact: smoother list scroll and faster updates after mutations.

6. Tests to add
Performance test: list render/scroll workload with large mixed dataset.
Functional test: day counts and navigation targets remain correct after grouping refactor.
Deletion regression test: delete rows and verify grouped totals update exactly once.

## Case 6: Analytics view triggers heavy recompute storms on main actor

File references:
- `/Users/shahar/Desktop/code/ClimbingProgram/ClimbingProgram/features/analytics/ProgressViewScreen.swift:421`
- `/Users/shahar/Desktop/code/ClimbingProgram/ClimbingProgram/features/analytics/ProgressViewScreen.swift:569`
- `/Users/shahar/Desktop/code/ClimbingProgram/ClimbingProgram/features/analytics/ProgressViewScreen.swift:1180`
- `/Users/shahar/Desktop/code/ClimbingProgram/ClimbingProgram/features/analytics/ProgressViewScreen.swift:1271`
- `/Users/shahar/Desktop/code/ClimbingProgram/ClimbingProgram/features/analytics/ProgressViewScreen.swift:1294`

1. Issue
`ClimbStatsVM` is `@MainActor`; `recomputeAll()` performs multi-pass filtering and aggregation over all climbs. It is triggered by many `.onChange` handlers, including per-keystroke search, with duplicate triggers for climb type.

2. Why it is important
This creates high-frequency heavy work on the UI thread and can freeze interactions while typing or toggling filters.

3. How to reproduce in the app
1. Seed/import a large climb history.
2. Open analytics/progress screen.
3. Type quickly in search field and toggle multiple filters in succession.
4. Observe lagging controls and delayed chart updates.
5. Inspect with Time Profiler; main thread time concentrates in recompute pipeline.

4. Suggested solution
Coalesce trigger events (debounce/throttle), remove duplicate onChange paths, and move heavy aggregation off main actor with cancellation-aware tasks. Publish only final reduced result back on main actor.

5. Potential down/upstream impact
Upstream impact: asynchronous recompute introduces out-of-order result risk unless stale tasks are canceled.
Downstream impact: large responsiveness improvement for analytics interactions.

6. Tests to add
Performance test: rapid filter/search interaction benchmark with large dataset.
Concurrency regression test: newest filter state always wins (no stale result overwrite).
Functional test: KPI/distribution values match baseline for fixed fixture dataset.

## Case 7: Climb list filtering does multi-pass work inside render-used computed property

File references:
- `/Users/shahar/Desktop/code/ClimbingProgram/ClimbingProgram/features/climb/ClimbView.swift:69`
- `/Users/shahar/Desktop/code/ClimbingProgram/ClimbingProgram/features/climb/ClimbView.swift:448`
- `/Users/shahar/Desktop/code/ClimbingProgram/ClimbingProgram/features/climb/ClimbView.swift:462`

1. Issue
`filteredClimbs` performs repeated filtering and date min/max scans and is read multiple times by the same render path (`isEmpty` check and `ForEach`).

2. Why it is important
As climb count grows, frequent recomputation during list updates and search input increases UI latency and battery/cpu cost.

3. How to reproduce in the app
1. Seed/import thousands of climb entries.
2. Open climb list.
3. Type in search and switch date/type/WIP/resend filters quickly.
4. Observe list hitching and delayed row refresh.

4. Suggested solution
Compute filtered results once per dependency change and store in view model/state, or memoize within a lightweight derived-state layer. Avoid multiple reads that retrigger full pipelines in one render cycle.

5. Potential down/upstream impact
Upstream impact: filtered-state invalidation must include all filter inputs and source list changes.
Downstream impact: smoother list interactions and faster filter response.

6. Tests to add
Performance test: filter/search benchmark on large climb fixture.
Functional test: all filter combinations return expected record IDs.
Regression test: clearing filters restores exact full list ordering.

## Case 8: Media picker preview generation does synchronous image requests on main actor

File references:
- `/Users/shahar/Desktop/code/ClimbingProgram/ClimbingProgram/shared/ClimbLogForm.swift:226`
- `/Users/shahar/Desktop/code/ClimbingProgram/ClimbingProgram/shared/ClimbLogForm.swift:1214`
- `/Users/shahar/Desktop/code/ClimbingProgram/ClimbingProgram/shared/ClimbLogForm.swift:1228`
- `/Users/shahar/Desktop/code/ClimbingProgram/ClimbingProgram/shared/ClimbLogForm.swift:1233`

1. Issue
Media preview loading runs on `@MainActor`, loops through selected items, and uses `PHImageRequestOptions.isSynchronous = true`.

2. Why it is important
Selecting multiple photos/videos, especially cloud-backed media, can block the UI thread long enough to feel like a hang.

3. How to reproduce in the app
1. Open climb log form.
2. Select many media items (for example 15-30), including videos and iCloud items.
3. Immediately interact with form controls while previews load.
4. Observe delayed taps/scrolling and possible temporary freeze.

4. Suggested solution
Load thumbnails asynchronously off main actor, keep ordering by index, and append results in batched main-actor updates. Keep placeholder/progress UI visible while work is in flight.

5. Potential down/upstream impact
Upstream impact: asynchronous loading can change preview arrival order unless explicitly stabilized.
Downstream impact: significantly better form responsiveness during media attachment.

6. Tests to add
Functional test: selected media order and type mapping remain correct after async pipeline.
Performance test: selecting N media items keeps main-thread blocking below threshold.
UI regression test: form remains interactive while thumbnails are loading.
