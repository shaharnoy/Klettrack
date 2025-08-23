# AI Instructions for ClimbingProgram iOS App

## 🤖 Project Overview for AI Assistants

This is a **SwiftUI-based iOS climbing training application** using **SwiftData** for persistence. The app tracks climbing training sessions, manages workout plans, and monitors progress through analytics.

## 🏗️ Architecture Understanding

### Core Framework Stack
- **SwiftUI**: Modern declarative UI framework
- **SwiftData**: Apple's new data persistence framework (iOS 17+)
- **Foundation**: Core iOS development framework
- **Xcode Project**: Standard iOS app structure

### Project Structure Map
```
ClimbingProgram/
├── app/                     # App entry points and main navigation
├── features/               # Feature-specific UI modules
│   ├── catalog/           # Exercise browsing
│   ├── plans/             # Training plan management
│   ├── sessions/          # Workout logging
│   └── analytics/         # Progress tracking
├── data/                  # Data layer
│   ├── models/            # SwiftData entities
│   ├── persistence/       # Data seeding and factories
│   └── io/                # CSV import/export
├── design/                # UI theming and constants
├── shared/                # Reusable components
└── tests/                 # Unit and integration tests
```

## 📊 Data Model Knowledge

### Core Entities (SwiftData Models)
1. **Activity** - Top-level exercise categories (Core, Antagonist, Climbing)
2. **TrainingType** - Subcategories within activities
3. **Exercise** - Individual exercises with recommended sets/reps
4. **Session** - Workout sessions on specific dates
5. **SessionItem** - Individual exercise logs within sessions
6. **Plan** - Training plan templates (Weekly, 3-2-1, 4-3-2-1)
7. **PlanDay** - Specific days within plans with chosen exercises
8. **BoulderCombination** - Special grouping for bouldering exercises

### Key Relationships
- Activity → [TrainingType] → [Exercise]
- Session → [SessionItem]
- Plan → [PlanDay] → [chosenExercises: String]
- SessionItem.planSourceId links to Plan for tracking

## 🔧 Development Guidelines for AI

### When Making Code Changes:

#### 1. **SwiftUI View Modifications**
- Use `@Query` for SwiftData fetching: `@Query var exercises: [Exercise]`
- Use `@Environment(\.modelContext)` for database operations
- Follow declarative patterns with `@State`, `@Binding`, `@ObservableObject`
- Use `NavigationStack` for navigation, sheets for modals

#### 2. **Data Model Changes**
- SwiftData entities use `@Model` macro
- Relationships use `@Relationship` with proper inverses
- Always update both sides of relationships
- Use `ModelContainer` setup in `ClimbingProgramApp.swift`

#### 3. **File Organization**
- UI views go in appropriate `/features/` subdirectories
- Data models in `/data/models/`
- Shared utilities in `/shared/`
- Keep single responsibility per file

### Common Patterns to Follow:

#### SwiftData Query Examples:
```swift
// Fetch all exercises for a training type
@Query(filter: #Predicate<Exercise> { exercise in
    exercise.trainingType?.name == typeName
}) var exercises: [Exercise]

// Fetch sessions for date range
@Query(sort: \Session.date, order: .reverse) var sessions: [Session]
```

#### Adding New Features:
1. **Create SwiftData model** if new entity needed
2. **Add to SeedData.swift** if default data required
3. **Create UI views** following existing patterns
4. **Wire up navigation** in appropriate parent view
5. **Update TabView** if new top-level feature

#### Common UI Patterns:
- List views with NavigationLink for drilling down
- Sheets for creation/editing forms
- Context menus for secondary actions
- Quick action buttons (green checkmarks) vs detailed forms

## 🔗 Key Integration Points

### SwiftData Operations:
```swift
// Insert new entity
context.insert(newEntity)

// Delete entity
context.delete(entity)

// Save changes (automatic in most cases)
try? context.save()
```

### Navigation Patterns:
- Use `NavigationStack` wrapper
- `NavigationLink` for hierarchical navigation
- `.sheet()` modifier for modal presentations
- `.navigationTitle()` for screen titles

### Data Binding:
- `@Query` for automatic data fetching
- `@State` for local view state
- `@Binding` for parent-child data sharing
- `@Environment(\.modelContext)` for database access

## 🎯 Feature-Specific Guidance

### Catalog Feature (`/features/catalog/`)
- Hierarchical navigation: Activity → TrainingType → Exercise
- Integration with plan creation
- Search and filtering capabilities

### Plans Feature (`/features/plans/`)
- Plan templates with factory pattern (`PlanFactory.swift`)
- Day-by-day exercise management
- Quick logging vs detailed logging flows

### Sessions Feature (`/features/sessions/`)
- Direct exercise logging without plans
- CSV export functionality via `LogCSV.swift`
- Session history and analytics

### Analytics Feature (`/features/analytics/`)
- Progress tracking charts
- Historical data visualization
- Performance metrics calculation

## 🛠️ Technical Implementation Notes

### Data Seeding:
- `SeedData.swift` handles initial data population
- `CatalogSeeder.swift` manages exercise catalog
- Run once pattern using `RunOnce.swift`

### Plan Generation:
- `PlanFactory.swift` creates different plan types
- Templates include: Weekly, 3-2-1, 4-3-2-1 structures
- Automatic day type assignment and exercise distribution

### CSV Import/Export:
- `LogCSV.swift` handles data serialization
- Maintains plan-exercise relationships
- Date normalization for consistency

## 🚨 Common Pitfalls to Avoid

1. **SwiftData Relationships**: Always update both sides of relationships
2. **Context Management**: Use environment context, don't create new ones
3. **Date Handling**: Use consistent date normalization (start of day)
4. **Plan Integration**: Maintain `planSourceId` links when logging
5. **Memory Management**: Let SwiftData handle cleanup automatically

## 🔍 Debugging and Testing

### Key Files for Debugging:
- `DevTools.swift` - Development utilities
- `test_export_import_compatibility.swift` - Data consistency tests
- Check SwiftData container setup in `ClimbingProgramApp.swift`

### Common Issues:
- **Relationship errors**: Check inverse relationships in models
- **Query performance**: Use predicates to filter data
- **Navigation state**: Ensure proper NavigationStack usage
- **Data consistency**: Verify bidirectional relationship updates

## 📱 Platform Considerations

- **iOS 17+ Required**: SwiftData dependency
- **SwiftUI Lifecycle**: Modern app lifecycle patterns
- **Device Compatibility**: iPhone/iPad universal
- **Data Persistence**: Local SQLite via SwiftData

## 🎨 UI/UX Guidelines

### Theme Integration:
- Use `Theme.swift` for consistent colors and spacing
- Follow iOS Human Interface Guidelines
- Maintain accessibility standards
- Support both light and dark modes

### User Experience Patterns:
- **Quick Actions**: Single-tap operations for common tasks
- **Progressive Disclosure**: Detailed forms when needed
- **Context Awareness**: Smart defaults based on current state
- **Feedback**: Visual confirmation for all user actions

This guide should provide AI assistants with comprehensive understanding of the ClimbingProgram codebase architecture, patterns, and best practices for making effective modifications and additions.
