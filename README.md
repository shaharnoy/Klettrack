# Klettrack

iOS app for planning, logging, and analyzing climbing and training.  
This is a **community-driven project**: created for climbers, shaped by feedback, and it will **always remain free**.

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)  ![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)  ![iOS](https://img.shields.io/badge/iOS-17+-lightgrey.svg)   ![Xcode](https://img.shields.io/badge/Xcode-15.3+-blue.svg)  

[![App Store](https://img.shields.io/badge/App_Store-Download-blue?logo=apple)](https://apps.apple.com/app/id6754015176) [![Website](https://img.shields.io/badge/Website-klettrack.com-black)](https://klettrack.com)



---

## 🗺️ Roadmap and Feature requests

 [klettrack Roadmap](https://klettrack.featurebase.app)  

---

## ✨ Key Features
- Log your climbs by **style, gym, grade, angle, hold types, and colors**.  
- Board climber? **Sync your Kilter/Tension Board sends** in a click for complete tracking.  
- Plan **training cycles** with templated time blocks and a catalog of ~100 exercises.  
- Use the **integrated interval timer** with built-in protocols, rest/prep configuration, and hangboard support.  
- Track progress **over time** with analytics, filters, and charts.  
- **Privacy-first:** all data stays local on your device — nothing leaves your phone.  

---

## 📱 Screenshots and examples

See [![App Store](https://img.shields.io/badge/App_Store-Download-blue?logo=apple)](https://apps.apple.com/app/id6754015176)

---

## 📖 Table of Contents
* [Requirements](#requirements)
* [Getting Started](#getting-started)
* [Project Structure](#project-structure)
* [Testing](#testing)
* [Contributing](#contributing)
* [Credits](#credits)
* [License](#license)

---

## 🛠 Requirements

* macOS with **Xcode 15.3+** (recommended Xcode 16+)
* **iOS 17.0+** (SwiftData requires iOS 17)
* **Swift 5.9+**
* No third-party package dependencies

---

## 🚀 Getting Started

1. Clone the repository

   ```bash
   git clone https://github.com/yourusername/klettrack.git
   cd klettrack
   ```
2. Open `ClimbingProgram.xcodeproj` in Xcode
3. Select an iOS 17+ simulator or device
4. Build & Run
5. On first launch, seed data is automatically loaded into SwiftData

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
ClimbingProgramTests
```

---

## ✅ Testing

Tests are grouped by feature/domain:

* **AppIntegrationTests** – schema, seeding, and user flows
* **BusinessLogicTests** – plan factory, seeding, linking, and performance
* **DataModelTests** – model relationships, cascade deletion, predicates
* **ImportExportTests** – CSV round-trip, import upserts, error cases
* **PerformanceAndEdgeCaseTests** – stress tests and large datasets
* **TimerTests & TimerTemplateTests** – timer logic and calculations
* …and more (see `ClimbingProgramTests/`)

Run tests with:

```bash
Cmd+U  # inside Xcode
```

---

## 🤝 Contributing

Contributions are more than welcome!
Just create a branch, commit your changes, add tests if applicable, and open a PR.

---

## 🙌 Credits  

Klettrack exercise catalog is inspired by the climbing and training principles shared by: 
- [Eric Hörst – Training for Climbing](https://trainingforclimbing.com/)  
- *Training for Climbing* [book] (https://physivantage.com/products/training-for-climbing)  

Klettrack’s boards integration sourced from [BoardLib](https://github.com/lemeryfertitta/BoardLib) by [@lemeryfertitta](https://github.com/lemeryfertitta).



## 📄 License  

### License

The source code of Klettrack is licensed under the **GNU GPL v3**.  
The binary version distributed via the **Apple App Store** is released under a **proprietary “All rights reserved” license**.


⚠️ **Note:**  
- Commercial redistribution, rebranding, or publishing this app under another name (e.g., on the App Store) is **not permitted**.  
- For personal use and contributions only.  


