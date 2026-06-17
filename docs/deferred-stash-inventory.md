# Deferred stash inventory

Date: 2026-06-17

This note records the app changes found while inspecting `stash@{0}` from `00:30:07`
(`WIP on main: 47229d0 activity fix`). The inspected app-file changes were parked
again as `stash@{0}` at `00:51:54` (`deferred app work from 2026-06-17 stash inspection`).
The original stash is still present as `stash@{1}`.

## Summary autofit bug

The proper focused fix is documented in `docs/walk-summary-autofit.md`: the walk
summary `WKWebView` is created at zero size, MapLibre fits the route too early,
and the map stays at the Warsaw fallback until a later state change re-runs the
data update. The current fix should be limited to retrying/refitting after the
MapLibre canvas has a real size.

## Deferred app changes from the stash

- `Cheeseek/Components/MapLibreMapView.swift`: large summary-map experiment with
  `persistsCoverage`, SVG summary overlay, preloaded building features, route
  layer restyling, summary route status handling, delayed refreshes, and JS error
  retry logging.
- `Cheeseek/ViewModels/WalkSummaryViewModel.swift`: summary-specific map style
  and perspective inputs, route interpolation, `summaryCoverageGeoJSON`, pace
  text, and route status changed to `summary`.
- `Cheeseek/Views/WalkSummaryView.swift`: removes the save button, increases
  map height, passes map style/perspective data, disables persisted coverage for
  the summary map, and switches the secondary stat from new area to pace.
- `Cheeseek/Extensions/Formatting.swift`: adds `formattedPace`.
- `Cheeseek/Services/WalkLiveActivityService.swift`: resets existing Live
  Activities before starting a new one and makes start asynchronous.
- `Cheeseek/Views/ActivityView.swift`, `Cheeseek/Views/MapScreen.swift`, and
  `Cheeseek/Views/RootTabView.swift`: pass current map style/perspective into
  summary screens from map and activity flows.

Keep these deferred until the focused walk-summary autofit fix is checked.
