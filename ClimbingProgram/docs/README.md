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

### **Data Layer** (`/data/`)
- **models/**: SwiftData entity definitions
- **persistence/**: Data seeding, factory patterns, utilities
- **io/**: Import/export functionality (CSV)

### **Design Layer** (`/design/`)
- **Theme.swift**: Color schemes, typography, spacing constants

### **Shared Layer** (`/shared/`)
- **SharedSheet.swift**: Reusable UI components

## 🔄 Key Design Patterns

### 1. **Repository Pattern**
- SwiftData handles data persistence automatically
- Context injection through SwiftUI environment
- Centralized model container configuration

### 2. **Factory Pattern**
- **PlanFactory**: Creates plan templates with appropriate day structures
- **SeedData**: Populates initial exercise catalog

### 3. **Observer Pattern**
- SwiftUI's reactive data binding
- @Query automatically updates views when data changes
- Environment-based dependency injection

### 4. **Strategy Pattern**
- **PlanKind**: Different plan generation strategies
- **DayType**: Different day type behaviors and UI representation

## 📱 User Journey Flow Charts

### Exercise Selection Journey
```
Start ──► Catalog Tab ──► Activity ──► TrainingType ──► Exercise
                                                         │
                                                         ▼
                                              Add to Plan ──► PlanDay
                                                         │
                                                         ▼
                                                    Save & Complete
```

### Workout Logging Journey
```
Start ──► Plans Tab ──► Select Plan ──► Select Day ──► View Exercises
                                                           │
                                        ┌──────────────────┼──────────────────┐
                                        ▼                  ▼                  ▼
                                   Quick Log          Detailed Log        Progress View
                                   (1 tap)           (Form entry)        (Analytics)
                                        │                  │                  │
                                        ▼                  ▼                  ▼
                                 SessionItem         SessionItem          Chart Display
                                (minimal data)      (full metrics)      (historical data)
```

### Plan Management Journey
```
Start ──► Plans Tab ──► Create/Select Plan ──► Configure Days ──► Add Exercises
                                                    │
                                                    ▼
                                              Daily Execution ──► Log Completion
                                                    │
                                                    ▼
                                              Track Progress ──► Analytics View
```

## 🔗 Integration Points

### SwiftData Integration
- **Automatic Persistence**: Changes save automatically
- **Relationship Management**: SwiftData handles entity relationships
- **Query Performance**: Optimized data fetching with FetchDescriptor

### CSV Import/Export
- **LogCSV.swift**: Handles data serialization/deserialization
- **Plan Reconstruction**: Maintains plan-exercise relationships during import
- **Date Normalization**: Consistent date handling across operations

### UI State Management
- **Environment Context**: Shared ModelContext across views
- **State Preservation**: SwiftUI maintains view state automatically
- **Navigation State**: Managed through NavigationStack and sheets

## 🛠️ Development Guidelines

### Adding New Features
1. **Data Model**: Define SwiftData entities if needed
2. **Factory/Seeder**: Add data population logic
3. **UI Views**: Create SwiftUI views following established patterns
4. **Integration**: Wire up data binding and navigation
5. **Testing**: Add to test suite in `/tests/`

### Best Practices
- **Single Responsibility**: Each view handles one primary function
- **Data Consistency**: Use SwiftData relationships over manual linking
- **User Experience**: Provide both quick and detailed interaction paths
- **Error Handling**: Graceful degradation with try? patterns

## 📈 Performance Considerations

### Data Access Patterns
- **Lazy Loading**: @Query fetches data as needed
- **Filtered Queries**: Use predicates to limit data sets
- **Memory Management**: SwiftData handles automatic cleanup

### UI Performance
- **View Decomposition**: Break complex views into smaller components
- **State Minimization**: Keep @State variables focused and minimal
- **Batch Operations**: Group related data changes together

This architecture provides a scalable, maintainable foundation for the climbing training app with clear separation of concerns and efficient data flow patterns.
