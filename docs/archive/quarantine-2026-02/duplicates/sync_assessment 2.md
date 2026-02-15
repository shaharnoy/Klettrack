# Sync Architecture Assessment (iOS app <-> Supabase <-> Web)

Date: February 14, 2026

## Scope and method

This assessment covered:

- iOS sync/auth code in `ClimbingProgram/features/sync/*` and `ClimbingProgram/features/auth/*`
- app lifecycle entrypoints in `ClimbingProgram/app/*`
- web sync client in `web/js/*`
- Supabase Edge Function and SQL migrations in `supabase/functions/sync/*` and `supabase/migrations/*`
- live Supabase project state via MCP (`list_tables`, `list_edge_functions`, `get_advisors`, `execute_sql`, `list_migrations`)
- Apple docs via Swift documentation MCP (BackgroundTasks, SwiftUI background task handling, SwiftData)
- Supabase docs via MCP (Edge function auth/security and RLS guidance)

Skills applied: `swiftui-expert-skill`, `supabase-postgres-best-practices`.

---

## Executive summary

Current sync has strong server-side guardrails (RLS, payload allowlists, parent validation, idempotency), but the iOS local-change capture path has high-risk gaps.

Most important issues:

1. iOS local edits are not reliably enqueued after initial bootstrap.
2. iOS local deletes are hard deletes, so many deletions never reach server tombstones.
3. Server tombstones can create ghost records in iOS UI because queries generally do not filter `isDeleted`.
4. Conflict resolution is not last-write-wins (LWW); it uses heuristic/manual strategy.
5. Relationship sync for `boulder_combination_exercises` is fragile and can generate persistent failed mutations.

---

## User-flow assessment (your requirements)

| Requirement | Current status | Notes |
|---|---|---|
| 1. User must start in app (no web-first account) | **Not enforced** | Web currently exposes self-registration flow (`web/js/bootstrap.js:188`). |
| 1.1 Server option is optional | **Supported** | Local-only is possible when user never signs in (`ClimbingProgram/features/auth/AuthManager.swift:64`). |
| 2. Seeded app data should upload on first web setup | **Partially supported** | Full bootstrap snapshot exists (`ClimbingProgram/features/sync/SyncStoreActor.swift:81`), but downstream issues reduce reliability for all entities/relationships. |
| 3. App edits should sync to server | **High risk / often broken** | No app-layer callsites enqueueing local mutations; snapshot heuristic depends on metadata usually not updated after edits. |
| 4. Server edits should sync to app | **Partially supported** | Pull path works, but depends on periodic/manual sync and has tombstone rendering issues. |
| 5. Conflicts should be low-friction LWW | **Not implemented** | Current strategy includes manual review/high-risk gating and threshold-based rebase (`ClimbingProgram/features/sync/SyncManager.swift:345`). |

---

## Findings (severity ordered)

### [Critical] F1. Local iOS changes are not reliably captured after bootstrap

Evidence:

- `SyncManager.enqueueLocalMutation(...)` exists (`ClimbingProgram/features/sync/SyncManager.swift:70`) but project-wide search found no callsites outside sync internals.
- Sync cycle relies on `enqueueLocalSnapshotIfNeeded()` (`ClimbingProgram/features/sync/SyncManager.swift:239`).
- Snapshot inclusion gate is `syncVersion == 0` or `updatedAtClient > lastSuccessfulSyncAt` (`ClimbingProgram/features/sync/SyncStoreActor.swift:93` to `ClimbingProgram/features/sync/SyncStoreActor.swift:101`).
- Outside migrations/pull-apply, `updatedAtClient` is generally not updated on user edits (search hits are mostly migrations and pull apply paths).

Impact:

- After first successful sync (rows now `syncVersion > 0`), many subsequent local edits are skipped.
- Requirement #3 fails for many edit paths.

---

### [Critical] F2. Local deletes are usually hard deletes, so delete sync is lost

Evidence:

- Many feature views call `context.delete(...)` directly (examples: `ClimbingProgram/features/catalog/CatalogView.swift:112`, `ClimbingProgram/features/plans/PlansViews.swift:215`, `ClimbingProgram/features/sessions/LogView.swift:26`, `ClimbingProgram/features/timer/TimerTemplatesListView.swift:83`).
- Sync outbox expects model presence + `isDeleted` flag to emit delete mutations (`ClimbingProgram/features/sync/SyncStoreActor.swift:196`).
- `isDeleted = true` assignments are effectively only in pull-apply delete path (`ClimbingProgram/features/sync/SyncStoreActor.swift:780`).

Impact:

- Local deletions can disappear before tombstones are enqueued.
- Server remains stale (deleted items can reappear after pull).

---

### [High] F3. Server tombstones can appear as ghost records in app UI

Evidence:

- Pull delete handler sets soft tombstone (`isDeleted = true`) rather than removing row (`ClimbingProgram/features/sync/SyncStoreActor.swift:780`).
- Delete path can create placeholder rows via `fetchOrCreate*` with default fields (`ClimbingProgram/features/sync/SyncStoreActor.swift:1425`).
- Most UI `@Query` lists do not filter `isDeleted` (examples: `ClimbingProgram/features/catalog/CatalogView.swift:20`, `ClimbingProgram/features/plans/PlansViews.swift:113`, `ClimbingProgram/features/sessions/LogView.swift:53`, `ClimbingProgram/features/climb/ClimbView.swift:24`, `ClimbingProgram/features/timer/TimerTemplatesListView.swift:21`).

Impact:

- Deleted server items can remain visible locally.
- First hydration with existing server tombstones can produce blank/ghost rows.

---

### [High] F4. Conflict handling is not LWW (last-write-wins)

Evidence:

- Strategy is heuristic/manual:
  - Manual review for deletes/sensitive keys/long text (`ClimbingProgram/features/sync/SyncManager.swift:459`)
  - Timestamp threshold (`30s`) for keep-mine (`ClimbingProgram/features/sync/SyncManager.swift:45`, `ClimbingProgram/features/sync/SyncManager.swift:447`)
  - Default keep-server (`ClimbingProgram/features/sync/SyncManager.swift:369`)

Impact:

- Violates requirement #5 (simple, low-disruption LWW).
- User-facing conflict prompts remain likely for common edit cases.

---

### [High] F5. `boulder_combination_exercises` sync has structural weaknesses

Evidence:

- Full bootstrap synthesizes random relation IDs (`linkID = UUID()`) (`ClimbingProgram/features/sync/SyncStoreActor.swift:519`).
- This relation upsert loop runs only during full bootstrap (`ClimbingProgram/features/sync/SyncStoreActor.swift:516`), so post-bootstrap relation edits are not explicitly captured.
- Pull delete for this entity is explicitly a no-op (`ClimbingProgram/features/sync/SyncStoreActor.swift:818`).
- Live DB has unique constraint `UNIQUE (owner_id, boulder_combination_id, exercise_id)` (confirmed via Supabase SQL MCP).

Impact:

- Re-bootstrap/sign-in cycles can generate `insert_failed` on duplicate relations.
- Relation delete correctness is incomplete.

---

### [High] F6. Session/token refresh is not integrated into sync request path

Evidence:

- Sync API token provider returns stored access token directly (`ClimbingProgram/features/auth/AuthManager.swift:77`).
- Session refresh happens in restore flow only (`ClimbingProgram/features/auth/AuthManager.swift:109`).
- `requireAccessToken()` does not check expiry (`ClimbingProgram/features/auth/SupabaseSessionStore.swift:94`).

Impact:

- Token expiry during normal app usage can stall sync until a full session-restore path happens.

---

### [Medium] F7. Outbox `updatedAtClient` uses mutation row creation time, not model change time

Evidence:

- Pending mutation maps `updatedAtClient` from `SyncMutation.createdAt` (`ClimbingProgram/features/sync/SyncStoreActor.swift:608`).
- Keep-mine rebase also mutates `createdAt` (`ClimbingProgram/features/sync/SyncStoreActor.swift:668`).

Impact:

- Timestamp semantics drift from true domain write time.
- Any LWW-like logic based on these timestamps is less trustworthy.

---

### [Medium] F8. Performance scaling risk from repeated full-table fetch-and-filter patterns

Evidence:

- `findMutationRow` fetches entire outbox then filters in memory (`ClimbingProgram/features/sync/SyncStoreActor.swift:711`).
- `fetchOrCreate*` helpers repeatedly fetch full tables + `first(where:)` (`ClimbingProgram/features/sync/SyncStoreActor.swift:1425`).

Impact:

- Increased latency and CPU/memory use as datasets grow.
- Higher energy cost during sync cycles.

---

### [Medium] F9. App-first account rule is not enforced

Evidence:

- Web registration path is active (`web/js/bootstrap.js:188`).

Impact:

- Violates requirement #1.
- Can create product-state divergence from expected onboarding assumptions.

---

### [Medium] F10. Edge function auth hardening gaps

Evidence:

- Live function config: `sync` deployed with `verify_jwt=false` (Supabase MCP `list_edge_functions`).
- Function derives `userId` by parsing JWT payload (`supabase/functions/sync/index.ts:150`) rather than explicit claims verification flow.
- Security advisor warning: `function_search_path_mutable` on `public.sync_pull_page` (Supabase MCP `get_advisors` security).

Impact:

- Current pattern can still work with Auth-context + RLS, but is less robust than explicit verification guidance.
- Search path advisory should be remediated.

---

### [Medium] F11. Server->app propagation latency is best-effort, not near-real-time

Evidence:

- iOS sync trigger points are manual, foreground active, and background task execution (`ClimbingProgram/features/auth/AuthManager.swift:191`, `ClimbingProgram/features/auth/AuthManager.swift:196`, `ClimbingProgram/features/auth/AuthManager.swift:204`).
- Background task scheduling uses `earliestBeginDate` only (`ClimbingProgram/features/sync/SyncBackgroundRefresh.swift:19`), and Apple documents this as "not earlier than" rather than exact execution time.

Impact:

- Requirement #4 is functionally supported, but latency is variable and system-scheduled.
- Users may see delayed server-originated updates until app activation/manual sync.

---

## What is working well

- Server push contract has strong controls:
  - allowlisted payload fields (`supabase/functions/sync/index.ts:342`)
  - required-field checks (`supabase/functions/sync/index.ts:386`)
  - parent ownership validation (`supabase/functions/sync/index.ts:467`)
  - idempotency via `last_op_id` (`supabase/functions/sync/index.ts:215`)
- Pull pagination is deterministic (cursor over `updated_at_server`, entity, id) (`supabase/migrations/20260214_sync_pull_rpc_unified.sql:82`).
- Metadata trigger increments version and updates `updated_at_server` (`supabase/migrations/20260210_sync_v1_schema.sql:7`).
- RLS enabled on sync tables (confirmed live via Supabase MCP `list_tables`).

---

## Test coverage gaps

Existing tests cover conflict helpers and store mechanics, but major behavior gaps remain untested:

- no end-to-end test proving local post-bootstrap edits are enqueued and pushed
- no end-to-end test proving hard-delete paths produce remote tombstones
- no UI-level assertion that tombstoned rows are excluded from queries
- no test for repeated sign-out/sign-in bootstrap behavior on relation uniqueness
- no auth-expiry sync continuation test (refresh and retry)

---

## Documentation-backed guidance used in this assessment

Apple docs (Swift documentation MCP):

- `BGTaskRequest.earliestBeginDate` states scheduling is earliest-only, not exact execution time:
  - https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate
- SwiftUI `Scene.backgroundTask(_:action:)` task can be cancelled when runtime budget expires:
  - https://developer.apple.com/documentation/swiftui/scene/backgroundtask(_:action:)
- SwiftData `ModelContext.save()` recommends checking `hasChanges` first:
  - https://developer.apple.com/documentation/swiftdata/modelcontext/save()
  - https://developer.apple.com/documentation/swiftdata/modelcontext/haschanges
- SwiftData `ModelActor` provides serialized access model:
  - https://developer.apple.com/documentation/swiftdata/modelactor

Supabase docs (Supabase docs MCP):

- Securing Edge Functions and explicit JWT verification patterns:
  - https://supabase.com/docs/guides/functions/auth
- Auth context with `Authorization` header and RLS in edge functions:
  - https://supabase.com/docs/guides/functions/auth-legacy-jwt
- RLS policy best practices and performance recommendations:
  - https://supabase.com/docs/guides/database/postgres/row-level-security

Live Supabase advisories (MCP snapshot, February 14, 2026):

- `function_search_path_mutable` for `public.sync_pull_page`
  - https://supabase.com/docs/guides/database/database-linter?lint=0011_function_search_path_mutable
- `auth_leaked_password_protection` disabled
  - https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection

---

## Bottom line

The server foundation is solid, but iOS mutation capture/deletion semantics currently prevent reliable bidirectional sync and do not meet your requested LWW behavior. Addressing iOS outbox capture + tombstone handling + deterministic LWW policy is the highest-value path to make the flow robust and low-friction.
