# Fix: Walk summary map should focus on the session immediately (no "Save" tap needed)

**Date:** 2026-06-17
**Area:** `WalkSummaryView` + `MapLibreMapView` (the summary map after a walk finishes).
**Goal:** When the summary opens after tapping **Finish**, the map must immediately fit/focus on the
just-finished session — the same result you currently only get after tapping **Save to Shared Map**.

---

## 1. Root cause

The summary map runs in a `WKWebView` created with `frame: .zero`. MapLibre reads the container size
**once at map creation** and the first `fitRouteBounds()` runs while the presenting sheet is still
animating, i.e. **before** SwiftUI gives the WebView its final size. Fitting against a ~0-size canvas
does nothing, so the camera stays at the hardcoded initial position:

```108:115:Myshachki/Components/MapLibreMapView.swift
        const map = new maplibregl.Map({
          container: 'map',
          style: fallbackStyle,
          center: [21.0122, 52.2297],
          zoom: 15.3,
          pitch: 0,
          attributionControl: false
        });
```

That `center: [21.0122, 52.2297]` is the Warsaw default → "it always shows the same place."

After layout settles, MapLibre auto-resizes its canvas (default `trackResize` listens to the WebView's
window-resize), **but nothing re-runs `fitBounds`**, so the camera never moves to the route.

### Why tapping "Save to Shared Map" appears to fix it
`WalkSummaryViewModel.routeGeoJSON` encodes the route status from the sync state:

```47:49:Myshachki/ViewModels/WalkSummaryViewModel.swift
    var routeGeoJSON: String {
        guard session.points.count > 1 else { return emptyFeatureCollection }
        let routeStatus = syncStatusText == SyncStatus.synced.label ? "explored" : "active"
```

When sync **succeeds**, `syncStatusText` becomes "Synced", so `routeStatus` flips `active → explored`.
That changes the generated JS string, which **defeats the de-dup guard** in `Coordinator.enqueue`
(`lastEvaluatedScript == script` no longer matches), so a fresh `myshachkiSetData(...)` →
`applyData()` → `fitRouteBounds()` runs — and by now the WebView has its real size, so the fit works.

So the button is not doing anything map-specific; it just triggers a **second fit after layout settles**.
It also only works when the backend sync actually succeeds. We want this to happen automatically on
Finish, regardless of backend.

---

## 2. The fix (recommended): re-fit on container resize + guard tiny canvas

Two small, self-contained changes in `Myshachki/Components/MapLibreMapView.swift` (the embedded JS).
No Swift/view changes required; backend-independent.

### Change A — guard `fitRouteBounds` against an unusable canvas size

Find `fitRouteBounds` (around lines 1015–1029):

```1015:1029:Myshachki/Components/MapLibreMapView.swift
        function fitRouteBounds() {
          const coordinates = currentRouteFeatures().flatMap(feature => feature.geometry.coordinates);
          if (coordinates.length < 2) {
            map.easeTo({ center: [pending.center.lon, pending.center.lat], zoom: 15.8, duration: 220 });
            return;
          }
          const bounds = coordinates.reduce((currentBounds, coordinate) => {
            return currentBounds.extend(coordinate);
          }, new maplibregl.LngLatBounds(coordinates[0], coordinates[0]));
          map.fitBounds(bounds, {
            padding: { top: 26, bottom: 26, left: 26, right: 26 },
            maxZoom: 17.2,
            duration: 280
          });
        }
```

Add a size guard at the top so a 0-size fit is skipped (it will be retried on resize, see Change B):

```js
        function fitRouteBounds() {
          const canvas = map.getCanvas();
          if (!canvas || canvas.clientWidth < 2 || canvas.clientHeight < 2) {
            // Container not laid out yet; the resize listener will re-fit once it is.
            return;
          }
          const coordinates = currentRouteFeatures().flatMap(feature => feature.geometry.coordinates);
          // ... unchanged ...
        }
```

### Change B — re-fit whenever the map resizes

MapLibre emits a `resize` event when its canvas size changes (including the auto window-resize that
fires once SwiftUI lays the WebView out). Add a listener next to the other `map.on(...)` handlers
(near lines 1195–1223). When in summary mode (`fitsRouteBounds`), re-fit:

```js
        map.on('resize', () => {
          if (pending.options && pending.options.fitsRouteBounds) {
            fitRouteBounds();
          }
        });
```

That is the core fix: the first fit is skipped (Change A) because the canvas is tiny; when the WebView
gets its real size, `resize` fires and `fitRouteBounds()` runs against a valid canvas → the map focuses
on the session immediately, with no Save tap and no backend.

> Optional robustness: also schedule a couple of delayed re-fits after data is set, to cover slow tile
> loads / animation timing. In `applyData()` where it calls `fitRouteBounds()`, you can add:
> ```js
>           if (pending.options.fitsRouteBounds) {
>             fitRouteBounds();
>             [120, 420, 900].forEach(delay => setTimeout(() => {
>               if (pending.options.fitsRouteBounds) fitRouteBounds();
>             }, delay));
>           } else {
>             applyCamera();
>           }
> ```

---

## 3. Alternative / belt-and-suspenders: an explicit fit hook from SwiftUI

If you want SwiftUI to be able to force a fit (e.g. on `onAppear`) without depending on resize timing,
expose a JS function and call it after presentation.

**JS (MapLibreMapView html):** add near the other globals:

```js
        window.myshachkiFitRoute = function() {
          if (pending.options && pending.options.fitsRouteBounds) {
            map.resize();
            fitRouteBounds();
          }
        };
```

**SwiftUI (WalkSummaryView):** after the map appears, ask for a fit once layout has settled. Add to the
`MapLibreMapView` usage:

```swift
                        MapLibreMapView(
                            center: viewModel.mapCenterCoordinate,
                            buildingGeoJSON: #"{"type":"FeatureCollection","features":[]}"#,
                            routeGeoJSON: viewModel.routeGeoJSON,
                            storageKey: viewModel.mapStorageKey,
                            showsUserLocation: false,
                            fitsRouteBounds: true
                        )
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
```

To call `window.myshachkiFitRoute()` you need a handle to the `WKWebView`. The cleanest way is to add an
optional `onReady: (() -> Void)?` (or a `fitToken: Int`) to `MapLibreMapView`:

- Add `var fitToken: Int = 0` to `MapLibreMapView`. Include it in the generated script as a harmless
  comment, e.g. append `// fit:\(fitToken)` to the `script` string in `updateUIView`. Because the string
  changes, `Coordinator.enqueue`'s de-dup is bypassed and `myshachkiSetData` re-runs → re-fit. This is
  exactly what the Save button does today, but triggered deliberately.
- In `WalkSummaryView`, keep `@State private var fitToken = 0` and bump it from `.task`/`.onAppear` after
  a short delay:

```swift
        .task {
            try? await Task.sleep(nanoseconds: 350_000_000) // ~0.35s, after sheet settles
            fitToken += 1
        }
```

Prefer **Section 2** (resize listener) as the primary fix; it addresses the real cause. Use this hook
only if you still see timing flakiness on slower devices.

---

## 4. Wire it to Finish (already correct, just confirm)

No change needed in the Finish path: `MapViewModel.finishWalk()` already sets `summarySession = session`,
which presents the summary sheet (`MapScreen.sheet(item:)`). With Section 2 in place, the map fits on
present. The "Save to Shared Map" button can remain for its real purpose (cloud upload), or be removed —
it is no longer required for the map to render correctly.

---

## 5. Verification

1. Build & run; in admin mode start a walk, step around with the N/E/S/W controls, tap **Finish**.
2. The summary map must open already centered/zoomed on the route — **without** tapping Save, and with the
   backend offline ("Sync failed" is fine).
3. Resize sanity check: rotate the simulator or present the sheet again — the map should re-fit, not jump
   to Warsaw.
4. Console should not show repeated `fitBounds` errors; `[myshachki-perf]` logs continue normally.

> Related, but separate: the buildings rendering yellow/cumulative vs purple/this-session is the
> `persistsCoverage` + load-order fix and the single-source-of-truth work (see
> `docs/walk-experience-review.md` §F2 and `docs/walk-experience-design.md` §F1). This auto-fit fix only
> addresses camera focus.
