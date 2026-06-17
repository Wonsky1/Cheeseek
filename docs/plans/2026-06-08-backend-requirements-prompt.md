# Cheeseek Backend Requirements Prompt

Use this document as the complete prompt/instructions for creating the Cheeseek backend POC.

## Copy-Paste Prompt

You are building the backend POC for **Cheeseek**, a private two-person iOS walking/exploration app. Build a small, maintainable FastAPI backend that stores nickname-only user profiles, walk sessions, track points, and simple shared progress. The iOS app is manually installed through Xcode, so server storage is required because local app data may be lost on reinstall.

Implement the backend exactly from the requirements below.

Do not implement production auth yet. The POC identity is nickname-only: a user enters a nickname, the backend creates or relinks a profile, and returns a stable UUID. This is not secure identity and must be documented as such. Keep the code structured so real auth can be added later.

Use FastAPI, SQLAlchemy, Pydantic, and SQLite by default. Make the database URL configurable so PostgreSQL can be used later. Do not add Firebase, external map SDKs, paid APIs, or unrelated services.

## Backend Goal

Create a durable private backend for:

- nickname-only profiles
- server-side walk session history
- server-side track points
- route restoration after iOS app reinstall
- placeholder shared progress for two-person use
- route DTOs that the iOS app can draw on MapKit

The backend should be simple enough to run on a personal server, but clean enough to extend with auth, partner relationships, covered street segments, and Cheese Hunt later.

## Required File Tree

Create this backend under the project root:

```text
backend/
├── README.md
├── requirements.txt
├── .env.example
├── app/
│   ├── __init__.py
│   ├── main.py
│   ├── config.py
│   ├── database.py
│   ├── models.py
│   ├── schemas.py
│   └── routers/
│       ├── __init__.py
│       ├── health.py
│       ├── profiles.py
│       ├── shared_progress.py
│       └── walk_sessions.py
└── scripts/
    └── run_dev.sh
```

Optional but recommended:

```text
backend/tests/
├── conftest.py
├── test_profiles.py
├── test_walk_sessions.py
└── test_shared_progress.py
```

## Dependencies

`requirements.txt` should include:

```text
fastapi
uvicorn[standard]
sqlalchemy
pydantic-settings
python-dotenv
pytest
httpx
```

Use Python 3.11+.

## Configuration

`.env.example`:

```text
DATABASE_URL=sqlite:///./data/cheeseek.sqlite3
APP_ENV=development
```

`app/config.py`:

- Load settings with `pydantic-settings`.
- Expose `database_url`.
- Default to SQLite path above.

## Database Requirements

Use SQLAlchemy ORM. For SQLite, store UUIDs as strings.

### Table: profiles

Fields:

- `id`: string UUID, primary key
- `nickname`: string, unique, required, case-insensitive lookup preferred
- `device_id`: string UUID, required
- `created_at`: datetime UTC, required
- `updated_at`: datetime UTC, required

Rules:

- `nickname` must be trimmed.
- `nickname` length: 1-32 characters.
- Nickname may contain letters, numbers, spaces, `_`, `-`.
- POC behavior: `POST /profiles` returns existing profile if nickname already exists.

### Table: walk_sessions

Fields:

- `id`: string UUID, primary key
- `user_id`: string UUID, foreign key to `profiles.id`, required, indexed
- `started_at`: datetime UTC, required
- `ended_at`: datetime UTC, nullable
- `distance_meters`: float, required, default `0`
- `duration_seconds`: float, required, default `0`
- `sync_status`: string, required, default `synced`
- `created_at`: datetime UTC, required
- `updated_at`: datetime UTC, required

Rules:

- `distance_meters >= 0`
- `duration_seconds >= 0`
- if `ended_at` exists, it must be greater than or equal to `started_at`
- session IDs come from the iOS app when possible; server must accept client UUID to make retries idempotent
- `POST /walk-sessions` is idempotent by session id

### Table: track_points

Fields:

- `id`: string UUID, primary key
- `session_id`: string UUID, foreign key to `walk_sessions.id`, required, indexed
- `latitude`: float, required
- `longitude`: float, required
- `altitude`: float, nullable
- `horizontal_accuracy`: float, required
- `timestamp`: datetime UTC, required, indexed
- `created_at`: datetime UTC, required

Rules:

- latitude must be between `-90` and `90`
- longitude must be between `-180` and `180`
- horizontal accuracy must be `>= 0`
- point IDs come from iOS when possible
- uploading the same point twice should not create duplicates
- `POST /walk-sessions/{session_id}/points` should be idempotent by point id

## Pydantic Schemas

Create request/response schemas in `app/schemas.py`.

### ProfileCreate

```json
{
  "nickname": "vlad",
  "deviceId": "00000000-0000-0000-0000-000000000001"
}
```

### ProfileResponse

```json
{
  "id": "profile-uuid",
  "nickname": "vlad",
  "deviceId": "device-uuid",
  "createdAt": "2026-06-08T12:00:00Z",
  "updatedAt": "2026-06-08T12:00:00Z"
}
```

### TrackPointCreate

```json
{
  "id": "point-uuid",
  "latitude": 52.2297,
  "longitude": 21.0122,
  "altitude": 110.0,
  "horizontalAccuracy": 8.5,
  "timestamp": "2026-06-08T12:00:00Z"
}
```

### WalkSessionCreate

```json
{
  "id": "session-uuid",
  "userId": "profile-uuid",
  "startedAt": "2026-06-08T12:00:00Z",
  "endedAt": "2026-06-08T12:30:00Z",
  "distanceMeters": 2100.5,
  "durationSeconds": 1800,
  "syncStatus": "readyToSync"
}
```

### WalkSessionResponse

```json
{
  "id": "session-uuid",
  "userId": "profile-uuid",
  "startedAt": "2026-06-08T12:00:00Z",
  "endedAt": "2026-06-08T12:30:00Z",
  "distanceMeters": 2100.5,
  "durationSeconds": 1800,
  "syncStatus": "synced",
  "points": []
}
```

For `GET /walk-sessions`, include `points` for MVP simplicity.

### TrackPointsUploadRequest

```json
{
  "userId": "profile-uuid",
  "points": [
    {
      "id": "point-uuid",
      "latitude": 52.2297,
      "longitude": 21.0122,
      "altitude": null,
      "horizontalAccuracy": 8.5,
      "timestamp": "2026-06-08T12:00:00Z"
    }
  ]
}
```

### TrackPointsUploadResponse

```json
{
  "saved": 123,
  "skippedDuplicates": 2
}
```

### SharedProgressResponse

```json
{
  "totalDistanceMeters": 12345.6,
  "totalWalks": 12,
  "completedRoutesPlaceholder": 0,
  "explorationProgressPercentPlaceholder": 0.0
}
```

### RouteResponse

```json
{
  "id": "session-uuid",
  "userId": "profile-uuid",
  "title": "Walk on 2026-06-08",
  "coordinates": [
    { "latitude": 52.2297, "longitude": 21.0122 }
  ]
}
```

## Required Endpoints

### Health

`GET /health`

Response:

```json
{ "status": "ok" }
```

### Create Or Relink Profile

`POST /profiles`

Behavior:

- Validate nickname.
- If nickname exists, return existing profile.
- If nickname does not exist, create profile.
- Store/update `device_id`.
- Return `ProfileResponse`.

Status codes:

- `200` if existing profile returned
- `201` if created
- `422` for validation errors

### Fetch Profile By Nickname

`GET /profiles/by-nickname/{nickname}`

Behavior:

- Trim and normalize nickname for lookup.
- Return profile if found.
- Return `404` if not found.

### Create Or Update Walk Session

`POST /walk-sessions`

Behavior:

- Validate `userId` exists.
- Accept client-provided `id`.
- If session id already exists, update metadata idempotently.
- Save session with `sync_status = "synced"` after successful server save.
- Return `WalkSessionResponse` with empty or existing points.

Status codes:

- `200` if updated existing session
- `201` if created
- `404` if profile not found
- `422` for validation errors

### Upload Track Points

`POST /walk-sessions/{session_id}/points`

Behavior:

- Validate session exists.
- Validate `userId` matches session owner.
- Insert points that do not exist by id.
- Skip duplicates by id.
- Return saved/skipped counts.
- Keep order by timestamp when returning sessions.

Status codes:

- `200` success
- `403` if user does not own the session
- `404` if session not found
- `422` validation errors

### Fetch Walk Sessions

`GET /walk-sessions?userId={uuid}`

Behavior:

- Validate profile exists.
- Return all sessions owned by user, newest first.
- Include points ordered by timestamp.

Status codes:

- `200` success
- `404` if profile not found

### Fetch Shared Progress

`GET /shared-progress`

POC behavior:

- Return totals across all profiles.
- `totalDistanceMeters`: sum of all session distances.
- `totalWalks`: count of all sessions.
- placeholders remain `0`.

Later this should become group/partner scoped.

### Fetch Routes

`GET /routes?userId={uuid}`

Behavior:

- Return route DTOs for sessions belonging to user.
- Each route contains session id, user id, title, and coordinates.
- Coordinates come from track points ordered by timestamp.

Status codes:

- `200` success
- `404` if profile not found

## Error Format

Use FastAPI default validation errors for `422`.

For custom errors, use:

```json
{
  "detail": "Human-readable error"
}
```

## Implementation Rules

- Use snake_case in database columns.
- Use camelCase in JSON API fields to match Swift Codable conventions.
- Store datetimes in UTC.
- Return ISO-8601 datetime strings.
- Make uploads idempotent.
- Never delete data automatically.
- Avoid global mutable state except the DB engine/session factory.
- Keep routers thin; put small helper functions in router modules only if they stay readable.
- Do not implement auth, passwords, JWT, OAuth, email, or accounts yet.
- Do not implement map matching, covered street segments, or Cheese Hunt in this backend pass.

## README Requirements

`backend/README.md` must include:

- what the backend does
- warning that nickname is not real auth
- setup commands
- run commands
- database location/config
- endpoint list
- simulator vs real iPhone base URL note:
  - simulator can use `http://127.0.0.1:8000`
  - real iPhone must use deployed server URL or the Mac/server LAN IP
- curl examples:
  - create profile
  - create walk session
  - upload points
  - fetch walk sessions

## Verification Commands

From `backend/`:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

In another terminal:

```bash
curl -s http://127.0.0.1:8000/health
```

Expected:

```json
{"status":"ok"}
```

Create profile:

```bash
curl -s -X POST http://127.0.0.1:8000/profiles \
  -H 'Content-Type: application/json' \
  -d '{"nickname":"vlad","deviceId":"00000000-0000-0000-0000-000000000001"}'
```

Create session:

```bash
curl -s -X POST http://127.0.0.1:8000/walk-sessions \
  -H 'Content-Type: application/json' \
  -d '{
    "id":"11111111-1111-1111-1111-111111111111",
    "userId":"REPLACE_WITH_PROFILE_ID",
    "startedAt":"2026-06-08T12:00:00Z",
    "endedAt":"2026-06-08T12:20:00Z",
    "distanceMeters":1200.5,
    "durationSeconds":1200,
    "syncStatus":"readyToSync"
  }'
```

Upload points:

```bash
curl -s -X POST http://127.0.0.1:8000/walk-sessions/11111111-1111-1111-1111-111111111111/points \
  -H 'Content-Type: application/json' \
  -d '{
    "userId":"REPLACE_WITH_PROFILE_ID",
    "points":[
      {
        "id":"22222222-2222-2222-2222-222222222222",
        "latitude":52.2297,
        "longitude":21.0122,
        "altitude":null,
        "horizontalAccuracy":8.5,
        "timestamp":"2026-06-08T12:01:00Z"
      }
    ]
  }'
```

Fetch sessions:

```bash
curl -s 'http://127.0.0.1:8000/walk-sessions?userId=REPLACE_WITH_PROFILE_ID'
```

## Required Tests

If adding tests, cover:

- creating a new profile returns `201`
- creating same nickname again returns existing profile and does not duplicate
- invalid nickname returns `422`
- fetching missing nickname returns `404`
- creating session for missing user returns `404`
- creating session twice with same id is idempotent
- uploading duplicate point ids skips duplicates
- uploading points with wrong user id returns `403`
- fetched sessions include points ordered by timestamp
- shared progress totals sum saved sessions
- routes return coordinate arrays from saved points

Run:

```bash
pytest
```

## Done Criteria

The backend is complete when:

- app starts with `uvicorn app.main:app`
- `/health` returns ok
- profile create/relink works
- walk session save is idempotent
- track point upload is idempotent
- sessions can be fetched after server restart
- README explains setup and nickname-auth limitation
- tests pass if tests were created

