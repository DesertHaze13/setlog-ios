# Project structure

The physical folders and Xcode navigator groups use the same platform-first layout:

```text
Setlog-iOS/
├── Sources/
│   ├── iOS/
│   │   ├── App/                 # iPhone/iPad entry point
│   │   ├── Features/Workouts/   # workout screens
│   │   ├── DesignSystem/        # solar appearance
│   │   ├── Services/            # persistence, Firebase, HealthKit, Watch bridge
│   │   └── Domain/              # workout data model
│   ├── Watch/App/               # native watchOS app
│   └── macOS/
│       ├── App/                 # native Mac entry point
│       └── Features/Workouts/   # native Mac screens
├── Resources/
│   ├── iOS/                     # schedule, asset catalog, Firebase config, entitlement
│   ├── Watch/                   # reserved for watch-only assets
│   ├── macOS/                   # Mac Firebase config
│   └── DonyLifts2026.icon       # active Icon Composer source for all targets
├── Documentation/
│   ├── CALCULATIONS.md
│   ├── PROJECT_STRUCTURE.md
│   ├── Screenshots/
│   └── Archive/                 # older icon concepts and original layout sketch
├── Setlog.xcodeproj/
├── firestore.rules
└── README.md
```

`Sources/iOS/Domain/Models.swift` is compiled by the iOS, Watch, and Mac targets. The Mac target also shares `WorkoutStore.swift` and `SharedCloud.swift` from `Sources/iOS/Services`; their location does not limit their target membership. The active icon is linked to all three targets, and `Resources/iOS/workout-seed.json` is linked to iOS and Mac. `Resources/Watch` is currently empty because the Watch app uses the shared icon and has no watch-only asset.

`Documentation/Archive` is excluded from Xcode builds. Device backups and derived build outputs are ignored by Git. Keep the bundle identifiers and data schema unchanged when rearranging folders so app updates continue to find existing workout data. When moving a source or resource again, update its Xcode group path and any explicit build-setting path, then build the iOS/Watch and Mac schemes.
