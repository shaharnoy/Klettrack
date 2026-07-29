# Nested sets and reps in the rep-based timer

**Date:** 2026-07-29
**Status:** approved, not yet implemented

## Problem

A rep-based exercise is described as "5 sets × 3 reps", and for wall work those three reps
are three goes at the same boulder: you rest a short time between goes, and a longer time
between bouts. The timer models none of that.

`TimerManager.SetSequence` is flat. It holds one `restSeconds`, and `repsPerSet` is a
**display label only** — the prompt reads "3 reps", you tap Done once, and one rest runs. There
is no rep-level counting and nowhere to put a second rest duration.

The conflation is visible on screen. `ExerciseTimerDefaults.plan(for:in:)` contains, in its
attempts branch:

```swift
sets: parseCount(exercise.repsText, upperBound: true)
    ?? parseCount(exercise.setsText, upperBound: true)
    ?? 10
```

The **Reps** field is read as the **set** count. So a bouldering exercise configured with 5 sets
and 3 reps runs three sets and ignores the five, while the chips are labelled `TRY` and the row
beneath them says `Next up: set 3 of 4` — two nouns for one counter, neither of them right.

Two capabilities already exist and are being discarded:

- `TimerTemplate` carries **both** rests — `restTimeBetweenIntervals` (between sets) and
  `TimerInterval.restTimeSeconds` (between reps). `Models.swift` says so in a comment. But
  `ExerciseTimerDefaults.plan(from:)` throws the interval rest away for rep-based templates.
- `Exercise` carries only `restText`, so a catalog exercise cannot express both.

## Decisions

| Question | Decision |
|---|---|
| Where does rest-between-reps come from? | A new `Exercise.restBetweenRepsText`, with an editor row and a CSV column. Existing `restText` keeps meaning rest-between-sets. |
| What is one chip? | Whatever you rest after. Rep-rest present → a chip per rep, grouped by set. Absent → a chip per set, exactly as today. |
| A bouldering exercise with only a Reps count? | Reps in one set. `3 ascents` is one bout of three goes. |
| Wording | `SET` outside, `REP` inside. `ExerciseShape.unitLabel` — the source of `TRY` — is deleted, not reworded. |

## Model

A sequence becomes an ordered list of **efforts**, each tagged with the set it belongs to.

```
Boulder Limit Session — 5 sets × 3 reps, 30s between reps, 3min between sets

effort:  1   2   3    4   5   6    7   8   9   ...
set:     1   1   1    2   2   2    3   3   3
rest:      30s 30s  3m  30s 30s  3m  30s 30s
```

```swift
struct SetSequence: Equatable {
    /// One entry per effort, in order; the value is its 1-based set number.
    /// A list rather than a (sets × reps) pair, so `addRep` can widen a single
    /// set without the others having to match.
    var setNumbers: [Int]
    let restBetweenRepsSeconds: Int   // 0 ⇒ reps run continuously
    let restBetweenSetsSeconds: Int
    let shape: ExerciseShape
    var currentEffort: Int = 1        // 1-based index into setNumbers
    var accumulatedSeconds: Int = 0

    var totalSets: Int { setNumbers.last ?? 1 }
    var currentSet: Int { setNumbers[currentEffort - 1] }
    var isNested: Bool { restBetweenRepsSeconds > 0 }
    var isFinalEffort: Bool { currentEffort >= setNumbers.count }
}
```

`setNumbers` is never empty and `currentEffort` is always a valid index into it: the initialiser
clamps reps and sets to at least 1, as `startSetSequence` already does with `max(1, sets)`, and
`goToEffort` clamps its target the way `goToSet` does today. `currentSet` therefore subscripts
without a guard, and `totalSets` needs none either.

**One rule replaces the flat/nested distinction.** On confirming effort *i*:

- next effort is in the **same** set → run `restBetweenRepsSeconds`
- next effort is in a **new** set → run `restBetweenSetsSeconds`
- no next effort → finish

A continuous exercise is one effort per set, so every boundary is a set boundary and the rest
that runs is the same one that runs today. Nothing about `Weighted Pull-Ups` changes.

`addRep()` (the `+`, still attempts-only) inserts the current set's number after that set's last
effort, and inserts a matching `LoggedSet` at the same index. On a limit session `+` means *one
more go at this problem*, not an extra bout.

## Data changes

| Where | Change | Compatibility |
|---|---|---|
| `Exercise` | `restBetweenRepsText: String?` | Additive optional; lightweight migration, as `shapeKey` was |
| Catalog editor | One row under Rest; derived-timer summary describes both rests | — |
| `LoggedSet` | `setNumber: Int?` | Codable; rows written before this decode as `nil` |
| CSV | `rest_between_reps` column appended; `sets_detail` JSON gains `setNumber` | Resolved by name, so older files import unchanged |
| `TimerTemplate` | **None** | Already carries both rests |
| `ExerciseTimerPlan` | `.repBased(reps:sets:restBetweenReps:restBetweenSets:templateId:)` | Internal |
| `TimerSpec` | Rep-based encoding gains a `restReps=` token | Absent on decode ⇒ 0 |

## `plan(for:in:)`

The attempts branch keeps its **precedence** rule and loses its **count** rule. Those were two
separate things sharing a branch, and only the second was wrong:

- *Kept:* for `.attempts`, a rest beats a duration. A limit boulder is seeded with both `30 min`
  and `3 min/asc`; counting down thirty blind minutes tells you nothing. Deleting this outright
  would regress every seeded bouldering exercise into a duration timer.
- *Removed:* reading `repsText` as the set count. Reps mean reps and sets mean sets, for every
  shape. Missing sets ⇒ 1; missing reps ⇒ 1.

So `3 ascents · 3 min/asc` resolves to one set of three reps with three minutes between them —
which is what the phrase means, and what the athlete does.

## UI

- **Chips.** Nested: one row per set, captioned `SET n`, chips labelled `REP n`. Flat: today's
  single wrapped run of `SET n` chips, ungrouped. The noun follows what the chip *is*, which is a
  property of the sequence's structure, not of the exercise's shape — which is why `unitLabel`
  goes away rather than being renamed.
- **Two rests read differently.** `REST` in orange between reps; `REST BETWEEN SETS` in purple
  between sets, reusing the `.betweenSets` phase colour `getPhaseColor()` already defines.
- **The nav row and the "next up" line** carry both counters when nested —
  `Next up: rep 1 of 3 · set 3 of 5` — and only the set when flat. This replaces the hardcoded
  `"Next up: set \(nextSet) of ..."`.
- **Weight stepper** stays hidden for attempts, so a boulder rep shows effort and note only.
- `TRY` disappears from every site that renders it — the chip, the nav row, the Done accessibility
  label, *"How hard was this try?"*, the note placeholder, and `Add another try`. Five read it from
  `unitLabel`; the sixth hardcodes the word.

## Testing

Extending `SetSequenceTests`:

- The rest **kind** chosen at each boundary: rep-rest within a set, set-rest across one.
- The stub clock proving both rest lengths and the efforts themselves land in
  `totalElapsedSeconds` — the accounting fixed in `3dcfbc4` must survive nesting.
- `addRep` widening one set without disturbing the others, and its `LoggedSet` landing in the
  right group.
- `performedSetCount` → per-effort, and `finishSetSequence` mid-set logging only confirmed efforts.
- **A regression guard**: an exercise with no rep-rest produces exactly today's behaviour —
  effort count, rest durations, and logged output all unchanged.

`ExerciseTimerDefaultsTests`: reps/sets no longer swapped for attempts; a lone reps count giving
one set; rest-beats-duration still holding for attempts.

`ImportExportTests`: the new column round-trips; a CSV without it still imports.

## Out of scope

- `TimerEngine` still has no test coverage. The set sequence leans on it harder after this.
- Duration-based exercises already nest through `TimerConfiguration.intervals` +
  `restTimeBetweenIntervals`; this changes nothing there.
- Per-set weight for nested reps. Attempts take no load, and no book protocol asks for a
  different weight per rep within a set.

## Delivery

A separate branch and PR. PR #29 is coherent as it stands and has just been through review; this
touches `TimerManager`'s core sequencing, `Exercise`, the catalog editor and the CSV, and should
be reviewed on its own.
