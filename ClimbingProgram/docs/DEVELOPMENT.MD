
Great choice 🙌 That way your **README stays friendly and concise**, while contributors still get the full detail.

Here’s a **`docs/DEVELOPMENT.md`** draft, structured for contributors:

```markdown
# Klettrack Development Guide

This document provides in-depth details for developers contributing to **Klettrack**.  
For a high-level overview, please see the main [README.md](../README.md).

---

## 📂 Project Structure  

```

ClimbingProgram
├── app/                  # App entrypoint & root views
├── data/                 # Models, persistence, CSV I/O
├── design/               # App-wide design system (theme, colors)
├── docs/                 # Documentation
├── features/             # Modular feature groups
├── shared/               # Reusable UI components
├── Assets.xcassets       # Images, colors, symbols
└── ClimbingProgramTests/ # Unit & integration tests

````

---

## ✅ Testing  

### Test Suites

- **AppIntegrationTests.swift**
  - Verifies app constructs and SwiftData schema readiness.
  - Smoke checks main flows (catalog → plan → session logging → analytics/export).
  - Ensures seed data loads and survives simulated app restarts.

- **BusinessLogicTests.swift**
  - Validates plan creation (weekly, 3-2-1), seeding, and idempotency.
  - Checks session–plan linkage and exercise grouping.
  - Includes performance and theme color tests.

- **DataModelTests.swift**
  - Tests entity relationships (Activity ↔ TrainingType ↔ Exercise).
  - Handles cascade deletions, predicates, and normalized dates.

- **ImportExportTests.swift**
  - Validates CSV round-trip (export → clear → import).
  - Tests error cases, date consistency, and climb upsert logic (explicit ID + TB2 UUID).

- **PerformanceAndEdgeCaseTests.swift**
  - Large dataset creation, stress tests, Unicode/special character handling.
  - Edge cases: empty data, extreme values, very large plans.

- **TimerAppStateTests.swift**
  - Ensures switching tabs updates app state correctly.

- **TimerTemplateTests.swift**
  - Confirms `effectiveTotalTimeSeconds` calculations and overrides.

- **TimerTests.swift**
  - Sets up `TimerManager` for timer-related functionality.

- **LogCSVTests.swift**
  - Round-trip CSV reconstruction of plans and sessions.
  - Climb import via stable IDs.

- **SeedDataTests.swift**
  - Confirms bouldering combinations, climbing styles, gyms, and timer templates seeded correctly.

- **IsDataReadyEnvironmentTests.swift**
  - Exercises SwiftUI environment propagation in UIKit hosting.

- **TestSupport.swift**
  - Base test helpers for in-memory SwiftData setups and entity factories.

---

## 🛠 Running Tests  

Inside Xcode:  
- Select the test target `ClimbingProgramTests`  
- Run `Cmd+U`  

From command line:  
```bash
xcodebuild test \
  -scheme ClimbingProgram \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.0'
````

---

## 👩‍💻 Contributing Workflow

1. Create a branch:

   ```bash
   git checkout -b feature/my-feature
   ```
2. Commit changes with clear messages
3. Ensure all tests pass locally (`Cmd+U`)
4. Open a Pull Request


---

## 📄 License

Klettrack is licensed under **GPL-3.0**, with additional restrictions on redistribution and commercial use.
See the [LICENSE](../LICENSE) file for details.

