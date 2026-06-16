# Myshachki — Walk Experience Review

**Date:** 2026-06-16
**Scope:** Walk recording → live coverage painting → walk summary screen, plus the GPS pipeline.
**Reviewer:** Engineering review (code read of `Myshachki/` + `docs/sandbox/`).

---

## 1. Executive summary

The app records a GPS walk, paints "covered" buildings on a MapLibre map in real time, and shows a
summary screen when the walk finishes. The core loop works, but there are three issues worth fixing,
and they share one underlying cause.

| # | Area | Symptom | Severity | Root cause |
|---|------|---------|----------|------------|
| **F1** | Coverage model | Stats/summary never match what's painted on the live map | **High** | Two independent coverage systems that never reconcile |
| **F2** | Walk summary map | "Image" of the result feels fake / unconvincing | ✅ **Fixed** | Summary drew a *synthetic* map (fake roads + jittered blocks); now uses the real MapLibre map |
| **F3** | Coverage painting | "Sometimes takes time to paint buildings" | **Med-High** | Detection depends on rendered map tiles + throttled recompute |
| **F4** | GPS | Movement "feels like teleporting" | **Med-High** | Raw GPS plotted with no track smoothing + camera re-centered on every noisy point |
| **F5** | Camera | Small jumps / animation interruptions | **Med** | Two camera writes per location update; `map.stop()` kills in-flight eases |

The single biggest lever is **F1**: today there is no single source of truth for "what did I cover."
Fixing that makes the summary map honest (F2), and lets coverage detection move off the render-tile
hot path (F3).

---

## 2. How the system works today

```
CLLocationManager
   │  didUpdateLocations (raw CLLocation)
   ▼
LocationManager  ──(accuracy ≤ 50 m, moved ≥ 3 m)──► MapViewModel.consumeLatestLocationIfNeeded
   │                                                      │ append TrackPoint (raw, unsmoothed)
   │                                                      ▼
   │                                          activeRouteGeoJSON  ──► MapLibreMapView (WKWebView)
   │                                                      │                │
   │                                                      │                ▼
   │                                                      │   JS: queryRenderedFeatures along route
   │                                                      │        → paints REAL OSM buildings
   │                                                      │        → persists to localStorage  ← (A)
   │                                                      ▼
   │                                  CoverageBuildingCodec.sideIDs(points)
   │                                       → SYNTHETIC grid rectangles      ← (B)
   │                                       → stats, persistence, backend sync, summary
```

There are **two coverage truths**:

- **(A) Live map (real):** `MapLibreMapView` JS queries the OSM vector-tile `building` layer along the
  route and paints the actual buildings, persisting them to the WebView's `localStorage`
  (`myshachki.coveredBuildings.v2.<storageKey>`). See `processRouteCoordinates` /
  `queryRenderedBuildings` in `Myshachki/Components/MapLibreMapView.swift`.
- **(B) Swift side (synthetic):** `CoverageBuildingCodec` invents building "sides" as 30×24 m rectangles
  offset 28 m perpendicular to the path and snapped to a coarse grid. These do **not** correspond to any
  real building. See `Myshachki/Models/CoverageBuildingArea.swift`.

```50:107:Myshachki/Models/CoverageBuildingArea.swift
    static func sides(from points: [TrackPoint]) -> [CoverageBuildingSide] {
        guard points.count > 1 else { return [] }
        var seenIDs: Set<String> = []
        return zip(points, points.dropFirst()).flatMap { previous, current in
            sides(from: previous.coordinate, to: current.coordinate)
        }
        .filter { seenIDs.insert($0.id).inserted }
    }
```

Everything the user *reads* — "X buildings" on the summary, `ProgressCard`, backend coverage sync, and
the summary snapshot blocks — comes from **(B)**. Everything the user *sees painted while walking* comes
from **(A)**. They are computed differently and never compared.

---

## 3. Findings

### F1 — Two divergent coverage systems  ·  Severity: High

**Observation.** The number on the summary ("`\(newBuildingCount) buildings`") is derived from the
synthetic codec, not from the buildings that were actually highlighted on the map.

```32:34:Myshachki/ViewModels/WalkSummaryViewModel.swift
        self.newBuildingCount = CoverageBuildingCodec.buildingIDs(
            from: CoverageBuildingCodec.sideIDs(from: session.points)
        ).count
```

**Why it matters.**
- Stats are not trustworthy (count of imaginary parcels vs. real buildings painted).
- Backend coverage (`/coverage`) stores synthetic IDs; the painted-building set lives only in WebView
  `localStorage` and is never uploaded → coverage is not portable across devices/reinstalls and can't be
  rendered server-side.
- It makes the summary map hard to do correctly (F2), because Swift has no real building geometry to draw.

**Recommendation.** Establish **one source of truth: real OSM buildings**.
- During the live walk the JS already determines the real covered features. Bridge that set back to Swift
  via a new `WKScriptMessageHandler` message (e.g. `myshachkiCoverage` posting `{id, polygon, status}`),
  so `MapViewModel` owns the canonical covered-building set *with geometry*.
- Persist & sync *that* (id + minimal polygon) instead of synthetic side IDs.
- Keep `CoverageBuildingCodec` only as an offline fallback (no tiles loaded), clearly labeled.

**Effort:** Medium (1–2 days). Highest leverage — unlocks F2 and F3.

---

### F2 — Walk summary map is a synthetic drawing, not the real result  ·  Status: ✅ Fixed (2026-06-16)

> **Resolution:** `WalkSummaryView` now embeds the real `MapLibreMapView` with `fitsRouteBounds: true`,
> so the summary shows the actual basemap and the real route. It runs in a new **ephemeral** mode
> (`persistsCoverage: false`): it does **not** load or save the cumulative coverage cache, so it shows only
> the buildings detected by replaying *this* walk's route — rendered as `active`/**purple** and sitting on
> the path, in every mode. (Before, it reused the live map's `storageKey` and loaded all-time coverage as
> `explored`/yellow, which is why it "always showed the same place" in admin mode.) The synthetic
> `WalkSummarySnapshotView` (~257 lines) and its now-unused view-model helpers were deleted. The original
> finding is kept below for context. Per-session-*exact* coverage (independent of tile-render timing) is
> finalized by F1.


**Observation.** The current summary (`WalkSummarySnapshotView`) is a SwiftUI `Canvas` that fabricates the
map: a fake diagonal street grid, fake roads sprinkled along the route, and "discovered" blocks placed by
a deterministic jitter function — not real buildings.

```71:116:Myshachki/Views/WalkSummarySnapshotView.swift
    private func drawDiscoveredBlocks(
        in context: GraphicsContext,
        projection: SummarySnapshotProjection,
        palette: SnapshotPalette
    ) {
        guard routeCoordinates.count > 1 else { return }

        let blockCount = min(max(coverageAreas.count, 8), 34)
        ...
            let isExplored = index < routeCoordinates.count / 3
```

Only the **route polyline** is real; the streets and blocks are decorative. The "explored vs active"
split is literally "first third of the route." So the headline artifact of a finished walk doesn't show
what was actually covered.

**The good news:** the project already prototyped the right answer. `docs/sandbox/summary-map-sandbox.html`
renders a **real MapLibre basemap, fit to the route bounds, with the route + coverage polygons drawn as an
SVG overlay** — exactly the "small map of the result" the product wants. Rendered output:

![Summary map sandbox](sandbox/output/summary-map-sandbox.png)

And `MapLibreMapView` already supports this mode in-app: `fitsRouteBounds`, `renderSummaryOverlay`,
`scheduleSummaryRefreshes`, and the explored-route replay all exist for the summary use case. The WIP
diff *removed* the real map from the summary in favor of the Canvas — that's the regression to reverse.

**Recommendation (pick one):**
1. **Quick (reuse what exists):** Put `MapLibreMapView` back in the summary with `fitsRouteBounds: true`,
   `showsUserLocation: false`, and the **same `storageKey`** as the live map (they already match:
   `session.userId == profile.id`), so the WebView replays its persisted real buildings. To kill the
   "blank until tiles load" flakiness, also pass the covered building polygons via `buildingGeoJSON`
   (depends on F1) so the overlay is deterministic instead of relying on `queryRenderedFeatures` replay.
2. **Robust (static image):** Once F1 gives Swift the real polygons, render a **static snapshot** (the
   sandbox approach: basemap + SVG overlay, or `fitBounds` then capture) and show a `UIImage`. This is the
   most reliable for a results card — no live WebView lifecycle, instantly shareable.

For "nice to have interactive," option 1 gives it for free; option 2 can add a tap-to-expand.

**Effort:** Quick option ~half a day; robust option ~1 day on top of F1.

**Cleanup:** If you adopt a real map, delete `WalkSummarySnapshotView.swift` (≈257 lines of synthetic
drawing) rather than leaving two summary implementations.

---

### F3 — Coverage painting latency & inconsistency  ·  Severity: Med-High

**Observation.** Buildings are detected with `map.queryRenderedFeatures(...)` along the route. That API
**only returns features for tiles currently loaded and rendered** in the WebView viewport.

```1197:1208:Myshachki/Components/MapLibreMapView.swift
        function queryRenderedBuildings(x, y, radius) {
          const bounds = [
            [x - radius, y - radius],
            [x + radius, y + radius]
          ];
          try {
            return map.queryRenderedFeatures(bounds, renderedQueryOptions);
          } catch (error) {
            reportOnce('building-query', error);
            return [];
          }
        }
```

Consequences:
- **Tile-load dependency:** when you move into a fresh area, buildings aren't found until tiles download &
  render, then the next `idle`/`sourcedata`/rAF recompute fires → the visible delay you described.
- **Zoom dependency:** detection uses a fixed **pixel** radius (`buildingQueryRadiusPixels = 30`) and pixel
  sampling step (`routeSampleStepPixels = 34`). The covered *real-world* area therefore changes with zoom —
  more buildings caught when zoomed out, fewer when zoomed in.
- **Throttling/back-pressure:** recompute is gated behind `requestAnimationFrame` + an `idleRecomputeNeeded`
  flag, and active routes only re-scan the last few segments (`unprocessedActiveSegments` walks
  `coordinates.length - 4 … length`). Under sparse GPS or a busy main thread this lags.

**Recommendation.**
- Decouple detection from rendering: do point-in-polygon against building geometry rather than
  `queryRenderedFeatures`. Two viable sources — (a) `querySourceFeatures` on the vector source (not
  limited to the painted viewport, but still tile-gated), or (b) the F1 server/client building set with a
  proper spatial test. Prefer geometry-based hit testing with a **meters** buffer (e.g. 15–20 m corridor)
  so results are zoom-independent.
- If staying with the current JS approach short-term: switch the radius to a meters→pixels conversion at
  the current zoom, and pre-warm tiles by querying a bbox slightly ahead of travel direction.
- Consider moving coverage to a small server endpoint (`/map/coverage-candidates` already exists in
  `BackendSyncServing`) that intersects the polyline with real OSM building polygons — deterministic and
  device-independent.

**Effort:** Medium–High depending on path; the meters-radius + look-ahead tweak is a quick partial win.

---

### F4 — GPS "teleporting"  ·  Severity: Med-High

**Observation.** Raw `CLLocation`s are appended to the track essentially unfiltered (only an accuracy gate
and a 3 m min-move gate). There is **no smoothing of the recorded path** — no outlier rejection, no
speed/heading sanity check, no Kalman/exponential smoothing.

```533:544:Myshachki/ViewModels/MapViewModel.swift
    private func shouldAccept(location: CLLocation) -> Bool {
        if location.horizontalAccuracy < 0 || location.horizontalAccuracy > LocationManager.maxAcceptedHorizontalAccuracy {
            return false
        }
        if let lastAcceptedLocation {
            let movedDistance = location.distance(from: lastAcceptedLocation)
            if movedDistance < LocationManager.minimumMovementDistance {
                return false
            }
        }
        return true
    }
```

Contributing factors:
- `maxAcceptedHorizontalAccuracy = 50 m` is loose for a walking app — a 40 m-accurate fix can sit 40 m off
  and still be plotted, producing a visible jump.
- `distanceFilter = 1` + `kCLLocationAccuracyBest` yields frequent, jittery fixes; without smoothing the
  polyline zig-zags.
- The blue **dot** is animated in JS (`updateUserLocationSource` eases between fixes), but the **recorded
  route** and the **camera target** use the raw coordinate, so the dot glides while the line/camera jump —
  reinforcing the teleport feel.

**Recommendation (industry-standard pipeline):**
1. **Reject outliers:** drop fixes whose implied speed (`distance / Δt`) exceeds a walking ceiling
   (e.g. > 3–4 m/s sustained), and tighten accepted accuracy to ~20–25 m for recording (keep 50 m only for
   the first-fix bootstrap).
2. **Smooth the position:** apply a 1-D Kalman filter (classic for CL apps) or at least an
   exponential/secondary moving average on accepted coordinates before appending to the track and before
   driving the camera. Weight by `horizontalAccuracy`.
3. **Snap optional:** for a polished route line, map-match to the road/path network (server-side) — bigger
   effort, do later.
4. Drive the camera from the **smoothed** coordinate (see F5).

**Effort:** Medium. A Kalman/EMA filter + speed gate is a contained, high-impact change in `MapViewModel`/
`LocationManager`.

---

### F5 — Camera writes twice per fix and interrupts its own animation  ·  Severity: Med

**Observation.** On each accepted fix the camera center is set directly in `handleLocationUpdate`, then
again inside `refreshMapData()` (called from `consumeLatestLocationIfNeeded`). On the JS side, `applyCamera`
calls `map.stop()` before every `easeTo`, cancelling any in-flight ease (including the smooth user-dot
animation timing).

```423:434:Myshachki/ViewModels/MapViewModel.swift
    private func handleLocationUpdate(_ location: CLLocation) {
        userCoordinate = location.coordinate
        if isFollowingUser {
            setMapCenter(location.coordinate)
        }
        refreshLocationStatus()
        let consumedLocation = consumeLatestLocationIfNeeded(location)
        if !consumedLocation {
            updateExplorationState()
            refreshMapData()
        }
    }
```

```558:575:Myshachki/Components/MapLibreMapView.swift
        function applyCamera() {
          ...
          map.stop();
          map.easeTo({
            center: [pending.center.lon, pending.center.lat],
            zoom, pitch, bearing: 0, duration
          });
        }
```

**Recommendation.**
- Collapse to a **single** camera update per fix, fed by the smoothed coordinate from F4.
- Avoid `map.stop()` on every update; let `easeTo` retarget smoothly, or only `stop()` when the jump is
  large. Use a steadier follow (e.g. `easeTo` with a consistent ~700–1000 ms duration matching GPS cadence,
  or `panTo`).

**Effort:** Low.

---

### Smaller observations

- **Timer for elapsed time** uses a repeating `Timer` plus `consumeLatestLocationIfNeeded` also recomputing
  `elapsedTime` — minor duplication; fine, but a single clock source is cleaner. (`MapViewModel.startTimer`)
- **`localFeatureCollection()`** in `MapViewModel` is built but `mapFeatureGeoJSON` is always set to an empty
  collection in `refreshMapData()` — dead-ish path; confirm intent or remove.
- **Coverage normalization** (`normalizedCoverageIDs`) mixes two ID schemes (`building:v1:…` and
  `…:side:…` backend IDs) — a symptom of F1; unifying the model removes this.
- **WebView basemap** loads MapLibre + tiles from `unpkg`/`openfreemap` over the network. Offline or slow
  network = no basemap and no `queryRenderedFeatures` buildings. Consider bundling the MapLibre JS/CSS
  (you already vendored them in `docs/sandbox/vendor/`) and document the tile dependency.
- **`maxAcceptedHorizontalAccuracy`/`minimumMovementDistance`** are static constants on `LocationManager`
  but the policy lives in `MapViewModel`. Keep filtering policy in one place once F4 lands.

---

## 4. Recommended roadmap (prioritized)

**Phase 1 — Make the result honest (highest leverage)**
1. **F1**: Bridge real covered-building features from the WebView back to Swift; make that the single source
   of truth for stats, persistence, and backend sync.
2. **F2**: Restore a *real* map in the summary (reuse `MapLibreMapView` + `fitsRouteBounds`, feeding the F1
   polygons) or render a static snapshot image. Delete `WalkSummarySnapshotView`.

**Phase 2 — Make it feel smooth**
3. **F4**: Add speed-gate + Kalman/EMA smoothing; tighten accepted accuracy.
4. **F5**: Single, smoothed camera update; stop calling `map.stop()` every fix.

**Phase 3 — Make coverage robust**
5. **F3**: Move building detection to geometry-based, zoom-independent hit testing (client `querySourceFeatures`
   with a meters buffer, or the server `/map/coverage-candidates` endpoint).

**Quick wins you can land today (low risk):**
- Tighten `maxAcceptedHorizontalAccuracy` to ~25 m and add a speed-outlier gate in `shouldAccept`.
- Remove the duplicate camera write in `handleLocationUpdate` vs `refreshMapData`.
- Convert `buildingQueryRadiusPixels` to a meters-based radius at current zoom.

---

## 5. Appendix — key files

| Concern | File |
|---|---|
| GPS acquisition | `Myshachki/Services/LocationManager.swift` |
| Walk orchestration, filtering, camera | `Myshachki/ViewModels/MapViewModel.swift` |
| Live map + real coverage (JS) | `Myshachki/Components/MapLibreMapView.swift` |
| Synthetic coverage model | `Myshachki/Models/CoverageBuildingArea.swift` |
| Summary screen (now real map) | `Myshachki/Views/WalkSummaryView.swift` |
| Summary view model / stats | `Myshachki/ViewModels/WalkSummaryViewModel.swift` |
| Real-map summary prototype | `docs/sandbox/summary-map-sandbox.html` |
| Coverage persistence (local) | `Myshachki/Services/CoverageStore.swift` |
| Backend sync contract | `Myshachki/Services/BackendSyncService.swift` |
