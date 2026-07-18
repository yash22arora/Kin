# Kin — The Living Sky

A phase-by-phase plan for making the background sky *agree with the real sky
outside the user's window*. Not a decorative gradient cycle — the app's core
conceit (these people are a sky you tend) made continuous with reality.

**Status:** Phase A ✅ BUILT — `Core/SkyPalette.swift`: six OkLCh anchors
interpolated along approximate solar altitude (clock+season model, assumed
mid-latitude), morning legs violet-shifted, 3-stop gradient (zenith/mid/
horizon) in both SkyScene and the widget, 60s live drift, plus a Settings
"Sky mood" picker (Auto or pinned phase, App-Group-shared with widgets).
Deliberately deferred from A: Milky Way band (waits for hue sign-off),
adaptive legibility scrim, P3 rendering, real location.
Phases B–E not built. WeatherKit (Phase C) needs the paid account.

---

## The principle

The variation is the metaphor, not ornament. When the evening nudge fires,
the user opens Kin, and the in-app dusk matches the dusk they can see through
the window — the metaphor stops being a metaphor. Every decision below serves
that: **real, slow, mostly subliminal.** Noticed over weeks, not seconds.

Three rules that hold across every phase:

1. **Hue journey, not a brightness slider.** The eye reads a *hue* change as
   "different sky"; it barely registers a few percent of lightness. Today's
   palette only nudges lightness and stays blue — that's why it reads as one
   color.
2. **Drive it off the real sun, not a clock hack.** Anchor to solar altitude
   for the user's location (golden hour, civil / nautical / astronomical
   twilight, the moonless deep, pre-dawn). Season and latitude then shift the
   timing for free.
3. **Weight everything toward dusk and night.** This is an evening-ritual app.
   Twilight is the set piece; noon is the throwaway. (The current curve peaks
   at noon — backwards for a night app.)

---

## Color space

All stops are authored and **interpolated in OkLCh** (Oklab's cylindrical
form): `L` ∈ [0,1] lightness, `C` chroma (≈0–0.37 usable), `h` hue in degrees.
RGB interpolation between a warm and a cool sky passes through muddy gray —
reviewers feel it even if they can't name it. Oklab stays clean. Render to
**Display P3**.

Each phase defines three vertical stops: **Zenith** (top), **Mid**, and
**Horizon** (bottom band, where real dusk warmth lingers). Values below are
*design targets* to be tuned on-device against OLED.

---

## Phase-by-phase palette

Anchored to solar altitude (degrees above/below horizon). The renderer
**interpolates continuously along the altitude axis** between adjacent phase
control points — these rows are the anchors, not discrete states.

### Day  · sun > +6°  · *rarely seen; kept subdued so stars stay legible*
| Stop | L | C | h |
|------|-----|------|-----|
| Zenith | 0.55 | 0.05 | 240 |
| Mid | 0.62 | 0.045 | 235 |
| Horizon | 0.70 | 0.04 | 230 |
Pale, desaturated blue. Faint stars suppressed; only the brightest people show.

### Golden hour · sun +6° → 0° · *warm, the day letting go*
| Stop | L | C | h |
|------|-----|------|-----|
| Zenith | 0.45 | 0.06 | 250 |
| Mid | 0.55 | 0.10 | 60 |
| Horizon | 0.70 | 0.14 | 70 |
Cool sky above, amber/gold pooling at the horizon.

### Civil twilight · sun 0° → −6° · *rose into magenta; first stars*
| Stop | L | C | h |
|------|-----|------|-----|
| Zenith | 0.30 | 0.07 | 285 |
| Mid | 0.42 | 0.10 | 320 |
| Horizon | 0.55 | 0.13 | 25 |
The brightest people (closest) begin to ignite out of a still-lit sky.

### Blue hour · sun −6° → −12° · **★ THE HERO ★**
| Stop | L | C | h |
|------|-----|------|-----|
| Zenith | 0.20 | 0.08 | 265 |
| Mid | 0.28 | 0.11 | 275 |
| Horizon | 0.40 | 0.10 | 300 |
Deep luminous indigo, a magenta lean low on the horizon. Fainter stars arrive
as it deepens. Spend the disproportionate polish here.

### Astronomical twilight · sun −12° → −18° · *settling into night*
| Stop | L | C | h |
|------|-----|------|-----|
| Zenith | 0.14 | 0.05 | 268 |
| Mid | 0.19 | 0.06 | 272 |
| Horizon | 0.28 | 0.07 | 285 |

### Deep night · sun < −18° · *deepest; the whole field visible*
| Stop | L | C | h |
|------|-----|------|-----|
| Zenith | 0.10 | 0.03 | 265 |
| Mid | 0.13 | 0.04 | 268 |
| Horizon | 0.17 | 0.05 | 275 |
**Never true black** (floor L ≈ 0.06) — OLED true black loses depth. Full dust
field + Milky Way band (season-gated) at their densest.

### Pre-dawn · mirror of evening but **cooler** · *violet, not magenta*
| Phase | Stop | L | C | h |
|-------|------|-----|------|-----|
| Nautical | Zenith | 0.20 | 0.07 | 260 |
| Nautical | Horizon | 0.38 | 0.08 | 285 |
| Dawn (civil) | Horizon | 0.60 | 0.11 | 50 |
The return leg reads cooler and paler than dusk — a different emotional
temperature, so morning never feels like a rerun of evening.

---

## Modifier layers (composed on top of the solar base)

Order of composition: **solar palette → moon → weather → season → clamp to
floors**, final result interpolated in OkLCh.

### 1. Moon — highest subliminal payoff
Inputs: illuminated fraction (0–1) + moon altitude.
- `skyglow = illumFraction · max(0, sin(altitude)) · k`
- Raise Zenith/Mid **L** by up to ~0.06 and drop chroma slightly (moonwash).
- **Raise the faint-star visibility threshold** — near a bright gibbous/full
  moon high in the sky, the faintest people fade, exactly as real faint stars
  do. New-moon nights go deepest and let the most stars (and the Milky Way)
  emerge. Tying star *visibility* to the real moon is the quiet, magical
  detail.

### 2. Weather — WeatherKit *(needs paid dev account; see POLISH.md)*
Input: `cloudCover` (0–1), plus fog/haze.
- Cloud raises **L**, collapses **C** toward gray, cuts contrast.
- `cloudCover > 0.7` hides faint stars; `> 0.9` hides most.
- Fog/haze → soften with a light blur.
- `cloudCover < 0.2` → deepen contrast; earns the **"the real sky is clear
  tonight too"** moment.

### 3. Season
- Winter: shift hue cooler (toward blue), raise clarity/contrast.
- Summer: warmer floor, higher **Milky Way band density**, slightly higher
  night **L** (warm nights).
- Equinox: neutral. (Solar timing already encodes most seasonality for free.)

---

## Craft rules (the "nice" → "award-grade" gap)

- **OkLCh interpolation**, always. No RGB lerps.
- **≥3 gradient stops** + a distinct horizon warmth band.
- **Never true black** — minimum luminance floor keeps depth on OLED.
- **Live drift**: recompute every ~60s in foreground, animate across the delta
  so the sky visibly-but-barely moves while open. Correct at the instant of
  open.
- **App ↔ widget parity**: one shared palette function; widget timeline entries
  placed at phase boundaries so the home screen and app never disagree.
- **Adaptive legibility scrim**: measure contrast of overlay text against the
  current bottom stop; insert only as much scrim as needed — heavy at dusk,
  near-nothing at deep night.
- **Reduce Motion**: color still shifts (it's not motion). Disable only the
  cloud drift / parallax animation, not the palette.
- **Performance/battery**: bake the gradient to a texture; rebuild only on a
  meaningful phase delta, not every frame. Gate the whole system behind a
  feature flag for staged rollout and measurement.
- **Graceful degradation**: no location permission → approximate sun altitude
  from timezone + date. No WeatherKit → skip the weather layer silently.

---

## Signature moment

**Blue-hour ignition.** Open the app during the blue hour: the brightest
people ignite first out of a warm, still-lit sky; the fainter ones arrive one
by one as it deepens to indigo. The daily reward for showing up at the ritual
hour — and the shot that goes in the award submission.

---

## Build order

- **Phase A — Solar hue arc.** Replace `skyPhase` curve + palette; OkLCh
  interp; 3 stops + horizon band; app/widget parity; adaptive scrim. Optional
  location, timezone fallback. *This alone is the headline visual win — no paid
  account or entitlements required.*
- **Phase B — Moon layer.** Illumination + altitude → skyglow + faint-star
  visibility.
- **Phase C — Weather layer.** WeatherKit (paid dev account). Cloud/fog/clear.
- **Phase D — Season.** Hue/clarity nudges + summer Milky Way band.
- **Phase E — Signature + rare events.** Blue-hour ignition sequence; hook to
  meteor-shower nights and set pieces already in POLISH.md.

---

## Where it touches code (for later)

- `SkySnapshot.skyPhase` / `skyGradientColors` — solar model + palette source
  of truth.
- `SkyScene.layoutBackground` — consume multi-stop OkLCh gradient; live
  refresh.
- Widget `WidgetSky` — same palette function; timeline at phase boundaries.
- New `SolarClock` / astronomy helper — sun & moon altitude (SunCalc-style).
- WeatherKit integration (Phase C).
- Star rendering — faint-star visibility threshold responds to moon/weather.
