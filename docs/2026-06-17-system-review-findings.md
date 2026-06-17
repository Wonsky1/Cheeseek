# Cheeseek System Review Findings

**Date:** 2026-06-17  
**Scope:** iOS app, MapLibre/WebView coverage logic, local stores, FastAPI backend, and future design docs.  
**Source docs carried forward:** `docs/walk-experience-review.md`, `docs/walk-experience-design.md`, `docs/plans/2026-06-08-walking-exploration-mvp.md`, and `docs/plans/2026-06-08-backend-requirements-prompt.md`.

This document is the consolidated punch-list for the current app/backend. It intentionally focuses on issues and future improvements, not on what already works.

## Findings

### F1 — Active route rendering truncates after ~700 interpolated coordinates

**Severity:** High  
**Area:** iOS route rendering, coverage detection, summary map

`MapViewModel.interpolatedRouteCoordinates` and `WalkSummaryViewModel.interpolatedRouteCoordinates` interpolate every route segment at roughly 2 m intervals, then return once `coordinates.count >= 700`. That means long walks can stop rendering the route after roughly 1.4 km of interpolated path. Because the WebView coverage logic receives the generated route GeoJSON, this can also make building detection and summary coverage incomplete.

**Evidence**

- `Cheeseek/ViewModels/MapViewModel.swift`
  - `liveRouteInterpolationStepMeters = 2.0`
  - `maxLiveRouteVisualCoordinates = 700`
  - early return in `interpolatedRouteCoordinates`
- `Cheeseek/ViewModels/WalkSummaryViewModel.swift`
  - same 2 m interpolation and 700 coordinate cap

**Recommendation**

Replace raw interpolation plus truncation with route simplification and/or tail-preserving sampling.

Options:

1. Keep full recorded points for persistence and sync.
2. Generate display GeoJSON with a bounded simplification algorithm such as Douglas-Peucker.
3. For live updates, include the full historical simplified route plus the newest tail, not only the first 700 interpolated points.
4. Add unit tests for short, medium, and long routes so the rendered final coordinate still reaches the walk endpoint.

### F2 — Finished sessions may not appear in Activity tab

**Severity:** High  
**Status:** Fixed in the backend-owned history pass on 2026-06-17. Keep the finding as regression context.  
**Area:** iOS backend history, Activity tab, post-finish refresh

Reported bug: after a session is finished, the Activity tab still shows "No walks yet".

Root cause: the app had two competing history paths. `MapViewModel.finishWalk()` could publish local saved state while backend sync was still pending, and `ActivityViewModel.refresh()` tried to merge local sessions with backend sessions. The product direction is now clearer: backend is expected to be always on and is the source of truth for finished walk history.

**Fix applied**

- `MapViewModel.finishWalk()` now uploads the finished session to the backend before publishing it as completed history.
- `ActivityViewModel.refresh()` now reads walk history from backend only.
- The local walk JSON store was removed from the app dependency graph.
- `RootTabView` refreshes Activity from the explicit `walkHistoryRevision` signal.
- A Swift test target was added with regression coverage for backend-owned Finish and Activity rendering.

**Remaining hardening**

If offline recording becomes a requirement later, implement it as an explicit outbox/retry feature. Do not reintroduce ad hoc local Activity history as a hidden second source of truth.

Acceptance criteria:

- A finished walk appears in Activity after backend save succeeds.
- Activity history matches `/walk-sessions` for the current profile.
- If backend save fails, Activity does not show a fake local-only walk.
- It remains visible after app restart because it is fetched from backend.

### F3 — Startup does not render existing coverage until a new walk starts

**Severity:** High  
**Area:** startup restore, coverage rendering, offline/after-kill experience

Reported bug: on first startup, or after the process was killed and reloaded, coverage is not rendered until the user starts walking.

This matches the current shape of the code. `MapViewModel.refreshCoverage()` loads local and remote synthetic coverage IDs into `persistedCoverageSideIDs`, but `refreshMapData()` always sets `mapFeatureGeoJSON` to an empty FeatureCollection. The local `localFeatureCollection()` helper exists but is not wired into the WebView. Separately, the WebView can load real covered buildings from its own `localStorage`, but that is separate from Swift's `CoverageStore` and backend coverage state.

**Evidence**

- `MapViewModel.refreshCoverage()` loads and merges `CoverageStore` and backend coverage.
- `MapViewModel.updateExplorationState()` computes `exploredBuildingAreas`.
- `MapViewModel.localFeatureCollection()` converts those areas to GeoJSON.
- `MapViewModel.refreshMapData()` sets `mapFeatureGeoJSON = empty`.
- `MapLibreMapView.loadPersistedFeaturesIfNeeded()` loads only WebView `localStorage`, not Swift/backend coverage.

**Recommendation**

Short-term:

1. Pass `localFeatureCollection()` into `mapFeatureGeoJSON` on startup after `refreshCoverage()`.
2. Call `refreshMapData()` after coverage changes so the WebView receives the restored overlay.
3. Add a launch/reload test: seed coverage, restart app, verify map paints coverage before starting a walk.

Long-term:

This should be solved by F4/F5 below: one canonical `CoveredBuilding` model, stored by Swift and synced by backend, with WebView `localStorage` treated only as a rendering cache.

### F4 — Coverage has two sources of truth

**Severity:** High  
**Area:** coverage model, stats, summary, backend sync

This is carried forward from `docs/walk-experience-review.md` and `docs/walk-experience-design.md`.

Today:

- WebView/JS detects real OSM buildings via `queryRenderedFeatures`.
- WebView persists those real building polygons only in `localStorage`.
- Swift computes synthetic `CoverageBuildingCodec` building-side IDs from GPS points.
- Backend `/coverage` stores synthetic IDs.
- Summary and stats can count something different from what the map visibly painted.

**Recommendation**

Adopt one canonical model:

```swift
struct CoveredBuilding: Codable, Identifiable, Equatable {
    let id: String
    let polygon: [Coordinate2D]
    var firstCoveredAt: Date
    var firstCoveredSessionId: UUID?
    var lastSeenAt: Date
}
```

Swift should own the canonical covered-building set. The WebView should report newly covered real buildings to Swift through the existing `cheeseekCoverage` bridge. Backend coverage should store real building IDs plus geometry, not opaque synthetic side IDs.

Migration:

1. Version the coverage storage key.
2. Treat WebView `localStorage` as an import/cache source, not the truth.
3. Keep `CoverageBuildingCodec` only as an offline fallback until server-side geometry is ready.
4. Update summary and progress counts to use `CoveredBuilding` records.

### F5 — Coverage detection depends on rendered tiles and viewport zoom

**Severity:** Medium-High  
**Area:** map algorithm, latency, correctness

This is carried forward from the future design docs.

The WebView currently detects covered buildings by sampling the route in screen pixels and calling `map.queryRenderedFeatures` around each sample point. That only sees rendered tiles/layers and the physical corridor changes with zoom.

**Recommendation**

Incremental path:

1. Convert building query radius and route sample step from pixels to meters.
2. Warm or query tiles ahead of the user's movement direction.
3. Move from `queryRenderedFeatures` to `querySourceFeatures` plus explicit geometry checks.
4. Best long-term path: server-side intersection using real OSM building polygons, ideally in PostGIS.

Acceptance criteria:

- Same physical route produces the same covered-building set at zoom 14 and zoom 18.
- Fresh area coverage appears within about 1 second on normal connection.
- Summary uses the exact session-covered set, not a replay that depends on tile timing.

### F6 — GPS pipeline needs smoothing, outlier rejection, and single-camera follow

**Severity:** Medium-High  
**Area:** location quality, distance accuracy, perceived movement

This is carried forward from the future design docs.

Current behavior:

- `LocationManager` publishes only the last item from a CoreLocation batch.
- `MapViewModel.shouldAccept` checks only horizontal accuracy and minimum movement.
- There is no stale timestamp check, speed gate, Kalman/EMA smoothing, or map matching.
- The user dot is visually animated in JS, but the recorded route and camera use raw coordinates.

**Recommendation**

Introduce a `LocationProcessor` between `LocationManager` and `MapViewModel`.

Pipeline:

1. Process every received `CLLocation`, not just `locations.last`.
2. Drop invalid/stale fixes.
3. Keep a looser bootstrap accuracy gate, then tighten recording accuracy to around 20-25 m.
4. Drop impossible walking speeds, e.g. sustained > 4 m/s.
5. Apply Kalman or accuracy-weighted EMA smoothing.
6. Append and draw the smoothed coordinate.
7. Drive the camera from the same smoothed coordinate.

Also remove duplicate camera writes and avoid calling `map.stop()` on every JS camera update.

### F7 — Finish flow blocks user feedback on backend sync

**Severity:** High  
**Status:** Changed to backend-owned completion on 2026-06-17.  
**Area:** session finish UX, offline behavior

Previous behavior: `MapViewModel.finishWalk()` could publish local state before backend history was confirmed. That made the UI look successful even when Activity, which needs backend history, still had nothing to show.

Current behavior: backend save is the completion boundary for finished history. The finished state, summary, stored routes, and Activity refresh signal update after `syncWalkSession` succeeds. If backend save fails, the walk stays retryable and Activity remains backend-truthful.

**Remaining recommendation**

If offline recording becomes a requirement, add a formal outbox:

1. Enqueue backend sync events explicitly.
2. Retry in foreground/background lifecycle.
3. Keep Activity visually clear that an item is not server-backed yet.
4. Store retry metadata and last error.

The user should never wait for backend availability to see their completed walk.

### F8 — Backend storage is in-memory; migrate to durable database

**Severity:** High  
**Area:** backend durability, reinstall recovery, multi-device restore

Current backend README says in-memory storage is intentional for the POC. That is fine for a very early prototype, but it contradicts the original backend requirements and the product need: server storage exists so walks survive reinstall, device loss, and app data deletion.

**Recommendation**

Move backend persistence to PostgreSQL. If map/coverage geometry will be server-side, use PostgreSQL + PostGIS rather than plain PostgreSQL.

Why Postgres/PostGIS fits:

- durable storage for profiles, sessions, points, coverage, and sync outbox acknowledgements
- strong constraints for ownership and idempotency
- indexes for user/session lookup
- geometry types and spatial indexes for building coverage intersection later
- future partner/group support without rewriting storage

Minimum schema direction:

- `profiles`
- `devices`
- `walk_sessions`
- `track_points`
- `covered_buildings`
- `coverage_events`
- `sync_events` or `client_mutation_log`
- later: `groups`, `memberships`, `partner_links`

Implementation notes:

1. Use SQLAlchemy and Alembic migrations.
2. Keep SQLite only as a local dev/test option if useful.
3. Enforce foreign keys and ownership in the database and service layer.
4. Make `/health` remain liveness-only and add `/ready` for database readiness.

### F9 — Backend ownership and profile validation are incomplete

**Severity:** High  
**Area:** API correctness, data safety

Current backend behavior:

- `POST /walk-sessions` accepts any `userId` and does not validate that the profile exists.
- If a session ID already exists, the incoming payload can overwrite the existing session owner.
- `/coverage` returns empty coverage for unknown users instead of rejecting unknown profile IDs.
- Routes/progress are globally accessible under nickname-only POC identity.

The original backend requirements explicitly asked for profile validation and `404` on missing profiles.

**Recommendation**

Even before real auth:

1. Validate `userId` exists on every write/read that is scoped to a user.
2. On session upsert, if the session exists and `userId` differs, return `403`.
3. Keep point upload owner validation.
4. Add tests for missing profile and owner overwrite attempts.
5. Document nickname-only identity as a POC limitation.

### F10 — Device-only information needs a backup/sync design

**Severity:** High  
**Area:** data ownership, offline-first sync, recovery

The app currently keeps several important pieces of state only on the device or only in WebView storage:

- local profile/device ID in `UserDefaults`
- backend base URL and preferences in `UserDefaults`
- synthetic coverage IDs in `CoverageStore`
- real covered building polygons in WebView `localStorage`
- map style/perspective preferences in `UserDefaults`

Local cache is good for speed. It should not be the only durable place for important domain data.

**Recommended data policy**

Server authoritative:

- profile identity
- device registrations
- finished walk sessions
- track points
- real covered buildings and coverage events
- shared progress
- partner/group relationships later

Device authoritative or device-only:

- currently selected tab/view
- map style/perspective preference
- admin simulator state
- transient Live Activity state
- short-lived map render cache

Device as write-ahead cache:

- newly accepted track points
- newly covered buildings
- unsynced session metadata, only if formal offline mode is added
- failed sync attempts, only if formal offline mode is added

**Recommended sync design**

Add a local outbox. Every important local mutation writes two things:

1. the local domain state for immediate UI
2. an idempotent outbox event for server backup

Example event types:

- `profile.upserted`
- `walk_session.started`
- `walk_session.finished`
- `track_points.appended`
- `coverage.buildings_covered`
- `settings.server_url_changed` if you decide to back it up later

Each event should have:

- stable event ID
- entity ID
- user ID
- device ID
- created-at timestamp
- payload version
- retry count/status
- last error

**When to sync**

Immediate sync triggers:

- after profile create/relink
- every N accepted track points or every 30-60 seconds during recording
- after a batch of newly covered buildings
- when finishing a walk
- when pressing manual refresh

Lifecycle sync triggers:

- app launch
- app enters foreground
- network becomes reachable
- app enters background, with a best-effort flush
- periodic foreground timer while recording

Important rule:

Current product rule: finished walk history commits after server acknowledgement. A future offline mode can relax this only if it clearly labels unsynced items and uses a real outbox.

Conflict/idempotency rules:

- client-generated UUIDs for sessions, points, buildings, and outbox events
- server upserts by stable IDs
- server returns `updatedAt`, revision, or sync cursor
- client periodically fetches server truth and merges
- server never deletes local-only entities unless a tombstone/delete event exists

### F11 — Summary coverage can mix session and all-time coverage

**Severity:** High  
**Area:** walk summary correctness

The summary receives `summaryCoverageGeoJSON` from `currentSessionCoverageGeoJSON`, but the posted WebView coverage payload is built from the merged overlay. That overlay can include persisted/all-time features and active features. Old activity summaries can also be affected because summary mode can load cached `localStorage` if no preloaded buildings exist.

**Recommendation**

Once `CoveredBuilding` exists, summary should receive exactly:

- route for this session
- buildings first covered during this session
- optionally all-time already-covered buildings as a separate, clearly styled layer

Do not derive per-session summary by replaying a route against whatever tiles happen to load.

### F12 — Map and backend feature paths are disconnected/dead-ish

**Severity:** Medium  
**Area:** maintainability

Current examples:

- `BackendSyncService.fetchMapFeatures` exists, but `MapViewModel.refreshBackendMapData()` only calls `refreshMapData()`.
- `MapViewModel.localFeatureCollection()` exists, but `mapFeatureGeoJSON` is always set to empty.
- `refreshBackendCoverageCandidates()` exists but is not called.
- `CoverageSegmentCodec` appears unused.
- `FilterSegmentControl` exists, but `MapFilter` only has `.me`.

**Recommendation**

Decide which direction the map is going:

1. WebView-only real OSM building detection with Swift bridge.
2. Backend/PostGIS coverage detection.
3. Hybrid short-term approach.

Then delete or wire the unused path. Dead map/coverage paths are risky because they look like safety nets but do not actually run.

### F13 — Backend map-vector algorithm is a prototype and needs spatial rigor

**Severity:** Medium  
**Area:** server-side map/coverage

Current backend map vector logic:

- fetches OSM data from Overpass on demand
- silently catches all Overpass failures
- marks failed bboxes as loaded empty areas
- uses endpoint-to-segment distance that can miss crossing segments
- does O(n) loops over loaded buildings/edges
- has no bbox size limit

**Recommendation**

For the durable backend:

1. Move OSM building/road data into PostGIS or a prepared local dataset.
2. Use spatial indexes.
3. Use real line-buffer / polygon intersection.
4. Validate bbox order and maximum area.
5. Do not cache failed Overpass requests as successful empty loads.

### F14 — Runtime external dependencies are brittle

**Severity:** Low-Medium  
**Area:** reliability, repeatability

The iOS map loads MapLibre JS/CSS from `unpkg` and tiles/fonts from OpenFreeMap at runtime. The app also has a hardcoded ngrok backend URL as default configuration.

**Recommendation**

- Bundle MapLibre JS/CSS locally if keeping WKWebView.
- Make default backend URL environment/build-config driven.
- Keep tile dependency documented and consider a graceful offline state.
- Do not use a temporary tunnel URL as a production default.

### F15 — No Swift automated tests for the highest-risk algorithms

**Severity:** Medium  
**Area:** quality

Backend has pytest coverage. A Swift test target now exists and includes backend-owned Finish/Activity regression tests, but the riskiest logic still needs broader coverage:

- route simplification/truncation
- GPS filtering/smoothing
- coverage restoration on startup
- sync state transitions

**Recommendation**

Broaden Swift coverage with pure logic tests:

1. `LocationProcessorTests`
2. `RouteGeometryTests`
3. `WalkSessionRepositoryTests`
4. `CoverageStoreTests`
5. `ActivityRefreshTests`

For WebView coverage behavior, keep a small deterministic JS harness or integration smoke test if practical.

### F16 — GitHub foundation is now in place; keep CI as the baseline

**Severity:** High  
**Status:** Completed on 2026-06-17.  
**Area:** project operations, collaboration, backup, CI/CD foundation

Both repos have now been moved to GitHub, which removes the biggest operational blocker around backup, collaboration, and deployment hooks. The next step here is not another migration task; it is keeping CI present and useful so every later storage/deploy change has a basic safety net.

**Recommendation**

Keep the following in place:

1. Separate GitHub repositories for `Cheeseek` and `cheeseek-backend`.
2. Branch protection for `main`.
3. `.gitignore` coverage for Xcode derived data, secrets, local environment files, tunnel URLs, and backend `.env`.
4. Minimal GitHub Actions:
   - iOS: `xcodebuild build-for-testing -project Cheeseek.xcodeproj -scheme Cheeseek`
   - Backend: `uv sync --frozen` and `uv run python -m pytest`
5. README setup docs in each repo.

The CI baseline should stay lightweight until the startup-coverage and durable-storage work settles.

### F17 — Backend autodeploy needs a design before implementation

**Severity:** High  
**Area:** backend delivery, reliability, operations

Backend deployment should be designed before adding production database work, otherwise migrations, secrets, health checks, and rollback behavior will be patched in late.

**Recommendation**

Design the deployment plan around:

1. target host/platform
2. PostgreSQL/PostGIS provisioning
3. environment variables and secret storage
4. build/start command
5. `/health` for liveness and `/ready` for database readiness
6. Alembic migration execution
7. deploy trigger from GitHub pushes
8. rollback strategy
9. log access and basic monitoring
10. separate staging/prod settings, even if production starts as one small instance

Autodeploy design should happen after the immediate app correctness fixes, but still before backend persistence migration begins.

## Proposed Implementation Sequence

Completed in current pass:

- **History and Activity correctness**
  - Finished walks are uploaded before becoming completed history.
  - Activity reads backend history only.
  - The local walk JSON store was removed from the app path.
  - Regression tests were added and compile successfully.

Next priorities:

1. **Startup coverage restore**
   - Render stored coverage on startup.
   - Confirm after process kill/relaunch.

2. **Single coverage source of truth**
   - Add `CoveredBuilding`.
   - Bridge newly covered real buildings from JS to Swift.
   - Sync real buildings to backend.

3. **Backend deployment baseline**
   - Keep both repos on GitHub with branch protection.
   - Keep the new GitHub Actions workflows green.
   - Pick hosting/deployment approach, env/secrets, health/readiness, migrations, rollback, and logs.
   - Make sure the deploy design supports the upcoming PostgreSQL/PostGIS migration.

4. **Durable backend**
   - Move from in-memory to PostgreSQL/PostGIS.
   - Add migrations and ownership constraints.

5. **Outbox and backup sync**
   - Add local mutation queue.
   - Sync on important events and lifecycle triggers.

6. **GPS and camera quality**
   - Add location processor.
   - Smooth route/camera.

7. **Deterministic coverage detection**
   - Replace rendered-tile dependency with geometry-based detection.

8. **Cleanup**
   - Remove or wire unused map/backend paths.
   - Add tests for the chosen path.

## Verification Notes From Review

Commands run during review:

```bash
uv run python -m pytest
```

Result: 11 backend tests passed.

```bash
xcodebuild build-for-testing -project Cheeseek.xcodeproj -scheme Cheeseek -destination 'generic/platform=iOS Simulator'
```

Result: Swift test target and app test bundle compiled successfully.

```bash
xcodebuild -project Cheeseek.xcodeproj -scheme Cheeseek -destination 'generic/platform=iOS Simulator' build
```

Result: iOS app and Live Activity extension built successfully.

Remaining verification gap:

- `xcodebuild test-without-building` currently stalls in Xcode's runner before executing tests with `waiting for workers to materialize`. The test bundle compiles, but the local test runner did not report XCTest results.
- Startup coverage bug still needs simulator reproduction after its fix is implemented.
