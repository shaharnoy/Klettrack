# SwiftUI Audit TODO (Skill + Apple Docs)

## Status key
- [ ] pending
- [x] done

## Per-file tasks

### ClimbingProgram/shared/ClimbLogForm.swift
- [x] Replace `foregroundColor` with `foregroundStyle`
- [x] Replace `showsIndicators: false` with `.scrollIndicators(.hidden)`
- [x] Replace tap-only interactive rows with `Button`
- [x] Replace `UIScreen.main.bounds` usage in media loading

### ClimbingProgram/features/climb/ClimbView.swift
- [x] Replace `UIScreen.main.bounds` usage in media loading
- [x] Replace row `onTapGesture` with `Button`
- [x] Move add-climb modal to item/route-based sheet

### ClimbingProgram/features/catalog/CatalogView.swift
- [x] Replace row `onTapGesture` with `Button`
- [x] Consolidate boolean sheets into route enum

### ClimbingProgram/features/sessions/LogView.swift
- [x] Replace row `onTapGesture` with `Button`
- [x] Consolidate boolean sheets into route enum where feasible

### ClimbingProgram/data/persistence/MediaManagerView.swift
- [x] Replace thumbnail `onTapGesture` with `Button`

### ClimbingProgram/features/plans/PlansViews.swift
- [x] Make `@State var plan` private
- [x] Convert new-plan boolean sheet to route/item presentation

### ClimbingProgram/app/RootTabView.swift
- [x] Convert settings boolean sheet to route/item presentation

### ClimbingProgram/app/SettingsSheet.swift
- [x] Collapse about/contribute booleans into enum-backed sheet

### ClimbingProgram/features/timer/TimerViews.swift
- [x] Consolidate boolean sheets into route enum

### ClimbingProgram/features/timer/TimerTemplatesListView.swift
- [x] Convert new-template boolean sheet to route/item presentation

### ClimbingProgram/features/timer/TimerTemplateViews.swift
- [x] Convert new-template boolean sheet to route/item presentation

### ClimbingProgram/features/analytics/ProgressViewScreen.swift
- [x] Remove `AnyView` type erasure with `@ViewBuilder`
- [x] Consolidate filter booleans into route enum for sheet presentation

### ClimbingProgram/shared/Undobanner.swift
- [x] Re-check GeometryReader usage and reduce if feasible

### ClimbingProgram/data/io/LogCSV.swift
- [x] Replace `String(format:)` numeric formatting with Swift formatting API
- [x] Add/adjust tests for formatting stability

### ClimbingProgram/features/sessions/LogView.swift
- [x] Consolidate remaining nested boolean sheets (`showingCatalogPicker`, `showingMultiExercisePicker`, `showingAddItem`, `showingAddClimb`) into route/item presentation where feasible

### ClimbingProgram/features/catalog/CatalogView.swift
- [x] Consolidate remaining boolean sheets (`showingEditAbout`, `showingNewExercise`, `showingNew`) into route/item presentation where feasible

### ClimbingProgram/features/plans/PlansViews.swift
- [x] Consolidate remaining boolean sheets (`showingCloneRecurringSheet`, `showingPicker`) into route/item presentation where feasible

### ClimbingProgram/features/climb/ClimbMetaManagerView.swift
- [x] Consolidate add-flow boolean sheets (`showingAddStyle`, `showingAddGym`, `showingAddDay`) into route/item presentation where feasible

### ClimbingProgram/features/analytics/ProgressViewScreen.swift
- [x] Re-check `GeometryReader` usage at all occurrences and replace/reduce with modern layout alternatives where feasible
