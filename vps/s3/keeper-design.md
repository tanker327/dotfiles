# Keeper — System Design Document

## 1. Overview

Keeper is a **standalone, independent media backup service**. Any system submits a URL, Keeper downloads the file, stores it in Garage S3, and the `s3_key` serves as the permanent stable reference. No knowledge of Juicer or any other caller.

### Core capabilities

1. Accepts a URL via API
2. Returns `s3_key` immediately (generated at submission, no waiting)
3. Downloads the file asynchronously via background workers
4. Stores the file in Garage S3 (local, same machine)
5. Tracks status and metadata in database
6. Generates video thumbnails via ffmpeg (post-upload, non-blocking)
7. Deduplicates by URL — same URL submitted twice returns existing record

---

## 2. Infrastructure

| Component | Details |
|---|---|
| OS | Ubuntu, Linux x86_64 |
| CPU | Intel Core i5-2415M @ 2.30GHz — 2 cores / 4 threads |
| RAM | 7.2 GB total, ~5.9 GB available |
| Disk | 1.8 TB total, 1.7 TB free |
| Network | 300 Mbps down / 280 Mbps up |
| Storage | Garage S3 — running on same machine (local I/O, no network latency) |
| Services | Keeper API + Garage S3 only — fully dedicated |

### Bottleneck order
1. **ffmpeg** — CPU-bound, no GPU
2. **Worker count** — 4 threads total
3. **Network** — not a concern at 300 Mbps

---

## 3. S3 Key Generation

Generated at submission time — no network call required, purely string parsing.

### Key format
```
{category}/{year}/{month}/{day}/{uuid}.{ext}
```

**Examples:**
```
image/2026/03/15/uuid.jpg
video/2026/03/15/uuid.mp4
audio/2026/03/15/uuid.mp3
document/2026/03/15/uuid.pdf
unknown/2026/03/15/uuid.bin
```

Thumbnail keys follow the same pattern:
```
image/2026/03/15/uuid_thumb.jpg
```

### Extension extraction (in order)

1. **URL pathname** — text after last `.` in final path segment (1–10 chars, alphanumeric)
   - `https://example.com/photo.jpg` → `jpg`
2. **Query param `?format=`** — if no pathname extension
   - `https://pbs.twimg.com/media/abc?format=png&name=900x900` → `png`
3. **Default `bin`** — if both above fail
   - `https://example.com/noext` → `bin`

### Category map (from extension)

| Category | Extensions |
|---|---|
| `image` | jpg, jpeg, png, gif, webp, svg, bmp, tiff, ico, avif |
| `video` | mp4, webm, mov, avi, mkv, flv, wmv, m4v |
| `audio` | mp3, wav, ogg, flac, aac, m4a, opus, wma |
| `document` | pdf, doc, docx, txt, csv, xls, xlsx, ppt, pptx |
| `unknown` | bin, anything unrecognized |

> Note: S3 key category is determined purely from URL extension. Real MIME type is detected later via magic bytes in the worker and stored in `content_type`. Key never changes after generation.

---

## 4. Database Schema

Single table. No joins needed for normal operations.

### `resources` table

| Column | Type | Nullable | Notes |
|---|---|---|---|
| `id` | UUID | No | Primary key, generated at submission |
| `url` | TEXT | No | Original submitted URL, unique index |
| `s3_key` | TEXT | No | Full S3 path, generated at submission |
| `status` | ENUM | No | See state machine below |
| `category` | ENUM | No | `image` `video` `audio` `document` `unknown` |
| `extension` | TEXT | No | URL-derived, e.g. `jpg`, `bin` |
| `content_type` | TEXT | Yes | Real MIME type from magic bytes |
| `content_hash` | TEXT | Yes | SHA256, computed post-download (informational only) |
| `file_size` | INTEGER | Yes | Bytes |
| `width` | INTEGER | Yes | Pixels, image/video only |
| `height` | INTEGER | Yes | Pixels, image/video only |
| `duration_ms` | INTEGER | Yes | Milliseconds, video/audio only |
| `thumbnail_key` | TEXT | Yes | S3 key for thumbnail |
| `thumbnail_status` | ENUM | No | `none` `pending` `done` `failed`, default `none` |
| `fail_reason` | TEXT | Yes | Human readable failure message |
| `fail_stage` | ENUM | Yes | `probe` `download` `upload` `thumbnail` |
| `attempt_count` | INTEGER | No | Default 0, increments per retry |
| `next_retry_at` | TIMESTAMP | Yes | When to retry, null if not scheduled |
| `caller_metadata` | JSON | No | Pass-through blob from caller, stored as-is |
| `created_at` | TIMESTAMP | No | Submission time |
| `updated_at` | TIMESTAMP | No | Last status change |
| `completed_at` | TIMESTAMP | Yes | When status became `done` |

### Indexes

```sql
resources.url          -- UNIQUE (URL dedup)
resources.status       -- worker queue polling + retry scheduler
resources.category     -- list filtering
resources.created_at   -- pagination
resources.content_hash -- duplicate discovery queries
```

### Useful duplicate discovery query

```sql
SELECT content_hash, COUNT(*) as copies, GROUP_CONCAT(url) as urls
FROM resources
WHERE content_hash IS NOT NULL
GROUP BY content_hash
HAVING COUNT(*) > 1
```

---

## 5. State Machine

```
pending → probing → queued → downloading → uploading → done
                                                      ↘ failed (at any stage)
```

| Status | Meaning |
|---|---|
| `pending` | Submitted, waiting for probe worker |
| `probing` | HEAD request in progress |
| `queued` | Probe done, waiting in light or heavy queue |
| `downloading` | Download in progress |
| `uploading` | Upload to Garage in progress |
| `done` | File available in S3 |
| `failed` | Permanently failed, see `fail_stage` + `fail_reason` |

> `thumbnail_status` is a separate state on the same row — a failed thumbnail does **not** affect the resource status. Resource stays `done`.

---

## 6. API Endpoints

### `POST /resource` — Submit a URL

**Request:**
```json
{
  "url": "https://pbs.twimg.com/media/abc?format=png&name=900x900",
  "metadata": {}
}
```

**Response 201** — new job created:
```json
{
  "id": "uuid",
  "s3_key": "image/2026/03/15/uuid.png",
  "category": "image",
  "status": "pending",
  "created_at": "2026-03-15T10:00:00Z"
}
```

**Response 200** — URL already exists, dedup hit, returns existing record in full shape.

---

### `GET /resource/:id` — Get single resource

**While processing:**
```json
{
  "id": "uuid",
  "url": "https://pbs.twimg.com/media/abc?format=png",
  "s3_key": "image/2026/03/15/uuid.png",
  "category": "image",
  "status": "downloading",
  "content_type": null,
  "file_size": null,
  "width": null,
  "height": null,
  "duration_ms": null,
  "thumbnail_key": null,
  "caller_metadata": {},
  "created_at": "2026-03-15T10:00:00Z",
  "updated_at": "2026-03-15T10:00:01Z",
  "completed_at": null
}
```

**When done:**
```json
{
  "id": "uuid",
  "url": "https://pbs.twimg.com/media/abc?format=png",
  "s3_key": "image/2026/03/15/uuid.png",
  "category": "image",
  "status": "done",
  "content_type": "image/png",
  "file_size": 204800,
  "width": 900,
  "height": 900,
  "duration_ms": null,
  "thumbnail_key": null,
  "thumbnail_status": "none",
  "content_hash": "sha256:abc123...",
  "caller_metadata": {},
  "created_at": "2026-03-15T10:00:00Z",
  "updated_at": "2026-03-15T10:00:02Z",
  "completed_at": "2026-03-15T10:00:02Z"
}
```

**When failed:**
```json
{
  "id": "uuid",
  "url": "https://pbs.twimg.com/media/abc.mp4",
  "s3_key": "video/2026/03/15/uuid.mp4",
  "category": "video",
  "status": "failed",
  "fail_stage": "probe",
  "fail_reason": "URL returned 403 Forbidden",
  "attempt_count": 3,
  "content_type": null,
  "file_size": null,
  "width": null,
  "height": null,
  "duration_ms": null,
  "thumbnail_key": null,
  "thumbnail_status": "none",
  "content_hash": null,
  "caller_metadata": {},
  "created_at": "2026-03-15T10:00:00Z",
  "updated_at": "2026-03-15T10:00:02Z",
  "completed_at": null
}
```

---

### `GET /resource/lookup?url=` — Lookup by original URL

Same response shape as `GET /resource/:id`. Returns `404` if URL has never been submitted.

---

### `GET /resource/list` — List with filters

**Query params:**

| Param | Type | Default | Notes |
|---|---|---|---|
| `category` | enum | — | `image` `video` `audio` `document` `unknown` |
| `status` | enum | — | any status value |
| `page` | integer | 1 | |
| `limit` | integer | 20 | max 100 |

**Sort order:** `created_at DESC` — latest first, always.

**Response:**
```json
{
  "data": [ ...resource objects ],
  "pagination": {
    "page": 1,
    "limit": 20,
    "total": 1500,
    "total_pages": 75
  }
}
```

---

### `GET /health`

Checks API, DB, and Garage S3 connectivity. Returns `200` if all healthy, `503` if any dependency is down.

```json
{
  "status": "ok",
  "timestamp": "2026-03-15T10:00:00Z",
  "dependencies": {
    "database": "ok",
    "storage": "ok"
  }
}
```

**When degraded (`503`):**
```json
{
  "status": "degraded",
  "timestamp": "2026-03-15T10:00:00Z",
  "dependencies": {
    "database": "ok",
    "storage": "error: connection refused"
  }
}
```

---

## 7. Worker Architecture

### Queue structure

```
POST /resource
     ↓
  DB insert (status: pending)
     ↓
  probe_queue
     ↓
  Probe Workers (4)
     ↓
  light_queue          heavy_queue
     ↓                      ↓
  Light Workers (6)    Heavy Workers (2)
     ↓                      ↓
  DB: done             DB: done → ffmpeg_queue
                                      ↓
                              ffmpeg Workers (2)
                                      ↓
                              DB: thumbnail done
```

### Worker pools

| Pool | Workers | Handles |
|---|---|---|
| Probe | 4 | HEAD request, metadata, routing decision |
| Light | 6 | Images, audio, documents |
| Heavy | 2 | Videos, large files |
| ffmpeg | 2 | Thumbnail generation (post-upload, non-blocking) |

### Probe worker flow

```
pull from probe_queue
→ update status: probing
→ HEAD request to URL
→ if fails (4xx) → mark failed (stage: probe), permanent
→ if fails (timeout/5xx) → increment attempt_count, schedule retry
→ if succeeds:
    → read Content-Type + Content-Length headers if available
    → determine pool: video → heavy_queue, else → light_queue
    → update status: queued
```

### Download worker flow

```
pull from light_queue or heavy_queue
→ update status: downloading
→ stream download to /tmp/keeper/{uuid}.tmp
→ compute SHA256 hash during stream (no extra pass)
→ update status: uploading
→ stream upload from /tmp/keeper/{uuid}.tmp to Garage S3
→ delete /tmp/keeper/{uuid}.tmp immediately after upload
→ detect real MIME type (magic bytes)
→ extract dimensions (images via sharp) or duration (video via ffprobe)
→ update DB: status done, all metadata fields
→ if video → push to ffmpeg_queue
```

### ffmpeg worker flow

```
pull from ffmpeg_queue
→ update thumbnail_status: pending
→ download video from Garage to /tmp/keeper/{uuid}_video.tmp
→ run ffmpeg → extract frame at 1s mark → save as /tmp/keeper/{uuid}_thumb.jpg
→ upload thumbnail to Garage
    → key: image/{year}/{month}/{day}/{uuid}_thumb.jpg
→ delete /tmp/keeper/{uuid}_video.tmp and /tmp/keeper/{uuid}_thumb.jpg
→ update DB: thumbnail_key, thumbnail_status: done
```

### Concurrency model

Each pool runs independent worker loops. No shared mutable state except DB and queues.

```
for each worker in pool:
  loop:
    job = queue.dequeue()  // blocking wait
    process(job)
```

### Crash recovery

On startup, two cleanup steps run before workers start:

**1. Temp file cleanup** — purge `/tmp/keeper/` entirely:
```
rm -rf /tmp/keeper/*
```
Any partial downloads from the previous run are invalid — safe to delete. Workers will re-download from scratch.

**2. Job re-queue** — re-queue all non-terminal jobs:

```sql
SELECT * FROM resources
WHERE status NOT IN ('done', 'failed')
```

All jobs re-enter `probe_queue`. Safe — probe and upload are both idempotent.

---

## 8. Error Handling & Retry Strategy

### Failure classification

| Failure | Retryable | Reason |
|---|---|---|
| 403 / 404 / 410 | ❌ No | URL permanently bad |
| Network timeout | ✅ Yes | Transient |
| DNS failure | ✅ Yes | Transient |
| Garage S3 unavailable | ✅ Yes | Transient |
| Disk full | ❌ No | Operational issue |
| ffmpeg crash | ✅ Yes | Could be transient |
| Invalid / corrupt content | ❌ No | Won't change on retry |

### Retry schedule

| Attempt | Delay |
|---|---|
| 1 | Immediate |
| 2 | 30 seconds |
| 3 | 5 minutes |
| 4+ | Mark `failed`, stop |

Max 3 attempts. After that → permanent `failed`.

### Retry scheduler

Lightweight background timer, runs every 10 seconds:

```sql
SELECT * FROM resources
WHERE status = 'pending'
AND next_retry_at <= NOW()
AND next_retry_at IS NOT NULL
```

Jobs returned are pushed back into `probe_queue`.

### Manual resubmit flow

When a caller submits a URL that previously failed:

```
POST /resource { url: "..." }
→ URL found in DB, status: failed
→ reset: status → pending, attempt_count → 0
→ generate fresh s3_key (new date, new uuid)
→ return 200 with reset record
```

Fresh start — old failure is overwritten. URL is the unique key.

### Thumbnail failure isolation

If ffmpeg fails after 3 attempts:
- `thumbnail_status` → `failed`
- Resource `status` stays `done`
- File is fully available in S3 — thumbnail failure is non-fatal

---

## 9. Status & Observability

### `GET /status` — System Snapshot

Returns current state of all queues and workers at a point in time. Queue and worker data come from in-memory state. Stats come from DB.

```json
{
  "timestamp": "2026-03-15T10:00:00Z",
  "queues": {
    "probe": {
      "waiting": 2,
      "jobs": [
        { "id": "uuid1", "url": "https://pbs.twimg.com/media/abc.jpg" },
        { "id": "uuid2", "url": "https://pbs.twimg.com/media/def.mp4" }
      ]
    },
    "light": {
      "waiting": 1,
      "jobs": [
        { "id": "uuid3", "url": "https://pbs.twimg.com/media/ghi.png" }
      ]
    },
    "heavy": { "waiting": 0, "jobs": [] },
    "ffmpeg": {
      "waiting": 1,
      "jobs": [
        { "id": "uuid4", "url": "https://pbs.twimg.com/media/jkl.mp4" }
      ]
    }
  },
  "workers": {
    "probe": {
      "total": 4, "busy": 2, "idle": 2,
      "active": [
        { "worker_id": 1, "job_id": "uuid5", "url": "https://example.com/img.jpg" },
        { "worker_id": 2, "job_id": "uuid6", "url": "https://example.com/vid.mp4" }
      ]
    },
    "light":  { "total": 6, "busy": 0, "idle": 6, "active": [] },
    "heavy": {
      "total": 2, "busy": 1, "idle": 1,
      "active": [
        { "worker_id": 1, "job_id": "uuid7", "url": "https://example.com/big.mp4" }
      ]
    },
    "ffmpeg": { "total": 2, "busy": 0, "idle": 2, "active": [] }
  },
  "stats": {
    "total": 1500,
    "pending": 16,
    "done": 1450,
    "failed": 34
  }
}
```

---

### `GET /status/events` — SSE Stream

Every status transition emits an event. Frontend connects once, receives pushed updates, and updates UI accordingly. No polling needed.

**Query params:**

| Param | Type | Default | Notes |
|---|---|---|---|
| `workers` | boolean | false | Include `worker.busy` / `worker.idle` events |

#### Event → Status alignment

| Event | Status transition |
|---|---|
| `job.submitted` | `→ pending` |
| `job.probing` | `→ probing` |
| `job.queued` | `→ queued` |
| `job.downloading` | `→ downloading` |
| `job.uploading` | `→ uploading` |
| `job.done` | `→ done` |
| `job.failed` | `→ failed` |
| `job.retry` | `→ pending` (with retry info) |
| `thumbnail.pending` | thumbnail_status `→ pending` |
| `thumbnail.done` | thumbnail_status `→ done` |
| `thumbnail.failed` | thumbnail_status `→ failed` |
| `worker.busy` | worker picked up a job (opt-in) |
| `worker.idle` | worker finished a job (opt-in) |

#### Event shapes

Every event includes the same base fields. Additional fields per type:

```
event: job.submitted
data: {
  "event": "job.submitted",
  "timestamp": "2026-03-15T10:00:00Z",
  "id": "uuid",
  "url": "https://pbs.twimg.com/media/abc.jpg",
  "s3_key": "image/2026/03/15/uuid.jpg",
  "category": "image"
}

event: job.probing
data: {
  "event": "job.probing",
  "timestamp": "2026-03-15T10:00:00Z",
  "id": "uuid",
  "url": "https://pbs.twimg.com/media/abc.jpg",
  "s3_key": "image/2026/03/15/uuid.jpg",
  "category": "image"
}

event: job.queued
data: {
  "event": "job.queued",
  "timestamp": "2026-03-15T10:00:01Z",
  "id": "uuid",
  "url": "https://pbs.twimg.com/media/abc.jpg",
  "s3_key": "image/2026/03/15/uuid.jpg",
  "category": "image",
  "pool": "light"
}

event: job.downloading
data: {
  "event": "job.downloading",
  "timestamp": "2026-03-15T10:00:01Z",
  "id": "uuid",
  "url": "https://pbs.twimg.com/media/abc.mp4",
  "s3_key": "video/2026/03/15/uuid.mp4",
  "category": "video",
  "pool": "heavy"
}

event: job.uploading
data: {
  "event": "job.uploading",
  "timestamp": "2026-03-15T10:00:03Z",
  "id": "uuid",
  "url": "https://pbs.twimg.com/media/abc.mp4",
  "s3_key": "video/2026/03/15/uuid.mp4",
  "category": "video"
}

event: job.done
data: {
  "event": "job.done",
  "timestamp": "2026-03-15T10:00:05Z",
  "id": "uuid",
  "url": "https://pbs.twimg.com/media/abc.mp4",
  "s3_key": "video/2026/03/15/uuid.mp4",
  "category": "video",
  "content_type": "video/mp4",
  "file_size": 524288,
  "width": 1280,
  "height": 720,
  "duration_ms": 4200
}

event: job.failed
data: {
  "event": "job.failed",
  "timestamp": "2026-03-15T10:00:02Z",
  "id": "uuid",
  "url": "https://pbs.twimg.com/media/abc.mp4",
  "s3_key": "video/2026/03/15/uuid.mp4",
  "category": "video",
  "fail_stage": "probe",
  "fail_reason": "403 Forbidden",
  "attempt_count": 3
}

event: job.retry
data: {
  "event": "job.retry",
  "timestamp": "2026-03-15T10:00:03Z",
  "id": "uuid",
  "url": "https://pbs.twimg.com/media/abc.mp4",
  "s3_key": "video/2026/03/15/uuid.mp4",
  "category": "video",
  "fail_stage": "download",
  "attempt_count": 2,
  "next_retry_at": "2026-03-15T10:05:00Z"
}

event: thumbnail.done
data: {
  "event": "thumbnail.done",
  "timestamp": "2026-03-15T10:00:10Z",
  "id": "uuid",
  "url": "https://pbs.twimg.com/media/abc.mp4",
  "thumbnail_key": "image/2026/03/15/uuid_thumb.jpg"
}

event: worker.busy
data: {
  "event": "worker.busy",
  "timestamp": "2026-03-15T10:00:01Z",
  "pool": "heavy",
  "worker_id": 1,
  "job_id": "uuid",
  "url": "https://pbs.twimg.com/media/abc.mp4"
}

event: worker.idle
data: {
  "event": "worker.idle",
  "timestamp": "2026-03-15T10:00:05Z",
  "pool": "heavy",
  "worker_id": 1
}
```

#### Frontend usage pattern

```
1. Connect to GET /status/events
2. Call GET /status once → hydrate initial UI state
3. Listen to SSE stream → apply incremental updates
   - job.* events → update job row in list
   - worker.* events → update worker slot in status panel
4. No polling needed
```

#### Performance notes

- Max ~14 workers × ~6 events per job lifecycle = ~80–100 events/second at absolute peak
- In practice far lower — downloads take seconds, not milliseconds
- SSE is plain text over an open socket — trivial overhead at this scale
- `worker.busy` / `worker.idle` are opt-in (`?workers=true`) to reduce noise for clients that don't need that granularity
- `GET /status` is the heavier call (hits DB) — SSE eliminates the need to poll it

---

## 10. Environment Configuration

All runtime config is provided via environment variables. No hardcoded values.

| Variable | Required | Notes |
|---|---|---|
| `PORT` | No | API port, default `3000` |
| `DATABASE_URL` | Yes | Turso connection string |
| `DATABASE_AUTH_TOKEN` | Yes | Turso auth token |
| `S3_ENDPOINT` | Yes | Garage S3 endpoint e.g. `http://localhost:3900` |
| `S3_BUCKET` | Yes | Garage bucket name |
| `S3_ACCESS_KEY_ID` | Yes | Garage access key |
| `S3_SECRET_ACCESS_KEY` | Yes | Garage secret key |
| `S3_PUBLIC_BASE_URL` | Yes | Base URL callers use to construct full file URL e.g. `http://192.168.10.101:3900/keeper` |
| `WORKER_PROBE_COUNT` | No | Probe pool size, default `4` |
| `WORKER_LIGHT_COUNT` | No | Light pool size, default `6` |
| `WORKER_HEAVY_COUNT` | No | Heavy pool size, default `2` |
| `WORKER_FFMPEG_COUNT` | No | ffmpeg pool size, default `2` |
| `TEMP_DIR` | No | Temp file directory, default `/tmp/keeper` |

> Callers construct full file URLs as: `{S3_PUBLIC_BASE_URL}/{s3_key}`
> Example: `http://192.168.10.101:3900/keeper/image/2026/03/15/uuid.jpg`

---

## 11. Tech Stack

| Concern | Choice | Notes |
|---|---|---|
| Language | TypeScript (strict) | Same as Juicer |
| Runtime | Bun | Native TS, built-in fetch, fast startup |
| Framework | Hono + zod-openapi | Lightweight REST + auto OpenAPI spec |
| Database | Turso + Drizzle | Separate DB from Juicer, SQLite locally |
| Validation | Zod | API + config validation |
| Logging | Pino | Structured JSON logs |
| Linting | Biome | Lint + format |
| Testing | bun test | Built-in, Jest-compatible |
| Container | Docker (oven/bun) | Same pattern as Juicer |
| S3 client | `@aws-sdk/client-s3` | S3-compatible, works with Garage |
| File type detection | `file-type` | Magic bytes MIME detection |
| Image metadata | `sharp` | Dimensions extraction, fast |
| Video metadata | `ffprobe` (child_process) | Duration + dimensions |
| Thumbnail generation | `ffmpeg` (child_process) | Already installed on server |
| Hash computation | `Bun.CryptoHasher` | SHA256, no extra dependency |
| Worker queues | In-memory + Bun | Same pattern as Juicer fetch queue |

### What is NOT in Keeper

- No LLM client — no AI processing
- No FTS5 search — not needed
- No hey-api — Keeper is a server, not a client

---

## 12. Design Decisions Summary

| Decision | Choice | Reason |
|---|---|---|
| s3_key generated at submission | ✅ Yes | Caller gets stable reference immediately |
| Keeper URL returned | ❌ No | `s3_key` is the reference, caller constructs full URL |
| Content-hash dedup | ❌ No | s3_key already given to caller, cannot redirect |
| Content-hash stored | ✅ Yes | Informational — allows duplicate discovery queries |
| URL dedup | ✅ Yes | Same URL → return existing record, 200 vs 201 |
| Probe in worker | ✅ Yes | Keeps API submission instant |
| Thumbnail blocking resource | ❌ No | Video available in S3 immediately, thumbnail async |
| External queue (Redis) | ❌ No | Single server, in-memory sufficient |
| Shared DB with Juicer | ❌ No | Keeper is fully independent |
| Audio support | ✅ Yes | Routes to light pool |
