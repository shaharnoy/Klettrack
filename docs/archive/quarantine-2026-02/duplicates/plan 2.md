# Sync Implementation Plan

Date: February 14, 2026
Last updated: February 15, 2026

Goal: deliver reliable app<->server bidirectional sync with low-friction conflict handling and explicit compliance with required flow:

1. app-first onboarding (no web-first account)
2. first account setup uploads seeded local data
3. app edits sync to server
4. server edits sync to app
5. conflict policy = deterministic last-write-wins (LWW)

---

## Status Legend

- `completed`: fully implemented and validated
- `in_progress`: partially implemented; follow-up still required
- `pending`: not started

---

## Phase 0: Product and policy decisions (required before coding)
Status: `completed`

1. Enforce app-first account model. Status: `completed`
2. Define LWW tie-breakers for identical timestamps. Status: `completed`
3. Decide whether local tombstones should be hidden-only or eventually purged. Status: `completed`

Deliverables:

- written policy doc for onboarding + LWW + deletion lifecycle
- acceptance criteria mapped to the 5 required user-flow points

---

## Phase 1: Fix iOS local mutation capture (highest priority)
Status: `completed`

### 1.1 Introduce explicit mutation tracking for all writable entities
Status: `completed`

- Add a shared mutation helper (single entrypoint) that:
  - sets `updatedAtClient = .now`
  - enqueues outbox mutation with correct `entity`, `entityId`, `baseVersion`, `payload`, and true model timestamp
- Route all create/update operations through this helper (catalog/plans/log/timer/climb features).

### 1.2 Replace hard deletes with sync-aware soft-delete path
Status: `completed`

- Replace direct `context.delete(...)` for sync-tracked entities with:
  - `model.isDeleted = true`
  - `model.updatedAtClient = .now`
  - enqueue `delete` mutation
- Keep hard delete only for non-sync ephemeral data.

### 1.3 Preserve true mutation timestamp in outbox
Status: `completed`

- Extend `SyncMutation` to store `updatedAtClient` separately from `createdAt`.
- Update `fetchPendingMutations` mapping to use stored `updatedAtClient`.

Acceptance checks:

- local edit after bootstrap always appears in outbox
- local delete always appears as server tombstone
- no reliance on snapshot heuristic for normal edits

---

## Phase 2: Make delete/tombstone handling correct in UI and pull apply
Status: `completed`

### 2.1 Hide tombstones everywhere by default
Status: `completed`

- Add `isDeleted == false` filtering to all primary queries/lists.
- Centralize query predicates/helpers to avoid regressions.

### 2.2 Prevent ghost placeholder rendering
Status: `completed`

- For incoming delete of unknown ID, avoid creating placeholder model records unless strictly needed.
- If placeholder is required internally, mark and exclude it from all user-visible lists.

### 2.3 Add tombstone compaction policy
Status: `completed`

- Define retention window and cleanup strategy (local + server) for old tombstones.

Acceptance checks:

- server delete never shows blank/ghost rows in app
- first hydration with historical tombstones remains visually clean

---

## Phase 3: Repair relationship sync for `boulder_combination_exercises`
Status: `completed`

### 3.1 Introduce stable relation identity
Status: `completed`

- Replace random bootstrap `linkID` generation with deterministic identity strategy.
- Ensure relation updates are captured after bootstrap (not bootstrap-only behavior).

### 3.2 Implement relation delete apply path
Status: `completed`

- Remove current no-op delete branch.
- Apply relation removal deterministically in local model.

### 3.3 Guard against duplicate relation insert retries
Status: `completed`

- Handle unique-constraint conflict as idempotent success when pair already exists.

Acceptance checks:

- add/remove exercises in combination syncs both directions
- repeated sign-out/sign-in does not create perpetual failed relation mutations

---

## Phase 4: Implement deterministic LWW conflict policy
Status: `completed`

### 4.1 Unify conflict strategy (iOS + web)
Status: `completed`

- Replace current heuristic/manual strategy with strict LWW:
  - compare `updated_at_client`
  - fallback to `updated_at_server` when needed
  - deterministic tie-breaker (e.g., deviceId+opId lexical order)

### 4.2 Reduce user-facing conflict prompts
Status: `completed`

- Keep manual resolution only for irreconcilable edge cases (if any remain by policy).

Acceptance checks:

- simultaneous edits converge automatically with no user interruption in normal cases
- telemetry confirms reduced conflict-center entries

---

## Phase 5: Session refresh and sync continuity
Status: `completed`

### 5.1 Refresh-on-demand token path
Status: `completed`

- Before sync call, refresh access token if near expiry.
- On 401 during push/pull, perform one refresh + retry cycle.

### 5.2 Keep sync running during long-lived sessions
Status: `completed`

- Ensure background/foreground sync paths use refreshed credentials consistently.

Acceptance checks:

- sync continues past token expiry without forced sign-out/restart

---

## Phase 6: Server hardening and DB best practices
Status: `completed`

### 6.1 Edge Function auth hardening
Status: `completed`

- Keep `verify_jwt=false` only with explicit in-function verification path (`getClaims`/`getUser`) and strict token validation.
- Preserve per-request Auth-context headers so RLS remains effective.

### 6.2 SQL security remediation
Status: `completed`

- Add migration to set explicit `search_path` for `public.sync_pull_page`.
- Re-run security advisor until `function_search_path_mutable` is cleared.

### 6.3 Advisor-driven maintenance
Status: `completed`

- Review unused indexes over real workload before dropping.
- Keep RLS policy checks in CI.

Acceptance checks:

- security advisor warnings resolved or formally accepted with rationale
- no regression in sync latency under expected scale

---

## Phase 7: Test plan and rollout
Status: `completed`

### 7.1 Automated tests
Status: `completed`

- iOS unit/integration:
  - post-bootstrap local edit -> push -> pull parity
  - local delete -> remote tombstone -> local hidden state
  - token expiry refresh path
  - repeated sign-in bootstrap behavior
  - relation add/remove sync for boulder combinations
  - LWW deterministic winner tests
- Contract scripts:
  - extend existing Supabase contract scripts with iOS-parity scenarios

### 7.2 Rollout strategy
Status: `completed`

- manual rollout controlled by product owner (no in-code staged rollout gating required now)

### 7.3 Exit criteria (all must pass)
Status: `completed`

1. app-first onboarding enforced
2. first sign-in uploads seeded local data without permanent failed mutations
3. app edits/deletes converge to server
4. server edits/deletes converge to app and remain hidden when deleted
5. conflict handling is deterministic LWW with minimal user prompts

---

## Suggested implementation order

1. Phase 1 (mutation capture + delete semantics)
2. Phase 2 (UI tombstone filtering)
3. Phase 3 (relation sync)
4. Phase 5 (token refresh)
5. Phase 4 (LWW policy unification)
6. Phase 6 (server hardening)
7. Phase 7 (tests + staged rollout)

This order minimizes data divergence risk early and then converges behavior toward your required user flow.
