# Kin — Xcode Project Scaffold

Your people as a private night sky. See `kin-product-plan.md` for the full product plan.

## Requirements
- Xcode 16+, iOS 17.0 deployment target
- Apple Developer account (for CloudKit + widgets on device; simulator works without)

## Setup — Option A: XcodeGen (recommended)
```bash
brew install xcodegen
cd Kin
xcodegen generate
open Kin.xcodeproj
```
Then in Signing & Capabilities set your team, and add capabilities: **iCloud → CloudKit** (container `iCloud.com.yourteam.kin`), **App Groups** (`group.com.yourteam.kin`) on both app and widget targets.

## Setup — Option B: Manual
1. Xcode → New Project → iOS App → name `Kin`, SwiftUI, Swift, include Tests.
2. Delete the generated `ContentView.swift`; drag the `Kin/` source folders into the target.
3. File → New → Target → Widget Extension → name `KinWidget`; replace its template with `KinWidget/SkyWidget.swift`.
4. Add `KinTests/LuminosityEngineTests.swift` to the test target.
5. Add capabilities as above.

## Structure
```
Kin/
├── project.yml              XcodeGen config
├── Kin/
│   ├── KinApp.swift         App entry, ModelContainer
│   ├── Models/              SwiftData models (Person, Moment, StarGroup)
│   ├── Core/                Pure logic — no UI, no SwiftData imports
│   │   ├── LuminosityEngine.swift   ← the heart; unit-tested
│   │   ├── SkyLayout.swift          deterministic star positions
│   │   └── SkySnapshot.swift        value type bridging data → rendering
│   ├── Scenes/SkyScene.swift        SpriteKit starfield (week-1 spike)
│   ├── Views/               SwiftUI screens
│   └── Support/             Haptics, Analytics
├── KinWidget/SkyWidget.swift
└── KinTests/LuminosityEngineTests.swift
```

## Design decisions already baked in
- **Luminosity is computed, never stored** — pure function in `LuminosityEngine`, trivially testable, no sync conflicts.
- **Glow floor at 0.25** — stars never go dark; dimming reads as "distant," not "dying."
- **Orbit cadences** scale decay per person, so a twice-a-year friend stays bright.
- Core/ has zero Apple-UI dependencies — engine logic is portable and testable headlessly.
- Analytics is a protocol with a no-op default; wire TelemetryDeck later without touching call sites.

## Week-1 priorities (from the plan)
1. Run `LuminosityEngineTests` — they encode the product's emotional contract.
2. Get `SkyScene` to 60fps with 60 stars on device; tune twinkle.
3. Prototype the widget snapshot renderer (`SkySnapshotRenderer` stub in SkyWidget.swift).
4. Decide art direction before polishing any view.
