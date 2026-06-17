# Walking Exploration MVP Implementation Plan

> **For agentic workers:** Implement this plan task-by-task. Use checkbox (`- [ ]`) steps for tracking. Preferred execution skills: `~/.codex/skills/subagent-driven-development/SKILL.md` (this session, per-task subagents) or a parallel session with `~/.codex/skills/executing-plans/SKILL.md`.

**Goal:** Turn the starter SwiftUI app into a polished server-backed iOS MVP that records live walks, draws routes on a MapKit map, persists sessions locally while walking, and syncs profiles/walk history to a private backend so data survives app reinstalls.

**Architecture:** Use a small MVVM architecture with native Apple frameworks on iOS. Keep domain models Codable and UI-independent, put GPS tracking, local persistence, and network sync behind services, and let SwiftUI views consume observable view models. The backend POC should expose a tiny REST API with nickname-only profiles now, while keeping room for real auth later.

**Tech Stack:** SwiftUI, MapKit, CoreLocation, URLSession, Foundation Codable file storage, Xcode project with filesystem-synchronized source group. Backend POC: FastAPI plus SQLite for simplest deployment, or PostgreSQL if already available on the server. No paid APIs, external map SDKs, Firebase, or iOS package dependencies.

---

## Dev-Pipeline Route

We are in `dev-pipeline` planning-only mode.

- **Phase 1: Strategic Planner** was compressed because the pasted brief is already detailed and the user explicitly asked for a plan.
- **Phase 2: Solution Architect** is included below as the target architecture.
- **Phase 3: Task Decomposer / Writing Plans** is included as ordered implementation tasks.
- **Phase 4: Implementation** is intentionally not performed in this handoff.
- **Phase 5: Quality Gate** is described as verification commands and manual checks for the implementer.

Assumption to confirm if needed: there is no existing backend repo yet. This plan assumes a new lightweight backend can live under `/Users/vlad/Xcode projects/Cheeseek/backend/` for the POC, then later move to a separate repo/server deployment if desired.

Backend build handoff prompt/spec:

- `/Users/vlad/Xcode projects/Cheeseek/docs/plans/2026-06-08-backend-requirements-prompt.md`

## Current Project Context

- Repo root: `/Users/vlad/Xcode projects/Cheeseek`
- Xcode project: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek.xcodeproj`
- Existing source files:
  - `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/CheeseekApp.swift`
  - `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/ContentView.swift`
- Existing app is a default "Hello, world!" SwiftUI starter.
- The project uses `PBXFileSystemSynchronizedRootGroup` for the `Cheeseek/` folder. New Swift files placed under `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/` should be picked up by Xcode without manually adding PBX file references.
- `GENERATE_INFOPLIST_FILE = YES`, so location permission text should be added through build settings unless the implementer chooses to create a custom Info.plist.
- Current target settings include iOS, iOS Simulator, macOS, and xros. This MVP is iOS-first and should be built against iPhone/iPad simulator or device destinations.
- Current bundle identifier: `wonsky.Cheeseek`
- Current deployment target: `26.5`
- Swift default actor isolation: `MainActor`

## Context Brief

- **Goal:** Two-person private walking app MVP that visually marks explored routes, records live walking sessions locally, and stores durable history on the user's private server.
- **Consumers:** Two manually installed iPhone users living together.
- **Scale:** Very small local dataset at MVP stage; later shared progress for two users.
- **Latency/Freshness:** Live route drawing while the app is foregrounded; local saves should feel immediate.
- **Growth:** Backend sync, partner routes, covered street segments, and possible background tracking later.
- **Failure tolerance:** Losing recorded walks is the biggest MVP failure; backend failures should not block local recording, and unsynced sessions must remain queued locally.
- **Infra:** Native iOS frameworks, user-owned server, FastAPI POC backend, SQLite or PostgreSQL database.
- **Team:** Small/personal project; optimize for readability and simple extension.
- **Timeline:** Local working MVP first, no App Store release requirement.

## Strategic Scope

### In Scope

- Full-screen MapKit-based main map.
- User location display.
- Mock completed/partner/together route overlays.
- Filter segmented control: Me, Partner, Together, All.
- Local walk lifecycle: idle, recording, paused, finished.
- Live route polyline while walking.
- GPS permission and foreground tracking via CoreLocation.
- GPS point filtering by accuracy and minimum movement.
- Local Codable file persistence for `WalkSession` and `TrackPoint`.
- Nickname-only user profile POC.
- Server persistence for profiles, walk sessions, and track points.
- Restore/sync from server after reinstall using nickname lookup for POC.
- Summary screen after finishing a walk.
- Real backend API client/service for the POC, with mock implementations only for previews/offline development.
- Polished SwiftUI UI components: floating cards, primary buttons, tabs, live card, summary stat cards, legend.
- Info.plist permission text for when-in-use location.
- Build verification on iOS Simulator.

### Out of Scope

- Firebase, Mapbox, Google Maps, paid services, or external dependencies.
- Background location tracking.
- Street-segment coverage algorithms.
- Real shared progress calculations.
- Real auth, passwords, OAuth, sessions, refresh tokens, and production identity management.
- App Store production hardening.
- Cloud conflict resolution.

### Backend/User POC Slice

Because the app will be installed manually through Xcode, local app data may disappear during reinstalls or device changes. Treat the server as the durable source of truth and the phone as a recorder/cache.

POC identity model:

- A user profile is just a nickname.
- The backend assigns a stable `userId` UUID.
- The iOS app stores `userId` and nickname locally after onboarding.
- If the app is reinstalled, the user can enter the same nickname to fetch/relink the profile for the POC.
- Later, replace nickname relinking with proper authentication. Do not design the POC as secure identity.

Handy addition: also store a generated `deviceId` locally so the backend can tell which manually installed phone uploaded a walk. This is not auth; it is debugging/traceability.

### Add-On Slice: Cheese Hunt Mode

This is a strong follow-up slice after the walking MVP is stable. It turns exploration into a small local game:

- User draws or confirms a rectangular spawn area.
- User chooses approximate hunt duration.
- User confirms a starting point.
- App places a hidden cheese target on or near a reachable street inside the rectangle.
- User wins once their GPS location enters a configurable radius around the target.
- **Hint Mode is a switch.** When hints are off, the user explores freely with no direction/distance help. When hints are on, the app can show lightweight help such as warmer/colder, distance band, or a coarse direction indicator.

Keep Cheese Hunt Mode local-first for MVP. Do not add external APIs just to get street graph data. Use MapKit walking directions to validate candidate locations, then later replace the spawn algorithm with backend/OpenStreetMap street-segment placement if needed.

## Architecture Proposal

### Reuse Report

- **Use native iOS frameworks:** SwiftUI, MapKit, CoreLocation, URLSession, Foundation file IO.
- **Use simple backend framework:** FastAPI is a good fit for a tiny private REST API and was already anticipated by the original endpoint examples.
- **Use server DB:** SQLite is enough for two-person POC if deployment simplicity matters; PostgreSQL is preferable if the server already has it or if you want smoother growth.
- **Do not add dependencies:** the requirements explicitly prefer native Apple frameworks and no paid/external map stack.
- **Use existing Xcode structure:** add folders inside `Cheeseek/`; the synchronized root group should include them automatically.
- **Build app-specific domain logic:** walk session lifecycle, GPS filtering, persistence format, user profile linking, server sync, mock shared routes.

### Data Flow

1. `ContentView` displays `RootTabView`.
2. `RootTabView` receives shared app dependencies and passes them into feature screens.
3. `MapScreen` observes `MapViewModel`.
4. `LocationManager` requests permission and publishes latest filtered location updates.
5. `MapViewModel` starts a `WalkSession`, appends accepted `TrackPoint`s while recording, updates live distance and elapsed time, and saves completed sessions through `WalkSessionStore`.
6. `WalkSessionStore` reads/writes sessions from Application Support as JSON so an in-progress walk is protected if network is unavailable.
7. `BackendSyncService` uploads finished sessions and points to the private backend.
8. `ProfileService` creates or relinks a nickname-only server profile.
9. On launch, the app loads local cache, then fetches server sessions/progress for the current nickname/user id.
10. Mock route providers provide fallback visual routes until real partner/shared routes exist on the backend.

### Pattern Decisions

| Pattern | Used? | Justification |
|---------|-------|---------------|
| MVVM | Yes | Keeps SwiftUI views presentation-focused while state/lifecycle logic sits in view models. |
| Repository-like store protocol | Yes | `WalkSessionStore` lets file persistence be swapped for SwiftData or backend-backed storage later. |
| Backend adapter protocol | Yes | Keeps networking behind a stable boundary; preview/mock clients can coexist with the real FastAPI client. |
| State machine enum | Yes | Walk lifecycle is clearer as `idle`, `recording`, `paused`, `finished`. |
| Heavy DI container | No | Overkill for a small personal MVP; wire dependencies in `CheeseekApp` or `ContentView`. |
| SwiftData | No, unless already present | Existing project does not use SwiftData. Codable file storage is simpler and reliable for MVP. |
| Auth framework | No | Nickname-only POC is intentionally not secure auth; add real auth later when the private backend shape is proven. |

### Proposed File Tree

Create these files under `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/`:

```text
Cheeseek/
├── App/
│   └── AppDependencies.swift
├── Models/
│   ├── APIModels.swift
│   ├── MapFilter.swift
│   ├── UserProfile.swift
│   ├── RouteStyle.swift
│   ├── RouteOverlay.swift
│   ├── SharedProgress.swift
│   ├── SyncStatus.swift
│   ├── TrackPoint.swift
│   ├── WalkSession.swift
│   └── WalkState.swift
├── Services/
│   ├── APIClient.swift
│   ├── BackendSyncService.swift
│   ├── LocationManager.swift
│   ├── MockRouteProvider.swift
│   ├── ProfileStore.swift
│   ├── ProfileService.swift
│   ├── ServerConfiguration.swift
│   └── WalkSessionStore.swift
├── ViewModels/
│   ├── ActivityViewModel.swift
│   ├── MapViewModel.swift
│   ├── ProfileViewModel.swift
│   └── WalkSummaryViewModel.swift
├── Views/
│   ├── ActivityView.swift
│   ├── MapScreen.swift
│   ├── ProfileView.swift
│   ├── RootTabView.swift
│   ├── SharedView.swift
│   └── WalkSummaryView.swift
├── Components/
│   ├── FilterSegmentControl.swift
│   ├── LiveWalkCard.swift
│   ├── MapOverlayLegend.swift
│   ├── PrimaryButton.swift
│   ├── ProgressCard.swift
│   └── SummaryStatCard.swift
├── CheeseekApp.swift
└── ContentView.swift
```

Create these backend POC files under `/Users/vlad/Xcode projects/Cheeseek/backend/`:

```text
backend/
├── README.md
├── requirements.txt
├── .env.example
├── app/
│   ├── __init__.py
│   ├── main.py
│   ├── database.py
│   ├── models.py
│   ├── schemas.py
│   └── routers/
│       ├── __init__.py
│       ├── profiles.py
│       ├── shared_progress.py
│       └── walk_sessions.py
└── scripts/
    └── run_dev.sh
```

Modify:

- `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/ContentView.swift`
- `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/CheeseekApp.swift` if wiring dependencies at app level
- `/Users/vlad/Xcode projects/Cheeseek/Cheeseek.xcodeproj/project.pbxproj` for location permission build setting and optional platform cleanup

## Key Model Contracts

Implement these shapes. Names can be adjusted slightly, but keep responsibilities intact.

```swift
struct TrackPoint: Identifiable, Codable, Equatable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    let horizontalAccuracy: Double
    let timestamp: Date
}
```

```swift
struct WalkSession: Identifiable, Codable, Equatable {
    let id: UUID
    var startedAt: Date
    var endedAt: Date?
    var distanceMeters: Double
    var durationSeconds: TimeInterval
    var points: [TrackPoint]
    var userId: String
    var syncStatus: SyncStatus
}
```

```swift
struct UserProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var nickname: String
    var deviceId: UUID
    var createdAt: Date?
}
```

```swift
enum WalkState: Equatable {
    case idle
    case recording
    case paused
    case finished(WalkSession)
}
```

```swift
enum SyncStatus: String, Codable, CaseIterable {
    case localOnly
    case readyToSync
    case syncing
    case synced
    case failed
}
```

```swift
enum MapFilter: String, CaseIterable, Identifiable {
    case me = "Me"
    case partner = "Partner"
    case together = "Together"
    case all = "All"
}
```

```swift
struct RouteOverlay: Identifiable {
    let id: UUID
    let owner: MapFilter
    let title: String
    let coordinates: [CLLocationCoordinate2D]
    let style: RouteStyle
}
```

```swift
struct RouteStyle: Equatable {
    let colorName: String
    let lineWidth: Double
}
```

Because `CLLocationCoordinate2D` is not Codable/Equatable by default, keep Codable storage on `TrackPoint`, do not rely on synthesized `Equatable` for route overlays, and expose computed coordinate helpers where needed.

### Backend API Contracts

Use JSON over HTTP. The POC does not need auth headers yet, but every write should include `userId` and `deviceId` where useful.

```text
POST /profiles
Body: { "nickname": "Vlad", "deviceId": "UUID" }
Returns: { "id": "UUID", "nickname": "Vlad", "deviceId": "UUID", "createdAt": "ISO-8601" }
Behavior: create profile if nickname does not exist; for POC, return the existing profile if nickname already exists.
```

```text
GET /profiles/by-nickname/{nickname}
Returns: profile or 404.
Behavior: used after reinstall to relink a nickname-only profile.
```

```text
POST /walk-sessions
Body: WalkSession without points or with summary fields.
Returns: saved WalkSession metadata.
```

```text
POST /walk-sessions/{sessionId}/points
Body: { "userId": "UUID", "points": [TrackPoint] }
Returns: { "saved": 123 }
```

```text
GET /walk-sessions?userId={uuid}
Returns: saved sessions for the profile, including points for MVP simplicity.
```

```text
GET /shared-progress
Returns: placeholder totals for current two-person group.
```

```text
GET /routes?userId={uuid}
Returns: route overlays derived from saved sessions.
```

Production auth later should replace nickname relinking. Until then, document clearly in UI/dev notes that nickname is convenience identity, not security.

## Task Breakdown

### Task 1: Establish Folders And App Shell

**Files:**
- Create folders listed in the proposed file tree.
- Modify: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/ContentView.swift`
- Create: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/Views/RootTabView.swift`

- [ ] Replace the starter `ContentView` with a root shell that displays `RootTabView`.
- [ ] Add a tab view with four tabs: Map, Activity, Profile, Shared.
- [ ] Use SF Symbols for tab icons: `map`, `figure.walk`, `person.crop.circle`, `person.2`.
- [ ] Add placeholder views temporarily if later task files do not exist yet.

**Verify:**

Run:

```bash
xcodebuild -project Cheeseek.xcodeproj -scheme Cheeseek -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Expected: build succeeds or fails only because later referenced files have not yet been created. After completing this task fully, the shell should build.

### Task 2: Add Domain Models

**Files:**
- Create all files under `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/Models/`

- [ ] Implement `TrackPoint` with computed `coordinate: CLLocationCoordinate2D` in a non-Codable extension.
- [ ] Implement `WalkSession` with helper properties for `isFinished`, formatted duration if desired, and a static factory for a new local session.
- [ ] Implement `UserProfile`, API DTOs, `SyncStatus`, `WalkState`, `MapFilter`, `RouteStyle`, `RouteOverlay`, and `SharedProgress`.
- [ ] Keep models UI-light; avoid SwiftUI imports except where genuinely required. Prefer `Foundation`, `CoreLocation`, and `MapKit` only where needed.

**Verify:**

Run the iOS simulator build command above.

Expected: models compile.

### Task 3: Implement Local Persistence

**Files:**
- Create: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/Services/WalkSessionStore.swift`

- [ ] Define a `WalkSessionStoring` protocol with `loadSessions() async throws -> [WalkSession]`, `saveSession(_:) async throws`, and `replaceSessions(_:) async throws`.
- [ ] Implement `FileWalkSessionStore` using JSON in Application Support, e.g. `Application Support/Cheeseek/walk-sessions.json`.
- [ ] Use `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)`.
- [ ] Create the directory if missing.
- [ ] Use `JSONEncoder` / `JSONDecoder` with `.iso8601` dates or default Date encoding consistently.
- [ ] Write atomically by encoding to a temporary file then replacing/moving to the final file, or by using `.atomic` where appropriate.
- [ ] If saving a session with an existing id, replace it instead of duplicating.

**Verify:**

Run the iOS simulator build command.

Expected: persistence compiles with async callers available for view models.

### Task 4: Implement Backend POC Server

**Files:**
- Create all files under `/Users/vlad/Xcode projects/Cheeseek/backend/`
- Reference: `/Users/vlad/Xcode projects/Cheeseek/docs/plans/2026-06-08-backend-requirements-prompt.md`

- [ ] Follow the backend requirements prompt/spec exactly.
- [ ] Create a FastAPI app with routers for profiles, walk sessions, health, and shared progress.
- [ ] Use SQLite by default at `backend/data/cheeseek.sqlite3`; make database URL configurable through `.env`.
- [ ] Add tables/models for:
  - `profiles`: id UUID, nickname unique, device_id, created_at
  - `walk_sessions`: id UUID, user_id, started_at, ended_at, distance_meters, duration_seconds, sync_status, created_at
  - `track_points`: id UUID, session_id, latitude, longitude, altitude nullable, horizontal_accuracy, timestamp
- [ ] Add `POST /profiles` and `GET /profiles/by-nickname/{nickname}`.
- [ ] Add `POST /walk-sessions`, `POST /walk-sessions/{sessionId}/points`, and `GET /walk-sessions?userId=...`.
- [ ] Add `GET /shared-progress` returning placeholder totals from saved sessions where feasible.
- [ ] Add `GET /routes?userId=...` returning saved route point arrays or simple route DTOs.
- [ ] Add permissive CORS only if needed for local debugging; the iOS app itself does not need browser CORS.
- [ ] Document server startup in `backend/README.md`.

**Verify:**

Run from `/Users/vlad/Xcode projects/Cheeseek/backend`:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

In another terminal:

```bash
curl -s -X POST http://127.0.0.1:8000/profiles \
  -H 'Content-Type: application/json' \
  -d '{"nickname":"vlad","deviceId":"00000000-0000-0000-0000-000000000001"}'
```

Expected: JSON profile with stable UUID.

### Task 4A: Implement iOS API Client And Profile Storage

**Files:**
- Create: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/Models/APIModels.swift`
- Create: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/Models/UserProfile.swift`
- Create: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/Services/APIClient.swift`
- Create: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/Services/ProfileStore.swift`
- Create: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/Services/ProfileService.swift`
- Create: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/Services/ServerConfiguration.swift`

- [ ] `ServerConfiguration` should hold the base URL, defaulting to `http://127.0.0.1:8000` for simulator.
- [ ] Add a clear note that real iPhone cannot use `127.0.0.1` to reach the Mac/server; it needs the Mac LAN IP or deployed server URL.
- [ ] `APIClient` should wrap `URLSession` and handle JSON encoding/decoding, HTTP status validation, and useful error messages.
- [ ] `ProfileStore` should persist `UserProfile` and generated `deviceId` locally with Codable JSON.
- [ ] `ProfileService` should:
  - create or relink profile by nickname
  - save returned profile locally
  - expose current profile to view models
  - support "change nickname" by creating/relinking another profile for POC
- [ ] Keep nickname as the entire visible profile for now.
- [ ] Do not add passwords/tokens yet.

**Verify:**

Run the iOS simulator build command.

Expected: API/profile types compile.

### Task 4B: Implement Real Backend Sync Service

**Files:**
- Create/modify: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/Services/BackendSyncService.swift`

- [ ] Define a `BackendSyncServing` protocol with:
  - `syncWalkSession(_ session: WalkSession) async throws`
  - `fetchSharedProgress() async throws -> SharedProgress`
  - `fetchPartnerRoutes() async throws -> [RouteOverlay]`
  - `uploadTrackPoints(sessionId: UUID, points: [TrackPoint]) async throws`
- [ ] Implement `HTTPBackendSyncService` using `APIClient`.
- [ ] Keep `MockBackendSyncService` only for SwiftUI previews/offline UI development.
- [ ] `syncWalkSession` should upload metadata first, then upload points.
- [ ] If upload fails, leave `syncStatus` as `readyToSync` or `failed` locally so it can retry later.
- [ ] `fetchPartnerRoutes` can still return mock/fallback data until partner route endpoint is fully useful.
- [ ] Include comments documenting future endpoint:
  - `GET /covered-segments`

**Verify:**

Run the iOS simulator build command.

Expected: sync protocol, HTTP implementation, and mock implementation compile.

### Task 4C: Add Profile Onboarding And Reinstall Recovery

**Files:**
- Create: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/ViewModels/ProfileViewModel.swift`
- Modify/create: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/Views/ProfileView.swift`
- Modify: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/Views/RootTabView.swift`
- Modify: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/App/AppDependencies.swift`

- [ ] On first launch, ask for nickname before or on the Profile tab.
- [ ] Call `ProfileService` to create/relink the profile on the server.
- [ ] Store returned `userId`, nickname, and `deviceId` locally.
- [ ] Let user edit/relink nickname in Profile for POC.
- [ ] Show profile sync state: local profile, server reachable/unreachable, last sync result.
- [ ] If no profile exists, disable server sync but still allow local walking only if that fallback is desired. Recommended: require nickname before starting a walk so every saved walk has a `userId`.

**Verify:**

Start backend locally, run the app in simulator, enter nickname, relaunch app, and confirm the profile persists locally. Delete local app data or reset simulator app, enter the same nickname, and confirm the server profile is relinked.

### Task 5: Implement Mock Routes

**Files:**
- Create: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/Services/MockRouteProvider.swift`

- [ ] Provide several hard-coded route polylines centered around Warsaw by default, e.g. near `52.2297, 21.0122`.
- [ ] Include separate route ownership/style values for me, partner, and together.
- [ ] Keep the API simple: `func routes() -> [RouteOverlay]`.
- [ ] Later, `MapViewModel` should combine these with locally completed sessions.

**Verify:**

Run the iOS simulator build command.

Expected: mock routes compile.

### Task 6: Implement Location Manager

**Files:**
- Create: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/Services/LocationManager.swift`
- Modify: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek.xcodeproj/project.pbxproj`

- [ ] Implement `final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate`.
- [ ] Publish authorization status, latest location, latest accuracy, and a user-facing status string.
- [ ] Add thresholds as constants near the top:
  - maximum accepted horizontal accuracy: 50 meters
  - preferred accuracy label threshold: 30 meters
  - minimum movement before recording a point: 7 meters
- [ ] Request when-in-use authorization.
- [ ] Start and stop foreground updates.
- [ ] Set `desiredAccuracy = kCLLocationAccuracyBest` while recording.
- [ ] Set a reasonable `distanceFilter`, e.g. 5-10 meters.
- [ ] Do not implement background location yet. Add a TODO comment where background support would be configured later.
- [ ] Filter bad points in the view model or helper method: ignore negative accuracy, accuracy over threshold, duplicate/tiny movement, and stale timestamps if needed.
- [ ] In project build settings, add:

```text
INFOPLIST_KEY_NSLocationWhenInUseUsageDescription = We use your location to draw your walking route and mark streets you have explored.
```

- [ ] Consider narrowing supported target platforms to iOS/iOS Simulator for this MVP if macOS/xros build destinations cause friction:

```text
SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
TARGETED_DEVICE_FAMILY = "1,2";
```

**Verify:**

Run:

```bash
xcodebuild -project Cheeseek.xcodeproj -scheme Cheeseek -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Expected: build succeeds and the generated app Info.plist contains `NSLocationWhenInUseUsageDescription`.

Optional check:

```bash
xcodebuild -project Cheeseek.xcodeproj -scheme Cheeseek -showBuildSettings | rg 'NSLocationWhenInUse|SUPPORTED_PLATFORMS|TARGETED_DEVICE_FAMILY'
```

### Task 7: Implement Map View Model

**Files:**
- Create: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/ViewModels/MapViewModel.swift`

- [ ] Inject `LocationManager`, `WalkSessionStoring`, `BackendSyncServing`, and `MockRouteProvider`.
- [ ] Publish:
  - selected filter
  - stored sessions
  - mock routes
  - active session
  - walk state
  - elapsed time
  - live distance
  - GPS accuracy label/value
  - summary session for presentation
  - map position/camera state if using SwiftUI `Map`
- [ ] Implement `onAppear()` to request permission, load stored sessions, load mock routes, and center on current/default coordinate.
- [ ] Implement `startWalk()`: create a new session, reset live metrics, start location updates.
- [ ] Implement `pauseWalk()`: set state to paused and stop appending points; location updates may continue or pause, but must not add points.
- [ ] Implement `resumeWalk()` if the UI exposes resume; otherwise let the Pause button toggle between Pause and Resume.
- [ ] Implement `finishWalk()`: stop location updates, finalize endedAt/duration/distance, save session locally, and expose the summary sheet.
- [ ] Implement location consumption so only valid filtered points append to the active session.
- [ ] Calculate distance incrementally using `CLLocation.distance(from:)`.
- [ ] Convert stored sessions into completed route polylines.
- [ ] Filter visible overlays by `MapFilter`.

**Verify:**

Run the iOS simulator build command.

Expected: view model compiles and does not require UI to perform local persistence calls.

### Task 8: Implement Reusable UI Components

**Files:**
- Create all files under `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/Components/`

- [ ] `PrimaryButton`: large filled button with optional disabled/loading style.
- [ ] `FilterSegmentControl`: floating segmented control for `MapFilter.allCases`.
- [ ] `ProgressCard`: percentage placeholder, total distance, completed route count placeholder.
- [ ] `LiveWalkCard`: LIVE badge, GPS quality/accuracy, elapsed time, distance, new area placeholder, new streets placeholder, sync status placeholder, Pause/Finish controls.
- [ ] `SummaryStatCard`: compact stat for summary screen.
- [ ] `MapOverlayLegend`: small overlay explaining completed/live/partner route colors.
- [ ] Use light material backgrounds, 8-16 point spacing, readable typography, teal/green completed routes, blue active route.
- [ ] Avoid in-app instructional text about how the app works. Labels should be product UI labels only.

**Verify:**

Run the iOS simulator build command.

Expected: components compile independently.

### Task 9: Implement Main Map Screen

**Files:**
- Create: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/Views/MapScreen.swift`
- Modify: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/Views/RootTabView.swift`

- [ ] Use SwiftUI `Map` with `MapPolyline` overlays for stored routes, mock routes, and active route.
- [ ] Show user location using native map user annotation APIs.
- [ ] Make the map full-screen under floating controls.
- [ ] Overlay top `FilterSegmentControl`.
- [ ] Overlay bottom `ProgressCard` and large Start Walk button when idle.
- [ ] Overlay `LiveWalkCard` when recording or paused.
- [ ] Present `WalkSummaryView` after finishing.
- [ ] Keep layout safe-area aware; controls should not collide with the tab bar.
- [ ] If `MapPolyline` syntax differs for the installed SDK, use the current Xcode completion/docs and keep the same view model contract.

**Verify:**

Run the iOS simulator build command.

Expected: app builds and shows a full-screen map with mock route overlays on first launch.

### Task 10: Implement Walk Summary Screen

**Files:**
- Create: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/ViewModels/WalkSummaryViewModel.swift`
- Create: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/Views/WalkSummaryView.swift`

- [ ] Show title: "Great walk!"
- [ ] Show distance, duration, track point count, new streets placeholder, and new area placeholder.
- [ ] Add "Save to Shared Map" button that calls `BackendSyncServing.syncWalkSession`.
- [ ] Update displayed sync status after mock sync success.
- [ ] Add "View Full Map" button that dismisses the summary.
- [ ] Add a small route preview if quick with SwiftUI `Map`; otherwise use a polished route-colored mini panel and leave a TODO for route preview.

**Verify:**

Run the iOS simulator build command.

Expected: finishing a mock/manual walk can present and dismiss the summary.

### Task 11: Implement Secondary Tabs

**Files:**
- Create: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/ViewModels/ActivityViewModel.swift`
- Create: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/Views/ActivityView.swift`
- Create: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/Views/ProfileView.swift`
- Create: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/Views/SharedView.swift`
- Modify: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/Views/RootTabView.swift`

- [ ] Activity should list locally saved walk sessions with distance, date, duration, and sync status.
- [ ] Profile should show nickname, server profile id, device id, total distance, total walks, and sync/relink controls.
- [ ] Shared should show partner/shared progress placeholders and server sync status.
- [ ] Keep these screens useful but lightweight; the map is the MVP center.

**Verify:**

Run the iOS simulator build command.

Expected: all tabs navigate without crashes or empty default demo content.

### Task 12: Wire Dependencies At Composition Root

**Files:**
- Create: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/App/AppDependencies.swift`
- Modify: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/CheeseekApp.swift`
- Modify: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/ContentView.swift`
- Modify: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/Views/RootTabView.swift`

- [ ] Create `AppDependencies` containing shared instances:
  - `ServerConfiguration`
  - `APIClient`
  - `LocationManager`
  - `FileWalkSessionStore`
  - `ProfileStore`
  - `ProfileService`
  - `HTTPBackendSyncService`
  - `MockBackendSyncService` for previews only if useful
  - `MockRouteProvider`
- [ ] Instantiate dependencies once in `CheeseekApp` with `@StateObject` where applicable.
- [ ] Pass dependencies into `ContentView`/`RootTabView`/`MapScreen`.
- [ ] Avoid hidden singletons. `FileManager.default` and `CLLocationManager` are acceptable inside infrastructure services.

**Verify:**

Run the iOS simulator build command.

Expected: the app builds with stable object ownership and no duplicate location managers created by view refreshes.

### Task 13: Polish UI And Edge States

**Files:**
- Modify relevant files under `Views/`, `Components/`, and `ViewModels/`

- [ ] Add location permission denied/restricted UI state on the map screen.
- [ ] Add server unreachable/offline sync state.
- [ ] Add no-profile state and require nickname before server-backed walks.
- [ ] Disable Start Walk until permission is available or show a permission request path.
- [ ] Show "Saved locally" / "Ready to sync" status clearly.
- [ ] Ensure Pause does not keep appending track points.
- [ ] Ensure Finish stops tracking and saves exactly once.
- [ ] Add empty states for Activity and Shared tabs.
- [ ] Tune colors so the app is not a one-note palette: white/light surfaces, teal/green completed, blue live, neutral text, subtle partner color.
- [ ] Make controls readable in compact iPhone width.

**Verify:**

Run the iOS simulator build command and manually inspect in an iPhone simulator.

### Task 14: Final Build And Manual QA

**Files:**
- No new files unless fixing issues.

- [ ] Run a clean simulator build:

```bash
xcodebuild clean build -project Cheeseek.xcodeproj -scheme Cheeseek -destination 'platform=iOS Simulator,name=iPhone 17'
```

- [ ] Open the app in Xcode or run to simulator.
- [ ] Start the backend and verify health/profile endpoints before testing server sync.
- [ ] Simulator manual QA:
  - nickname profile can be created
  - same nickname can relink after local data reset
  - map appears
  - mock completed routes appear
  - filter control changes visible route set
  - tabs switch
  - permission prompt appears if location is requested
  - Start Walk changes to live state
  - Pause stops adding points
  - Finish saves and shows summary
  - completed walk uploads to backend
  - Activity list shows completed session
  - after app reinstall/reset, entering same nickname restores server-backed walk history
- [ ] Real iPhone QA:
  - select the development team
  - connect iPhone
  - trust developer profile if prompted
  - run from Xcode
  - configure backend base URL to deployed server URL or Mac LAN IP, not `127.0.0.1`
  - allow location permission
  - walk outdoors with the app open
  - confirm route draws live and is still present after relaunch
  - confirm the walk appears again after reinstall/relink by nickname

**Expected final result:** the project builds and runs as a server-backed iOS walking MVP with polished map UI, local persistence for recording/offline safety, live foreground route drawing, nickname-only profile POC, and durable server-stored walk history.

## Cheese Hunt Mode Follow-Up Plan

Implement this after Tasks 1-14, unless the user explicitly chooses to prioritize the game loop before Activity/Profile/Shared polish.

### Cheese Hunt Architecture

Add a separate hunt feature rather than burying hunt state inside walk tracking:

- `HuntSession` stores the active game state.
- `CheeseTarget` stores the hidden target coordinate, reveal state, and win radius.
- `SpawnArea` stores the user-selected rectangle.
- `CheeseSpawnService` generates candidate points and validates approximate walking time with MapKit directions.
- `CheeseHuntViewModel` coordinates setup, target generation, hint display, and win detection.
- Existing `LocationManager` continues to provide GPS updates.

The main walking session and hunt session can run together: a hunt is a reason to walk, while `WalkSession` remains the route recording/persistence object.

### Cheese Hunt Model Contracts

```swift
struct SpawnArea: Codable, Equatable {
    let northEastLatitude: Double
    let northEastLongitude: Double
    let southWestLatitude: Double
    let southWestLongitude: Double
}
```

```swift
struct CheeseTarget: Identifiable, Codable, Equatable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let createdAt: Date
    let targetDurationSeconds: TimeInterval
    let estimatedWalkingSeconds: TimeInterval?
    let winRadiusMeters: Double
}
```

```swift
struct HuntSession: Identifiable, Codable, Equatable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date?
    var spawnArea: SpawnArea
    var startLatitude: Double
    var startLongitude: Double
    var target: CheeseTarget
    var hintsEnabled: Bool
    var status: HuntStatus
}
```

```swift
enum HuntStatus: String, Codable {
    case setup
    case hunting
    case found
    case abandoned
}
```

### Hint Mode Behavior

- `hintsEnabled == false`
  - Do not show exact cheese coordinate.
  - Do not show distance, arrow, or warmer/colder.
  - Keep only normal map/walk UI and a small hunt status card, e.g. "Cheese hidden".
  - Trigger victory when user enters the win radius.
- `hintsEnabled == true`
  - Still do not need to reveal the exact coordinate by default.
  - Show one or more gentle hints:
    - distance band: "near", "getting closer", "far"
    - warmer/colder compared with previous distance
    - optional coarse compass direction
  - Consider revealing exact target only after the user is very close or after timeout.

### Cheese Task 1: Add Hunt Models

**Files:**
- Create: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/Models/SpawnArea.swift`
- Create: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/Models/CheeseTarget.swift`
- Create: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/Models/HuntSession.swift`
- Create: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/Models/HuntStatus.swift`

- [ ] Add the model contracts above.
- [ ] Add computed coordinate helpers in extensions where useful.

**Verify:**

Run the iOS simulator build command.

### Cheese Task 2: Add Spawn Service

**Files:**
- Create: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/Services/CheeseSpawnService.swift`

- [ ] Define `CheeseSpawnServing` protocol.
- [ ] Generate random candidate coordinates inside `SpawnArea`.
- [ ] Use `MKDirections` walking routes from start coordinate to candidate.
- [ ] Accept candidates whose ETA is near the requested duration, e.g. 70%-130% of requested time.
- [ ] Reject candidates too close to start, unreachable by MapKit, or outside the area.
- [ ] Reverse-geocode candidates with `CLGeocoder` and prefer candidates with road/address-like placemarks.
- [ ] Fall back gracefully if no ideal candidate is found: pick the best reachable candidate and label confidence as low internally.

**Verify:**

Run the iOS simulator build command and test candidate generation from a known Warsaw rectangle.

### Cheese Task 3: Add Hunt Setup UI

**Files:**
- Create: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/ViewModels/CheeseHuntViewModel.swift`
- Create: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/Views/CheeseHuntSetupView.swift`
- Modify: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/Views/MapScreen.swift`

- [ ] Add a way to enter Cheese Hunt setup from the map.
- [ ] Let user define a rectangular spawn area. MVP can start with a draggable/resizable rectangle overlay if feasible; otherwise use "use visible map area" as the rectangle.
- [ ] Let user choose approximate time with a segmented control or slider.
- [ ] Let user use current location as start point, with an option to move the start marker.
- [ ] Add a `Hints` switch.
- [ ] Add a "Hide Cheese" / "Start Hunt" button.

**Verify:**

Run the app and confirm a hunt can be configured without starting GPS recording yet.

### Cheese Task 4: Add Active Hunt UI And Win Detection

**Files:**
- Create: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/Components/CheeseHuntCard.swift`
- Modify: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/ViewModels/CheeseHuntViewModel.swift`
- Modify: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/Views/MapScreen.swift`

- [ ] Show active hunt status on the map.
- [ ] If hints are off, show only minimal status: hidden target, elapsed time, and maybe "searching".
- [ ] If hints are on, show distance band / warmer-colder / optional coarse direction.
- [ ] Detect win when current location is within `target.winRadiusMeters`, default 20 meters.
- [ ] Show a victory state: "Cheese found!", time spent, walking distance, and route summary.
- [ ] Offer "View Full Map" and "Start Another Hunt".

**Verify:**

Use simulator location changes or a temporary debug coordinate override during development, then remove or hide debug-only controls before final handoff.

### Cheese Task 5: Persist Hunt History Later If Useful

**Files:**
- Optional create: `/Users/vlad/Xcode projects/Cheeseek/Cheeseek/Services/HuntSessionStore.swift`

- [ ] For the first Cheese Hunt MVP, active hunt state can be in memory if implementation speed matters.
- [ ] If data-loss protection matters for hunts too, add Codable file persistence similar to `WalkSessionStore`.
- [ ] Do not block the base walking persistence on hunt history.

**Verify:**

If persisted, relaunch the app mid-hunt and confirm the hunt can resume.

## Final Deliverable Notes For The Implementer

When implementation is complete, report:

- Files created and modified.
- Exact build command run and result.
- Xcode capability/permission notes:
  - required: `NSLocationWhenInUseUsageDescription`
  - not required yet: Background Modes / Location updates
  - do not claim background tracking works
- Backend notes:
  - server base URL used for simulator and real iPhone
  - database type/path used
  - how to start backend
  - nickname is not real authentication
- How to run on simulator:
  - pick `Cheeseek` scheme
  - choose an iPhone simulator
  - build/run
- How to run on iPhone:
  - plug in device
  - select development team
  - choose the device destination
  - run from Xcode
  - grant location permission
- What remains mocked/TODO:
  - production auth
  - partner routes
  - together/all shared progress
  - street coverage/new area calculations
  - Cheese Hunt exact street placement unless a backend/OpenStreetMap street graph is added later
  - Cheese Hunt hint tuning
  - background tracking

## Risk Notes

- MapKit SwiftUI APIs have changed across iOS versions. Since this project targets the current installed SDK, prefer current Xcode compiler feedback over old examples.
- Generated Info.plist means permission strings live in project build settings unless a custom Info.plist is introduced.
- Do not use UserDefaults for sessions; it is less appropriate for growing arrays of GPS points.
- Do not record every location callback; apply both accuracy and distance filters.
- Do not keep tracking after Finish.
- Do not introduce external map SDKs, Firebase, or paid APIs during this MVP.
