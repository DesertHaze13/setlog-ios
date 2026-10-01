# Xcode project layout

The on-disk directories match the groups in `Setlog.xcodeproj`:

- `Setlog/App` — iPhone/iPad entry point, solar appearance, Watch bridge.
- `Setlog/Models` — shared workout model, also compiled by Watch and Mac.
- `Setlog/Stores` — workout state, Fitness rings, Firebase sync.
- `Setlog/Views` — iPhone/iPad interface.
- `Setlog/Resources` — active icon, asset catalog, Firebase plist, starter schedule.
- `Setlog/Configuration` — active HealthKit entitlement.
- `SetlogWatch/App` — watchOS app and interface.
- `SetlogMac/App`, `Views`, `Resources` — native Mac app.
- `DesignArchive` — old icon designs and unused entitlement retained for recovery, excluded from the Xcode navigator and builds.

The original proposed grouping remains in `project-layout.txt` for reference. The actual project file uses the groups above. When moving a source file, update its Xcode file reference and build setting paths, then build the iPhone/Watch and Mac schemes.
