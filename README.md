# Kin

*Your people as a private night sky. Tend it, and it glows.*

Every person you love is a star. Log a shared moment — a call, a coffee, a
laugh — and their star brightens. Quiet weeks let it soften (never go dark).
Friend groups become constellations. The widget is the product; the app is
where you tend.

**Product values** (the filter for every feature):
1. Never guilt, only warmth. No streaks, no scores, no red badges.
2. Five seconds a day is enough.
3. Private by default. No accounts, no server. The sky never leaves the device.
4. The widget is the product.

## Status

Feature-complete for v1 pending on-device tuning. See `POLISH.md` for the
polish backlog and parked items.

| Area | State |
|---|---|
| Sky (SpriteKit): gradient by time of day, parallax, twinkle, constellation lines, drag-to-arrange, long-press birth w/ ghost star, tap → camera focus-zoom | ✅ |
| Moments: log/edit/delete, photos, feelings, backdating | ✅ |
| Stars: add/edit, orbits, release ritual, remembered state | ✅ |
| Onboarding: 8 steps + animated glow demo | ✅ |
| Widgets: My Sky (S/M/L), One Star (configurable person) | ✅ |
| Siri / App Intents: log moment, star brightness, open star + donations | ✅ (log works; other phrases parked) |
| Monetization: StoreKit 2 lifetime, 7-day trial (AppTransaction-anchored), 3-star free tier | ✅ |
| Extras: Face ID lock, stargazing notification, JSON export, deep links | ✅ |
| Accessibility: VoiceOver star list w/ custom actions, Reduce Motion everywhere | ✅ (needs device audit) |
| Analytics: protocol + TelemetryDeck behind `canImport` | wired, inactive |
| iCloud sync | ⏸ parked (needs paid dev account; recipe in `KinModelContainer.swift`) |
| Unit tests | LuminosityEngine covered; rest parked |

## Building

Open `Kin.xcodeproj` (Xcode 16+, iOS 17 deployment target). Three targets:
app, `KinWidgetExtension`, `KinTests`.

Configuration touchpoints:
- **App Group**: `group.com.servatom.kin` — set in both targets' entitlements
  and `KinShared.appGroupID` (Core/SkySnapshotStore.swift). Widget shows demo
  stars if these don't match.
- **StoreKit testing**: select `Kin.storekit` in Edit Scheme → Run → Options.
  Product: `com.servatom.kin.lifetime`.
- **URL scheme**: `kin://` (Kin/Info.plist) — `kin://log`, `kin://star/<uuid>`.
- **Analytics**: add the TelemetryDeck SPM package and paste the app ID into
  `AnalyticsFactory.telemetryDeckAppID` (Support/Analytics.swift) to go live.

## Architecture

```
Kin/
├── Core/            Pure logic — Foundation only, shared with widget & tests
│   ├── LuminosityEngine.swift   luminosity = f(moments, orbit, now); COMPUTED, NEVER STORED
│   ├── SkySnapshot.swift        value type bridging data → all renderers (+ sky gradient)
│   ├── SkySnapshotStore.swift   App Group JSON: app writes, widget reads
│   └── SkyLayout.swift          seeded star positions
├── Models/          SwiftData (CloudKit-compatible: defaults, optional rels, no unique)
├── Scenes/          SkyScene (SpriteKit): camera, layers, gestures, textures
├── Views/           SwiftUI: SkyView (no tab bar — one canvas + sheets), sheets, onboarding
├── Support/         Store, Haptics, Analytics, Notifications, PhotoStore,
│                    SnapshotBuilder, KinModelContainer, KinAppIntents
KinWidget/           Canvas renderers consuming the same SkySnapshot
KinTests/            LuminosityEngineTests — the emotional contract, as asserts
```

Load-bearing invariants:
- **Luminosity is computed, never stored, never shown as a number.** Floor
  glow 0.25 — stars soften, they never die. Orbits scale decay per person.
- **One snapshot, three consumers**: `SnapshotBuilder` feeds SkyScene, the
  widgets (via App Group JSON), and App Intents. Change the sky's meaning in
  one place only.
- **Models stay CloudKit-compatible** for the parked sync work.
- Every animation has a Reduce Motion path. Every string is written in the
  app's voice: warm, brief, never guilt.

## Docs

- `POLISH.md` — polish backlog + parked items (Siri phrases → CloudKit → ASC)
- `Kin/Views/SettingsSheet.swift` → "How glow works" — the user-facing rules
