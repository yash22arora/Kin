# Kin — Visual Polish Backlog (post-functionality)

## Next up: onboarding upgrades (agreed, not yet built)
- Live starfield (dust + faint stars) behind ALL onboarding steps
- Names igniting into their real seeded sky positions as they're typed
- Orbit step goes visual: tappable orbit rings around the person's star
- Haptic crescendo: warmer haptic per step, peaking at the sky reveal
- Line-by-line text reveal for poetic headlines

## ⏸ Parked: pick up just before CloudKit integration
- **Siri phrase refinement** — "Log a moment" works; StarBrightness and OpenStar
  phrases don't resolve reliably. Try: more phrase variants per shortcut,
  simpler trigger words ("check on", "visit"), test vocabulary sync timing,
  and verify parameterSummary rendering in Shortcuts app.

## ⏸ Parked: needs paid Apple Developer account
- **iCloud sync** — re-enable steps documented in `KinApp.init` (entitlements,
  background mode, flip `.none` → `.automatic`). Models stay CloudKit-compatible.
  Until then, the honest privacy copy is "stays on your device", not "your devices".
- **App Store Connect** — lifetime IAP product, TestFlight, privacy labels.

Ideas noted during development, roughly ordered by impact-per-effort.

## Signature moments
- **Ghost star on long-press**: faint pulsing star at the press point behind the
  new-star sheet — the birth feels anticipated. (Agreed during dev.)
- **Comet trail tuning**: CometTrail.sks — scale ~0.05–0.1, birthrate ~200,
  lifetime ~0.5s, negative alpha speed so the streak dissolves behind the comet.
- **Ignition choreography**: new star born via long-press should ignite from a
  spark → bloom, not just fade in.

## The sky itself
- Background gradient driven by `SkySnapshot.skyPhase` (time of day) + season;
  replace flat indigo. Same gradient in app and widget.
- Subtle parallax on device tilt (CMMotionManager), disabled with Reduce Motion.
- Milky Way density band in summer months.
- Real moon phase in the header (currently decorative icon).
- Dust field: vary density/size with season; consider one slow ambient drift.
- Constellation lines between co-mentioned stars (data model ready): thin,
  brightening with repetition; draw in both SkyScene and widget Canvas.
- Remembered stars: distinct fixed rendering (softer, steadier — no twinkle).

## Interactions & motion
- Pinch to zoom sky ↔ star view (plan's spatial navigation).
- Drag to rearrange stars, position persists (model fields already exist).
- Pause shimmer during shooting-star pulse (done); consider star "leaning"
  toward an incoming comet.
- Sheet transitions: log sheet should feel like kneeling at the sky's edge —
  keep stars visible above the sheet, glow anticipating while typing.

## Widgets & system surfaces
- Lock screen accessory widget + StandBy mode (bedside sky).
- One Star widget: AppIntentConfiguration person picker.
- iOS 18 tinted/dark app icon variants + real icon artwork (glowing star on indigo).

## Sound & haptics
- Off-by-default ambient shimmer layer that thickens with sky brightness;
  soft chime on shooting-star arrival (commission a sound designer).
- Distinct haptic curve for "remembered" stars (steadier, deeper).

## Big set pieces (v2)
- "Your Year of Light" — Dec 31 animated flythrough, shareable video.
- Meteor showers on real meteor-shower nights (WeatherKit / astronomy table).
- "The real sky is clear tonight too" moments via WeatherKit.
