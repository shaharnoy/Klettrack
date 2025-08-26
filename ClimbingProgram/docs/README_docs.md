# ClimbingProgram - Architecture & Design Documentation

## 📱 App Overview
ClimbingProgram is a SwiftUI-based iOS application for tracking climbing training sessions, managing workout plans, and monitoring progress. The app follows a modular architecture with clear separation of concerns between data models, UI components, and business logic.

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    ClimbingProgram App                       │
├─────────────────────────────────────────────────────────────┤
│  SwiftUI + SwiftData Framework                              │
└─────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────┐
│                   App Layer                                 │
│  ┌─────────────────┐  ┌─────────────────┐                  │
│  │ ClimbingProgram │  │   RootTabView   │                  │
│  │     App.swift   │  │                 │                  │
│  └─────────────────┘  └─────────────────┘                  │
└─────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────┐
│                  Feature Layer                              │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────┐│
│  │   Catalog   │ │    Plans    │ │     Log     │ │Progress ││
│  │    View     │ │    Views    │ │    View     │ │  View   ││
│  └─────────────┘ └─────────────┘ └─────────────┘ └─────────┘│
└─────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────┐
│                  Data Layer                                 │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐           │
│  │   Models    │ │ Persistence │ │     I/O     │           │
│  │  (SwiftData)│ │   Layer     │ │  (CSV)      │           │
│  └─────────────┘ └─────────────┘ └─────────────┘           │
└─────────────────────────────────────────────────────────────┘
```

## 📊 Data Model Architecture

### Core Entity Relationships

```
Activity (1) ──────── (N) TrainingType
    │                        │
    │                        ├── (N) Exercise
    │                        └── (N) BoulderCombination ──── (N) Exercise
    │
    └── name: String
        types: [TrainingType]

Session (1) ──────── (N) SessionItem
    │                        │
    ├── date: Date            ├── exerciseName: String
    └── items: [SessionItem]  ├── planSourceId: UUID?
                              ├── reps, sets, weight
                              └── notes: String?

Plan (1) ──────── (N) PlanDay
    │                   │
    ├── name: String     ├── date: Date
    ├── kind: PlanKind   ├── type: DayType
    ├── startDate: Date  └── chosenExercises: [String]
    └── days: [PlanDay]
```

### Data Model Details

#### 1. **Exercise Catalog Models**
- **Activity**: Top-level category (Core, Antagonist, Climbing)
- **TrainingType**: Subcategory within activity (Anterior Core, Wrist Stabilizers)
- **Exercise**: Individual exercise with recommended reps/sets
- **BoulderCombination**: Special grouping for bouldering exercises

#### 2. **Session Tracking Models**
- **Session**: Workout session on a specific date
- **SessionItem**: Individual exercise performed with actual metrics
- **Plan Integration**: SessionItems can be linked to specific plans via `planSourceId`

#### 3. **Planning Models**
- **Plan**: Training plan template (Weekly, 3-2-1, 4-3-2-1)
- **PlanDay**: Specific day within a plan with chosen exercises
- **DayType**: Classification of training day intensity/focus

## 🔄 Data Flow Architecture

### 1. **App Initialization Flow**
```
ClimbingProgramApp.swift
        │
        ▼
    SwiftData Model Container Setup
        │
        ▼
    RootTabView.swift
        │
        ▼ 
    SeedData.loadIfNeeded() ──── Catalog Population
        │
        ▼
    Tab Views Ready for User Interaction
```

### 2. **Exercise Catalog Flow**
```
CatalogView ──► Activity List
     │
     ▼
TypesList ──► TrainingType Selection
     │
     ▼
ExercisesList ──► Individual Exercise Selection
     │
     ▼
Plan Integration (Add to PlanDay.chosenExercises)
```

### 3. **Plan Creation & Management Flow**
```
PlansListView ──► Plan Selection/Creation
     │
     ▼
PlanDetailView ──► Weekly/Monthly View
     │
     ▼
PlanDayEditor ──► Exercise Management
     │
     ├── Add from Catalog
     ├── Quick Log (✓ button)
     ├── Detailed Log (pencil button)
     └── Progress View (chart button)
```

### 4. **Logging Flow**
```
Exercise Selection
     │
     ├── Quick Log ──► SessionItem (no details)
     │                    └── notes: "Quick logged"
     │
     └── Detailed Log ──► SessionItem (full metrics)
                             ├── reps: Int?
                             ├── sets: Int?
                             ├── weightKg: Double?
                             └── notes: String?
```

## 🎨 UI Component Architecture

### Tab Structure
```
RootTabView
├── Tab 1: CatalogView (Browse exercises)
├── Tab 2: PlansListView (Manage training plans)
├── Tab 3: LogView (Direct exercise logging)
└── Tab 4: ProgressViewScreen (Analytics & charts)
```

### Key UI Patterns

#### 1. **Navigation Hierarchy**
- **List Views**: Display collections with navigation links
- **Detail Views**: Show specific item details with editing capabilities
- **Sheet Modals**: Used for creation, selection, and detailed forms

#### 2. **Data Binding Patterns**
- **@Query**: SwiftData automatic data fetching
- **@Environment(\.modelContext)**: Database operations
- **@State/@Binding**: Local state management

#### 3. **User Interaction Patterns**
- **Quick Actions**: Single-tap logging with green checkmark
- **Detailed Actions**: Multi-step forms for comprehensive data entry
- **Context Menus**: Additional options without cluttering UI

## 🔧 Module Responsibilities

### **App Layer** (`/app/`)
- **ClimbingProgramApp.swift**: Main app entry point, SwiftData setup
- **RootTabView.swift**: Primary navigation container, data seeding
- **RunOnce.swift**: Utility for one-time operations

### **Feature Layer** (`/features/`)
- **catalog/**: Exercise browsing and selection
- **plans/**: Training plan management and day-by-day tracking
- **sessions/**: Direct workout logging
- **analytics/**: Progress tracking and visualization
- **timer/**: Interval training and workout timing system

## ⏱️ Timer Module Architecture

The timer module provides a comprehensive interval training system with template management, customizable workout timers, and session tracking. This system integrates with the main app to enhance workout planning and execution.

### Timer System Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     Timer Module                            │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐│
│  │  TimerManager   │  │ Timer Templates │  │ Timer Sessions  ││
│  │  (State Logic)  │  │  (Presets)      │  │   (History)     ││
│  └─────────────────┘  └─────────────────┘  └─────────────────┘│
└─────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────┐
│                   Timer Components                          │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐│
│  │   TimerView     │  │  Template Mgmt  │  │  Custom Setup   ││
│  │ (Main Interface)│  │    Views        │  │     Views       ││
│  └─────────────────┘  └─────────────────┘  └─────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

### Core Timer Components

#### 1. **TimerManager** (`TimerManager.swift`)
Central state management class that handles all timer logic and coordination.

**Key Responsibilities:**
- **State Management**: Controls timer states (stopped, running, paused, completed)
- **Interval Logic**: Manages work/rest cycles and interval progressions
- **Time Calculations**: Tracks elapsed time, remaining time, and phase transitions
- **Audio Feedback**: Provides countdown beeps and phase transition sounds
- **Screen Management**: Keeps screen awake during active timer sessions
- **Session Integration**: Links timer sessions to workout plans and logging

**Core Properties:**
```swift
@Published var state: TimerState = .stopped
@Published var currentTime: Int = 0
@Published var totalElapsedTime: Int = 0
@Published var currentInterval: Int = 0
@Published var currentRepetition: Int = 0
@Published var currentPhase: IntervalPhase = .work
@Published var laps: [TimerLap] = []
```

**Timer States:**
- **Stopped**: Initial state, timer not running
- **Running**: Timer actively counting
- **Paused**: Timer temporarily halted but retains state
- **Completed**: Timer finished all configured intervals

#### 2. **Timer Data Models** (`TimerModels.swift`)

**TimerConfiguration:**
```swift
struct TimerConfiguration {
    let totalTimeSeconds: Int?              // Overall time limit
    let intervals: [IntervalConfiguration]  // Work/rest cycles
    let isRepeating: Bool                  // Repeat entire sequence
    let repeatCount: Int?                  // Number of repetitions
    let restTimeBetweenIntervals: Int?     // Rest between different intervals
}
```

**IntervalConfiguration:**
```swift
struct IntervalConfiguration {
    let name: String           // Interval description
    let workTimeSeconds: Int   // Active work period
    let restTimeSeconds: Int   // Rest period
    let repetitions: Int       // How many work/rest cycles
}
```

**Persistent Models:**
- **TimerTemplate**: Saved timer configurations for reuse
- **TimerInterval**: Individual interval definitions within templates
- **TimerSession**: Historical record of completed timer sessions
- **TimerLap**: Lap markers during timer execution

#### 3. **Timer User Interface** (`TimerViews.swift`)

**Main TimerView Features:**
- **Large Time Display**: Primary countdown/elapsed time (60pt monospaced font)
- **Progress Indicators**: Visual progress bars for overall and interval progress
- **Phase Indicators**: Color-coded work/rest status with remaining time
- **Control Buttons**: Start, pause, resume, lap, and stop functionality
- **Session Integration**: Links to plan days and exercise logging

**Screen Management:**
```swift
// Keeps screen on during timer sessions
UIApplication.shared.isIdleTimerDisabled = timerManager.isRunning || timerManager.isPaused
```

**Visual Design Patterns:**
- **Work Phase**: Green indicators and buttons
- **Rest Phase**: Orange indicators
- **Between Intervals**: Purple indicators for distinct rest periods
- **Completed**: Gray indicators when finished

#### 4. **Timer Templates** (`TimerTemplateViews.swift`)

**Template Management Features:**
- **Template Creation**: Save custom timer configurations
- **Template Library**: Browse and select from saved templates
- **Usage Tracking**: Track how often templates are used
- **Template Editing**: Modify existing timer configurations

**Template Integration:**
```swift
TimerTemplateSelector { template in
    let config = TimerConfiguration(from: template)
    timerManager.start(with: config, session: session)
}
```

### Timer Flow Architecture

#### 1. **Timer Setup Flow**
```
TimerView Launch
     │
     ▼
Timer Setup Options
     │
     ├── Load Template ──► TimerTemplateSelector ──► Pre-configured Timer
     │
     ├── Custom Timer ───► CustomTimerSetup ──────► User-defined Timer
     │
     └── Plan Integration ──► PlanDay Context ────► Plan-linked Session
```

#### 2. **Timer Execution Flow**
```
Timer Start
     │
     ▼
TimerManager.start()
     │
     ├── State: .running
     ├── Screen: Always On
     ├── Audio: Countdown Beeps
     └── Session: Created & Tracked
     │
     ▼
Interval Progression
     │
     ├── Work Phase ──► Rest Phase ──► Next Repetition
     │
     ├── Interval Complete ──► Next Interval (with rest)
     │
     └── All Intervals ──► Sequence Repeat (if enabled)
```

#### 3. **Timer Control Flow**
```
Running Timer
     │
     ├── Pause ──► State: .paused (Screen: Still On)
     │    │
     │    └── Resume ──► State: .running
     │
     ├── Lap ──► Add TimerLap ──► Continue Running
     │
     └── Stop ──► State: .stopped ──► Screen: Normal ──► Session: Saved
```

### Timer Integration Points

#### 1. **Plan Integration**
- **Plan Day Context**: Timers launched from PlanDayEditor include plan context
- **Exercise Correlation**: Timer sessions can be linked to specific exercises
- **Progress Tracking**: Timer usage contributes to overall training analytics

#### 2. **Session Tracking**
- **TimerSession Creation**: Each timer run creates a persistent session record
- **Metadata Capture**: Template name, plan context, duration, and completion status
- **Historical Analysis**: Timer sessions contribute to progress and usage analytics

#### 3. **Audio System**
- **Countdown Beeps**: 3-2-1 countdown at phase transitions
- **Phase Transitions**: Audio cues for work/rest changes
- **Completion Sounds**: Audio feedback when intervals or entire timer completes

### Timer Use Cases

#### 1. **Interval Training**
```
Example: "Hangboard Protocol"
- Work: 7 seconds hanging
- Rest: 53 seconds recovery
- Repetitions: 6 cycles
- Between Sets: 3 minutes rest
- Total Sets: 3
```

#### 2. **Circuit Training**
```
Example: "Core Circuit"
- Interval 1: Plank (30s work, 10s rest, 3 reps)
- Interval 2: Dead Bug (20s work, 10s rest, 4 reps)
- Interval 3: Superman (25s work, 15s rest, 3 reps)
- Rest Between Intervals: 60 seconds
```

#### 3. **Simple Countdown**
```
Example: "Rest Timer"
- Total Time: 5 minutes
- No intervals, just countdown
- Used between exercise sets
```

### Advanced Timer Features

#### 1. **Template System**
- **Reusable Configurations**: Save frequently used timer setups
- **Community Sharing**: Templates can be exported/imported via CSV
- **Usage Analytics**: Track which templates are most effective

#### 2. **Smart Progression**
- **Automatic Advancement**: Timer progresses through complex sequences
- **Visual Feedback**: Clear indication of current position in workout
- **Completion Tracking**: Records successful completion of timer protocols

#### 3. **Integration Benefits**
- **Plan Coordination**: Timer sessions enhance plan-based training
- **Progress Analytics**: Timer data contributes to overall training insights
- **Exercise Context**: Timers can be associated with specific exercises for targeted training

This timer module transforms the app from a simple exercise tracker into a comprehensive training system capable of guiding users through complex interval protocols while maintaining detailed records of their training sessions.
