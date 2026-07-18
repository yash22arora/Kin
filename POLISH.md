# Kin — Polish Backlog

## ✅ Done (kept for the record)
- Onboarding: living starfield backdrop, names igniting at real seeded
  positions, orbit carousel (left-anchored star, plate rotation, camera
  dive/return), glow demo w/ streak comet + third star, widget card rotation
  with real first-star name, gated Continue buttons, haptic crescendo,
  poetic text reveal, Fraunces voice
- Sky: point-spread stars w/ earned tapered crosses, time-of-day gradient
  (app+widget shared), parallax, constellation lines, drag-to-arrange,
  ghost star, spark→bloom ignition, remembered stars (steady render + deep
  steady haptic), real moon phase in header, focus zoom w/ sheet
- Ambient: random comet streaks + meteor showers (flags), 20–25s cadence
- System: widgets (My Sky S/M/L + configurable One Star), Siri log-moment,
  launch storyboard (full-bleed), app icon (uniform hairline cross, by choice)
- Monetization: trial-end keep-3 flow, dormant/restore, StoreKit test setup,
  offline paywall messaging, cached entitlements

## Next (pre- or post-launch, no account needed)
- Comet trail `.sks` final tuning on device (owner: Yash)
- Line-by-line *word* reveal (current reveal is per-line; word-stagger needs
  a custom layout — revisit if a screen still feels flat)
- Star "leaning" toward an incoming comet (micro-delight, low priority)
- Sound design: ambient shimmer + arrival chime — commission before v1.1
- Device audit: VoiceOver walkthrough, Dynamic Type max, 60fps @ 40 stars

## ⏸ Parked: pick up just before CloudKit integration
- **Siri phrase refinement** — "Log a moment" works; StarBrightness and
  OpenStar phrases don't resolve reliably. Try more phrase variants, simpler
  trigger words ("check on", "visit"), vocabulary sync timing.

## ⏸ Parked: needs paid Apple Developer account
- **iCloud sync** — recipe in `KinModelContainer.swift`; models stay
  CloudKit-compatible. Then flip copy back to "your devices".
- **App Store Connect** — IAP product, TestFlight, privacy labels, featuring
  form with ADA-rubric language. Remember: TestFlight trial anchor makes your
  own trial appear expired (expected; use mock purchase).

## v1.x / v2 set pieces
- Lock screen accessory + StandBy bedside sky
- Season layer: Milky Way band in summer, seasonal dust — see `LIVING_SKY.md`
- Pinch to zoom sky ↔ constellation view
- Meteor showers on real shower nights; "the real sky is clear tonight too"
  (WeatherKit)
- **"Your Year of Light"** — Dec 31 flythrough, shareable video (launch
  marketing gold)
