# Supabase Sync Runbooks (v2)

## Scope
- Plans + catalog + sessions/timers/climbs sync (`sync` function)
- iOS and web clients using push/pull contract
- Climb media metadata sync (`climb_media` rows; binary objects remain in Storage)

## Signals to watch
- iOS trigger metrics: total triggers, failures
- Conflict volume (`version_mismatch`)
- Edge function logs for `sync`
- Outbox depth in local client diagnostics

## Runbook: Stuck outbox
1. Confirm user is authenticated and sync rollout is enabled.
2. Trigger manual sync once.
3. Check latest conflict list; resolve with `Keep Mine` or `Keep Server`.
4. If still stuck, sign out and sign in to refresh session.
5. If still stuck, capture failing mutation reason from function response and open incident.

## Runbook: Cursor reset
1. Record current user id and current cursor value.
2. Clear local cursor key:
- Web: remove `web_sync_cursor:<userId>` in localStorage.
- iOS: call signed-out cleanup path (`prepareForSignedOutState`) and re-enable sync.
3. Run pull from `null` cursor.
4. Verify no duplicate local records and conflict count remains bounded.

## Runbook: Selective entity resync
1. Disable local writes for affected entity (temporary guard).
2. Pull latest cursor window and inspect entity rows only.
3. If needed, soft-delete and re-upsert affected rows through push contract.
4. Re-enable writes and validate bidirectional sync.

## Runbook: Climb media incident (metadata drift or missing blob)
1. Confirm the `climb_media` row exists and is owned by the user (`owner_id` + `id`).
2. Check `storage_bucket` and `storage_path` values and verify object existence in Storage.
3. If metadata exists but object is missing, keep row and mark media unavailable in UI; do not delete climb entry automatically.
4. If object exists but metadata is stale, issue `upsert` mutation for `climb_media` with corrected storage fields.
5. Re-run pull from latest cursor and verify the client resolves to a stable single media row.

## Runbook: Parent-link validation failures
1. Capture failed mutation payload and `reason` (expect `invalid_parent_reference`).
2. Verify parent entity row exists and belongs to same `owner_id`.
3. If parent is missing, replay parent upsert first, then replay child mutation.
4. If parent exists with different ownership, treat as cross-tenant bug and escalate immediately.

## Escalation path
1. App engineer on-call
2. Supabase operator / project owner
3. Product owner for user-impact decisions (rollback/kill switch)

## Rollback controls
- iOS kill switch: `syncKillSwitchEnabled`
- iOS rollout gate: `syncRolloutEnabled`
- Web fallback: disable realtime (`SYNC_REALTIME_ENABLED=false`) and rely on pull
