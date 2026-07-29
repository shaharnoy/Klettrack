# Nested Sets and Reps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a rep-based timer run "5 sets × 3 reps" as fifteen efforts with a short rest between reps and a long one between sets, and stop reading the Reps field as a set count.

**Architecture:** `TimerManager.SetSequence` becomes an *effort* counter — `effortsPerSet × totalSets` — carrying two rest durations. On confirming an effort, `isLastRepOfSet` decides which rest runs. A continuous exercise has one effort per set, so every boundary is a set boundary and behaviour is byte-identical to today. Set membership is arithmetic, not stored, because nothing can widen a set.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, XCTest. iOS Simulator (iPhone 17).

## Global Constraints

- Spec: [`docs/specs/2026-07-29-nested-sets-and-reps-design.md`](../specs/2026-07-29-nested-sets-and-reps-design.md). It is authoritative; this plan implements it.
- Run tests with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` — the active developer dir is a Command Line Tools instance and `xcodebuild` fails without it.
- Full suite command: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -scheme ClimbingProgram -destination 'platform=iOS Simulator,name=iPhone 17'`
- **Never pipe `xcodebuild` into `tail`/`head`** — the pipeline's exit status is the filter's, not the build's. Redirect to a file, then grep.
- Baseline before starting: **304 tests passing**. No task may reduce that count except by deleting the `addSet` tests named in Task 1.
- New SwiftData fields must be **optional** with no default in the `@Model`, so the migration stays lightweight — follow `Exercise.shapeKey` as the precedent.
- New CSV columns are **appended** and resolved by name; the legacy positional fallback must stay untouched so older files import unchanged.
- Vocabulary: `SET` for the outer unit, `REP` for the inner one. The word `TRY` must not appear in any user-facing string when this is done.
- Commit messages: `type(scope): lowercase sentence`, a body explaining *why*, ending with `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`.
- Branch: `feat/nested-sets-and-reps`, already created off `7de9653`.

---

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `ClimbingProgram/data/models/LoggedSet.swift` | Add `setNumber` so a stored log keeps its bout structure | 1 |
| `ClimbingProgram/features/timer/TimerManager.swift` | Effort-based sequencing; two rests; delete `addSet` | 1 |
| `ClimbingProgramTests/SetSequenceTests.swift` | Nesting, rest choice, duration accounting, regression guard | 1 |
| `ClimbingProgram/data/models/Models.swift` | `Exercise.restBetweenRepsText` | 2 |
| `ClimbingProgram/features/timer/ExerciseTimerDefaults.swift` | Two rests in the plan; reps/sets unswapped | 2 |
| `ClimbingProgram/features/catalog/CatalogView.swift` | Editor row + derived-timer summary | 2 |
| `ClimbingProgram/features/timer/TimerViews.swift` | Call site, labels, rest wording | 2, 4 |
| `ClimbingProgram/data/io/LogCSV.swift` | `rest_between_reps` column | 3 |
| `ClimbingProgram/features/timer/TimerSpec.swift` | `restReps=` token | 3 |
| `ClimbingProgram/features/timer/SetLogPanel.swift` | Grouped chips; delete `AddSetChip` | 4 |
| `ClimbingProgram/data/models/ExerciseShape.swift` | Delete `unitLabel` | 4 |
| `ClimbingProgram/shared/LoggedSetsRow.swift` | Group the stored log by set | 4 |

---

### Task 1: Effort-based sequencing in TimerManager

**Files:**
- Modify: `ClimbingProgram/data/models/LoggedSet.swift`
- Modify: `ClimbingProgram/features/timer/TimerManager.swift:41-99` (`SetSequence`, log properties, `setStatus`), `:171-190` (`progressPercentage`), `:338-499` (sequencing)
- Modify: `ClimbingProgram/features/timer/TimerViews.swift:296-307` (the `startSetSequence` call site), `:86-105`, `:252-269` (renamed method calls)
- Modify: `ClimbingProgram/features/timer/SetLogPanel.swift` (renamed method calls only — the visual rework is Task 4)
- Test: `ClimbingProgramTests/SetSequenceTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces, for Tasks 2–4:
  - `TimerManager.SetSequence` with `effortsPerSet: Int`, `totalSets: Int`, `restBetweenRepsSeconds: Int`, `restBetweenSetsSeconds: Int`, `shape: ExerciseShape`, `currentEffort: Int`, `accumulatedSeconds: Int`, and computed `totalEfforts`, `currentSet`, `currentRep`, `isLastRepOfSet`, `isFinalEffort`, `isNested`, `restAfterCurrentEffort` — all `Int`/`Bool`.
  - `TimerManager.startSetSequence(reps: Int, sets: Int, restBetweenReps: Int, restBetweenSets: Int, seedWeightKg: Double?, shape: ExerciseShape, session: TimerSession?)`
  - `confirmEffort()`, `nextEffort()`, `previousEffort()`, `goToEffort(_ target: Int)`, `selectEffort(at index: Int)`, `effortStatus(at index: Int) -> SetStatus`, `finishSetSequence()`, `advanceSetSequence()`, `skipRest()`
  - `effortLogs: [LoggedSet]`, `editingEffortIndex: Int`, `performedEffortCount: Int`, `performedEffortLogs: [LoggedSet]`
  - `LoggedSet.setNumber: Int?`
  - **Removed:** `addSet()`, `setLogs`, `editingSetIndex`, `performedSetCount`, `performedSetLogs`, `confirmSet()`, `nextSet()`, `previousSet()`, `goToSet(_:)`, `selectSet(at:)`, `setStatus(at:)`, `SetSequence.repsPerSet`, `SetSequence.restSeconds`, `SetSequence.currentSet` (as a stored property), `SetSequence.isFinalSet`

- [ ] **Step 1: Add `setNumber` to `LoggedSet`**

In `LoggedSet.swift`, add the property after `note` and include it in `CodingKeys`:

```swift
    /// Perceived effort, 1...5. See `LoggedSet.effortLabels`.
    var rpe: Int?
    var note: String?
    /// Which set this effort belonged to, 1-based.
    ///
    /// Stored rather than derived because the log outlives the sequence that produced
    /// it: `SessionItem` has no rep count to reconstruct the grouping from, so without
    /// this a fifteen-effort boulder session reads back as a flat run of fifteen.
    /// `nil` on anything logged before this existed, and on hand-entered items.
    var setNumber: Int?

    /// `id` is identity for `ForEach` only. Leaving it out of the coding keys keeps
    /// exported cells small and stops a stale UUID surviving a CSV round-trip;
    /// the default value covers the decode.
    private enum CodingKeys: String, CodingKey { case reps, weightKg, rpe, note, setNumber }
```

- [ ] **Step 2: Write the failing tests for nesting**

Add to `SetSequenceTests.swift`, after the `makeManager`/`StubClock` helpers:

```swift
    // MARK: - Nested reps inside sets

    /// The reported case: 5 sets of 3 goes at the same boulder. Fifteen efforts, a short
    /// rest between goes and a long one between bouts.
    func testANestedSequenceRunsEveryRepOfEverySet() {
        let manager = makeManager()
        manager.startSetSequence(reps: 3, sets: 5, restBetweenReps: 30, restBetweenSets: 180,
                                 shape: .attempts, session: makeSession())

        let sequence = try? XCTUnwrap(manager.setSequence)
        XCTAssertEqual(sequence?.totalEfforts, 15)
        XCTAssertEqual(sequence?.effortsPerSet, 3)
        XCTAssertEqual(sequence?.currentSet, 1)
        XCTAssertEqual(sequence?.currentRep, 1)
        XCTAssertEqual(manager.effortLogs.count, 15)
        XCTAssertEqual(manager.effortLogs.map(\.setNumber).prefix(4), [1, 1, 1, 2])
    }

    /// Which rest runs is the whole point: short within a bout, long between them.
    func testTheRestBetweenRepsDiffersFromTheRestBetweenSets() {
        let manager = makeManager()
        manager.startSetSequence(reps: 3, sets: 2, restBetweenReps: 30, restBetweenSets: 180,
                                 shape: .attempts, session: makeSession())

        // Rep 1 → rep 2, still inside set 1.
        manager.confirmEffort()
        XCTAssertEqual(manager.configuration?.totalTimeSeconds, 30, "Between reps")
        manager.advanceSetSequence()

        // Rep 2 → rep 3, still inside set 1.
        manager.confirmEffort()
        XCTAssertEqual(manager.configuration?.totalTimeSeconds, 30)
        manager.advanceSetSequence()

        // Rep 3 is the last of set 1, so the next rest crosses into set 2.
        XCTAssertTrue(manager.setSequence?.isLastRepOfSet ?? false)
        manager.confirmEffort()
        XCTAssertEqual(manager.configuration?.totalTimeSeconds, 180, "Between sets")
        manager.advanceSetSequence()

        XCTAssertEqual(manager.setSequence?.currentSet, 2)
        XCTAssertEqual(manager.setSequence?.currentRep, 1)
    }

    /// No rep-rest means reps run continuously: five pull-ups in a row are one effort,
    /// not five. This is the guard that today's behaviour is untouched.
    func testWithoutARepRestTheSequenceIsOneEffortPerSet() {
        let manager = makeManager()
        let session = makeSession()
        manager.startSetSequence(reps: 5, sets: 3, restBetweenReps: 0, restBetweenSets: 180,
                                 shape: .weighted, session: session)

        let sequence = try? XCTUnwrap(manager.setSequence)
        XCTAssertEqual(sequence?.effortsPerSet, 1, "Not 5 — the reps aren't separate efforts")
        XCTAssertEqual(sequence?.totalEfforts, 3)
        XCTAssertEqual(manager.effortLogs.count, 3)
        XCTAssertEqual(manager.effortLogs.map(\.reps), [5, 5, 5], "Each log is a set of five")
        XCTAssertEqual(manager.effortLogs.map(\.setNumber), [1, 2, 3])

        manager.confirmEffort()
        XCTAssertEqual(manager.configuration?.totalTimeSeconds, 180)
    }

    /// A nested effort is a single rep, so it carries no rep count of its own.
    func testANestedEffortLogsNoRepCount() {
        let manager = makeManager()
        manager.startSetSequence(reps: 3, sets: 2, restBetweenReps: 30, restBetweenSets: 180,
                                 shape: .attempts, session: makeSession())

        XCTAssertTrue(manager.effortLogs.allSatisfy { $0.reps == nil })
    }

    /// Both rest lengths and the efforts themselves belong in the logged duration.
    func testNestedDurationCountsBothRestsAndTheEfforts() {
        let clock = StubClock()
        let manager = TimerManager(clock: clock)
        let session = makeSession()
        manager.startSetSequence(reps: 2, sets: 2, restBetweenReps: 30, restBetweenSets: 180,
                                 shape: .attempts, session: session)

        // set 1 rep 1 (10s) → 30s rest → rep 2 (10s) → 180s rest
        clock.advance(10); manager.confirmEffort()
        manager.totalElapsedTime = 30; manager.advanceSetSequence()
        clock.advance(10); manager.confirmEffort()
        manager.totalElapsedTime = 180; manager.advanceSetSequence()
        // set 2 rep 1 (10s) → 30s rest → rep 2 (10s) → finish
        clock.advance(10); manager.confirmEffort()
        manager.totalElapsedTime = 30; manager.advanceSetSequence()
        clock.advance(10); manager.confirmEffort()

        XCTAssertEqual(session.totalElapsedSeconds, 40 + 30 + 180 + 30)
        XCTAssertEqual(session.completedIntervals, 4, "Four efforts confirmed")
    }

    /// Nothing may push past the prescription — the plan is set in the catalog.
    func testNavigationCannotRunPastThePlan() {
        let manager = makeManager()
        manager.startSetSequence(reps: 3, sets: 1, restBetweenReps: 30, restBetweenSets: 0,
                                 shape: .attempts, session: makeSession())

        manager.goToEffort(99)
        XCTAssertEqual(manager.setSequence?.currentEffort, 3, "Clamped to the last effort")
        XCTAssertEqual(manager.effortLogs.count, 3, "No effort was invented")
    }
```

- [ ] **Step 3: Run the tests to verify they fail**

```bash
cd /Users/work-enrique/Projects/Klettrack
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -scheme ClimbingProgram -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:ClimbingProgramTests/SetSequenceTests > /tmp/t1.log 2>&1; echo "EXIT=$?"
grep -E "error:" /tmp/t1.log | head
```

Expected: compile errors — `startSetSequence` has no `restBetweenReps:` parameter, `confirmEffort` / `effortLogs` / `totalEfforts` are undefined.

- [ ] **Step 4: Replace `SetSequence`**

Replace `TimerManager.swift:41-61` entirely:

```swift
    struct SetSequence: Equatable {
        /// Efforts in each set: the rep count when a rest separates the reps, otherwise 1.
        /// Five continuous pull-ups are one effort, not five — you stop once, not five times.
        let effortsPerSet: Int
        let totalSets: Int
        /// 0 ⇒ the reps run continuously, so every boundary is a set boundary and this
        /// whole structure collapses to the flat sequence it replaced.
        let restBetweenRepsSeconds: Int
        let restBetweenSetsSeconds: Int
        /// Decides whether the log panel offers added load. Declared before the defaulted
        /// fields so it stays a required memberwise argument — a `let` *with* a default is
        /// left out of the memberwise init entirely, which would make it unsettable.
        let shape: ExerciseShape
        /// 1-based, counted across the whole exercise rather than within a set, so
        /// navigation and the performed high-water mark stay one-dimensional.
        var currentEffort: Int = 1
        /// How long the exercise has run: every effort and every rest so far, summed.
        ///
        /// Both, not just the rests. This is what the log's duration is read from, and
        /// counting only the rests reported a 3×3 min session as 6 minutes — with the
        /// final set, which has no rest after it, missing entirely.
        var accumulatedSeconds: Int = 0

        // Set membership is arithmetic because nothing can widen a single set: the plan
        // comes from the catalog and the timer can only under-deliver it.
        var totalEfforts: Int { effortsPerSet * totalSets }
        var currentSet: Int { (currentEffort - 1) / effortsPerSet + 1 }
        var currentRep: Int { (currentEffort - 1) % effortsPerSet + 1 }
        var isLastRepOfSet: Bool { currentRep == effortsPerSet }
        var isFinalEffort: Bool { currentEffort >= totalEfforts }
        var isNested: Bool { restBetweenRepsSeconds > 0 }

        /// The rest that runs once the current effort is confirmed.
        var restAfterCurrentEffort: Int {
            isLastRepOfSet ? restBetweenSetsSeconds : restBetweenRepsSeconds
        }

        /// Which set an effort index (0-based) belongs to, for seeding and reading the log.
        func setNumber(forEffortIndex index: Int) -> Int { index / effortsPerSet + 1 }
    }
```

- [ ] **Step 5: Rename the log properties**

`TimerManager.swift:63-99`. Rename `setLogs` → `effortLogs`, `editingSetIndex` → `editingEffortIndex`, `performedSetCount` → `performedEffortCount`, `performedSetLogs` → `performedEffortLogs`, `setStatus(at:)` → `effortStatus(at:)`, and make the status compare efforts:

```swift
    // MARK: Per-effort log

    /// One entry per planned effort, seeded when the sequence starts so that advancing
    /// past one you never touched still records it at its planned values.
    private(set) var effortLogs: [LoggedSet] = []

    /// Which effort the log panel is editing, 0-based. Independent of `currentEffort`:
    /// reviewing rep 1 mid-rest must not move the timer.
    private(set) var editingEffortIndex: Int = 0

    /// The weight every effort was seeded with, for the panel's "Last: N kg" caption.
    private(set) var seedWeightKg: Double?

    /// How many efforts were confirmed with Done. High-water mark, so stepping back to
    /// correct rep 2 of 4 doesn't retract reps 3 and 4.
    private(set) var performedEffortCount: Int = 0

    /// The efforts to write to the log: those confirmed, in order.
    var performedEffortLogs: [LoggedSet] {
        Array(effortLogs.prefix(performedEffortCount))
    }

    /// How an effort reads in the panel, derived rather than stored.
    enum SetStatus: Equatable { case done, current, upcoming }

    func effortStatus(at index: Int) -> SetStatus {
        guard let sequence = setSequence else { return .upcoming }
        let effort = index + 1
        if effort < sequence.currentEffort { return .done }
        if effort > sequence.currentEffort { return .upcoming }
        // The current effort counts as done once we've moved on to resting after it.
        return state == .awaitingUser ? .current : .done
    }
```

- [ ] **Step 6: Rewrite `startSetSequence`**

Replace `TimerManager.swift:338-370`:

```swift
    /// Begin a rep-based exercise. Lands on the first prompt with nothing counting;
    /// the caller supplies one session that spans the whole sequence.
    ///
    /// `restBetweenReps` is what decides the shape. Non-zero and each rep becomes its own
    /// effort with its own log row; zero and a set is one effort, which is what every
    /// continuous exercise wants and exactly what this did before nesting existed.
    ///
    /// `seedWeightKg` pre-fills every effort, so skipping ahead needs no special case —
    /// the row for an untouched effort already holds its planned values.
    func startSetSequence(
        reps: Int,
        sets: Int,
        restBetweenReps: Int,
        restBetweenSets: Int,
        seedWeightKg: Double? = nil,
        shape: ExerciseShape = .weighted,
        session: TimerSession? = nil
    ) {
        ticker?.stop()
        engine = nil
        lastSnapshot = nil
        self.session = session

        let repCount = max(1, reps)
        let nested = restBetweenReps > 0
        let sequence = SetSequence(
            effortsPerSet: nested ? repCount : 1,
            totalSets: max(1, sets),
            restBetweenRepsSeconds: max(0, restBetweenReps),
            restBetweenSetsSeconds: max(0, restBetweenSets),
            shape: shape
        )
        setSequence = sequence
        self.configuration = TimerConfiguration(totalTimeSeconds: sequence.restAfterCurrentEffort)

        self.seedWeightKg = seedWeightKg
        effortLogs = (0..<sequence.totalEfforts).map { index in
            LoggedSet(
                // A nested effort *is* one rep, so a count would be noise. A flat effort is
                // a whole set, and its count is the thing worth recording.
                reps: nested ? nil : Double(repCount),
                weightKg: seedWeightKg,
                setNumber: sequence.setNumber(forEffortIndex: index)
            )
        }
        editingEffortIndex = 0
        performedEffortCount = 0

        currentTime = 0
        totalElapsedTime = 0
        laps = []
        lastLapTime = 0
        state = .awaitingUser
        awaitingSince = clock.now()
        UIApplication.shared.isIdleTimerDisabled = true
        print("TimerManager.startSetSequence: \(sequence.totalSets) sets x \(sequence.effortsPerSet) efforts, rest \(restBetweenReps)s/\(restBetweenSets)s")
    }
```

`LoggedSet`'s memberwise init takes `setNumber` last and defaulted, so every existing call site still compiles.

- [ ] **Step 7: Rewrite the sequencing methods**

Replace `TimerManager.swift:372-499` (from `confirmSet` through `addSet`), keeping `bank(into:)` and `awaitingSince` exactly as they are:

```swift
    /// The user finished the current effort. Starts the appropriate rest, or finishes the
    /// sequence after the last effort (which has no trailing rest).
    func confirmEffort() {
        guard var sequence = setSequence, state == .awaitingUser else { return }
        // Done is the only thing that makes an effort count as performed. Skipping past
        // one with the chevron deliberately doesn't.
        performedEffortCount = max(performedEffortCount, sequence.currentEffort)

        // Bank the time the effort took before the rest's clock starts.
        bank(into: &sequence)
        setSequence = sequence

        if sequence.isFinalEffort {
            finishSetSequence()
            return
        }

        // Which rest runs is the whole nesting rule, in one line.
        // No get-ready: you tapped Done because the effort is over.
        // `start` leaves `setSequence` alone, so our bookkeeping survives it.
        start(
            with: TimerConfiguration(totalTimeSeconds: sequence.restAfterCurrentEffort, getReady: false),
            session: session
        )
    }

    /// End the current rest early and move straight to the next effort.
    /// The time actually rested still counts, so cutting a 3 min rest at 2 min logs 2 min.
    func skipRest() {
        guard setSequence != nil, !isAwaitingUser, state != .completed else { return }
        advanceSetSequence()
    }

    /// Called when a rest countdown finishes and efforts remain.
    /// Internal rather than private so tests can drive it without waiting out a real rest.
    func advanceSetSequence() {
        guard let sequence = setSequence else { return }
        goToEffort(sequence.currentEffort + 1)
    }

    /// Park on `target`'s prompt, 1-based across the whole exercise and clamped to it.
    /// Used by a rest completing, by Skip, and by the panel's arrows.
    ///
    /// Whatever has elapsed is banked first, so jumping — forwards or backwards — never
    /// invents or discards time. Clamping is also what stops navigation from growing the
    /// plan: there is no effort beyond `totalEfforts` to reach.
    func goToEffort(_ target: Int) {
        guard var sequence = setSequence, state != .completed else { return }
        let clamped = min(max(1, target), sequence.totalEfforts)
        // Already parked on that prompt: nothing to tear down.
        guard clamped != sequence.currentEffort || state != .awaitingUser else { return }

        bank(into: &sequence)
        sequence.currentEffort = clamped
        setSequence = sequence
        // Via `selectEffort` rather than assigning the index, so arriving by chevron and
        // arriving by chip tap carry the weight forward the same way.
        selectEffort(at: clamped - 1)

        ticker?.stop()
        engine = nil
        lastSnapshot = nil
        currentTime = 0
        totalElapsedTime = 0
        state = .awaitingUser
        awaitingSince = clock.now()
        print("TimerManager.goToEffort → set \(sequence.currentSet) rep \(sequence.currentRep)")
        playSound(.restToWork)
    }

    /// Forward one effort. From a prompt this is the skip: the effort keeps the values it
    /// was seeded with and is not counted as performed. Mid-rest it cuts the rest short.
    func nextEffort() {
        guard let sequence = setSequence, state != .completed else { return }
        guard isAwaitingUser else {
            skipRest()
            return
        }
        if sequence.isFinalEffort {
            finishSetSequence()
        } else {
            goToEffort(sequence.currentEffort + 1)
        }
    }

    /// Back one effort, to redo it or correct what was recorded. No-op on the first.
    func previousEffort() {
        guard let sequence = setSequence else { return }
        goToEffort(sequence.currentEffort - 1)
    }
```

`addSet()` is deleted outright: the plan comes from the catalog and the timer may only under-deliver it.

- [ ] **Step 8: Update `selectEffort` and `progressPercentage`**

Rename `selectSet(at:)` to `selectEffort(at:)` at `TimerManager.swift:510`, changing `setLogs` to `effortLogs` throughout its body. Then replace the set-sequence branch of `progressPercentage` (`TimerManager.swift:175-186`):

```swift
        // A set sequence's configuration describes one rest, so measuring time against it
        // would report that rest's progress instead of the exercise's. Count efforts
        // instead: each effort plus the rest that follows it is one equal slice.
        if let sequence = setSequence {
            let completed = Double(sequence.currentEffort - 1)
            // Waiting on an effort contributes nothing: the work itself isn't timed.
            var restFraction = 0.0
            let rest = sequence.restAfterCurrentEffort
            if !isAwaitingUser, rest > 0 {
                restFraction = min(1, Double(totalElapsedTime) / Double(rest))
            }
            return min(1, max(0, (completed + restFraction) / Double(max(1, sequence.totalEfforts))))
        }
```

- [ ] **Step 9: Fix `finishSetSequence`, `clearSetLogs` and `stop`**

In `finishSetSequence`, change `session.completedIntervals = performedSetCount` to `performedEffortCount`, and the print's `sequence.totalSets` to `sequence.totalEfforts`. In `clearSetLogs`, rename the properties and reset `performedEffortCount = 0`. `stop()` and `clearSetSequence()` need no logic change, only the renamed calls.

- [ ] **Step 10: Update the call sites**

- `TimerViews.swift:296-307` — `apply(_:)` passes the new parameters. The plan still carries one rest until Task 2, so pass `restBetweenReps: 0`:

```swift
        case .repBased(let reps, let sets, let restSeconds, let templateId):
            let session = TimerSession(
                templateId: templateId,
                planDayId: planDay?.id,
                exerciseName: exercise.exerciseName
            )
            context.insert(session)
            try? context.save()
            timerManager.startSetSequence(
                reps: reps ?? 1,
                sets: sets,
                // Task 2 replaces this with the exercise's own rest-between-reps.
                restBetweenReps: 0,
                restBetweenSets: restSeconds,
                seedWeightKg: exercise.shape.takesLoad
                    ? lastLoggedWeight(for: exercise.exerciseName, in: context)
                    : nil,
                shape: exercise.shape,
                session: session
            )
```

- `TimerViews.swift:324-326` — `logPrefill` reads `timerManager.performedEffortLogs`.
- `TimerViews.swift:96` — the nav row label still uses `sequence.currentSet`, which now computes. Leave the wording to Task 4.
- `TimerViews.swift:253` — `restSkipSection`'s `nextSet` uses `min(sequence.currentSet + 1, sequence.totalSets)`; unchanged for now.
- `SetLogPanel.swift` — mechanical renames only: `timerManager.setLogs` → `effortLogs`, `selectSet` → `selectEffort`, `setStatus` → `effortStatus`, `editingSetIndex` → `editingEffortIndex`, `confirmSet` → `confirmEffort`, `previousSet`/`nextSet` → `previousEffort`/`nextEffort`, `performedSetCount` → `performedEffortCount`. Delete the `if shape == .attempts { … AddSetChip … }` block and the `AddSetChip` struct.
- `SetLogPanel.swift:67` — the Done accessibility label references `sequence.restSeconds`; use `sequence.restAfterCurrentEffort`.

- [ ] **Step 11: Delete the obsolete `addSet` tests**

Remove from `SetSequenceTests.swift` every test naming `addSet` — including `testAddSetIsANoOpOnceCompleted` — and rename the remaining `confirmSet`/`nextSet`/`previousSet`/`goToSet`/`setLogs` references to the new API. Find them with:

```bash
grep -nE "addSet|confirmSet|nextSet|previousSet|goToSet|setLogs|performedSetCount|setStatus|selectSet" ClimbingProgramTests/SetSequenceTests.swift
```

- [ ] **Step 12: Run the tests to verify they pass**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -scheme ClimbingProgram -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:ClimbingProgramTests/SetSequenceTests > /tmp/t1.log 2>&1; echo "EXIT=$?"
echo "passed: $(grep -cE '^Test case .* passed' /tmp/t1.log)  failed: $(grep -cE '^Test case .* failed' /tmp/t1.log)"
```

Expected: EXIT=0, zero failures.

- [ ] **Step 13: Run the full suite**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -scheme ClimbingProgram -destination 'platform=iOS Simulator,name=iPhone 17' > /tmp/full.log 2>&1; echo "EXIT=$?"
grep -E "TEST SUCCEEDED|TEST FAILED" /tmp/full.log
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 14: Commit**

```bash
git add -A
git commit -F - <<'MSG'
feat(timer): a set sequence counts efforts, not sets

A rep-based sequence held one rest, and repsPerSet was a label the timer never
counted — so "5 sets x 3 reps", three goes at the same boulder with a short rest
between goes and a long one between bouts, had nowhere to live.

SetSequence now counts efforts across the whole exercise, carrying both rests.
On confirming one, isLastRepOfSet picks which rest runs; that single line is the
entire nesting rule. A continuous exercise has one effort per set, so every
boundary is a set boundary and it behaves exactly as before — five pull-ups in a
row are one effort, not five.

Set membership is arithmetic rather than stored, because nothing can widen a
set: addSet and the "+" chip are gone, so the plan comes from the catalog and
the timer may only under-deliver it. LoggedSet keeps a setNumber all the same —
the log outlives the sequence, and SessionItem has no rep count to rebuild the
grouping from.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
```

---

### Task 2: The catalog drives both rests

**Files:**
- Modify: `ClimbingProgram/data/models/Models.swift:59-101` (`Exercise`)
- Modify: `ClimbingProgram/features/timer/ExerciseTimerDefaults.swift:16-25` (`ExerciseTimerPlan`), `:98-160` (`plan(for:in:)`, `plan(from:)`)
- Modify: `ClimbingProgram/features/catalog/CatalogView.swift` (both `ExerciseEditSheet` call sites, `startNewExercise`, `openEditor`, the sheet's Form, `derivedTimerSummary`)
- Modify: `ClimbingProgram/features/timer/TimerViews.swift:287-307`
- Test: `ClimbingProgramTests/ExerciseTimerDefaultsTests.swift`

**Interfaces:**
- Consumes: `TimerManager.startSetSequence(reps:sets:restBetweenReps:restBetweenSets:seedWeightKg:shape:session:)` from Task 1.
- Produces: `Exercise.restBetweenRepsText: String?`; `ExerciseTimerPlan.repBased(reps: Int, sets: Int, restBetweenReps: Int, restBetweenSets: Int, templateId: UUID?)`.

- [ ] **Step 1: Write the failing tests**

Add to `ExerciseTimerDefaultsTests.swift`:

```swift
    // MARK: - Two rests

    func testARepRestMakesThePlanNested() throws {
        let activity = createTestActivity(name: "Bouldering")
        let type = createTestTrainingType(activity: activity, name: "Limit")
        let exercise = Exercise(name: "Boulder Limit Session", repsText: "3", setsText: "5",
                                restText: "3 min", shapeKey: ExerciseShape.attempts.rawValue)
        exercise.restBetweenRepsText = "30 sec"
        type.exercises.append(exercise)
        try context.save()

        guard case .repBased(let reps, let sets, let restReps, let restSets, _) =
                try XCTUnwrap(ExerciseTimerDefaults.plan(for: exercise, in: context))
        else { return XCTFail("Expected a rep-based plan") }

        XCTAssertEqual(reps, 3, "Reps mean reps")
        XCTAssertEqual(sets, 5, "Sets mean sets — not read from the reps field")
        XCTAssertEqual(restReps, 30)
        XCTAssertEqual(restSets, 180)
    }

    /// The conflation this whole change is about: the attempts branch used to read the
    /// Reps field as the set count, so 5 sets x 3 reps ran three sets and lost the five.
    func testAttemptsNoLongerReadRepsAsTheSetCount() throws {
        let activity = createTestActivity(name: "Bouldering")
        let type = createTestTrainingType(activity: activity, name: "Limit")
        let exercise = Exercise(name: "Boulder Campusing", repsText: "3", setsText: "5",
                                restText: "3 min", shapeKey: ExerciseShape.attempts.rawValue)
        type.exercises.append(exercise)
        try context.save()

        guard case .repBased(let reps, let sets, _, _, _) =
                try XCTUnwrap(ExerciseTimerDefaults.plan(for: exercise, in: context))
        else { return XCTFail("Expected a rep-based plan") }

        XCTAssertEqual(sets, 5)
        XCTAssertEqual(reps, 3)
    }

    /// "3 ascents · 3 min/asc" is one bout of three goes, three minutes apart. With a
    /// single set there are no set boundaries, so a lone rest can only mean between reps.
    func testALoneCountBecomesRepsInOneSetAndTheRestGoesBetweenThem() throws {
        let activity = createTestActivity(name: "Bouldering")
        let type = createTestTrainingType(activity: activity, name: "Limit")
        let exercise = Exercise(name: "Limit Boulders", repsText: "3 ascents",
                                durationText: "30 min", restText: "3 min/asc",
                                shapeKey: ExerciseShape.attempts.rawValue)
        type.exercises.append(exercise)
        try context.save()

        guard case .repBased(let reps, let sets, let restReps, let restSets, _) =
                try XCTUnwrap(ExerciseTimerDefaults.plan(for: exercise, in: context))
        else { return XCTFail("Expected rest to beat the 30 min session budget") }

        XCTAssertEqual(reps, 3)
        XCTAssertEqual(sets, 1)
        XCTAssertEqual(restReps, 180, "The lone rest separates the goes")
        XCTAssertEqual(restSets, 0)
    }

    /// A rep-based template already carries both rests; it was discarding one of them.
    func testARepBasedTemplateKeepsItsIntervalRest() throws {
        let template = TimerTemplate(name: "Limit bouts", isRepeating: true,
                                     repeatCount: 5, restTimeBetweenIntervals: 180,
                                     repsPerSet: 3)
        template.intervals.append(
            TimerInterval(name: "Go", workTimeSeconds: 0, restTimeSeconds: 30,
                          repetitions: 3, order: 0)
        )
        context.insert(template)
        try context.save()

        guard case .repBased(let reps, let sets, let restReps, let restSets, let id) =
                ExerciseTimerDefaults.plan(from: template)
        else { return XCTFail("Expected a rep-based plan") }

        XCTAssertEqual(reps, 3)
        XCTAssertEqual(sets, 5)
        XCTAssertEqual(restReps, 30, "The interval rest is the rest between reps")
        XCTAssertEqual(restSets, 180)
        XCTAssertEqual(id, template.id)
    }
```

- [ ] **Step 2: Run to verify they fail**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -scheme ClimbingProgram -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:ClimbingProgramTests/ExerciseTimerDefaultsTests > /tmp/t2.log 2>&1; echo "EXIT=$?"
```

Expected: compile errors — `restBetweenRepsText` undefined, `.repBased` has four associated values not five.

- [ ] **Step 3: Add the model field**

In `Models.swift`, after `restText`:

```swift
    var restText: String?
    /// Rest between the reps *inside* a set, where `restText` is the rest between sets.
    /// nil ⇒ the reps run continuously, which is most exercises.
    var restBetweenRepsText: String?
```

Add `restBetweenRepsText: String? = nil` to the initialiser after `restText`, and `self.restBetweenRepsText = restBetweenRepsText` to its body.

- [ ] **Step 4: Widen `ExerciseTimerPlan`**

```swift
enum ExerciseTimerPlan: Equatable {
    case durationBased(TimerConfiguration, templateId: UUID?)
    /// `restBetweenReps` of 0 means the reps run continuously and a set is one effort.
    case repBased(reps: Int, sets: Int, restBetweenReps: Int, restBetweenSets: Int, templateId: UUID?)

    var templateId: UUID? {
        switch self {
        case .durationBased(_, let id), .repBased(_, _, _, _, let id): return id
        }
    }
}
```

- [ ] **Step 5: Rewrite `plan(for:in:)`**

Replace the body after the attached-template check:

```swift
        let reps = parseCount(exercise.repsText) ?? 1
        let sets = parseCount(exercise.setsText, upperBound: true) ?? 1

        var restBetweenReps = parseSeconds(exercise.restBetweenRepsText) ?? 0
        var restBetweenSets = parseSeconds(exercise.restText) ?? 0

        // With a single set there are no set boundaries, so a lone rest can only be the
        // rest between reps. This is what makes "3 ascents · 3 min/asc" read as one bout
        // of three goes three minutes apart, rather than three goes with no rest at all.
        if sets == 1, restBetweenReps == 0, restBetweenSets > 0 {
            restBetweenReps = restBetweenSets
            restBetweenSets = 0
        }

        let hasRest = restBetweenReps > 0 || restBetweenSets > 0

        func repBasedPlan() -> ExerciseTimerPlan {
            .repBased(reps: reps, sets: sets, restBetweenReps: restBetweenReps,
                      restBetweenSets: restBetweenSets, templateId: nil)
        }

        // Attempts: a rest beats the duration, which is a session budget rather than a
        // work interval. A limit boulder is seeded with both — "30 min" and "3 min/asc" —
        // and counting down 30 blind minutes tells you nothing. Only the precedence is
        // special here; the counts above are read the same way for every shape.
        if exercise.shape == .attempts, hasRest {
            return repBasedPlan()
        }

        // Duration-based: the work itself is timed.
        if let work = parseSeconds(exercise.durationText), work > 0 {
            let repetitions = parseCount(exercise.repsText)
                ?? parseCount(exercise.setsText, upperBound: true)
                ?? 1
            let interval = IntervalConfiguration(
                name: exercise.name,
                workTimeSeconds: work,
                restTimeSeconds: restBetweenSets > 0 ? restBetweenSets : restBetweenReps,
                repetitions: max(1, repetitions)
            )
            return .durationBased(TimerConfiguration(intervals: [interval]), templateId: nil)
        }

        // Rep-based: nothing to time except the rests.
        if hasRest { return repBasedPlan() }

        return nil
    }
```

- [ ] **Step 6: Stop `plan(from:)` discarding the interval rest**

```swift
    /// A template's own plan, independent of any exercise.
    static func plan(from template: TimerTemplate) -> ExerciseTimerPlan {
        if let reps = template.repsPerSet {
            return .repBased(
                reps: max(1, reps),
                sets: max(1, template.repeatCount ?? 1),
                // The template has carried this all along — it was simply thrown away.
                restBetweenReps: template.intervals.sorted { $0.order < $1.order }
                    .first?.restTimeSeconds ?? 0,
                restBetweenSets: template.restTimeBetweenIntervals ?? 0,
                templateId: template.id
            )
        }
        return .durationBased(template.makeConfiguration(), templateId: template.id)
    }
```

- [ ] **Step 7: Wire the call site**

`TimerViews.swift` — replace the `restBetweenReps: 0` placeholder from Task 1:

```swift
        case .repBased(let reps, let sets, let restBetweenReps, let restBetweenSets, let templateId):
            let session = TimerSession(
                templateId: templateId,
                planDayId: planDay?.id,
                exerciseName: exercise.exerciseName
            )
            context.insert(session)
            try? context.save()
            timerManager.startSetSequence(
                reps: reps,
                sets: sets,
                restBetweenReps: restBetweenReps,
                restBetweenSets: restBetweenSets,
                seedWeightKg: exercise.shape.takesLoad
                    ? lastLoggedWeight(for: exercise.exerciseName, in: context)
                    : nil,
                shape: exercise.shape,
                session: session
            )
```

Also update `logPrefill`'s `.repBased` pattern to five bindings: `case .repBased(let reps, let sets, _, _, _):`.

- [ ] **Step 8: Add the catalog editor row**

In `CatalogView.swift`, add `@State private var draftRestBetweenReps = ""` alongside `draftRest` in both `TrainingTypeDetailView` and `CombinationDetailView`; pass `restBetweenReps: $draftRestBetweenReps` to both `ExerciseEditSheet` call sites in each; set it in `startNewExercise` (`draftRestBetweenReps = ""`) and `openEditor` (`draftRestBetweenReps = ex.restBetweenRepsText ?? ""`); and write it on save:

```swift
                ex.restBetweenRepsText = draftRestBetweenReps.isEmpty ? nil : draftRestBetweenReps
```

For the new-exercise paths, set it after `ensureExercise`/`Exercise(...)` returns, since the initialiser call there is already long:

```swift
                    ex.restBetweenRepsText = draftRestBetweenReps.isEmpty ? nil : draftRestBetweenReps
```

In `ExerciseEditSheet`, add `@Binding var restBetweenReps: String` and a field directly after the Rest field, matching the surrounding style:

```swift
                    LabeledContent {
                        TextField("e.g. 30 sec", text: $restBetweenReps)
                            .multilineTextAlignment(.trailing)
                    } label: {
                        Text("Rest between reps")
                    }
```

- [ ] **Step 9: Teach the derived-timer summary about both rests**

Replace `derivedTimerSummary`'s rep-based cases so the editor shows what will actually happen:

```swift
    private var derivedTimerSummary: String {
        let setRest = ExerciseTimerDefaults.parseSeconds(rest)
        let repRest = ExerciseTimerDefaults.parseSeconds(restBetweenReps)
        let setCount = ExerciseTimerDefaults.parseCount(sets, upperBound: true) ?? 1
        let repCount = ExerciseTimerDefaults.parseCount(reps) ?? 1

        if shape == .attempts, (setRest ?? 0) > 0 || (repRest ?? 0) > 0 {
            return nestedSummary(sets: setCount, reps: repCount, setRest: setRest, repRest: repRest)
        }

        if let work = ExerciseTimerDefaults.parseSeconds(duration), work > 0 {
            let restPart: String = setRest.map { ", \(readable($0)) rest" } ?? ""
            return "Duration-based: \(readable(work)) work\(restPart)."
        }

        if (setRest ?? 0) > 0 || (repRest ?? 0) > 0 {
            return nestedSummary(sets: setCount, reps: repCount, setRest: setRest, repRest: repRest)
        }

        return "No timer can be derived — attach a template, or add a duration or rest."
    }

    /// Says the two-level shape out loud, because a rest in the wrong box is invisible
    /// until you are mid-session.
    private func nestedSummary(sets: Int, reps: Int, setRest: Int?, repRest: Int?) -> String {
        // Mirrors plan(for:in:): with one set, a lone rest separates the reps.
        var betweenReps = repRest ?? 0
        var betweenSets = setRest ?? 0
        if sets == 1, betweenReps == 0, betweenSets > 0 {
            betweenReps = betweenSets
            betweenSets = 0
        }

        if betweenReps > 0 {
            let setPart = betweenSets > 0 ? ", \(readable(betweenSets)) between sets" : ""
            return "\(sets) sets of \(reps) reps: \(readable(betweenReps)) between reps\(setPart)."
        }
        return "\(sets) sets of \(reps) reps, \(readable(betweenSets)) between sets."
    }
```

- [ ] **Step 10: Run the tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -scheme ClimbingProgram -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:ClimbingProgramTests/ExerciseTimerDefaultsTests > /tmp/t2.log 2>&1; echo "EXIT=$?"
echo "passed: $(grep -cE '^Test case .* passed' /tmp/t2.log)  failed: $(grep -cE '^Test case .* failed' /tmp/t2.log)"
```

Expected: EXIT=0. **`testWeightedPullUpsClassifyAsRepBased` will need its pattern widened to five bindings** — it asserts `sets == 6` and `reps == 5`, which still hold.

- [ ] **Step 11: Run the full suite, then commit**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -scheme ClimbingProgram -destination 'platform=iOS Simulator,name=iPhone 17' > /tmp/full.log 2>&1; echo "EXIT=$?"
grep -E "TEST SUCCEEDED|TEST FAILED" /tmp/full.log
git add -A
git commit -F - <<'MSG'
fix(catalog): reps mean reps, and an exercise can carry both rests

plan(for:in:) read the Reps field as the set count for attempts exercises, so a
bouldering exercise set to 5 sets of 3 ran three sets and silently dropped the
five. That line was the sets/reps conflation, and it is gone: counts are read
the same way for every shape.

Only the precedence part of the attempts branch survives, because it was doing
two unrelated jobs. A limit boulder is seeded with both "30 min" and "3 min/asc",
and a rest has to beat the duration or the timer counts down thirty blind
minutes instead of running the protocol.

Exercise gains restBetweenRepsText, so the catalog can say both rests. With a
single set there are no set boundaries, so a lone rest is taken as the rest
between reps — which is what makes "3 ascents · 3 min/asc" one bout of three
goes three minutes apart.

TimerTemplate needed no change: it has carried an interval rest and a
between-sets rest all along, and plan(from:) was throwing the first away.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
```

---

### Task 3: Carry the second rest through the CSV and TimerSpec

**Files:**
- Modify: `ClimbingProgram/data/io/LogCSV.swift:63` (header), `:121-153` + `:168-198` + `:231-262` (row builders), `:435-458` (`ParsedEntry`), `:493-497` (`Cols`), `:572` + `:605-607` + `:640-642` + `:713-715` (extraction), `:1112-1125` (`CatalogCandidate`), `:781-791` (candidate collection), `:1185-1200` (healing)
- Modify: `ClimbingProgram/features/timer/TimerSpec.swift:32-101`
- Test: `ClimbingProgramTests/ImportExportTests.swift`

**Interfaces:**
- Consumes: `Exercise.restBetweenRepsText` (Task 2), `LoggedSet.setNumber` (Task 1).
- Produces: CSV column `rest_between_reps` at index 33; `TimerSpec` token `restReps=`.

- [ ] **Step 1: Write the failing tests**

```swift
    /// Both rests survive a round trip, so an imported plan arrives able to nest.
    func testRestBetweenRepsSurvivesExportImport() async throws {
        let activity = createTestActivity(name: "Bouldering")
        let type = createTestTrainingType(activity: activity, name: "Limit")
        let exercise = Exercise(name: "Nested Boulder", repsText: "3", setsText: "5",
                                restText: "3 min", shapeKey: ExerciseShape.attempts.rawValue)
        exercise.restBetweenRepsText = "30 sec"
        type.exercises.append(exercise)

        let planKind = try ensurePlanKind(context, key: "weekly", name: "Weekly")
        let plan = Plan(name: "Nest Block", kind: planKind, startDate: parseDay("2026-05-04"))
        let day = PlanDay(date: parseDay("2026-05-04"))
        day.chosenExercises = ["Nested Boulder"]
        plan.days.append(day)
        context.insert(plan)
        try context.save()

        let exported = LogCSV.makeExportCSV(context: context).csv
        XCTAssertTrue(exported.contains("30 sec"), "The rep rest is in the file")

        type.exercises.removeAll { $0.name == "Nested Boulder" }
        context.delete(exercise)
        try context.save()

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rep_rest_rt.csv")
        try exported.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try await LogCSV.importCSVAsync(from: url, into: context, tag: "rt", dedupe: true)

        let restored = try XCTUnwrap(exercise(named: "Nested Boulder"))
        XCTAssertEqual(restored.restBetweenRepsText, "30 sec")
        XCTAssertEqual(restored.restText, "3 min")
    }

    /// Per-effort rows keep the bout they belonged to.
    func testSetNumberSurvivesThePerSetDetailColumn() {
        let sets = [
            LoggedSet(reps: nil, weightKg: nil, rpe: 4, note: "crux", setNumber: 1),
            LoggedSet(reps: nil, weightKg: nil, rpe: 5, note: nil, setNumber: 2)
        ]
        let decoded = [LoggedSet].csvDecoded(sets.csvEncoded)
        XCTAssertEqual(decoded.map(\.setNumber), [1, 2])
    }

    func testTimerSpecCarriesBothRests() throws {
        let template = TimerTemplate(name: "Bouts", isRepeating: true, repeatCount: 5,
                                     restTimeBetweenIntervals: 180, repsPerSet: 3)
        template.intervals.append(
            TimerInterval(name: "Go", workTimeSeconds: 0, restTimeSeconds: 30,
                          repetitions: 3, order: 0)
        )
        let spec = TimerSpec.encode(template)
        XCTAssertEqual(spec, "reps=3;sets=5;rest=180;restReps=30")

        let draft = try XCTUnwrap(TimerSpec.decode(spec))
        XCTAssertEqual(draft.repsPerSet, 3)
        XCTAssertEqual(draft.repeatCount, 5)
        XCTAssertEqual(draft.restBetweenSeconds, 180)
        XCTAssertEqual(draft.restBetweenRepsSeconds, 30)
    }

    /// A spec written before the token existed still decodes.
    func testATimerSpecWithoutTheRepRestStillDecodes() throws {
        let draft = try XCTUnwrap(TimerSpec.decode("reps=5;sets=3;rest=180"))
        XCTAssertEqual(draft.restBetweenRepsSeconds, 0)
    }
```

- [ ] **Step 2: Run to verify they fail**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -scheme ClimbingProgram -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:ClimbingProgramTests/ImportExportTests > /tmp/t3.log 2>&1; echo "EXIT=$?"
```

Expected: compile error on `restBetweenRepsSeconds`, and assertion failures on the round trip.

- [ ] **Step 3: Extend `TimerSpec`**

Add `var restBetweenRepsSeconds: Int = 0` to `TimerTemplateDraft`, include it in `==`, emit it in the rep-based branch of `encode` when non-zero, decode `"restreps"`, and pass it into the first interval in `makeTemplate`:

```swift
        if let reps = template.repsPerSet {
            tokens.append("reps=\(reps)")
            tokens.append("sets=\(max(1, template.repeatCount ?? 1))")
            tokens.append("rest=\(template.restTimeBetweenIntervals ?? 0)")
            let repRest = template.intervals.sorted { $0.order < $1.order }
                .first?.restTimeSeconds ?? 0
            if repRest > 0 { tokens.append("restReps=\(repRest)") }
            return tokens.joined(separator: ";")
        }
```

```swift
            case "restreps": draft.restBetweenRepsSeconds = Int(value) ?? 0
```

In `makeTemplate`, a rep-based draft with a rep rest needs an interval to hold it, because that is where `plan(from:)` reads it:

```swift
        // A rep-based template keeps its rest between reps on an interval, which is
        // where plan(from:) looks for it.
        if draft.repsPerSet != nil, draft.restBetweenRepsSeconds > 0, draft.intervals.isEmpty {
            template.intervals.append(
                TimerInterval(name: "Rep", workTimeSeconds: 0,
                              restTimeSeconds: draft.restBetweenRepsSeconds,
                              repetitions: max(1, draft.repsPerSet ?? 1), order: 0)
            )
        }
```

- [ ] **Step 4: Add the CSV column**

Append `,rest_between_reps` to the header string at `LogCSV.swift:63`. Add to the `catalogColumns(for:)` helper so all three row builders pick it up in one place:

```swift
        func catalogColumns(for exerciseName: String) -> [String] {
            let path = catalogPathByName[exerciseName]
            let exercise = exerciseByName[exerciseName]
            return [
                csvEscape(path?.activity ?? ""),
                csvEscape(path?.type ?? ""),
                exercise?.shapeKey ?? "",
                csvEscape(exercise?.restBetweenRepsText ?? "")
            ]
        }
```

The climb row builder writes literals, so add one more `""` there with the comment `// rest_between_reps (climbs don't use this)`.

- [ ] **Step 5: Parse it**

Add `static let restBetweenReps = ["rest_between_reps", "restbetweenreps"]` to `Cols`; add `restBetweenRepsStr` to the `let` declaration list; assign `val(parts, Cols.restBetweenReps)` in the header branch and `""` in the legacy branch; add `restBetweenRepsText: restBetweenRepsStr.isEmpty ? nil : restBetweenRepsStr` to `ParsedEntry` and its construction; add the same field to `CatalogCandidate` and its construction; and heal it in `ensureCatalogEntries`:

```swift
                if existing.restBetweenRepsText == nil {
                    existing.restBetweenRepsText = trimmedOrNil(meta.restBetweenRepsText)
                }
```

For newly created exercises, set it after `CatalogSeeder.ensureExercise` returns, next to `created.shapeKey`:

```swift
                created.restBetweenRepsText = trimmedOrNil(meta.restBetweenRepsText)
```

- [ ] **Step 6: Update the header-structure test**

`testCSVExportStructure` asserts the exact header. Append `"rest_between_reps"` to `expectedFields`.

- [ ] **Step 7: Run tests and commit**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -scheme ClimbingProgram -destination 'platform=iOS Simulator,name=iPhone 17' > /tmp/full.log 2>&1; echo "EXIT=$?"
grep -E "TEST SUCCEEDED|TEST FAILED" /tmp/full.log
git add -A
git commit -F - <<'MSG'
feat(import): carry the rest between reps through the CSV

A plan CSV could describe a nested exercise's counts but not its shape: with one
rest column, an imported "5 sets x 3 reps" arrived with no rest between the reps
and ran flat. Appends rest_between_reps, resolved by name like the columns before
it, so older files import unchanged.

TimerSpec gains restReps= for the same reason, and materialises it as an interval
on decode — that is where plan(from:) reads a template's rest between reps.

sets_detail carries setNumber now, so a re-imported boulder session keeps its
bouts instead of flattening to fifteen numbered lines.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
```

---

### Task 4: The screen says sets and reps

**Files:**
- Modify: `ClimbingProgram/data/models/ExerciseShape.swift:42-45` (delete `unitLabel`)
- Modify: `ClimbingProgram/features/timer/SetLogPanel.swift` (`SetLogPanel`, `SetChipStrip`, `SetChip`, `SetEffortBar`, `SetNoteField`, `SetNavigationRow`)
- Modify: `ClimbingProgram/features/timer/TimerViews.swift:86-105` (nav row label), `:252-269` (`restSkipSection`)
- Modify: `ClimbingProgram/shared/LoggedSetsRow.swift`
- Test: `ClimbingProgramTests/LoggedSetTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 1–3.
- Produces: no new API. `ExerciseShape.unitLabel` is removed.

**Deliberately untouched:** the weight stepper's visibility. It already keys on
`sequence.shape.takesLoad`, so an attempts effort shows effort and note only, exactly as the spec
requires — no change needed, and changing it would be scope creep.

- [ ] **Step 1: Write the failing test for the log's grouping**

```swift
    /// A nested session reads back as bouts, not as a flat run of fifteen.
    func testGroupingAPerEffortLogBySet() {
        let sets = [
            LoggedSet(rpe: 3, setNumber: 1),
            LoggedSet(rpe: 4, setNumber: 1),
            LoggedSet(rpe: 5, setNumber: 2)
        ]
        XCTAssertEqual(sets.groupedBySet.map(\.setNumber), [1, 2])
        XCTAssertEqual(sets.groupedBySet.map { $0.efforts.count }, [2, 1])
    }

    /// Hand-logged and pre-nesting rows have no set number; they stay one flat group.
    func testUngroupedLogsStayFlat() {
        let sets = [LoggedSet(reps: 5, weightKg: 40), LoggedSet(reps: 5, weightKg: 40)]
        XCTAssertEqual(sets.groupedBySet.count, 1)
        XCTAssertNil(sets.groupedBySet.first?.setNumber)
    }
```

- [ ] **Step 2: Run to verify it fails**

Expected: `groupedBySet` is undefined.

- [ ] **Step 3: Add the grouping helper**

In `LoggedSet.swift`, in the existing `extension Array where Element == LoggedSet`:

```swift
    /// The log split into bouts for display. One group with a `nil` number when the
    /// entries carry no set — hand-logged items, and anything written before nesting.
    var groupedBySet: [(setNumber: Int?, efforts: [LoggedSet])] {
        guard contains(where: { $0.setNumber != nil }) else {
            return isEmpty ? [] : [(nil, self)]
        }
        return Dictionary(grouping: self) { $0.setNumber }
            .sorted { ($0.key ?? .max) < ($1.key ?? .max) }
            .map { (setNumber: $0.key, efforts: $0.value) }
    }
```

- [ ] **Step 4: Group the stored log's display**

Rewrite `LoggedSetsRow`'s body so a nested log reads as bouts, and give `LoggedSetLine` the right noun:

```swift
    var body: some View {
        if !sets.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(sets.groupedBySet.enumerated()), id: \.offset) { _, group in
                    VStack(alignment: .leading, spacing: 2) {
                        if let number = group.setNumber {
                            Text("Set \(number)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        ForEach(Array(group.efforts.enumerated()), id: \.element.id) { index, set in
                            LoggedSetLine(
                                number: index + 1,
                                unit: group.setNumber == nil ? "Set" : "Rep",
                                set: set
                            )
                        }
                    }
                }
            }
        }
    }
```

and in `LoggedSetLine`, add `var unit: String = "Set"` and render `Text("\(unit) \(number)")`.

- [ ] **Step 5: Delete `unitLabel`**

Remove from `ExerciseShape.swift`:

```swift
    /// The noun for one unit of work, for the timer's set chips and navigation row.
    var unitLabel: String {
        self == .attempts ? "TRY" : "SET"
    }
```

The noun now follows the sequence's structure, not the exercise's shape, so it belongs at the call sites below rather than on the enum.

- [ ] **Step 6: Group the live chips and fix the wording**

In `SetLogPanel.swift`, replace `SetChipStrip` so nested sequences get one captioned row per set:

```swift
struct SetChipStrip: View {
    let timerManager: TimerManager
    let sequence: TimerManager.SetSequence

    var body: some View {
        if sequence.isNested {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(1...sequence.totalSets, id: \.self) { set in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SET \(set)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        chips(forSet: set)
                    }
                }
            }
        } else {
            chips(forSet: nil)
        }
    }

    /// The chips for one set, or all of them when the sequence is flat.
    private func chips(forSet set: Int?) -> some View {
        FlowLayout(spacing: 8, rowSpacing: 8) {
            ForEach(indices(forSet: set), id: \.self) { index in
                Button {
                    timerManager.selectEffort(at: index)
                } label: {
                    SetChip(
                        number: sequence.isNested
                            ? index % sequence.effortsPerSet + 1
                            : index + 1,
                        unit: sequence.isNested ? "REP" : "SET",
                        log: timerManager.effortLogs[index],
                        status: timerManager.effortStatus(at: index),
                        isSelected: index == timerManager.editingEffortIndex
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func indices(forSet set: Int?) -> [Int] {
        guard let set else { return Array(timerManager.effortLogs.indices) }
        return timerManager.effortLogs.indices.filter {
            timerManager.effortLogs[$0].setNumber == set
        }
    }
}
```

Update `SetLogPanel`'s call to `SetChipStrip(timerManager: timerManager, sequence: sequence)`, and its `unit:` arguments for `SetEffortBar` and `SetNoteField` to `sequence.isNested ? "rep" : "set"`. Fix the Done accessibility label to say `"Rep"`/`"Set"` the same way.

- [ ] **Step 7: Fix the two labels in TimerViews**

The awaiting-set nav row (`TimerViews.swift:94`):

```swift
                                label: sequence.isNested
                                    ? "REP \(sequence.currentRep) OF \(sequence.effortsPerSet) · SET \(sequence.currentSet) OF \(sequence.totalSets)"
                                    : "SET \(sequence.currentSet) OF \(sequence.totalSets)",
```

And `restSkipSection`, where the rest that is running is the one *after* the effort just confirmed, so `isLastRepOfSet` tells you which:

```swift
    private func restSkipSection(_ sequence: TimerManager.SetSequence) -> some View {
        // Mid-rest, currentEffort is still the one just finished, so this reads the rest
        // that is actually running rather than the next one.
        let crossingSets = sequence.isLastRepOfSet
        let nextEffort = min(sequence.currentEffort + 1, sequence.totalEfforts)
        let nextSet = (nextEffort - 1) / sequence.effortsPerSet + 1
        let nextRep = (nextEffort - 1) % sequence.effortsPerSet + 1

        return VStack(spacing: 6) {
            SetNavigationRow(
                timerManager: timerManager,
                sequence: sequence,
                label: crossingSets && sequence.isNested ? "REST BETWEEN SETS" : "REST",
                labelColor: crossingSets && sequence.isNested ? .purple : .orange
            )

            Text(sequence.isNested
                 ? "Next up: rep \(nextRep) of \(sequence.effortsPerSet) · set \(nextSet) of \(sequence.totalSets)"
                 : "Next up: set \(nextSet) of \(sequence.totalSets)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
```

`SetNavigationRow`'s Previous button is disabled on `sequence.currentSet <= 1`; change to `sequence.currentEffort <= 1`.

- [ ] **Step 7b: Fix the weight stepper's caption**

`SetWeightStepper` renders `Text("Set \(index + 1)")` from the *effort* index, so a nested
weighted exercise — cluster sets, three sets of five singles — would caption rep 1 of set 2 as
"Set 6". Attempts hide the stepper entirely so this never showed before, but nesting is not
attempts-only. Give it the same treatment as the chips:

```swift
struct SetWeightStepper: View {
    let timerManager: TimerManager
    let index: Int
    let weightKg: Double?
    let seedWeightKg: Double?
    let status: TimerManager.SetStatus
    /// What this effort is called — "Set 3", or "Rep 2" inside a nested set.
    let caption: String
```

replacing the `Text("Set \(index + 1)")` with `Text(caption)`, and passing from `SetLogPanel`:

```swift
                        caption: sequence.isNested
                            ? "Rep \(timerManager.editingEffortIndex % sequence.effortsPerSet + 1)"
                            : "Set \(timerManager.editingEffortIndex + 1)",
```

- [ ] **Step 8: Confirm `TRY` is gone**

```bash
grep -rniE "\btry\b" ClimbingProgram --include=*.swift | grep -viE "try\?|try await|try context|try XCTUnwrap|do \{|// |/// "
```

Expected: no user-facing string matches.

- [ ] **Step 9: Run the full suite and commit**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -scheme ClimbingProgram -destination 'platform=iOS Simulator,name=iPhone 17' > /tmp/full.log 2>&1; echo "EXIT=$?"
grep -E "TEST SUCCEEDED|TEST FAILED" /tmp/full.log
git add -A
git commit -F - <<'MSG'
feat(timer): the screen says sets and reps

The chips were labelled TRY while the row beneath them read "set 3 of 4" — two
nouns for one counter, and neither of them the level the timer was actually
counting. Nested sequences now show a captioned row of REP chips per SET, and
flat ones keep the single run of SET chips they always had.

The noun follows the sequence's structure rather than the exercise's shape, so
ExerciseShape.unitLabel is deleted rather than reworded: bouldering stops having
its own dialect.

Two rests read differently now that there are two. Between reps is REST in
orange; between sets is REST BETWEEN SETS in purple, reusing the colour the
engine already gives that phase.

The stored log groups by bout too, so a fifteen-effort session reads back as five
sets of three instead of a flat run of fifteen.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
```

---

## Manual verification

Install **over** the existing build rather than deleting the app, so the `restBetweenRepsText` migration runs against real data.

1. Catalog → create an exercise: Reps `3`, Sets `5`, Rest `3 min`, Rest between reps `30 sec`. The summary should read *"5 sets of 3 reps: 30 sec between reps, 3 min between sets."*
2. Add it to a plan day, start its timer. Expect five captioned rows of three `REP` chips, and `REP 1 OF 3 · SET 1 OF 5` on the card.
3. Done → a 30 second `REST` in orange. Done twice more → a 3 minute `REST BETWEEN SETS` in purple.
4. Finish after two bouts. The log should show two sets of three, grouped, with per-rep effort ratings.
5. A `Weighted Pull-Ups`-style exercise with Rest between reps left blank must behave exactly as before: one chip per set, one rest length, `SET n` labels.
6. Export, delete the exercise from the catalog, re-import — both rests and the shape come back.
