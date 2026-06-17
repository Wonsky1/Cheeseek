# Cheeseek — Design Notes for F1, F3, F4

**Date:** 2026-06-16
**Status:** Proposal / "how we might do it" (no code yet).
**Companion:** see `docs/walk-experience-review.md` for the findings these address.
**Out of scope here:** F2 (walk summary map) — already implemented; see the review's appendix.

This document proposes concrete approaches for the three remaining issues. Each section gives the goal,
the recommended approach, alternatives considered, data-model/interface changes, a step-by-step plan, and
test criteria. Treat these as independent workstreams that can be sequenced F1 → F4 → F3.

---

## F1 — Single source of truth for coverage (real buildings)

### Goal
One canonical "covered buildings" set, computed from **real OSM buildings**, owned by Swift, used
everywhere (live map, stats, persistence, backend sync, summary). Retire the synthetic
`CoverageBuildingCodec` as the primary model.

### Today (the problem)
- Live map (JS) detects **real** buildings via `queryRenderedFeatures`, persists them only in the WebView's
  `localStorage`.
- Swift derives **synthetic** rectangles (`CoverageBuildingCodec`) for stats / `/coverage` sync / summary.
- The two never reconcile. See `walk-experience-review.md` §F1.

### Recommended approach: bridge the JS-detected set back to Swift

The JS already computes the real covered features during the walk. Surface them to Swift over the existing
`WKScriptMessageHandler` bridge and make Swift the owner.

**A. New message channel (WebView → Swift)**
Add a third handler alongside `cheeseekReady` / `cheeseekMapInteraction`, e.g. `cheeseekCoverage`.
When the JS marks a new building covered (in `processRouteCoordinates`, where `persistedChanged = true`),
post a compact payload:

```jsonc
// posted incrementally as buildings are covered
{
  "event": "covered",
  "sessionScoped": true,
  "features": [
    { "id": "building:12345", "status": "explored",
      "geometry": { "type": "Polygon", "coordinates": [[[lon,lat], ...]] } }
  ]
}
```

Keep payloads small: send only *newly* covered features (the `newlyCovered` array already exists), and
round coordinates to ~6 dp.

**B. New Swift model**
Replace synthetic side-IDs with a real building record:

```swift
struct CoveredBuilding: Codable, Identifiable, Equatable {
    let id: String                 // stable OSM-derived key from JS (featureKey)
    let polygon: [Coordinate2D]    // outer ring, ~6dp
    var firstCoveredAt: Date
    var sessionId: UUID?           // which walk first covered it (for per-walk summaries)
}
```

`MapViewModel` keeps `coveredBuildings: [String: CoveredBuilding]` as the live truth. The
`CoverageStore` and backend serialize `CoveredBuilding` (id + polygon) instead of opaque side IDs.

**C. Wire-through**
- Stats (`SharedProgress`, summary "X buildings") count `coveredBuildings` keys.
- `coverageStore.saveCoverage` stores the records (bump the storage key to `…-v2` and migrate/forget).
- Backend `upsertCoverage` / `fetchCoverage` carry id+polygon so coverage is portable across devices and
  renderable server-side.
- Summary renders the **session's** buildings directly (no `queryRenderedFeatures` replay needed).

### Alternatives considered
- **Server-side intersection** (send polyline, server intersects with OSM building polygons). Most correct
  and device-independent, but needs an OSM building dataset + spatial index server-side. Good long-term;
  heavier now. Can layer on later behind the same `CoveredBuilding` model.
- **Keep synthetic codec, just relabel.** Rejected: it never matches what's painted; the core complaint.

### Migration / risk
- `localStorage` building cache (`cheeseek.coveredBuildings.v2.*`) becomes a *cache*, not the source of
  truth. On first run after F1, seed Swift from it once, then Swift drives.
- Versioned storage key avoids mixing old synthetic IDs with new real IDs.

### Step-by-step
1. Add `CoveredBuilding` model + `Coordinate2D` codable.
2. Add `cheeseekCoverage` script message handler in `MapLibreMapView` + JS `postMessage` on
   `persistedChanged`.
3. Plumb a callback `onCoverageChanged([CoveredBuilding])` up to `MapViewModel`.
4. Switch `MapViewModel` coverage state, `CoverageStore`, and backend DTOs to `CoveredBuilding`.
5. Update stats + summary to read the new model. Delete synthetic `CoverageBuildingCodec` usage (keep file
   only if still needed as offline fallback).

### Test criteria
- After a walk, "X buildings" equals the number of buildings highlighted on the live map (±0).
- Reinstall / second device shows the same covered buildings after sync.
- Summary shows exactly the buildings covered during *that* session (via `sessionId`).

**Effort:** Medium (1–2 days).

---

## F3 — Zoom-independent, low-latency coverage detection

### Goal
Detect covered buildings deterministically and promptly, independent of current zoom and of which tiles
happen to be rendered.

### Today (the problem)
Detection uses `map.queryRenderedFeatures` with a fixed **pixel** radius along the route. It only sees
rendered tiles (latency when entering fresh areas) and the covered real-world area changes with zoom. See
`walk-experience-review.md` §F3.

### Recommended approach (incremental, two steps)

**Step 1 — Quick wins on the current JS path (low risk):**
- Convert the query radius from pixels to **meters**: compute pixels-per-meter at the current latitude/zoom
  and derive `buildingQueryRadiusPixels` so the corridor is a constant ~12–16 m regardless of zoom.
- Look-ahead tile warming: query a bbox slightly ahead of travel direction so tiles for the upcoming area
  load before you arrive, cutting paint latency.
- Sample the route by **meters** (not pixels) for the same reason.

**Step 2 — Decouple detection from rendering:**
- Use `map.querySourceFeatures('openmaptiles', { sourceLayer: 'building' })` instead of
  `queryRenderedFeatures`. Source features aren't limited to the painted viewport (still tile-gated, but not
  paint-gated), reducing "didn't paint yet" cases.
- Do a real **point-in-polygon / polyline-buffer ∩ polygon** test in JS (or Swift via Turf-style helpers)
  with a fixed meters buffer, rather than relying on the pixel box. Deterministic and zoom-independent.

**Step 3 (optional, best) — Server intersection:** the `/map/coverage-candidates` endpoint already exists in
`BackendSyncServing`. Send the (smoothed) polyline; server intersects with OSM building polygons and returns
covered building ids+polygons. Fully deterministic, offloads the device, and dovetails with F1's
`CoveredBuilding`. Requires server OSM data + spatial index.

### Alternatives considered
- Precise geometry corridor on-device with a vector tile decoder library: accurate but adds a dependency and
  CPU; the `querySourceFeatures` + buffer test is a good middle ground.

### Step-by-step (Step 1+2)
1. Add `metersToPixelsAtCurrentZoom(lat)` helper in the JS; replace pixel radius/step constants.
2. Add directional look-ahead bbox query on `move`/`idle`.
3. Switch `queryRenderedBuildings` → `querySourceFeatures` and add a polyline-buffer ∩ polygon test.
4. Keep the existing animation/persistence path unchanged.

### Test criteria
- Walking the same physical path produces the same covered-building set at zoom 14 and zoom 18 (±0–1).
- Entering a fresh area paints covered buildings within ≤1 s of arrival on a normal connection.
- No regression in `[cheeseek-perf]` average recompute time (watch the existing console counters).

**Effort:** Step 1 = quick (½ day). Step 2 = Medium. Step 3 = High (server work).

---

## F4 — GPS smoothing (kill the "teleporting")

### Goal
A stable, believable position and route line: reject outliers, smooth jitter, and drive a single calm
camera from the smoothed position.

### Today (the problem)
Raw `CLLocation`s are plotted with only an accuracy gate (loose 50 m) and a 3 m min-move gate — no outlier
rejection, no smoothing. The dot is animated but the route line and camera use raw coordinates. See
`walk-experience-review.md` §F4–F5.

### Recommended approach: a small location-processing pipeline

Introduce a `LocationProcessor` that sits between `LocationManager` and `MapViewModel` and emits *smoothed*
fixes. Stages:

1. **Accuracy gate (tighter):** drop fixes with `horizontalAccuracy < 0` or `> 25 m` during recording.
   Keep a one-time looser bootstrap (≤ 50 m) only until the first good fix.
2. **Outlier / speed gate:** drop fixes whose implied speed `distance / Δt` exceeds a walking ceiling
   (e.g. > 4 m/s sustained), and ignore fixes older than the last accepted one
   (`timestamp` regressions).
3. **Smoothing — 1-D Kalman filter** on lat/lon (classic for CoreLocation), variance seeded from
   `horizontalAccuracy`. Cheaper alternative: accuracy-weighted EMA
   `p = p_prev + k·(z − p_prev)` with `k` from accuracy. Output is the *recorded* point and the camera
   target.
4. **Cadence:** keep `distanceFilter`/min-move on the **smoothed** output so the route doesn't pile up
   redundant points.

```swift
protocol LocationProcessing {
    /// Returns a smoothed location to record/draw, or nil if the raw fix was rejected.
    func process(_ raw: CLLocation) -> CLLocation?
    func reset()
}
```

`MapViewModel.consumeLatestLocationIfNeeded` then appends the **smoothed** coordinate, and the camera
(see F5) follows the same smoothed coordinate.

### F5 folded in (camera)
- Collapse the two camera writes per fix (`handleLocationUpdate` + `refreshMapData`) into one.
- Stop calling `map.stop()` on every update in JS `applyCamera`; let `easeTo` retarget, or only `stop()` on
  large jumps. Use a steady ~700–1000 ms ease matched to GPS cadence.

### Alternatives considered
- **Map-matching / snap-to-path** (server or on-device): produces the cleanest line but is a bigger project;
  do after the Kalman filter if the line still looks rough.
- **`CLLocationManager` only tuning** (e.g. `activityType`, `distanceFilter`): helps a little but doesn't
  remove outliers; insufficient alone.

### Step-by-step
1. Add `LocationProcessor` (Kalman or weighted-EMA) + unit tests with synthetic noisy tracks.
2. Route accepted fixes through it in `MapViewModel`; tighten `maxAcceptedHorizontalAccuracy`.
3. Single smoothed camera update; remove duplicate write; relax `map.stop()` in JS.
4. Tune constants on-device (accuracy ceiling, speed ceiling, Kalman process noise).

### Test criteria
- Synthetic track with injected 30–40 m outliers: processed track has no visible spikes
  (max step ≤ realistic walking distance per Δt). Unit-testable.
- On device, standing still produces a near-stationary dot (no wandering) and the camera doesn't twitch.
- Recorded distance for a known loop is within a sane tolerance of ground truth (no inflation from jitter).

**Effort:** Medium. The processor + camera cleanup is contained and high-impact.

---

## Suggested sequencing

1. **F1** first — it gives every other piece real building data and makes the summary per-walk-accurate.
2. **F4** next — biggest *felt* quality improvement, self-contained, unit-testable.
3. **F3** last — Step 1 quick wins anytime; Steps 2–3 are larger and benefit from F1's model + server.

Each is independently shippable behind its own change; none requires the others to land first (F1 makes
F3 Step 3 cleaner, but isn't a hard dependency).
